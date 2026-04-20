import SwiftUI
import MapKit
import FirebaseDatabase
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import UserNotifications
import ActivityKit

// MARK: - Timeout Guard (internal, für deleteAccount)

/// Stellt sicher dass eine Continuation genau einmal resumt wird, egal ob die
/// Operation oder der Timeout-Timer zuerst fertig ist.
final class TimeoutGuard: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func resume(_ block: () -> Void) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        lock.unlock()
        block()
    }
}

// MARK: - User

struct User: Identifiable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var isAvailable: Bool
    var statusMessage: String
    var coordinate: CLLocationCoordinate2D

    init(id: UUID = UUID(), name: String, emoji: String,
         isAvailable: Bool, statusMessage: String,
         coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)) {
        self.id = id; self.name = name; self.emoji = emoji
        self.isAvailable = isAvailable; self.statusMessage = statusMessage
        self.coordinate = coordinate
    }
    static func == (lhs: User, rhs: User) -> Bool { lhs.id == rhs.id }
}

// MARK: - Activity

struct Activity: Identifiable {
    let id: UUID
    var name: String
    var emoji: String

    static let presets: [Activity] = [
        Activity(id: UUID(), name: "Kaffee", emoji: "☕️"),
        Activity(id: UUID(), name: "Drink",  emoji: "🍺"),
        Activity(id: UUID(), name: "Sport",  emoji: "🏃"),
        Activity(id: UUID(), name: "Essen",  emoji: "🍕"),
        Activity(id: UUID(), name: "Zocken", emoji: "🎮"),
        Activity(id: UUID(), name: "Eigene", emoji: "✏️")
    ]
}

enum LocationType { case current, searched, pin }

struct DropLocation {
    var title: String
    var subtitle: String
    var coordinate: CLLocationCoordinate2D
    var type: LocationType
}

// MARK: - Drop Event

struct DropEvent: Identifiable {
    let id: UUID
    let host: User
    var activity: Activity
    var location: DropLocation
    var participants: [User]
    let createdAt: Date
    var dropDescription: String
    var scheduledTime: String
    var maxParticipants: Int = 10   // 2–15, default 10
    var durationMinutes: Int = 120  // 0 = kein Limit (12h Fallback)
    var isBoosted: Bool = false     // Drops+ Feature: Boost auf der Karte

    /// Ablaufzeitpunkt: durationMinutes == 0 → 12h-Fallback (kein Limit)
    var expiresAt: Date {
        if durationMinutes > 0 {
            return createdAt.addingTimeInterval(Double(durationMinutes) * 60)
        }
        switch scheduledTime {
        case "Heute Abend":
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
            comps.hour = 23; comps.minute = 59; comps.second = 59
            return Calendar.current.date(from: comps) ?? createdAt.addingTimeInterval(12 * 60 * 60)
        default:
            return createdAt.addingTimeInterval(12 * 60 * 60)
        }
    }

    /// Drop gilt als abgelaufen nur wenn der Host ihn explizit beendet hat
    /// (via cancelDrop) — NICHT automatisch nach Zeit.
    /// Der expiryTimer räumt wirklich alte Drops (>12h) auf.
    var isExpired: Bool { Date() > expiresAt }

    /// Status-Label für eigene Drops — kein Countdown mehr, Drop läuft bis Host beendet
    var timeRemainingLabel: String { "Aktiv" }

    func distance(from userCoord: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let to   = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return from.distance(from: to)
    }

    func isNearby(from userCoord: CLLocationCoordinate2D, maxMeters: Double = 800) -> Bool {
        distance(from: userCoord) <= maxMeters
    }

    func etaMinutes(from userCoord: CLLocationCoordinate2D) -> Int {
        Int(distance(from: userCoord) / 80)
    }
}

// MARK: - Alert Item

struct AlertItem: Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let activity: String
    let eta: String
    var status: AlertStatus
    enum AlertStatus { case pending, accepted, declined }
}

// MARK: - Drop Join (kein Approval — direkt dabei)

/// Wer bei einem Drop vorbeischaut — wird dem Host als Info angezeigt, kein Accept/Decline.
struct JoinRequest: Identifiable {
    let id: UUID
    let dropID: UUID
    let dropEmoji: String
    let dropActivity: String
    let requesterName: String
    let requesterEmoji: String
    let createdAt: Date
    /// Wo der Drop stattfindet — für Entfernungsanzeige und Karten-Pin
    let dropCoordinate: CLLocationCoordinate2D?

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 24 * 60 * 60
    }

    /// Simulierter aktueller Standort des Joiners (~500–1500m vom Drop entfernt).
    /// In Produktion: echter GPS-Stream des Joiners.
    var simulatedCoordinate: CLLocationCoordinate2D? {
        guard let base = dropCoordinate else { return nil }
        let h = abs(id.hashValue)
        let latOff = (Double(h % 8 + 5) * 0.0010) * ((h / 20) % 2 == 0 ? 1 : -1)
        let lonOff = (Double((h >> 8) % 8 + 5) * 0.0010) * ((h >> 12) % 2 == 0 ? 1 : -1)
        return CLLocationCoordinate2D(latitude: base.latitude + latOff,
                                      longitude: base.longitude + lonOff)
    }

    var timeAgoLabel: String {
        let mins = Int(Date().timeIntervalSince(createdAt) / 60)
        if mins < 1  { return "Gerade eben" }
        if mins < 60 { return "Vor \(mins) Min" }
        let h = mins / 60
        return h == 1 ? "Vor 1 Std" : "Vor \(h) Std"
    }
}

// MARK: - Incoming Join Request (Host-Perspektive)

struct IncomingJoinRequest: Identifiable {
    let id: String               // joinerID (Firebase key)
    let dropID: String
    let joinerName: String
    let joinerEmoji: String
    let joinerProfileImageURL: String?
    let requestedAt: Date

    /// Nach 5 Min Auto-Accept wenn Host nicht reagiert
    static let autoAcceptDelay: TimeInterval = 5 * 60
    var autoAcceptAt: Date { requestedAt.addingTimeInterval(Self.autoAcceptDelay) }
    var shouldAutoAccept: Bool { Date() >= autoAcceptAt }

    var waitingMinutes: Int { max(0, Int(Date().timeIntervalSince(requestedAt) / 60)) }
}

// MARK: - Drop Participant

struct DropParticipant: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    var selfie: UIImage? = nil
    var reliabilityScore: Int = 85
    var age: Int? = nil
    var isVerified: Bool = false
    var statusMessage: String = ""
    /// 8-stelliger BLE-Token (Prefix der User-UUID) — für Bluetooth-Presence-Filter.
    var token: String = ""
    /// Simulierte Distanz in Metern zum Drop-Standort (für "Unterwegs"-Anzeige mit ETA).
    var simulatedDistance: Double? = nil
    /// Aktueller Live-Standort des Teilnehmers (simuliert; in Produktion: echter GPS-Stream).
    var liveCoordinate: CLLocationCoordinate2D? = nil
    var profileImageURL: String? = nil
}

// MARK: - Munich City Boundary

/// Drops-Servicegebiet: München + Umgebung (Unterschleißheim, Ismaning, Unterföhring,
/// Haar, Ottobrunn, Unterhaching, Grünwald, Gauting, Germering, Puchheim, Karlsfeld, Dachau)
/// ~40 Stützpunkte im Uhrzeigersinn, orientiert an den tatsächlichen Gemeindegrenzen
/// (Ortsschild-Positionen auf Haupteinfallstraßen).
enum MunichBoundary {
    static let coordinates: [CLLocationCoordinate2D] = [
        // ── Dachau (NW) ──────────────────────────────────────────────
        // Westgrenze Dachau: Sudetenlandstraße / St2342, Ortsschild ~11.372
        .init(latitude: 48.2200, longitude: 11.3750), // Dachau Süd-West (Amper / Karlsfeld-Grenze)
        .init(latitude: 48.2570, longitude: 11.3720), // Dachau West (Ortsschild Sudetenlandstraße)
        .init(latitude: 48.2850, longitude: 11.3930), // Dachau Nord-West
        .init(latitude: 48.3070, longitude: 11.4300), // Dachau Nord (B304 / Schleißheimer Str., Ortsschild)
        .init(latitude: 48.2970, longitude: 11.4960), // Dachau Nord-Ost (Grenze zu Karlsfeld N)
        // ── Unterschleißheim (N) ─────────────────────────────────────
        .init(latitude: 48.3060, longitude: 11.5000), // Unterschleißheim Nord-West
        .init(latitude: 48.3180, longitude: 11.5520), // Unterschleißheim Nord (Spitze)
        .init(latitude: 48.3090, longitude: 11.5880), // Unterschleißheim Nord-Ost
        // ── Oberschleißheim → Ismaning (NO) ──────────────────────────
        .init(latitude: 48.2820, longitude: 11.6120), // Oberschleißheim Ost
        .init(latitude: 48.2660, longitude: 11.6630), // Ismaning Nord
        .init(latitude: 48.2530, longitude: 11.7100), // Ismaning Nord-Ost
        .init(latitude: 48.2340, longitude: 11.7530), // Ismaning Ost (Spitze)
        // ── Unterföhring (O) ─────────────────────────────────────────
        .init(latitude: 48.2100, longitude: 11.7330), // Unterföhring Nord-Ost
        .init(latitude: 48.1950, longitude: 11.7230), // Unterföhring Ost
        // ── Haar (SO) ────────────────────────────────────────────────
        .init(latitude: 48.1680, longitude: 11.7450), // Haar Nord-Ost
        .init(latitude: 48.1340, longitude: 11.7840), // Haar Ost (Spitze, Ortsschild Wasserburger Landstr.)
        .init(latitude: 48.0980, longitude: 11.7760), // Haar Süd-Ost
        // ── Ottobrunn (S-O) ──────────────────────────────────────────
        // Ostgrenze: Rosenheimer Landstr. Ortsschild ~11.710; Südgrenze: Putzbrunner Str. ~48.047
        .init(latitude: 48.0860, longitude: 11.7110), // Ottobrunn Nord-Ost (Grenze Haar/Neubiberg)
        .init(latitude: 48.0640, longitude: 11.7110), // Ottobrunn Ost (Ortsschild Rosenheimer Landstr.)
        .init(latitude: 48.0450, longitude: 11.6950), // Ottobrunn SO-Ecke (Grenze Hohenbrunn/Brunnthal)
        .init(latitude: 48.0440, longitude: 11.6480), // Ottobrunn Süd (Ortsschild Putzbrunner Str.)
        // ── Unterhaching (S) ─────────────────────────────────────────
        .init(latitude: 48.0390, longitude: 11.6490), // Unterhaching Süd-Ost (Grenze Brunnthal)
        .init(latitude: 48.0230, longitude: 11.6080), // Unterhaching Süd (Spitze)
        .init(latitude: 48.0290, longitude: 11.5640), // Unterhaching Süd-West
        // ── Grünwald (S) ─────────────────────────────────────────────
        // Südgrenze: Grünwald erstreckt sich südlich der Isar bis ~47.997
        .init(latitude: 47.9970, longitude: 11.5300), // Grünwald Süd (Spitze, Ortsschild Tölzer Str.)
        .init(latitude: 48.0290, longitude: 11.4650), // Grünwald West (Ortsschild Würmtal)
        // ── Gauting (SW) ─────────────────────────────────────────────
        // Gauting ist großzügig: Südspitze ~47.991, Westgrenze ~11.329
        .init(latitude: 47.9940, longitude: 11.4560), // Gauting Süd-Ost
        .init(latitude: 47.9910, longitude: 11.3800), // Gauting Süd (Spitze, Ortsschild St2063)
        .init(latitude: 48.0480, longitude: 11.3390), // Gauting Nord-West (Ortsschild Gautinger Str.)
        // ── Germering (W) ────────────────────────────────────────────
        // Westgrenze Germering: ~11.316, Südgrenze: ~48.097
        .init(latitude: 48.0970, longitude: 11.3160), // Germering Süd-West
        .init(latitude: 48.1560, longitude: 11.3130), // Germering West (Spitze)
        // ── Puchheim (W) ─────────────────────────────────────────────
        // Westgrenze Puchheim: ~11.310, Südgrenze: ~48.142
        .init(latitude: 48.1680, longitude: 11.3100), // Puchheim West (Spitze, Ortsschild Friedenstr.)
        .init(latitude: 48.2100, longitude: 11.3450), // Puchheim Nord-West
        .init(latitude: 48.2190, longitude: 11.3820), // Puchheim Nord
        // ── Karlsfeld → Dachau (NW) ──────────────────────────────────
        .init(latitude: 48.2230, longitude: 11.4180), // Karlsfeld West (Ortsschild Münchner Str.)
        // zurück zum Startpunkt
        .init(latitude: 48.2200, longitude: 11.3750),
    ]

    /// Prüft ob eine Koordinate innerhalb der Münchner Stadtgrenze liegt (Ray-Casting).
    static func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        let pts = coordinates
        let n = pts.count
        var inside = false
        var j = n - 1
        for i in 0 ..< n {
            let xi = pts[i].longitude, yi = pts[i].latitude
            let xj = pts[j].longitude, yj = pts[j].latitude
            let intersect = ((yi > coord.latitude) != (yj > coord.latitude))
                && (coord.longitude < (xj - xi) * (coord.latitude - yi) / (yj - yi) + xi)
            if intersect { inside = !inside }
            j = i
        }
        return inside
    }
}

// MARK: - Map Annotation Item

struct MapAnnotationItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let activity: String
    var coordinate: CLLocationCoordinate2D
    let type: AnnotationType
    var dropDescription: String?
    var scheduledTime: String?
    var participants: [DropParticipant] = []
    var createdAt: Date = Date()
    var maxParticipants: Int = 10
    var durationMinutes: Int = 0       // 0 = kein Limit
    var dropLocationType: LocationType = .current
    var isFuzzy: Bool = false
    var creatorAgeGroup: AgeGroup? = nil
    var creatorAge: Int? = nil
    /// Lesbarer Ort-Titel (z.B. "Odeonsplatz 1, München") — für Live Activity / Karte
    var locationTitle: String = ""
    /// Echter Standort — nur befüllt wenn isFuzzy == true und Join akzeptiert wurde.
    /// Vor Accept immer nil (Joiner sieht nur fuzzy coordinate).
    var realCoordinate: CLLocationCoordinate2D? = nil
    /// Geschlecht des Hosts — für optionalen Geschlechts-Filter ("männlich" | "weiblich" | "divers" | nil)
    var hostGender: String? = nil
    var isBoosted: Bool = false     // Drops+ Boost: goldener Rand auf der Karte
    var isStranger: Bool { type == .stranger }
    var isFull: Bool { participants.count >= maxParticipants }
    var spotsLeft: Int { max(0, maxParticipants - participants.count) }

    /// Ablaufzeitpunkt — spiegelt DropEvent.expiresAt.
    var expiresAt: Date {
        if durationMinutes > 0 {
            return createdAt.addingTimeInterval(Double(durationMinutes) * 60)
        }
        switch scheduledTime ?? "Jetzt" {
        case "Heute Abend":
            var c = Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
            c.hour = 23; c.minute = 59; c.second = 59
            return Calendar.current.date(from: c) ?? createdAt.addingTimeInterval(12 * 60 * 60)
        default:
            return createdAt.addingTimeInterval(12 * 60 * 60)
        }
    }

    var isTimeExpired: Bool { durationMinutes > 0 && Date() > expiresAt }

    /// Verbleibende Zeit als lesbarer String
    var timeRemainingString: String {
        guard durationMinutes > 0 else { return "" }
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 { return "Abgelaufen" }
        let totalMins = max(1, Int(remaining / 60))
        if totalMins >= 60 {
            let h = totalMins / 60
            let m = totalMins % 60
            return m > 0 ? "noch \(h) Std \(m) Min" : "noch \(h) Std"
        }
        return "noch \(totalMins) Min"
    }
    enum AnnotationType { case friend, myDrop, stranger, joiner }

    func distance(from userCoord: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to)
    }

    func isNearby(from userCoord: CLLocationCoordinate2D, maxMeters: Double = 800) -> Bool {
        distance(from: userCoord) <= maxMeters
    }
}

// MARK: - Friend Suggestion

struct FriendSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let mutualFriend: String
    var dismissed = false
}

// MARK: - Emergency Contact


// MARK: - Past Drop (Verlauf)

struct PastDropParticipant: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let reliabilityScore: Int
    var wasHost: Bool = false
    var didShowUp: Bool = true
}

struct PastDrop: Identifiable {
    let id = UUID()
    let activityEmoji: String
    let activityName: String
    let locationName: String
    let date: Date
    let wasHost: Bool
    let participants: [PastDropParticipant]

    var participantCount: Int { participants.count }
    var avgReliability: Int {
        guard !participants.isEmpty else { return 0 }
        return participants.map(\.reliabilityScore).reduce(0, +) / participants.count
    }
    var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "E, d. MMM"
        return df.string(from: date)
    }
    var timeLabel: String {
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    static let demos: [PastDrop] = []
}

// MARK: - Encounter

struct Encounter: Identifiable {
    let id = UUID()
    let friendName: String
    let friendEmoji: String
    let activityEmoji: String
    let activityName: String
    let createdAt: Date
    var confirmed: Bool
    var denied: Bool

    static let confirmationWindow: TimeInterval = 12 * 60 * 60

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > Self.confirmationWindow
    }

    var remainingHours: Int {
        max(0, Int((createdAt.addingTimeInterval(Self.confirmationWindow).timeIntervalSince(Date())) / 3600))
    }

    var remainingMinutes: Int {
        let total = max(0, createdAt.addingTimeInterval(Self.confirmationWindow).timeIntervalSince(Date()))
        return Int((total.truncatingRemainder(dividingBy: 3600)) / 60)
    }

    var timeAgoLabel: String {
        let mins = Int(Date().timeIntervalSince(createdAt) / 60)
        if mins < 60 { return "Vor \(mins) Min" }
        let h = mins / 60
        return h == 1 ? "Vor 1 Std" : "Vor \(h) Std"
    }
}

// MARK: - Age Group

enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case young      = "18–24"
    case twenties   = "25–34"
    case thirties   = "35–44"
    case forties    = "45–59"
    case seniors    = "60–99"

    var id: String { rawValue }
    var label: String { rawValue }

    var systemIcon: String {
        switch self {
        case .young:    return "figure.run"
        case .twenties: return "briefcase.fill"
        case .thirties: return "leaf.fill"
        case .forties:  return "cup.and.saucer.fill"
        case .seniors:  return "star.fill"
        }
    }

    var minAge: Int {
        switch self {
        case .young: return 18; case .twenties: return 25
        case .thirties: return 35; case .forties: return 45; case .seniors: return 60
        }
    }
    var maxAge: Int {
        switch self {
        case .young: return 24; case .twenties: return 34
        case .thirties: return 44; case .forties: return 59; case .seniors: return 99
        }
    }

    /// Feste Farbe pro Altersgruppe — sichtbar auf Karte und in Einstellungen
    var color: Color {
        switch self {
        case .young:    return Color(hex: "22c55e") // grün (brand)
        case .twenties: return Color(hex: "06b6d4") // cyan
        case .thirties: return Color(hex: "f59e0b") // amber
        case .forties:  return Color(hex: "8b5cf6") // violet
        case .seniors:  return Color(hex: "ec4899") // pink
        }
    }

    static func group(for age: Int) -> AgeGroup {
        switch age {
        case 18...24: return .young
        case 25...34: return .twenties
        case 35...44: return .thirties
        case 45...59: return .forties
        default:      return .seniors
        }
    }

    static func defaultVisible(for age: Int) -> [AgeGroup] {
        let own = group(for: age)
        let all = AgeGroup.allCases
        guard let idx = all.firstIndex(of: own) else { return [own] }
        var result: [AgeGroup] = [own]
        if idx > 0             { result.append(all[idx - 1]) }
        if idx < all.count - 1 { result.append(all[idx + 1]) }
        return result
    }
}

// MARK: - Persistence Keys

private enum UDKey {
    static let userName             = "ud_userName"
    static let userEmoji            = "ud_userEmoji"
    static let isUnderageBlocked    = "ud_isUnderageBlocked"
        static let isIdVerified         = "ud_isIdVerified"
    static let userBirthdate        = "ud_userBirthdate"
    static let userGender           = "ud_userGender"
    static let blockedUsers         = "ud_blockedUsers"
    static let selectedAgeGroups    = "ud_ageGroups"
    static let userInterests        = "ud_interests"
    static let radiusFilter         = "ud_radius"
    static let unavailabilityReason = "ud_unavailReason"

    static let wasAgeRestricted     = "ud_wasAgeRestricted"
    static let backgroundedAt       = "ud_backgroundedAt"   // Session-Timeout
    static let reliabilityTotal     = "ud_reliabilityTotal"
    static let reliabilityShows     = "ud_reliabilityShows"
    static let reliabilityNoShows   = "ud_reliabilityNoShows"
    static let firebaseUID          = "ud_firebaseUID"   // Stabile UID für Drop-Filter
    static let appleEmail           = "ud_appleEmail"    // Apple relay E-Mail (nur beim 1. Login verfügbar)
    static let isAdmin              = "ud_isAdmin"       // Admin-Flag lokal cachen
    static let homeZoneLat         = "ud_homeZoneLat"
    static let homeZoneLng         = "ud_homeZoneLng"
    static let homeZoneRadius      = "ud_homeZoneRadius"
    static let userPhone           = "ud_userPhone"
    static let genderFilterEnabled = "ud_gender_filter"
    static let activityCategoryFilter = "ud_activity_category_filter"
    static let ageFilterMin        = "ud_ageFilterMin"
    static let ageFilterMax        = "ud_ageFilterMax"
}

// MARK: - Session Timeout Konfiguration

enum SessionTimeout {
    /// Nach wie vielen Sekunden Hintergrund-Pause die Session abläuft.
    /// Standard: 2 Stunden → Nutzer muss sich nach längerer Inaktivität neu einloggen.
    static let duration: TimeInterval = 2 * 60 * 60
}

// MARK: - Drop Notification Manager

enum DropNotificationManager {

    /// Benachrichtigungs-Berechtigung anfragen
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Plant 3 Erinnerungen vor Ablauf eines Drops (1h, 30min, 10min) + eine bei Ablauf
    static func scheduleExpiryReminders(for drop: MapAnnotationItem) {
        let center = UNUserNotificationCenter.current()
        let dropIDStr = drop.id.uuidString
        let expiresAt = drop.expiresAt

        // Erinnerungen vor Ablauf
        let reminders: [(TimeInterval, String)] = [
            (60 * 60, "⏳ Noch 1 Stunde — dein Drop \"\(drop.activity)\" läuft gleich ab."),
            (30 * 60, "⏰ Noch 30 Minuten — \"\(drop.activity)\" endet bald."),
            (10 * 60, "🔔 Nur noch 10 Minuten! \"\(drop.activity)\" läuft gleich ab.")
        ]

        for (offset, body) in reminders {
            let fireDate = expiresAt.addingTimeInterval(-offset)
            guard fireDate > Date() else { continue }   // Vergangenheit überspringen

            let content = UNMutableNotificationContent()
            content.title = "Drop läuft ab"
            content.body  = body
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(dropIDStr)_\(Int(offset))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        // Benachrichtigung bei Ablauf (nur wenn in der Zukunft)
        guard expiresAt > Date() else { return }
        let expiredContent = UNMutableNotificationContent()
        expiredContent.title = "Drop abgelaufen"
        expiredContent.body  = "🏁 \"\(drop.activity)\" ist abgelaufen."
        expiredContent.sound = .default
        let expComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expiresAt)
        let expTrigger = UNCalendarNotificationTrigger(dateMatching: expComps, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(dropIDStr)_0", content: expiredContent, trigger: expTrigger))
    }

    /// Überladung für DropEvent (beim Erstellen eines eigenen Drops)
    static func scheduleExpiryReminders(for drop: DropEvent) {
        let center = UNUserNotificationCenter.current()
        let dropIDStr = drop.id.uuidString
        let expiresAt = drop.expiresAt

        // Erinnerungen vor Ablauf
        let reminders: [(TimeInterval, String)] = [
            (60 * 60, "⏳ Noch 1 Stunde — dein Drop \"\(drop.activity.name)\" läuft gleich ab."),
            (30 * 60, "⏰ Noch 30 Minuten — \"\(drop.activity.name)\" endet bald."),
            (10 * 60, "🔔 Nur noch 10 Minuten! \"\(drop.activity.name)\" läuft gleich ab.")
        ]

        for (offset, body) in reminders {
            let fireDate = expiresAt.addingTimeInterval(-offset)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Drop läuft ab"
            content.body  = body
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(dropIDStr)_\(Int(offset))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        // Benachrichtigung bei Ablauf — Host: kurze Erinnerung, den Drop zu beenden
        guard expiresAt > Date() else { return }
        let expiredContent = UNMutableNotificationContent()
        expiredContent.title = "Drop abgelaufen"
        expiredContent.body  = "🏁 \"\(drop.activity.name)\" ist abgelaufen. War jemand dabei?"
        expiredContent.sound = .default
        let expComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expiresAt)
        let expTrigger = UNCalendarNotificationTrigger(dateMatching: expComps, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(dropIDStr)_0", content: expiredContent, trigger: expTrigger))
    }

    /// Entfernt alle geplanten Benachrichtigungen für einen Drop (inkl. Ablauf-Benachrichtigung)
    static func cancelReminders(for dropID: UUID) {
        let idStr = dropID.uuidString
        let ids = [3600, 1800, 600, 0].map { "\(idStr)_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - App Store

@MainActor
class AppStore: ObservableObject {
    @Published var isAuthenticated = false
    /// true = App ist gesperrt nach Timeout → Face ID erforderlich, kein Logout
    @Published var isSessionLocked = false

    @Published var currentUser = User(
        name: "Alex", emoji: "😊", isAvailable: false,
        statusMessage: "Tippe um verfügbar zu sein",
        coordinate: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)
    )

    // MARK: - Bluetooth Auto-Confirmation
    /// Erkennt andere Drop-Teilnehmer automatisch via BLE-Proximity.
    /// Treffen werden bestätigt, sobald beide ≥ 20 Sek. in Reichweite waren.
    let bluetoothMeetup = BluetoothMeetupManager()

    @Published var radiusFilter: Double = 2000   // Free-Default: 2km
    @Published var userGender: String = ""   // "männlich" | "weiblich" | "divers"
    @Published var genderFilterEnabled: Bool = false
    /// Aktuelle Aktivitäts-Kategorie im Umgebungs-Tab-Filter. Leer = "Alle".
    /// Gültige Werte: "Kaffee", "Drink", "Sport", "Essen", "Zocken"
    @Published var activityCategoryFilter: String = ""

    // MARK: - Heimzone
    @Published var homeZoneCoordinate: CLLocationCoordinate2D? = nil
    @Published var homeZoneRadius: Double = 150   // Meter: 50–500
    @Published var focusedDropCoordinate: CLLocationCoordinate2D? = nil
    @Published var liveStrangerDrops: [StrangerDropData] = []
    private var dbDropsHandle: DatabaseHandle?

    private let strangerTemplates: [(emoji: String, activity: String, name: String,
                                     participantEmojis: [String], ageGroup: AgeGroup, age: Int)] = [
        // 🎉 Young (18–24) — grün
        ("🎒", "Lernen",       "Lea",    ["📚","🎨"],        .young,    18),
        ("🎮", "Zocken",       "Nico",   ["🎮","😎","🎧"],   .young,    19),
        ("🛹", "Skaten",       "Hanna",  ["🛹","🎵"],        .young,    21),
        ("🧋", "Bubble Tea",   "Finn",   ["🧋","😊"],        .young,    20),

        // 💼 Twenties (25–34) — cyan
        ("☕️", "Kaffee",       "Mia",    ["😊","🎵"],        .twenties, 27),
        ("🍺", "Feierabend",   "Jonas",  ["🎮","🏃"],        .twenties, 27),
        ("🧘", "Yoga",         "Sophie", ["🌿","☕️"],        .twenties, 23),
        ("🏃", "Laufen",       "Lukas",  ["🎧","🌍"],        .twenties, 26),
        ("🎸", "Jam Session",  "Emma",   ["🎵","🎶"],        .twenties, 25),
        ("🍕", "Pizza-Abend",  "Noah",   ["🎮","🍕","😊"],   .twenties, 22),

        // 💼 Thirties (30–39) — amber
        ("🍷", "After Work",   "Anna",   ["🍷","💼"],        .thirties, 33),
        ("🏋️", "Gym",          "Ben",    ["💪","🏃"],        .thirties, 36),
        ("🌿", "Spazieren",    "Julia",  ["🌸","🐕"],        .thirties, 31),
        ("🍜", "Mittagessen",  "Paul",   ["🍜","😊"],        .thirties, 34),

        // 🌿 Forties (40–54) — violet
        ("🧗", "Klettern",     "Stefan", ["🧗","💪"],        .forties,  44),
        ("🎨", "Kunst",        "Petra",  ["🖌️","☕️"],       .forties,  48),
        ("🚴", "Radtour",      "Klaus",  ["🌿","🚴"],        .forties,  51),

        // ☕️ Seniors (55+) — pink
        ("♟️", "Schach",       "Werner", ["♟️","🎯"],        .seniors,  62),
        ("🎭", "Theater",      "Ingrid", ["🎭","🎵"],        .seniors,  58),
        ("🌳", "Spaziergang",  "Horst",  ["🌳","☕️"],       .seniors,  67),
    ]
    private var strangerDropsCache: [MapAnnotationItem] = []
    private var strangerDropsPlaced = false
    private var expiryTimer: Timer?

    @Published var friends: [User] = []

    @Published var activeDrops: [DropEvent] = []
    @Published var selectedTab: Tab = .map
    @Published var pendingDropID: UUID? = nil           // Universal Link → Drop direkt öffnen
    @Published var pendingInviteUsername: String? = nil // Universal Link → Freund hinzufügen
    @Published var selfieImage: UIImage? = nil
    @Published var profileImageURL: String? = nil
    /// Optionale Handynummer für Kontakt-Suche (z.B. "+4915712345678")
    @Published var userPhone: String = ""
    @Published var activeJoinedDropID: UUID? = nil
    /// dropID → Zeitpunkt des Verlassens. Schützt vor Missbrauch durch Re-Join.
    @Published var dropLeaveTimes: [UUID: Date] = [:]
    static let joinCooldown: TimeInterval = 10 * 60   // 10 Minuten
    @Published var activeDropAnnotation: MapAnnotationItem? = nil
    @Published var unavailabilityReason: String = ""
    @Published var userBirthdate: Date? = nil
    @Published var isUnderageBlocked: Bool = false
    @Published var isIdVerified: Bool = false
    @Published var isAdmin: Bool = false

    // MARK: - Drops+
    /// Ground truth kommt von DropsStoreManager — wird beim Start und nach Kauf synchronisiert.
    @Published var isPlusUser: Bool = false
    @Published var showDropsPlusPaywall: Bool = false
    /// Wird auf true gesetzt nach Kauf oder Admin-Freischaltung → MainTabView zeigt Success-Popup
    @Published var showDropsPlusSuccess: Bool = false

    /// Immer aktueller Plus-Status (direkt aus StoreKit — kein Caching-Lag).
    var isDropsPlusActive: Bool {
        isPlusUser || DropsStoreManager.shared.isPlusUser
    }
    /// Wird beim App-Start gehalten damit ARC den Manager nicht sofort freigibt
    private var earlyLocationManager: CLLocationManager?
    @Published var selectedAgeGroups: [AgeGroup] = AgeGroup.allCases
    @Published var ageFilterMin: Int = 18
    @Published var ageFilterMax: Int = 99

    /// Interessen des Nutzers — nur intern für Feed-Priorisierung, nie öffentlich sichtbar.
    @Published var userInterests: [String] = []

    // Drop-Verlauf
    @Published var pastDrops: [PastDrop] = []

    // Wer kommt zu meinen Drops — reine Info für den Host, kein Approval
    @Published var joinRequests: [JoinRequest] = []

    /// Gibt an ob die App gerade im Vordergrund ist (wird von LinkUpApp.swift gesetzt)
    var isAppActive: Bool = true

    /// Eingehende Beitrittsanfragen für den eigenen Drop (Host-Ansicht)
    @Published var pendingJoinRequests: [IncomingJoinRequest] = []
    /// Sheet: aktuell angezeigte Anfrage
    @Published var activeIncomingRequest: IncomingJoinRequest? = nil

    /// Status der eigenen Anfrage als Joiner: "pending" | "accepted" | "declined"
    @Published var myJoinRequestStatus: String = ""

    private var joinRequestObserverHandle: DatabaseHandle?
    private var myJoinStatusObserverHandle: DatabaseHandle?
    private var autoAcceptTimer: Timer?

    // MARK: - Init

    init() {
        // ── Firebase-Session beim App-Start wiederherstellen ──────────────
        // isAuthenticated startet als false. Wenn Firebase einen gültigen User
        // hat UND das Onboarding abgeschlossen wurde, direkt in die App.
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
        if FirebaseAuth.Auth.auth().currentUser != nil && hasOnboarded {
            isAuthenticated = true
            // Firebase UID persistent speichern damit der Drop-Filter auch beim Start funktioniert
            if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                UserDefaults.standard.set(uid, forKey: UDKey.firebaseUID)

                // Im Discovery-Index registrieren (phoneIndex + emailIndex) damit andere uns finden.
                // Bei Apple Sign-In ist FirebaseAuth.phoneNumber = nil — daher Fallback auf die
                // optional hinterlegte Nummer aus UserDefaults (wird beim Onboarding/Settings gespeichert).
                let authPhone  = FirebaseAuth.Auth.auth().currentUser?.phoneNumber
                let savedPhone = UserDefaults.standard.string(forKey: UDKey.userPhone)
                let idxPhone   = (authPhone?.isEmpty == false) ? authPhone : savedPhone
                let idxEmail   = FirebaseAuth.Auth.auth().currentUser?.email
                let savedName  = UserDefaults.standard.string(forKey: UDKey.userName) ?? ""
                let idxName    = savedName.isEmpty ? "Drops-Nutzer" : savedName
                RealtimeDBManager.shared.registerInDiscoveryIndex(
                    uid: uid, name: idxName,
                    phone: idxPhone, email: idxEmail
                )
            }

            // Sofort-Check per Telefon/E-Mail — kein Firebase-Roundtrip nötig
            let adminPhones: Set<String> = ["+4915771677000"]
            let adminEmails: Set<String> = ["dennisone95@hotmail.de", "ww688nmjp8@privaterelay.appleid.com"]
            let authPhone = FirebaseAuth.Auth.auth().currentUser?.phoneNumber ?? ""
            let authEmail = (FirebaseAuth.Auth.auth().currentUser?.email ?? "").lowercased()
            // Apple Relay-Email wird nur beim ersten Login gesendet → aus UserDefaults laden
            let storedAppleEmail = (UserDefaults.standard.string(forKey: UDKey.appleEmail) ?? "").lowercased()
            if adminPhones.contains(authPhone) || adminEmails.contains(authEmail) || adminEmails.contains(storedAppleEmail) {
                isAdmin = true
            }

            // Verwaiste eigene Drops in Firebase aufräumen (z.B. nach App-Crash)
            let cleanupUID = FirebaseAuth.Auth.auth().currentUser?.uid
                ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID) ?? ""
            if !cleanupUID.isEmpty {
                let activeIDs = Set(activeDrops.map { $0.id.uuidString })
                RealtimeDBManager.shared.cleanupOrphanedDrops(ownerUID: cleanupUID, activeDropIDs: activeIDs)
            }

            // Zusätzlich Firebase-Profil laden (Fallback + übrige Felder)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                // Einmalig isAdmin in Firebase schreiben falls Credentials passen aber Flag fehlt
                // (passiert wenn Account vor der Admin-Whitelist-Ergänzung registriert wurde)
                if self.isAdmin, let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                    RealtimeDBManager.shared.ensureAdminFlagInFirebase(uid: uid)
                }
                RealtimeDBManager.shared.loadUserProfile { [weak self] profile in
                    guard let self = self, let p = profile else { return }
                    DispatchQueue.main.async {
                        if p.isAdmin    { self.isAdmin    = true }
                        if p.isPlusUser { self.isPlusUser = true }   // Admin-gewährtes Plus
                        if let name = p.name, !name.isEmpty { self.currentUser.name = name }
                        // profileImageURL kommt aus Firestore (loadProfileImageURL)
                        self.loadProfileImageURL()
                    }
                }
            }
        }

        loadAll()

        // ── Eigene aktive Drops aus Firebase rehydrieren ─────────────────
        // activeDrops und joinRequests werden lokal nicht persistiert, aber nach
        // App-Neustart soll ein noch laufender Drop weiter im „Aktiv"-Tab erscheinen.
        // → Firebase ist die Single Source of Truth, wir laden die eigenen
        // aktiven Drops des Users einmalig zurück in den In-Memory-State.
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            Task { @MainActor in
                let snapshots = await RealtimeDBManager.shared.loadMyActiveDrops(ownerUID: uid)
                for snap in snapshots where !self.activeDrops.contains(where: { $0.id.uuidString == snap.dropID }) {
                    guard let dropUUID = UUID(uuidString: snap.dropID) else { continue }
                    let activity = Activity(id: UUID(), name: snap.activityName, emoji: snap.emoji)
                    let location = DropLocation(
                        title: "Dein aktiver Drop",
                        subtitle: "",
                        coordinate: snap.coordinate,
                        type: .current
                    )
                    let duration = max(0, Int(snap.expiresAt.timeIntervalSince(snap.createdAt) / 60))
                    var drop = DropEvent(
                        id: dropUUID, host: self.currentUser,
                        activity: activity, location: location,
                        participants: [self.currentUser],
                        createdAt: snap.createdAt,
                        dropDescription: "",
                        scheduledTime: snap.scheduledTime,
                        maxParticipants: snap.maxParticipants,
                        durationMinutes: duration
                    )
                    drop.isBoosted = snap.isBoosted
                    self.activeDrops.append(drop)
                    DropNotificationManager.scheduleExpiryReminders(for: drop)
                    self.startObservingDropIns(forDropID: snap.dropID)
                    self.startObservingJoinRequests(forDropID: snap.dropID)
                }
            }
        }

        // ── Veraltete Drop-Benachrichtigungen aus vorherigen Sessions löschen ─
        // Alte UNCalendarNotificationTrigger würden sonst feuern; neue werden nach
        // der Rehydration oben bzw. bei createDrop/joinDrop neu eingeplant.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        // ── Verwaiste Dynamic Island Live Activities aus früheren Sessions beenden ─
        // currentLiveActivity ist bei einem Neustart immer nil (in-memory).
        // ActivityKit hält aber laufende Activities über App-Neustarts hinweg am Leben.
        // → alle Activities dieses Typs sofort beenden, neue werden erst beim createDrop / joinDrop gestartet.
        Task {
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
        }

        startExpiryTimer()

        // ── Drops+ Entitlements prüfen ────────────────────────────────────
        Task {
            await DropsStoreManager.shared.refreshEntitlements()
            self.isPlusUser = DropsStoreManager.shared.isPlusUser
        }

        // ── Drops+ Status live synchronisieren (nach Kauf / Widerruf / Restore) ──
        NotificationCenter.default.addObserver(
            forName: .dropsPlusStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isPlus = notification.userInfo?["isPlus"] as? Bool
            else { return }
            self.isPlusUser = isPlus
        }

        // Benachrichtigungs-Berechtigung wird NICHT sofort angefragt —
        // das passiert beim ersten Drop-Erstellen (createDrop) oder wenn der Nutzer
        // Benachrichtigungen in den Einstellungen aktiviert.
        // Standort-Berechtigung früh anfragen (bevor LiveMapView geladen wird)
        let locMgr = CLLocationManager()
        earlyLocationManager = locMgr
        if locMgr.authorizationStatus == .notDetermined {
            locMgr.requestWhenInUseAuthorization()
        }
        // Abgelaufene Begegnungen ohne Bestätigung → No-Show werten
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.processExpiredEncounters()
        }

        // Auth-Listener: reagiert auf Logout/Token-Ablauf zur Laufzeit
        FirebaseAuth.Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                let onboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
                if user == nil && onboarded {
                    // User wurde extern ausgeloggt oder Token ungültig
                    self?.isAuthenticated = false
                }
                // Einloggen (user != nil) wird nur über den Onboarding-Flow
                // getriggert — kein automatisches isAuthenticated = true hier,
                // da sonst ein anonymer Firebase-User die App öffnet.
            }
        }
    }

    // MARK: - Session Timeout

    /// Wird beim App-Wechsel in den Hintergrund aufgerufen — speichert den Zeitstempel.
    func recordBackgrounded() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate,
                                  forKey: UDKey.backgroundedAt)
    }

    /// Wird beim App-Rückkehr in den Vordergrund aufgerufen.
    /// Wenn die Pause länger als `SessionTimeout.duration` war → ausloggen.
    func checkSessionTimeout() {
        let ud = UserDefaults.standard
        guard isAuthenticated,
              let ts = ud.object(forKey: UDKey.backgroundedAt) as? Double
        else {
            // Auch ohne Timeout: Firebase-Konto prüfen (z.B. extern gelöscht)
            validateFirebaseAccount()
            return
        }

        let elapsed = Date().timeIntervalSinceReferenceDate - ts
        if elapsed > SessionTimeout.duration {
            // Nicht ausloggen — stattdessen sperren und Face ID anfordern
            isSessionLocked = true
        }
        ud.removeObject(forKey: UDKey.backgroundedAt)
    }

    /// Prüft ob der Firebase-Account noch existiert (z.B. nach externer Löschung).
    /// Falls nicht → lokal ausloggen.
    private func validateFirebaseAccount() {
        guard let user = FirebaseAuth.Auth.auth().currentUser else { return }
        user.reload { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let nsError = error as? NSError {
                    let code = FirebaseAuth.AuthErrorCode(rawValue: nsError.code)
                    // Nur bei eindeutiger Konto-Löschung/-Sperrung ausloggen.
                    // userTokenExpired: Firebase erneuert Token selbst — kein Logout bei Netzwerkproblemen.
                    if code == .userNotFound || code == .userDisabled {
                        // Konto wurde extern gelöscht oder deaktiviert
                        self.clearLocalData()
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private var selfieURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drops_selfie.jpg")
    }

    /// Löscht das Konto: alle persönlichen Daten aus RTDB/Firestore/Storage + Indizes
    /// werden entfernt, der User wird ausgeloggt. Der Firebase-Auth-Account bleibt als
    /// technische Hülle bestehen (enthält keine PII) und wird mit einem `deletedAt`-
    /// Marker versehen. Meldet sich der User erneut mit derselben Apple-ID an, erkennt
    /// `handlePostLoginResurrection()` den Marker und startet das Onboarding von vorn
    /// — aus User-Sicht wie ein komplett neues Konto.
    ///
    /// Dieser Ansatz vermeidet den Apple-Reauth-Sheet (den Firebase bei `user.delete()`
    /// für Apple-Sign-In-User erzwingen würde) und ist DSGVO-konform: alle PII sind
    /// aus allen Stores weg.
    func deleteAccount(completion: @escaping (String?) -> Void = { _ in }) {
        guard let user = FirebaseAuth.Auth.auth().currentUser else {
            print("[deleteAccount] Kein currentUser — nur lokaler Cleanup")
            clearLocalData()
            completion(nil)
            return
        }

        let uid = user.uid
        print("[deleteAccount] Start uid=\(uid)")

        Task { @MainActor in
            // 1. Alle persönlichen Daten aus Firebase entfernen (Direktpfade, 10s Timeout)
            print("[deleteAccount] Schritt 1: Firebase-Daten löschen…")
            await Self.withTimeout(seconds: 10) {
                await RealtimeDBManager.shared.deleteUserData(uid: uid)
            }
            print("[deleteAccount] Schritt 1 ✓")

            // 2. Tombstone setzen, damit ein Wiederlogin mit derselben Apple-ID
            //    als Neuregistrierung behandelt wird (siehe handlePostLoginResurrection).
            print("[deleteAccount] Schritt 2: Tombstone setzen…")
            await Self.withTimeout(seconds: 5) {
                await RealtimeDBManager.shared.markAccountDeleted(uid: uid)
            }
            print("[deleteAccount] Schritt 2 ✓")

            // 3. Lokale Daten + Logout
            print("[deleteAccount] Schritt 3: Lokale Daten + Logout…")
            UserDefaults.standard.removeObject(forKey: "hasOnboarded")
            self.clearLocalData()
            print("[deleteAccount] Fertig — isAuthenticated=\(self.isAuthenticated)")

            completion(nil)
        }
    }

    /// Führt eine Void-async-Operation aus und bricht nach `seconds` ab.
    /// WICHTIG: Nutzt Task.detached + NSLock statt withTaskGroup, weil
    /// withTaskGroup auf ALLE Child-Tasks wartet (auch gecancelte). Firebase-
    /// Async-APIs reagieren nicht auf Cancellation → würden sonst ewig hängen.
    /// Mit diesem Pattern geht's weiter sobald Timer ODER Operation fertig ist.
    private static func withTimeout(seconds: Int, operation: @escaping @Sendable () async -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let state = TimeoutGuard()
            Task.detached {
                await operation()
                state.resume { cont.resume() }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                state.resume { cont.resume() }
            }
        }
    }

    /// Wie `withTimeout`, aber gibt das Operation-Ergebnis zurück (oder Fallback bei Timeout).
    private static func withTimeoutReturning<T: Sendable>(
        seconds: Int, fallback: T,
        operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            let state = TimeoutGuard()
            Task.detached {
                let result = await operation()
                state.resume { cont.resume(returning: result) }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                state.resume { cont.resume(returning: fallback) }
            }
        }
    }

    /// Meldet den User ab und löscht alle lokalen Daten.
    func logout() {
        clearLocalData()
    }

    /// Löscht alle lokalen Daten und meldet den User aus.
    func clearLocalData() {
        // ── 1. UserDefaults leeren ────────────────────────────────────────
        let ud = UserDefaults.standard
        let allKeys = [
            UDKey.userName, UDKey.userEmoji,
            UDKey.isUnderageBlocked, UDKey.userBirthdate,
            UDKey.userGender, UDKey.blockedUsers,
            UDKey.selectedAgeGroups, UDKey.userInterests, UDKey.radiusFilter,
            UDKey.unavailabilityReason, UDKey.wasAgeRestricted,
            UDKey.reliabilityTotal, UDKey.reliabilityShows, UDKey.reliabilityNoShows,
            UDKey.firebaseUID, UDKey.appleEmail, UDKey.isAdmin
        ]
        allKeys.forEach { ud.removeObject(forKey: $0) }
        // WICHTIG: hasOnboarded und Quick-Login-Daten NICHT löschen.
        // So sieht der User nach Session-Timeout den Login-Screen (nicht das Voll-Onboarding).
        // mapStyleMode und prefersDarkOnboarding sind harmlose UI-Präferenzen → auch behalten.
        // Nur wirklich sensitives löschen:
        ud.removeObject(forKey: "savedPhoneNumber")
        ud.removeObject(forKey: "savedPhoneDialCode")

        // ── 2. Selfie-Datei löschen ───────────────────────────────────────
        try? FileManager.default.removeItem(at: selfieURL)

        // ── 3. In-Memory-State zurücksetzen ───────────────────────────────
        // Wichtig: AppStore-Instanz bleibt beim Account-Wechsel dieselbe,
        // daher müssen alle @Published-Werte explizit zurückgesetzt werden.
        currentUser.name          = ""
        currentUser.emoji         = "😊"
        currentUser.isAvailable   = false
        currentUser.statusMessage = "Tippe um verfügbar zu sein"
        selfieImage               = nil
        userBirthdate             = nil
        isAdmin                   = false
        isIdVerified              = false
        isUnderageBlocked         = false
        userGender                = ""
        blockedUserNames          = []
        selectedAgeGroups         = AgeGroup.allCases
        ageFilterMin              = 18
        ageFilterMax              = 99
        userInterests             = []
        radiusFilter              = 2000
        unavailabilityReason      = ""
        reliabilityScore          = ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0)
        activeDrops               = []
        homeZoneCoordinate        = nil
        homeZoneRadius            = 150
        profileImageURL           = nil
        geocodedDropLocationTitle = ""
        ud.removeObject(forKey: UDKey.homeZoneLat)
        ud.removeObject(forKey: UDKey.homeZoneLng)
        ud.removeObject(forKey: UDKey.homeZoneRadius)

        // ── 4. Dynamic Island beenden ─────────────────────────────────────
        endDropLiveActivity()

        // ── 5. Firebase ausloggen + Session beenden ───────────────────────
        try? FirebaseAuth.Auth.auth().signOut()
        isAuthenticated = false
    }

    func saveAll() {
        let ud = UserDefaults.standard
        ud.set(currentUser.name,  forKey: UDKey.userName)
        ud.set(currentUser.emoji, forKey: UDKey.userEmoji)
        if isAdmin { ud.set(true, forKey: UDKey.isAdmin) }  // Admin-Flag cachen
        ud.set(isUnderageBlocked, forKey: UDKey.isUnderageBlocked)
        ud.set(isIdVerified,      forKey: UDKey.isIdVerified)
        if let bd = userBirthdate {
            ud.set(bd.timeIntervalSinceReferenceDate, forKey: UDKey.userBirthdate)
        } else {
            ud.removeObject(forKey: UDKey.userBirthdate)
        }
        ud.set(userGender,           forKey: UDKey.userGender)
        ud.set(userPhone,            forKey: UDKey.userPhone)
        ud.set(genderFilterEnabled,  forKey: UDKey.genderFilterEnabled)
        ud.set(activityCategoryFilter, forKey: UDKey.activityCategoryFilter)
        ud.set(Array(blockedUserNames),                       forKey: UDKey.blockedUsers)
        ud.set(selectedAgeGroups.map { $0.rawValue },         forKey: UDKey.selectedAgeGroups)
        ud.set(ageFilterMin, forKey: UDKey.ageFilterMin)
        ud.set(ageFilterMax, forKey: UDKey.ageFilterMax)
        ud.set(userInterests,                                  forKey: UDKey.userInterests)
        ud.set(radiusFilter,                                  forKey: UDKey.radiusFilter)
        ud.set(unavailabilityReason,                          forKey: UDKey.unavailabilityReason)
        if let hz = homeZoneCoordinate {
            ud.set(hz.latitude,  forKey: UDKey.homeZoneLat)
            ud.set(hz.longitude, forKey: UDKey.homeZoneLng)
        } else {
            ud.removeObject(forKey: UDKey.homeZoneLat)
            ud.removeObject(forKey: UDKey.homeZoneLng)
        }
        ud.set(homeZoneRadius, forKey: UDKey.homeZoneRadius)
        ud.set(isAgeRestricted, forKey: UDKey.wasAgeRestricted)
        ud.set(reliabilityScore.totalCommits, forKey: UDKey.reliabilityTotal)
        ud.set(reliabilityScore.showUps,      forKey: UDKey.reliabilityShows)
        ud.set(reliabilityScore.noShows,      forKey: UDKey.reliabilityNoShows)
        saveSelfie()
    }

    /// Schreibt den aktuellen Zuverlässigkeits-Score in Firestore,
    /// damit andere User den echten Wert sehen können.
    private func pushReliabilityScoreToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .setData([
                "reliabilityTotal":  reliabilityScore.totalCommits,
                "reliabilityShows":  reliabilityScore.showUps,
                "reliabilityNoShows": reliabilityScore.noShows
            ], merge: true)
    }

    func saveSelfie() {
        guard let img = selfieImage,
              let data = img.jpegData(compressionQuality: 0.75) else { return }
        // 1. Lokal speichern
        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drops_selfie.jpg")
        try? data.write(to: localURL)
        // 2. Firebase Storage Upload → URL in Firestore speichern
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        ref.putData(data, metadata: meta) { [weak self] _, error in
            guard error == nil else { return }
            ref.downloadURL { url, error in
                guard let self = self, let url = url, error == nil else { return }
                let urlString = url.absoluteString
                // Firestore: users/{uid} → profileImageURL
                Firestore.firestore()
                    .collection("users").document(uid)
                    .setData(["profileImageURL": urlString], merge: true)
                DispatchQueue.main.async {
                    self.profileImageURL = urlString
                }
            }
        }
    }

    func loadProfileImageURL() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .getDocument { [weak self] snapshot, _ in
                guard let self = self else { return }
                let data = snapshot?.data()
                if let url = data?["profileImageURL"] as? String {
                    DispatchQueue.main.async { self.profileImageURL = url }
                }
                if let phone = data?["phoneNumber"] as? String, !phone.isEmpty {
                    DispatchQueue.main.async {
                        self.userPhone = phone
                        UserDefaults.standard.set(phone, forKey: UDKey.userPhone)
                    }
                }
            }
    }

    /// Speichert die optionale Handynummer in Firestore (Persistenz) UND aktualisiert
    /// den phoneIndex in Realtime DB (für Kontakt-Matching durch andere User).
    /// Bei leerer Nummer wird der Index-Eintrag entfernt.
    func saveUserPhone(_ phone: String) {
        let oldPhone = userPhone
        userPhone = phone
        UserDefaults.standard.set(phone, forKey: UDKey.userPhone)

        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Firestore: Persistenz fürs Profil
        let value: Any = phone.isEmpty ? NSNull() : phone
        Firestore.firestore()
            .collection("users").document(uid)
            .setData(["phoneNumber": value], merge: true)

        // Realtime DB: phoneIndex für Discovery — alte Nummer räumen, neue eintragen
        let indexName = currentUser.name.isEmpty ? "Drops-Nutzer" : currentUser.name
        RealtimeDBManager.shared.updatePhoneDiscoveryIndex(
            uid: uid, name: indexName, oldPhone: oldPhone, newPhone: phone
        )
    }

    private func loadAll() {
        let ud = UserDefaults.standard
        if let name = ud.string(forKey: UDKey.userName), !name.isEmpty  { currentUser.name  = name }
        if let emoji = ud.string(forKey: UDKey.userEmoji), !emoji.isEmpty { currentUser.emoji = emoji }
        isUnderageBlocked = ud.bool(forKey: UDKey.isUnderageBlocked)
        isIdVerified      = ud.bool(forKey: UDKey.isIdVerified)
        if ud.bool(forKey: UDKey.isAdmin) { isAdmin = true }  // gecachtes Admin-Flag laden
        if let ti = ud.object(forKey: UDKey.userBirthdate) as? Double {
            userBirthdate = Date(timeIntervalSinceReferenceDate: ti)
        }
        userGender          = ud.string(forKey: UDKey.userGender) ?? ""
        userPhone           = ud.string(forKey: UDKey.userPhone)  ?? ""
        genderFilterEnabled = ud.bool(forKey: UDKey.genderFilterEnabled)
        activityCategoryFilter = ud.string(forKey: UDKey.activityCategoryFilter) ?? ""
        if let blocked = ud.stringArray(forKey: UDKey.blockedUsers) {
            blockedUserNames = Set(blocked)
        }
        if let groups = ud.stringArray(forKey: UDKey.selectedAgeGroups), !groups.isEmpty {
            let parsed = groups.compactMap { AgeGroup(rawValue: $0) }
            selectedAgeGroups = parsed.isEmpty ? AgeGroup.allCases : parsed
        }
        if let interests = ud.stringArray(forKey: UDKey.userInterests) {
            userInterests = interests
        }
        if ud.object(forKey: UDKey.ageFilterMin) != nil {
            ageFilterMin = ud.integer(forKey: UDKey.ageFilterMin)
        }
        if ud.object(forKey: UDKey.ageFilterMax) != nil {
            let saved = ud.integer(forKey: UDKey.ageFilterMax)
            ageFilterMax = saved > 0 ? saved : 99
        }
        // Auto-Unlock: War vorher unter 18, ist jetzt 18+ → Altersgruppen freischalten
        let wasRestricted = ud.bool(forKey: UDKey.wasAgeRestricted)
        if wasRestricted && !isAgeRestricted, let age = userAge {
            selectedAgeGroups = AgeGroup.defaultVisible(for: age)
        }
        // Mindestalter 18 — keine Einschränkung mehr nötig
        let radius = ud.double(forKey: UDKey.radiusFilter)
        if radius > 0 { radiusFilter = radius }
        unavailabilityReason = ud.string(forKey: UDKey.unavailabilityReason) ?? ""
        let hzLat = ud.double(forKey: UDKey.homeZoneLat)
        let hzLng = ud.double(forKey: UDKey.homeZoneLng)
        if hzLat != 0 || hzLng != 0 {
            homeZoneCoordinate = CLLocationCoordinate2D(latitude: hzLat, longitude: hzLng)
        }
        let hzRadius = ud.double(forKey: UDKey.homeZoneRadius)
        if hzRadius > 0 { homeZoneRadius = hzRadius }
        // Zuverlässigkeitsscore laden — nur wenn schon Daten gespeichert sind
        let savedTotal = ud.integer(forKey: UDKey.reliabilityTotal)
        let savedShows = ud.integer(forKey: UDKey.reliabilityShows)
        let savedNoShows = ud.integer(forKey: UDKey.reliabilityNoShows)
        // integer(forKey:) gibt 0 zurück wenn der Key nicht existiert —
        // das ist korrekt: neue User starten bei 0/0/0
        if ud.object(forKey: UDKey.reliabilityTotal) != nil {
            reliabilityScore = ReliabilityScore(
                totalCommits: savedTotal,
                showUps:      savedShows,
                noShows:      savedNoShows
            )
        }
        // Selfie vom Disk laden
        if let data = try? Data(contentsOf: selfieURL),
           let img = UIImage(data: data) {
            selfieImage = img
        }
    }

    // MARK: - Drop Expiry Timer

    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanExpiredDrops()
            }
        }
    }

    private func cleanExpiredDrops() {
        let expired = activeDrops.filter { $0.isExpired }
        guard !expired.isEmpty else { return }

        for drop in expired {
            DropNotificationManager.cancelReminders(for: drop.id)
            // Drop aus Firebase entfernen → für neue User unsichtbar.
            // Der Drop bleibt in activeDrops und die Live Activity läuft weiter —
            // der Host sieht noch wer vor Ort ist und beendet manuell.
            RealtimeDBManager.shared.unpublishDrop(dropID: drop.id.uuidString)
        }
        // Drops bleiben in activeDrops (isExpired == true), werden im UI als
        // "abgelaufen" markiert. cancelDrop() entfernt sie dann sauber.
        saveAll()
    }

    // MARK: - Drop Join (sofort, kein Approval)

    /// Wer bei einem Drop vorbeischaut (für Host-Anzeige)
    var activeJoinNotifications: [JoinRequest] {
        joinRequests.filter { !$0.isExpired }
    }

    /// Direkt beitreten — kein Warten auf Bestätigung.
    /// Gibt `false` zurück wenn Cooldown noch aktiv oder User bereits in einem anderen Drop ist.
    @discardableResult
    func joinDrop(_ drop: MapAnnotationItem) -> Bool {
        // Kein Beitritt wenn eigener Drop aktiv oder bereits einem anderen beigetreten
        guard !isInActiveDrop else { return false }
        guard !hasJoinedDrop(dropID: drop.id) else { return false }
        // Cooldown prüfen: nach Verlassen 10 Min sperren
        if let leftAt = dropLeaveTimes[drop.id],
           Date().timeIntervalSince(leftAt) < AppStore.joinCooldown {
            return false
        }
        let note = JoinRequest(
            id: UUID(), dropID: drop.id,
            dropEmoji: drop.emoji, dropActivity: drop.activity,
            requesterName: currentUser.name, requesterEmoji: currentUser.emoji,
            createdAt: Date(),
            dropCoordinate: drop.coordinate
        )
        joinRequests.append(note)
        activeDropAnnotation = drop
        setActiveJoin(drop.id)
        DropNotificationManager.scheduleExpiryReminders(for: drop)
        startDropLiveActivity(annotation: drop, isHost: false)
        Task { @MainActor in PushNotificationManager.shared.trackAction() }

        // ── Firebase: DropIn schreiben + Host benachrichtigen ──────────
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString
        RealtimeDBManager.shared.joinDrop(
            dropID: drop.id.uuidString,
            joinerID: uid,
            joinerName: currentUser.name,
            joinerEmoji: currentUser.emoji
        )
        // Auf DropIns des Hosts hören (falls der Host derselbe User auf anderem Gerät ist – Schutz)
        startObservingDropIns(forDropID: drop.id.uuidString)
        return true
    }

    func hasJoinedDrop(dropID: UUID) -> Bool {
        joinRequests.contains { $0.dropID == dropID && !$0.isExpired }
    }

    /// Verbleibende Cooldown-Sekunden für einen Drop (0 wenn frei).
    func joinCooldownRemaining(dropID: UUID) -> TimeInterval {
        guard let leftAt = dropLeaveTimes[dropID] else { return 0 }
        let remaining = AppStore.joinCooldown - Date().timeIntervalSince(leftAt)
        return max(0, remaining)
    }

    func leaveDropJoin(dropID: UUID) {
        // Score-Abzug nur im kritischen Fenster: 12–30 Min.
        // < 12 Min → noch schnell umentschieden, bevor jemand wirklich unterwegs ist → kein Abzug
        // 12–30 Min → die andere Person ist wahrscheinlich schon auf dem Weg → No-Show
        // > 30 Min → ausreichend teilgenommen → kein Abzug
        if let req = joinRequests.first(where: { $0.dropID == dropID }) {
            let elapsed = Date().timeIntervalSince(req.createdAt)
            if elapsed >= 12 * 60 && elapsed < 30 * 60 {
                reliabilityScore.totalCommits += 1
                if !isDropsPlusActive {
                    reliabilityScore.noShows += 1   // Mitten drin abgebrochen = No-Show
                }                                   // Drops+: kein Abzug
                saveAll()                           // Score lokal persistieren
                pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
            }
        }
        joinRequests.removeAll { $0.dropID == dropID }
        if activeJoinedDropID == dropID { leaveActiveJoin() }
        DropNotificationManager.cancelReminders(for: dropID)
        endDropLiveActivity()
        // Cooldown starten
        dropLeaveTimes[dropID] = Date()
    }

    // MARK: - Age Groups

    var userAgeGroup: AgeGroup? {
        guard let age = userAge else { return nil }
        return AgeGroup.group(for: age)
    }

    /// Mindestalter 18 — keine Alterseinschränkung mehr
    var isAgeRestricted: Bool { false }

    func applyDefaultAgeGroups() {
        guard let age = userAge else { return }
        selectedAgeGroups = AgeGroup.defaultVisible(for: age)
        saveAll()
    }

    @Published var friendSuggestions: [FriendSuggestion] = []

    var userAge: Int? {
        guard let bd = userBirthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: bd, to: Date()).year
    }

    func enforceAgeGuard() {
        if let age = userAge, age < 18 {
            isUnderageBlocked = true
            saveAll()
        }
    }

    // MARK: - Block

    @Published var blockedUserNames: Set<String> = []

    func blockUser(name: String) {
        guard name != currentUser.name else { return }
        blockedUserNames.insert(name)
        strangerDropsCache.removeAll { $0.name == name }
        saveAll()
    }

    // MARK: - Encounters

    @Published var encounters: [Encounter] = []

    var pendingEncounters: [Encounter] {
        encounters.filter { !$0.confirmed && !$0.denied && !$0.isExpired }
    }

    func confirmEncounter(id: UUID) {
        if let i = encounters.firstIndex(where: { $0.id == id }) {
            encounters[i].confirmed = true
            generateFriendSuggestions(from: encounters[i])
            // Bestätigung → ShowUp zählt positiv
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            saveAll()                           // Score lokal persistieren
            pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
        }
    }

    func denyEncounter(id: UUID) {
        if let i = encounters.firstIndex(where: { $0.id == id }) {
            encounters[i].denied = true
            // Ablehnung des anderen → kein Score-Einfluss auf eigenen Score
        }
    }

    /// Abgelaufene Encounters ohne Bestätigung als No-Show werten.
    /// Sollte beim App-Start und beim Tab-Wechsel aufgerufen werden.
    func processExpiredEncounters() {
        var changed = false
        for i in encounters.indices {
            let e = encounters[i]
            guard !e.confirmed && !e.denied && e.isExpired else { continue }
            // Als nicht erschienen markieren
            encounters[i].denied = true
            reliabilityScore.totalCommits += 1
            if !isDropsPlusActive {
                reliabilityScore.noShows += 1   // Drops+: kein Abzug
            }
            changed = true
        }
        if changed {
            saveAll()                           // Score lokal persistieren
            pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
        }
    }

    var isInActiveDrop: Bool {
        // Eigener Drop aktiv ODER direkt beigetreten (kein Approval nötig)
        !activeDrops.isEmpty || activeJoinedDropID != nil
    }

    /// Annotation für den aktuell aktiven Drop (eigener oder beigetretener).
    var currentActiveAnnotation: MapAnnotationItem? {
        if !activeDrops.isEmpty {
            return allMapAnnotations.first { $0.type == .myDrop }
        }
        return activeDropAnnotation
    }

    /// Ob BLE in der aktuellen Drop-Session eine Begegnung bestätigt hat.
    private var bleConfirmedInCurrentSession = false
    /// Zeitpunkt des Beitritts für Mindestzeit-Prüfung beim No-Show.
    private var joinSessionStartedAt: Date? = nil
    /// Drop-Standort der aktuellen Session (für GPS-Fallback).
    private var joinSessionDropCoord: CLLocationCoordinate2D? = nil

    /// Firebase-Handle für den DropIn-Observer (Host-Seite).
    private var dropInObserverHandle: DatabaseHandle? = nil
    private var dropInObservedDropID: String? = nil

    // MARK: - DropIn Observer

    /// Startet den Firebase-Observer für eingehende DropIns (Host-Seite).
    /// Feuert eine lokale Push-Benachrichtigung wenn jemand beitritt.
    func startObservingDropIns(forDropID dropID: String) {
        // Alten Observer sauber abmelden
        stopObservingDropIns()
        dropInObservedDropID = dropID
        // Kleines Delay damit der eigene joinDrop-Write nicht sofort als "neuer" DropIn gewertet wird
        let activityName = activeDrops.first?.activity.name
            ?? activeDropAnnotation?.activity
            ?? "Drop"
        dropInObserverHandle = RealtimeDBManager.shared.observeDropIns(dropID: dropID) { [weak self] name, emoji in
            guard let self = self else { return }
            // Nur den Host benachrichtigen — Joiner sollen keine eigene Notification bekommen
            guard !self.activeDrops.isEmpty else { return }
            PushNotificationManager.shared.notifyDropIn(joinerName: "\(emoji) \(name)".trimmingCharacters(in: .whitespaces),
                                                         activityName: activityName)
            // Live-Activity aktualisieren damit der neue Teilnehmer erscheint
            self.refreshLiveActivityParticipants()
        }
    }

    func stopObservingDropIns() {
        if let handle = dropInObserverHandle, let dropID = dropInObservedDropID {
            RealtimeDBManager.shared.removeDropInObserver(handle, dropID: dropID)
        }
        dropInObserverHandle = nil
        dropInObservedDropID = nil
    }

    // MARK: - Join Request Flow (Host-Seite)

    func startObservingJoinRequests(forDropID dropID: String) {
        stopObservingJoinRequests()
        joinRequestObserverHandle = RealtimeDBManager.shared.observeIncomingJoinRequests(
            dropID: dropID
        ) { [weak self] joinerID, name, emoji, imageURL, requestedAt in
            guard let self = self else { return }
            // Keine doppelten Einträge
            guard !self.pendingJoinRequests.contains(where: { $0.id == joinerID }) else { return }
            let req = IncomingJoinRequest(
                id: joinerID, dropID: dropID,
                joinerName: name, joinerEmoji: emoji,
                joinerProfileImageURL: imageURL,
                requestedAt: requestedAt
            )
            self.pendingJoinRequests.append(req)

            // App aktiv → Sheet zeigen; sonst Push
            if self.isAppActive {
                if self.activeIncomingRequest == nil {
                    self.activeIncomingRequest = req
                }
            } else {
                PushNotificationManager.shared.notifyIncomingJoinRequest(
                    joinerName: "\(emoji) \(name)",
                    activityName: self.activeDrops.first?.activity.name ?? "Drop"
                )
            }

            // Auto-Accept-Timer starten
            self.scheduleAutoAccept(for: req)
        }
    }

    func stopObservingJoinRequests() {
        autoAcceptTimer?.invalidate()
        autoAcceptTimer = nil
        if let handle = joinRequestObserverHandle,
           let dropID = activeDrops.first?.id.uuidString {
            RealtimeDBManager.shared.removeJoinRequestObserver(handle, dropID: dropID)
        }
        joinRequestObserverHandle = nil
        pendingJoinRequests.removeAll()
        activeIncomingRequest = nil
    }

    func acceptJoinRequest(_ req: IncomingJoinRequest) {
        RealtimeDBManager.shared.respondToJoinRequest(
            dropID: req.dropID, joinerID: req.id, accepted: true)
        removePendingRequest(req)
        refreshLiveActivityParticipants()
    }

    func declineJoinRequest(_ req: IncomingJoinRequest) {
        RealtimeDBManager.shared.respondToJoinRequest(
            dropID: req.dropID, joinerID: req.id, accepted: false)
        removePendingRequest(req)
    }

    private func removePendingRequest(_ req: IncomingJoinRequest) {
        pendingJoinRequests.removeAll { $0.id == req.id }
        if activeIncomingRequest?.id == req.id {
            activeIncomingRequest = pendingJoinRequests.first
        }
    }

    private func scheduleAutoAccept(for req: IncomingJoinRequest) {
        let delay = req.autoAcceptAt.timeIntervalSinceNow
        let safeDelay = max(1, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + safeDelay) { [weak self] in
            guard let self = self,
                  self.pendingJoinRequests.contains(where: { $0.id == req.id })
            else { return }
            // Noch nicht beantwortet → Auto-Accept
            self.acceptJoinRequest(req)
            PushNotificationManager.shared.notifyAutoAccepted(
                joinerName: req.joinerName,
                activityName: self.activeDrops.first?.activity.name ?? "Drop"
            )
        }
    }

    // MARK: - Join Request Flow (Joiner-Seite)

    func sendJoinRequest(to drop: MapAnnotationItem) {
        guard !isInActiveDrop else { return }
        guard !hasJoinedDrop(dropID: drop.id) else { return }
        if let leftAt = dropLeaveTimes[drop.id],
           Date().timeIntervalSince(leftAt) < AppStore.joinCooldown { return }

        myJoinRequestStatus = "pending"
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString

        // Anfrage senden
        RealtimeDBManager.shared.sendJoinRequest(
            dropID: drop.id.uuidString,
            joinerID: uid,
            joinerName: currentUser.name,
            joinerEmoji: currentUser.emoji,
            profileImageURL: profileImageURL
        )

        // Status beobachten
        myJoinStatusObserverHandle = RealtimeDBManager.shared.observeMyJoinRequestStatus(
            dropID: drop.id.uuidString, joinerID: uid
        ) { [weak self] status in
            guard let self = self else { return }
            self.myJoinRequestStatus = status
            switch status {
            case "accepted":
                // Jetzt tatsächlich joinen
                self.completeJoin(drop: drop)
            case "declined":
                self.myJoinRequestStatus = "declined"
                // Nach 3 Sek zurücksetzen
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.myJoinRequestStatus = ""
                }
            default: break
            }
        }

        // Live Activity & Annotation merken
        activeDropAnnotation = drop
        Task { @MainActor in PushNotificationManager.shared.trackAction() }
    }

    /// Wird aufgerufen wenn Host akzeptiert hat — eigentlicher Join.
    /// Nach Accept: echte Koordinate (realCoordinate) verwenden statt fuzzy.
    private func completeJoin(drop: MapAnnotationItem) {
        if let handle = myJoinStatusObserverHandle {
            let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString
            RealtimeDBManager.shared.removeJoinRequestObserver(handle, dropID: drop.id.uuidString)
            myJoinStatusObserverHandle = nil
        }
        myJoinRequestStatus = ""

        // Nach Accept: echten Standort nutzen
        let exactCoord = drop.realCoordinate ?? drop.coordinate
        var resolvedDrop = drop
        resolvedDrop.coordinate = exactCoord
        resolvedDrop.isFuzzy    = false
        resolvedDrop.realCoordinate = nil

        let note = JoinRequest(
            id: UUID(), dropID: drop.id,
            dropEmoji: drop.emoji, dropActivity: drop.activity,
            requesterName: currentUser.name, requesterEmoji: currentUser.emoji,
            createdAt: Date(), dropCoordinate: exactCoord
        )
        joinRequests.append(note)
        setActiveJoin(drop.id)
        DropNotificationManager.scheduleExpiryReminders(for: resolvedDrop)
        startDropLiveActivity(annotation: resolvedDrop, isHost: false)
        RealtimeDBManager.shared.joinDrop(
            dropID: drop.id.uuidString,
            joinerID: FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString,
            joinerName: currentUser.name, joinerEmoji: currentUser.emoji
        )
    }

    func setActiveJoin(_ id: UUID) {
        activeJoinedDropID = id
        bleConfirmedInCurrentSession = false
        joinSessionStartedAt = Date()
        // Drop-Koordinate für GPS-Fallback merken
        joinSessionDropCoord = activeDropAnnotation?.coordinate

        // BLE-Proximity starten
        let myToken  = String(currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        bluetoothMeetup.start(userToken: myToken, dropID: id, joinedAt: Date())
        bluetoothMeetup.onMeetupConfirmed = { [weak self] partnerToken in
            self?.autoConfirmBLEMeetup(partnerToken: partnerToken)
        }
    }

    func leaveActiveJoin() {
        defer {
            bluetoothMeetup.stop()
            bleConfirmedInCurrentSession = false
            joinSessionStartedAt         = nil
            joinSessionDropCoord         = nil
            activeJoinedDropID           = nil
            activeDropAnnotation         = nil
        }

        // Mindestzeit: erst nach 10 Min ist man "committed" genug für Score-Einfluss
        guard let startedAt = joinSessionStartedAt,
              Date().timeIntervalSince(startedAt) >= 10 * 60 else { return }

        // Bereits per BLE bestätigt → kein No-Show nötig
        if bleConfirmedInCurrentSession { return }

        // BLE-Fallback: GPS-Nähe prüfen (< 150 m vom Drop-Standort)
        if let dropCoord = joinSessionDropCoord {
            let userLoc = CLLocation(latitude: currentUser.coordinate.latitude,
                                     longitude: currentUser.coordinate.longitude)
            let dropLoc = CLLocation(latitude: dropCoord.latitude,
                                     longitude: dropCoord.longitude)
            let dist = userLoc.distance(from: dropLoc)

            if dist < 150 {
                // GPS bestätigt Anwesenheit → Show-up
                reliabilityScore.totalCommits += 1
                reliabilityScore.showUps += 1
                saveAll()
                pushReliabilityScoreToFirestore()
                return
            }

            // Weit weg → No-Show
            reliabilityScore.totalCommits += 1
            if !isDropsPlusActive {
                reliabilityScore.noShows += 1   // Drops+: kein Abzug
            }
            saveAll()
            pushReliabilityScoreToFirestore()
            return
        }

        // Kein GPS-Standort verfügbar → neutral (kein Score-Einfluss)
    }

    /// Wird aufgerufen wenn BLE-Proximity eine Begegnung automatisch bestätigt hat.
    private func autoConfirmBLEMeetup(partnerToken: String) {
        bleConfirmedInCurrentSession = true   // Verhindert No-Show beim Verlassen
        // Offenen Encounter suchen, der zu diesem Drop passt
        if let idx = encounters.firstIndex(where: { !$0.confirmed && !$0.denied }) {
            encounters[idx].confirmed = true
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            generateFriendSuggestions(from: encounters[idx])
        } else {
            // Kein Encounter-Eintrag vorhanden (z.B. spontaner Stranger-Drop) →
            // Score direkt gutschreiben
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
        }
        saveAll()                           // Score lokal persistieren
        pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
    }

    @Published var reliabilityScore = ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0)

    @Published var alerts: [AlertItem] = []

    enum Tab: Int { case map, feed, create, alerts, profile }

    // MARK: - Computed Map / Feed Properties

    var nearbyFriends: [User] {
        // Freunde sind immer sichtbar — unabhängig vom eingestellten Radius
        friends.filter { $0.isAvailable }
    }

    var allMapAnnotations: [MapAnnotationItem] {
        // Freunde nur sichtbar wenn sie einen aktiven Drop haben
        let friendsWithDrop = nearbyFriends.filter { friend in
            activeDrops.contains { $0.host.id == friend.id && !$0.isExpired }
        }
        var items: [MapAnnotationItem] = friendsWithDrop.map {
            MapAnnotationItem(id: $0.id, name: $0.name, emoji: $0.emoji,
                              activity: $0.statusMessage, coordinate: $0.coordinate, type: .friend)
        }
        for drop in activeDrops where drop.host.id == currentUser.id && !drop.isExpired {
            // Host ist immer als "bestätigt anwesend" markiert
            let myToken = String(currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
            let hostAge: Int? = userBirthdate.flatMap {
                Calendar.current.dateComponents([.year], from: $0, to: Date()).year
            }
            var dropParticipants = [DropParticipant(name: currentUser.name, emoji: currentUser.emoji,
                                                     selfie: selfieImage,
                                                     reliabilityScore: Int(reliabilityScore.score),
                                                     age: hostAge,
                                                     isVerified: false,
                                                     token: myToken,
                                                     profileImageURL: profileImageURL)]
            let dropCLLoc = CLLocation(latitude: drop.location.coordinate.latitude,
                                        longitude: drop.location.coordinate.longitude)
            for friend in nearbyFriends.prefix(3) {
                let friendToken = String(friend.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
                let friendCLLoc = CLLocation(latitude: friend.coordinate.latitude,
                                              longitude: friend.coordinate.longitude)
                let dist = friendCLLoc.distance(from: dropCLLoc)
                dropParticipants.append(DropParticipant(name: friend.name, emoji: friend.emoji,
                                                         token: friendToken,
                                                         simulatedDistance: dist,
                                                         liveCoordinate: friend.coordinate))
            }
            items.append(MapAnnotationItem(
                id: drop.id,
                name: "\(drop.activity.emoji) \(drop.activity.name)",
                emoji: drop.activity.emoji,
                activity: drop.activity.name,
                coordinate: drop.location.coordinate,
                type: .myDrop,
                dropDescription: drop.dropDescription.isEmpty ? nil : drop.dropDescription,
                scheduledTime: drop.scheduledTime,
                participants: dropParticipants,
                createdAt: drop.createdAt,
                maxParticipants: drop.maxParticipants,
                durationMinutes: drop.durationMinutes,
                dropLocationType: drop.location.type,
                locationTitle: drop.location.title,
                isBoosted: drop.isBoosted
            ))
        }
        if liveStrangerDrops.isEmpty {
            // No radius filter on map — show all drops distributed across Munich
            items += strangerDropsCache.filter {
                !blockedUserNames.contains($0.name)
                    && !$0.isFull
                    && ($0.creatorAgeGroup.map { $0.minAge <= ageFilterMax && $0.maxAge >= ageFilterMin } ?? true)
            }
        } else {
            items += liveStrangerDrops
                .filter { !blockedUserNames.contains($0.displayName) }
                .map { drop in
                    // Stabile UUID aus dem Firebase-Key — damit joinRequests
                    // auch nach Map-Rerendering korrekt matchen
                    let stableID = UUID(uuidString: drop.id) ?? UUID()
                    // Standort von Fremden verwischen: zufälliger Versatz 800 m–1 km
                    let fuzzyCoord = Self.fuzzyCoordinate(drop.coordinate, minMeters: 800, maxMeters: 1000, seed: drop.id)
                    return MapAnnotationItem(id: stableID, name: drop.displayName, emoji: drop.emoji,
                                            activity: drop.activityName, coordinate: fuzzyCoord,
                                            type: .stranger, scheduledTime: drop.scheduledTime,
                                            maxParticipants: drop.maxParticipants,
                                            isFuzzy: true,
                                             realCoordinate: drop.coordinate, hostGender: drop.hostGender,
                                             isBoosted: drop.isBoosted)
                }
        }
        // ── Joiner unterwegs (echter GPS-Standort des Users) ───────────
        for note in activeJoinNotifications {
            items.append(MapAnnotationItem(
                id: note.id,
                name: note.requesterName,
                emoji: note.requesterEmoji,
                activity: "→ \(note.dropEmoji) \(note.dropActivity)",
                coordinate: currentUser.coordinate,   // Echter Standort statt Simulation
                type: .joiner
            ))
        }
        return items
    }

    func placeStrangerDrops(around center: CLLocationCoordinate2D) {
        // Demo-Daten deaktiviert — Drops kommen live aus Firebase
        guard !strangerDropsPlaced else { return }
        strangerDropsPlaced = true
        strangerDropsCache = []
    }

    /// Versetzt eine Koordinate um einen zufälligen aber stabilen Betrag (seed-basiert).
    /// Gleicher seed → gleicher Versatz, damit der Pin nicht bei jedem Rerender springt.
    static func fuzzyCoordinate(_ coord: CLLocationCoordinate2D,
                                 minMeters: Double, maxMeters: Double,
                                 seed: String) -> CLLocationCoordinate2D {
        // Deterministischer Hash aus dem Seed → immer gleicher Versatz für denselben Drop
        var hashValue: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hashValue ^= UInt64(byte)
            hashValue &*= 1_099_511_628_211
        }
        // Winkel 0–360 und Distanz minMeters–maxMeters ableiten
        let angle = Double(hashValue % 3600) / 10.0   // 0.0 … 360.0 Grad
        let range = maxMeters - minMeters
        let dist  = minMeters + Double((hashValue >> 12) % UInt64(range))
        // 1 Grad Breitengrad ≈ 111 320 m
        let deltaLat = (dist * cos(angle * .pi / 180)) / 111_320.0
        let deltaLng = (dist * sin(angle * .pi / 180)) / (111_320.0 * cos(coord.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: coord.latitude + deltaLat,
                                      longitude: coord.longitude + deltaLng)
    }

    var nearbyDropsForFeed: [(name: String, emoji: String, status: String,
                               activity: String, place: String, eta: String, dist: String)] {
        // Wird live aus Firebase befüllt — kein Mock-Inhalt
        return []
    }

    var pendingAlertsCount: Int {
        alerts.filter { $0.status == .pending }.count
    }

    func isWithinRadius(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) <= radiusFilter
    }


    func startObservingLiveDrops(around coord: CLLocationCoordinate2D) {
        if let handle = dbDropsHandle { RealtimeDBManager.shared.removeObserver(handle) }
        dbDropsHandle = RealtimeDBManager.shared.observeNearbyDrops(around: coord, radiusKm: radiusFilter / 1000) { [weak self] drops in
            guard let self = self else { return }

            // 1. Eigene Drops ausfiltern — stabiler Identifier aus UserDefaults
            // Auth.auth().currentUser?.uid kann beim Start kurz nil sein → gespeicherte UID verwenden
            let myID = FirebaseAuth.Auth.auth().currentUser?.uid
                ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID)
                ?? ""
            let myDropIDs = Set(self.activeDrops.map { $0.id.uuidString })
            self.liveStrangerDrops = drops.filter {
                let byUID    = !myID.isEmpty && $0.ownerID == myID
                let byDropID = myDropIDs.contains($0.id)
                return !byUID && !byDropID
            }

            // 2. Auto-Leave: joinRequests bereinigen wenn der Drop vom Host gecancelt wurde
            let liveIDs = Set(drops.map { $0.id })
            let cancelledJoins = self.joinRequests.filter { req in
                !req.isExpired && !liveIDs.contains(req.dropID.uuidString)
            }
            for req in cancelledJoins {
                self.joinRequests.removeAll { $0.dropID == req.dropID }
                if self.activeJoinedDropID == req.dropID { self.leaveActiveJoin() }
                DropNotificationManager.cancelReminders(for: req.dropID)
                self.endDropLiveActivity()
            }
        }
    }

    private var hasRepositionedFriends = false
    /// Ob der User beim letzten Location-Update in der Heimzone war (für Edge-Detection).
    private var wasInHomeZone: Bool = false

    func updateUserLocation(_ coord: CLLocationCoordinate2D) {
        currentUser.coordinate = coord
        placeStrangerDrops(around: coord)
        startObservingLiveDrops(around: coord)

        let isNowInHomeZone = isInHomeZone(coord)

        let visible = allMapAnnotations.filter { $0.type == .stranger || $0.type == .friend }

        // Nearby-Drop-Notification — nur wenn kein eigener Drop aktiv
        if activeDrops.isEmpty && activeJoinedDropID == nil {
            PushNotificationManager.shared.checkNearbyDrops(visible, userLocation: coord)
        }

        // Heimzone-Warnung: immer prüfen — auch wenn eigener Drop aktiv,
        // da andere Nutzer dann den ungefähren Heimstandort sehen könnten.
        if isNowInHomeZone && !wasInHomeZone {
            let nearbyRadius: Double = max(homeZoneRadius * 2, 400)
            let nearby = visible.filter { $0.isNearby(from: coord, maxMeters: nearbyRadius) }
            if !nearby.isEmpty {
                PushNotificationManager.shared.notifyHomeZoneWarning(nearbyDropCount: nearby.count)
            }
        }

        wasInHomeZone = isNowInHomeZone

        // Live Activity mit aktuellem Teilnehmer-Stand aktuell halten
        refreshLiveActivityParticipants()
        guard !hasRepositionedFriends else { return }
        let offsets: [(Double, Double)] = [
            ( 0.0019, -0.0028), (-0.0031,  0.0042), ( 0.0008,  0.0051),
            (-0.0022, -0.0019), ( 0.0065,  0.0009), (-0.0055,  0.0068)
        ]
        for i in 0..<min(friends.count, offsets.count) {
            friends[i].coordinate = CLLocationCoordinate2D(
                latitude:  coord.latitude  + offsets[i].0,
                longitude: coord.longitude + offsets[i].1
            )
        }
        hasRepositionedFriends = true
    }

    func authenticate(code: String) -> Bool {
        isAuthenticated = true
        return true
    }

    func toggleAvailability() {
        currentUser.isAvailable.toggle()
        currentUser.statusMessage = currentUser.isAvailable ? "Ich bin verfügbar! 🎉" : "Gerade nicht verfügbar"
    }

    func generateFriendSuggestions(from encounter: Encounter) {
        // Keine Demo-Vorschläge — echte Vorschläge kommen später via Firebase
    }

    // MARK: - Heimzone

    func setHomeZone(coordinate: CLLocationCoordinate2D) {
        homeZoneCoordinate = coordinate
        saveAll()
    }

    func removeHomeZone() {
        homeZoneCoordinate = nil
        saveAll()
    }

    func isInHomeZone(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let hz = homeZoneCoordinate else { return false }
        let from = CLLocation(latitude: hz.latitude, longitude: hz.longitude)
        let to   = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to) <= homeZoneRadius
    }

    func dismissSuggestion(id: UUID) {
        friendSuggestions.removeAll { $0.id == id }
    }

    // MARK: - Dynamic Island / Live Activity
    // Hinweis: ActivityKit.Activity<T> wird vollständig qualifiziert, da
    // die lokale `Activity`-Struct (Aktivitäten wie Kaffee, Sport …)
    // sonst den Namen im Compiler auflöst.

    /// Laufende Live Activity (eine pro Nutzer, ActivityKit-Limit).
    private var currentLiveActivity: ActivityKit.Activity<DropLiveActivityAttributes>?

    /// Gecachter, aufgelöster Adress-String (Reverse-Geocode von "Aktueller Standort").
    private var geocodedDropLocationTitle: String = ""

    /// Tokens von Teilnehmern die per BLE als "vor Ort" erkannt wurden.
    private var bleArrivedTokens: Set<String> = []

    /// Wird aufgerufen wenn der Host via BLE einen Teilnehmer-Token in Reichweite erkennt.
    private func handleBLEParticipantArrived(token: String) {
        guard !bleArrivedTokens.contains(token) else { return }  // Bereits verarbeitet
        guard currentLiveActivity != nil else { return }

        // Teilnehmer mit diesem Token in allMapAnnotations suchen
        guard let myAnnotation = allMapAnnotations.first(where: { $0.type == .myDrop }),
              let myDrop = activeDrops.first(where: { !$0.isExpired }) else { return }

        let allParticipants = myAnnotation.participants
        guard let match = allParticipants.first(where: { $0.token == token }) else { return }

        bleArrivedTokens.insert(token)

        // Teilnehmer aus onTheWay entfernen (falls er dort war) und zu arrived hinzufügen
        // Für die Live Activity: alle bekannten Teilnehmer als "vor Ort" behandeln
        let arrivedEmojis = allParticipants.map { $0.emoji }
        let arrivedNames  = allParticipants.map { $0.name }
        let urls          = allParticipants.map { $0.profileImageURL ?? "" }
        let selfies       = allParticipants.map { $0.selfie }
        let keys          = allParticipants.map { $0.token }

        Task {
            var filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
            for i in filenames.indices where filenames[i].isEmpty {
                if let selfie = selfies[i] {
                    let key = keys[i].isEmpty ? "p\(i)" : keys[i]
                    filenames[i] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
                }
            }

            let locationTitle = geocodedDropLocationTitle.isEmpty
                ? myDrop.location.title : geocodedDropLocationTitle

            updateDropLiveActivity(
                participantCount: allParticipants.count,
                maxParticipants: myAnnotation.maxParticipants,
                expiresAt: myDrop.expiresAt,
                locationTitle: locationTitle,
                arrivedEmojis: arrivedEmojis,
                arrivedNames: arrivedNames,
                arrivedImageFilenames: filenames,
                onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
            )
        }

        print("BLE: \(match.name) (\(token)) ist angekommen → Live Activity aktualisiert")
    }
    /// Letzter Refresh-Zeitpunkt — verhindert zu häufige Updates bei GPS-Bursts.
    private var lastLiveActivityRefresh: Date = .distantPast

    // MARK: - Reverse Geocode Helper

    /// Wandelt GPS-Koordinate in lesbaren Adress-String um ("Straße Nr, Stadt").
    private func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let p = placemarks.first else { return nil }
        var parts: [String] = []
        if let name = p.name, !name.isEmpty, name != p.thoroughfare {
            parts.append(name)
        } else {
            if let street = p.thoroughfare { parts.append(street) }
            if let num   = p.subThoroughfare { parts.append(num) }
        }
        if let city = p.locality { parts.append(city) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Live Activity refresh (GPS-Updates)

    /// Aktualisiert Adresse + Profilbilder der Live Activity.
    /// Wird bei GPS-Updates aufgerufen; billig wenn alles bereits gecacht ist.
    private func refreshLiveActivityParticipants() {
        guard currentLiveActivity != nil else { return }
        // Max. 1x alle 30 Sekunden refreshen (GPS feuert viel häufiger)
        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityRefresh) > 30 else { return }
        lastLiveActivityRefresh = now
        guard let myAnnotation = allMapAnnotations.first(where: { $0.type == .myDrop }),
              let myDrop = activeDrops.first(where: { !$0.isExpired }) else { return }

        let arrivedEmojis    = myAnnotation.participants.map { $0.emoji }
        let arrivedNames     = myAnnotation.participants.map { $0.name }
        let urls             = myAnnotation.participants.map { $0.profileImageURL ?? "" }
        let selfies          = myAnnotation.participants.map { $0.selfie }
        let participantKeys  = myAnnotation.participants.map { $0.token }
        let cachedTitle      = geocodedDropLocationTitle

        Task {
            // 1. Profilbilder herunterladen — Selfie als Fallback wenn keine URL
            var filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
            for i in filenames.indices where filenames[i].isEmpty {
                if let selfie = selfies[i] {
                    let key = participantKeys[i].isEmpty ? "p\(i)" : participantKeys[i]
                    filenames[i] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
                }
            }

            // 2. Adresse auflösen — nur einmal geocoden, dann Cache nutzen
            var locationTitle = cachedTitle
            if locationTitle.isEmpty {
                let raw = myDrop.location.title
                if raw == "Aktueller Standort" || raw.isEmpty {
                    locationTitle = await reverseGeocode(myDrop.location.coordinate) ?? raw
                } else {
                    locationTitle = raw
                }
                geocodedDropLocationTitle = locationTitle
            }

            updateDropLiveActivity(
                participantCount: myAnnotation.participants.count,
                maxParticipants: myAnnotation.maxParticipants,
                expiresAt: myDrop.expiresAt,
                locationTitle: locationTitle,
                arrivedEmojis: arrivedEmojis,
                arrivedNames: arrivedNames,
                arrivedImageFilenames: filenames,
                onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
            )
        }
    }

    // MARK: - Live Activity permission hint

    /// true = User wurde schon darauf hingewiesen, Live Activities zu aktivieren
    @Published var showLiveActivitySettingsHint = false

    private func checkLiveActivityEnabled() -> Bool {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if !enabled {
            // Einmal pro App-Session anzeigen
            if !UserDefaults.standard.bool(forKey: "liveActivityHintShown") {
                showLiveActivitySettingsHint = true
                UserDefaults.standard.set(true, forKey: "liveActivityHintShown")
            }
        }
        return enabled
    }

    // MARK: - Start Live Activity

    /// Startet die Dynamic Island Live Activity für einen eigenen Drop.
    func startDropLiveActivity(drop: DropEvent, isHost: Bool) {
        guard checkLiveActivityEnabled() else { return }
        geocodedDropLocationTitle = ""   // Reset für neuen Drop

        let attributes = DropLiveActivityAttributes(
            activityName: drop.activity.name,
            activityEmoji: drop.activity.emoji,
            dropID: drop.id.uuidString,
            isHost: isHost
        )
        let arrivedEmojis = drop.participants.map { $0.emoji }
        let arrivedNames  = drop.participants.map { $0.name }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: drop.participants.count,
            maxParticipants: drop.maxParticipants,
            expiresAt: drop.expiresAt,
            locationTitle: drop.location.title,   // Wird sofort async überschrieben
            arrivedEmojis: arrivedEmojis,
            arrivedNames: arrivedNames,
            arrivedImageFilenames: Array(repeating: "", count: arrivedEmojis.count),
            onTheWayEmojis: [], onTheWayETAs: [], onTheWayNames: []
        )
        let content = ActivityContent(state: state, staleDate: drop.expiresAt)
        do {
            currentLiveActivity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            // Sofort Adresse + Profilbild nachladen
            let myImgURL  = self.profileImageURL ?? ""
            let mySelfie  = self.selfieImage
            let myUserKey = self.currentUser.id.uuidString
            let coord     = drop.location.coordinate
            let rawTitle  = drop.location.title
            Task {
                // Profilbild: Firebase-URL bevorzugen, sonst lokales Selfie
                var myFilename = await LiveActivityImageCache.shared.cacheImage(urlString: myImgURL)
                if myFilename.isEmpty, let selfie = mySelfie {
                    myFilename = LiveActivityImageCache.shared.cacheSelfie(selfie, key: myUserKey)
                }
                let filenames = arrivedEmojis.indices.map { i in i == 0 ? myFilename : "" }

                // Adresse geocoden wenn nötig
                var locationTitle = rawTitle
                if rawTitle == "Aktueller Standort" || rawTitle.isEmpty {
                    locationTitle = await reverseGeocode(coord) ?? rawTitle
                }
                geocodedDropLocationTitle = locationTitle

                updateDropLiveActivity(
                    participantCount: drop.participants.count,
                    maxParticipants: drop.maxParticipants,
                    expiresAt: drop.expiresAt,
                    locationTitle: locationTitle,
                    arrivedEmojis: arrivedEmojis,
                    arrivedNames: arrivedNames,
                    arrivedImageFilenames: filenames,
                    onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
                )
            }
        } catch {
            print("Live Activity start error: \(error)")
        }
    }

    /// Überladung für MapAnnotationItem (beim Beitreten über die Karte).
    func startDropLiveActivity(annotation: MapAnnotationItem, isHost: Bool) {
        guard checkLiveActivityEnabled() else { return }
        let attributes = DropLiveActivityAttributes(
            activityName: annotation.activity,
            activityEmoji: annotation.emoji,
            dropID: annotation.id.uuidString,
            isHost: isHost
        )
        let arrivedEmojis = annotation.participants.map { $0.emoji }
        let arrivedNames  = annotation.participants.map { $0.name }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: annotation.participants.count,
            maxParticipants: annotation.maxParticipants,
            expiresAt: annotation.expiresAt,
            locationTitle: annotation.locationTitle,   // Korrekt: Ort-Adresse, nicht Host-Name
            arrivedEmojis: arrivedEmojis,
            arrivedNames:  arrivedNames,
            arrivedImageFilenames: Array(repeating: "", count: arrivedEmojis.count),
            onTheWayEmojis: [], onTheWayETAs: [], onTheWayNames: []
        )
        let content = ActivityContent(state: state, staleDate: annotation.expiresAt)
        do {
            currentLiveActivity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            // Profilbilder + Adresse asynchron nachladen
            let urls      = annotation.participants.map { $0.profileImageURL ?? "" }
            let rawTitle  = annotation.locationTitle
            let coord     = annotation.coordinate
            Task {
                let filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
                var locationTitle = rawTitle
                if rawTitle.isEmpty || rawTitle == "Aktueller Standort" {
                    locationTitle = await reverseGeocode(coord) ?? rawTitle
                }
                geocodedDropLocationTitle = locationTitle
                updateDropLiveActivity(
                    participantCount: annotation.participants.count,
                    maxParticipants: annotation.maxParticipants,
                    expiresAt: annotation.expiresAt,
                    locationTitle: locationTitle,
                    arrivedEmojis: arrivedEmojis,
                    arrivedNames: arrivedNames,
                    arrivedImageFilenames: filenames,
                    onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
                )
            }
        } catch {
            print("Live Activity start error: \(error)")
        }
    }

    /// Aktualisiert die Live Activity mit aktuellen Teilnehmer- und Unterwegs-Daten.
    /// - arrivedEmojis/Names/ImageFilenames: Parallel-Arrays für vor Ort angekommene Personen
    /// - onTheWayEmojis/Names/ETAs: Parallel-Arrays für Personen unterwegs
    func updateDropLiveActivity(
        participantCount: Int,
        maxParticipants: Int,
        expiresAt: Date,
        locationTitle: String = "",
        arrivedEmojis: [String] = [],
        arrivedNames: [String] = [],
        arrivedImageFilenames: [String] = [],
        onTheWayEmojis: [String] = [],
        onTheWayNames: [String] = [],
        onTheWayETAs: [Int] = []
    ) {
        guard let liveActivity = currentLiveActivity else { return }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: participantCount,
            maxParticipants: maxParticipants,
            expiresAt: expiresAt,
            locationTitle: locationTitle,
            arrivedEmojis: arrivedEmojis,
            arrivedNames: arrivedNames,
            arrivedImageFilenames: arrivedImageFilenames,
            onTheWayEmojis: onTheWayEmojis,
            onTheWayETAs: onTheWayETAs,
            onTheWayNames: onTheWayNames
        )
        let content = ActivityContent(state: state, staleDate: expiresAt)
        Task { await liveActivity.update(content) }
    }

    /// Beendet die Live Activity sofort (Drop beendet / verlassen).
    /// Beendet ALLE laufenden Activities dieses Typs — auch Reste aus früheren App-Sessions,
    /// bei denen currentLiveActivity nil ist (z.B. nach Account-Wechsel oder App-Neustart).
    func endDropLiveActivity() {
        Task {
            // Tracked Activity beenden
            if let liveActivity = currentLiveActivity {
                await liveActivity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
            // Alle laufenden Activities dieses Typs beenden (Schutz vor Zombies)
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
        }
        currentLiveActivity = nil
    }

    func createDrop(activity: Activity, location: DropLocation,
                    description: String = "", scheduledTime: String = "Jetzt",
                    maxParticipants: Int = 10, durationMinutes: Int = 120) {
        let drop = DropEvent(
            id: UUID(), host: currentUser, activity: activity, location: location,
            participants: [currentUser], createdAt: Date(),
            dropDescription: description, scheduledTime: scheduledTime,
            maxParticipants: max(2, min(15, maxParticipants)),
            durationMinutes: durationMinutes
        )
        activeDrops.append(drop)
        RealtimeDBManager.shared.publishDrop(
            dropID: drop.id.uuidString, userID: FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString,
            displayName: currentUser.name, emoji: activity.emoji,
            activityName: activity.name, coordinate: location.coordinate, radius: radiusFilter,
            expiresAt: drop.expiresAt, scheduledTime: scheduledTime, hostGender: userGender,
            maxParticipants: drop.maxParticipants
        )
        DropNotificationManager.requestPermission()   // Lazy: erst beim ersten Drop fragen
        DropNotificationManager.scheduleExpiryReminders(for: drop)
        startDropLiveActivity(drop: drop, isHost: true)
        Task { @MainActor in PushNotificationManager.shared.trackAction() }

        // Host beobachtet eingehende DropIns (nach Accept) und neue Join-Requests
        startObservingDropIns(forDropID: drop.id.uuidString)
        startObservingJoinRequests(forDropID: drop.id.uuidString)

        // BLE: Host scannt nach Teilnehmer-Tokens desselben Drops
        let hostToken = String(currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        bluetoothMeetup.start(userToken: hostToken, dropID: drop.id, joinedAt: Date())
        bluetoothMeetup.onParticipantNearby = { [weak self] token in
            self?.handleBLEParticipantArrived(token: token)
        }

        saveAll()
    }

    func extendDrop(id: UUID, byMinutes: Int) {
        guard let idx = activeDrops.firstIndex(where: { $0.id == id }) else { return }
        // Verlängerung ab jetzt oder ab dem bisherigen Ablauf (je nachdem was später ist)
        let base = max(activeDrops[idx].expiresAt, Date())
        let newExpiry = base.addingTimeInterval(Double(byMinutes) * 60)
        // durationMinutes so anpassen dass expiresAt = newExpiry
        activeDrops[idx].durationMinutes = Int(newExpiry.timeIntervalSince(activeDrops[idx].createdAt) / 60)
        RealtimeDBManager.shared.extendDropExpiry(dropID: id.uuidString, newExpiry: newExpiry)
        // Neue Ablauf-Erinnerungen planen
        DropNotificationManager.cancelReminders(for: id)
        DropNotificationManager.scheduleExpiryReminders(for: activeDrops[idx])
        saveAll()
    }

    func cancelDrop(id: UUID) {
        stopObservingDropIns()
        stopObservingJoinRequests()
        RealtimeDBManager.shared.cleanupJoinRequests(dropID: id.uuidString)
        RealtimeDBManager.shared.cleanupDropIns(dropID: id.uuidString)
        activeDrops.removeAll { $0.id == id }
        currentUser.isAvailable = false
        currentUser.statusMessage = "Gerade nicht verfügbar"
        RealtimeDBManager.shared.cancelDrop(dropID: id.uuidString)
        DropNotificationManager.cancelReminders(for: id)
        endDropLiveActivity()
        bluetoothMeetup.stop()
        bleArrivedTokens.removeAll()
        saveAll()
    }

    // MARK: - Drops+ Boost

    /// Boosted den eigenen aktiven Drop (Drops+ Feature).
    /// Setzt isBoosted = true lokal und in Firebase.
    func boostActiveDrop() {
        guard isDropsPlusActive else { showDropsPlusPaywall = true; return }
        guard let idx = activeDrops.indices.first(where: { activeDrops[$0].host.id == currentUser.id }) else { return }
        let dropID = activeDrops[idx].id
        activeDrops[idx].isBoosted = true
        RealtimeDBManager.shared.boostDrop(dropID: dropID.uuidString)
    }

    /// Hebt den Boost des eigenen aktiven Drops auf.
    func unboostActiveDrop() {
        guard let idx = activeDrops.indices.first(where: { activeDrops[$0].host.id == currentUser.id }) else { return }
        let dropID = activeDrops[idx].id
        activeDrops[idx].isBoosted = false
        RealtimeDBManager.shared.boostDrop(dropID: dropID.uuidString, active: false)
    }

    func respondToAlert(id: Int, accept: Bool) {
        if let i = alerts.firstIndex(where: { $0.id == id }) {
            alerts[i].status = accept ? .accepted : .declined
        }
    }

    func etaString(to coordinate: CLLocationCoordinate2D) -> String {
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mins = Int(from.distance(from: to) / 80)
        return mins < 1 ? "< 1 Min" : "\(mins) Min"
    }

    func distanceString(to coordinate: CLLocationCoordinate2D) -> String {
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let m = from.distance(from: to)
        return m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000)
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Live Activity Image Cache
// Downloads profile photos and stores them in the shared App Group container
// (group.com.dennis.drops / la_avatars/) so the Widget Extension can read them.

final class LiveActivityImageCache {

    static let shared = LiveActivityImageCache()
    private init() {}

    private let groupID    = "group.com.dennis.drops"
    private let folderName = "la_avatars"

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private var avatarsFolderURL: URL? {
        guard let base = containerURL else { return nil }
        let folder = base.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: nil)
        }
        return folder
    }

    /// Downloads `urlString`, saves to App Group container, returns filename or "".
    func cacheImage(urlString: String) async -> String {
        guard !urlString.isEmpty else { return "" }
        let filename = stableFilename(for: urlString)
        guard let folder = avatarsFolderURL else { return "" }
        let fileURL = folder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) { return filename }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let jpeg  = image.jpegData(compressionQuality: 0.65) else { return "" }
        try? jpeg.write(to: fileURL, options: .atomic)
        return filename
    }

    /// Caches all URLs concurrently, returns filenames in the same order.
    func cacheImages(urlStrings: [String]) async -> [String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for (i, url) in urlStrings.enumerated() {
                group.addTask { (i, await self.cacheImage(urlString: url)) }
            }
            var results = Array(repeating: "", count: urlStrings.count)
            for await (index, filename) in group { results[index] = filename }
            return results
        }
    }

    func loadImage(filename: String) -> UIImage? {
        guard !filename.isEmpty, let folder = avatarsFolderURL else { return nil }
        return (try? Data(contentsOf: folder.appendingPathComponent(filename))).flatMap { UIImage(data: $0) }
    }

    /// Speichert ein lokales UIImage (z.B. Selfie) direkt in den App-Group-Container.
    /// Gibt den Dateinamen zurück, oder "" bei Fehler.
    @discardableResult
    func cacheSelfie(_ image: UIImage, key: String) -> String {
        let filename = stableFilename(for: "selfie_\(key)") // deterministisch pro User
        guard let folder = avatarsFolderURL,
              let jpeg = image.jpegData(compressionQuality: 0.7) else { return "" }
        let fileURL = folder.appendingPathComponent(filename)
        try? jpeg.write(to: fileURL, options: .atomic)
        return filename
    }

    func cleanupOldImages() {
        guard let folder = avatarsFolderURL,
              let files  = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return }
        let now = Date()
        for file in files {
            let url = folder.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mod = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(mod) > 24 * 3600 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func stableFilename(for s: String) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in s.utf8 { h ^= UInt64(b); h = h &* 1_099_511_628_211 }
        return String(h, radix: 16) + ".jpg"
    }
}
