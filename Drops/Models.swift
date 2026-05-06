import SwiftUI
import MapKit
import CoreBluetooth
import Combine
import FirebaseDatabase
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import FirebaseCrashlytics
import UserNotifications
import ActivityKit

// MARK: - Feature Flags

/// Zentrale Feature-Flags. Auf `false` setzen blendet alle UI-Touchpoints
/// für ein Feature aus, ohne Code zu löschen — so kann das Feature später
/// einfach wieder aktiviert werden.
enum FeatureFlags {
    /// Drops+ (Premium-Tier) ist für den initialen Launch deaktiviert.
    /// Wenn `true`: Settings-Banner, Boost-Option, Paywall-Trigger,
    /// Plus-Avatar-Ring etc. werden angezeigt. Sonst überall hidden.
    static let dropsPlusEnabled: Bool = false
}

// MARK: - Crash Reporter

/// Thin wrapper um FirebaseCrashlytics — zentrale Stelle für Logging, Custom Keys
/// und nicht-fatale Errors. Liegt bewusst hier statt in eigener Datei, damit kein
/// manuelles Xcode-Target-Hinzufügen nötig ist.
enum CrashReporter {

    /// Breadcrumb-Log — taucht im Crashlytics-Report als „Logs"-Zeile auf.
    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    /// Custom-Value pro Session — z.B. Feature-Flags, Drop-Status, Plus-Status.
    static func setValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    /// Nicht-fatale Fehler — App crasht NICHT, aber Firebase trackt Häufigkeit
    /// und Stack-Traces.
    static func record(_ error: Error, file: String = #file, line: Int = #line) {
        let userInfo: [String: Any] = [
            "file": (file as NSString).lastPathComponent,
            "line": line
        ]
        let ns = NSError(domain: (error as NSError).domain,
                         code: (error as NSError).code,
                         userInfo: userInfo.merging((error as NSError).userInfo) { $1 })
        Crashlytics.crashlytics().record(error: ns)
    }

    /// User-ID für Session-Tracking — nach Login / Session-Restore setzen.
    static func setUser(uid: String?) {
        if let uid = uid {
            Crashlytics.crashlytics().setUserID(uid)
            setValue(uid, forKey: "uid")
        } else {
            Crashlytics.crashlytics().setUserID("")
        }
    }

    /// Kontext-Snapshot beim App-Start.
    static func recordSessionContext(isPlus: Bool, hasActiveDrop: Bool) {
        setValue(isPlus, forKey: "is_plus")
        setValue(hasActiveDrop, forKey: "has_active_drop")
        let bundle = Bundle.main.infoDictionary
        if let v = bundle?["CFBundleShortVersionString"] as? String { setValue(v, forKey: "app_version") }
        if let b = bundle?["CFBundleVersion"] as? String { setValue(b, forKey: "build_number") }
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid { setUser(uid: uid) }
    }
}

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
    /// Firebase Storage Download-URL — wird für Avatare in Freundesliste etc. genutzt.
    var profileImageURL: String? = nil
    /// Firebase Auth UID des Users — stabiler Dedup-Key über alle Pfade hinweg
    /// (Contact-Match, Observer-Hydration, Direct-Add).
    var firebaseUID: String? = nil
    /// Reliability-Punkte des Users — Default ist der Start-Score (100).
    /// Wird bei Freunden aus RTDB (`users/{uid}/reliabilityPoints`) hydriert.
    var reliabilityPoints: Int = ReliabilityScore.startingPoints

    init(id: UUID = UUID(), name: String, emoji: String,
         isAvailable: Bool, statusMessage: String,
         coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
         profileImageURL: String? = nil,
         firebaseUID: String? = nil,
         reliabilityPoints: Int = ReliabilityScore.startingPoints) {
        self.id = id; self.name = name; self.emoji = emoji
        self.isAvailable = isAvailable; self.statusMessage = statusMessage
        self.coordinate = coordinate
        self.profileImageURL = profileImageURL
        self.firebaseUID = firebaseUID
        self.reliabilityPoints = reliabilityPoints
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
    let joinerAge: Int?
    let joinerProfileImageURL: String?
    var joinerReliabilityPoints: Int = 100
    var joinerIsPlus: Bool = false
    /// Entfernung in Metern vom Drop-Standort — wird vom Host berechnet
    /// sobald Joiner-Live-Position in Firebase steht.
    var joinerDistanceMeters: Double? = nil
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
    var reliabilityScore: Int = 100
    /// Anzahl der Commit-Einträge — wird gebraucht, um neue User (totalCommits=0)
    /// als „Drop-Entdecker" statt „Drop-Legende" korrekt zu markieren.
    /// Default 0 = „neuer User / unbekannt" → zeigt Drop-Entdecker-Tier.
    var reliabilityCommits: Int = 0
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
    /// Firebase Auth UID — für Plus-Badge-Lookup und Report-Funktion.
    var firebaseUID: String? = nil
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
    /// Firebase UID des Hosts — für Drop-Invite-Bonus (+5 an Host wenn via Link gejoint).
    var hostUID: String? = nil
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

struct PastDropParticipant: Identifiable, Codable {
    let id = UUID()
    let name: String
    let emoji: String
    let reliabilityScore: Int
    var wasHost: Bool = false
    var didShowUp: Bool = true

    // ID wird beim Decodieren neu erzeugt — sie hat keine semantische
    // Bedeutung über den App-Run hinweg.
    enum CodingKeys: String, CodingKey {
        case name, emoji, reliabilityScore, wasHost, didShowUp
    }
}

struct PastDrop: Identifiable, Codable {
    let id = UUID()
    let activityEmoji: String
    let activityName: String
    let locationName: String
    let date: Date
    let wasHost: Bool
    let participants: [PastDropParticipant]

    enum CodingKeys: String, CodingKey {
        case activityEmoji, activityName, locationName, date, wasHost, participants
    }

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
    static let reliabilityHostOK    = "ud_reliabilityHostOK"
    static let reliabilityStreakB   = "ud_reliabilityStreakB"
    static let reliabilityFirstB    = "ud_reliabilityFirstB"
    static let reliabilityInviteB   = "ud_reliabilityInviteB"
    static let reliabilityNewcB     = "ud_reliabilityNewcB"
    static let reliabilityAppInvB   = "ud_reliabilityAppInvB"
    static let reliabilityCreateB   = "ud_reliabilityCreateB"   // +5 pro Drop-Erstellung
    static let reliabilityBoostB    = "ud_reliabilityBoostB"    // +5 für Aktion während Boost-Phase
    /// Flag: User hat den einmaligen Erst-Host-Bonus (+10) bereits erhalten.
    /// Wird gesetzt wenn der erste eigene Drop tatsächlich Teilnehmer hatte.
    static let firstHostBonusReceived = "ud_firstHostBonusReceived"
    /// JSON-Array aller PastDrop-Einträge. Persistiert den Drop-Verlauf
    /// zwischen App-Sessions damit die Statistik / Drop-Verlauf-Section
    /// nicht jedes Mal leer ist nach App-Restart.
    static let pastDrops             = "ud_pastDrops"
    static let reliabilityStreak    = "ud_reliabilityStreak"
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
    static let feedDistanceFilter  = "ud_feed_distance_filter"
    static let feedTonightOnly     = "ud_feed_tonight_only"
}

/// Distanz-Filter im Umgebungs-Tab. Default: `.city` (verhält sich wie vorher
/// — alle Drops in der eigenen Stadt). `.nearby` und `.quarter` schränken auf
/// Distanz vom User-Standort ein.
enum FeedDistanceFilter: String, CaseIterable {
    case nearby   // 1 km
    case quarter  // 3 km
    case city     // ganze Stadt

    var meters: Double {
        switch self {
        case .nearby:  return 1000
        case .quarter: return 3000
        case .city:    return .infinity
        }
    }

    var label: String {
        switch self {
        case .nearby:  return "1 km"
        case .quarter: return "3 km"
        case .city:    return "Stadt"
        }
    }

    var detailLabel: String {
        switch self {
        case .nearby:  return "Nähe · 1 km"
        case .quarter: return "Viertel · 3 km"
        case .city:    return "Ganze Stadt"
        }
    }
}

/// Variante des First-Drop-Celebration-Sheets — wird einmal pro Variante
/// pro User getriggert.
enum FirstDropCelebration: String, Identifiable {
    case created   // Erster eigener Drop erstellt
    case joined    // Erstem fremden Drop beigetreten
    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: return "Dein erster Drop! 🎉"
        case .joined:  return "Erster Drop dabei! 🙌"
        }
    }

    var body: String {
        switch self {
        case .created:
            return "Drop läuft. Wer in der Nähe ist sieht's jetzt auf der Karte. Halte dein Telefon dabei — Bluetooth bestätigt, wer wirklich vorbeikommt."
        case .joined:
            return "Drop joined! Schau auf der Karte wo's lang geht. Vor Ort wirst du automatisch via Bluetooth bestätigt — kein manueller Check-In."
        }
    }
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
    /// Schwache Referenz für AppDelegate-Hooks (z.B. Quick Actions die VOR der
    /// SwiftUI-Scene laufen). Wird in LinkUpApp init gesetzt.
    nonisolated(unsafe) static weak var shared: AppStore?

    @Published var isAuthenticated = false
    /// true = App ist gesperrt nach Timeout → Face ID erforderlich, kein Logout
    @Published var isSessionLocked = false
    /// Pending Quick-Action — gesetzt von AppDelegate.routeQuickAction wenn
    /// bei Cold-Start noch keine MainTabView da ist (Auth restoration läuft).
    /// MainTabView konsumiert es beim onAppear.
    @Published var pendingQuickAction: String? = nil

    @Published var currentUser = User(
        name: "Alex", emoji: "😊", isAvailable: false,
        statusMessage: "Tippe um verfügbar zu sein",
        coordinate: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)
    )

    // MARK: - Bluetooth Auto-Confirmation
    /// Erkennt andere Drop-Teilnehmer automatisch via BLE-Proximity.
    /// Treffen werden bestätigt, sobald beide ≥ 20 Sek. in Reichweite waren.
    /// Lazy, damit der BLE-Permission-Dialog NICHT beim App-Start erscheint —
    /// erst beim ersten Drop (create/join) wird CBCentralManager instanziert.
    lazy var bluetoothMeetup: BluetoothMeetupManager = BluetoothMeetupManager()

    @Published var radiusFilter: Double = 2000   // Free-Default: 2km
    @Published var userGender: String = ""   // "männlich" | "weiblich" | "divers"
    @Published var genderFilterEnabled: Bool = false
    /// Aktuelle Aktivitäts-Kategorie im Umgebungs-Tab-Filter. Leer = "Alle".
    /// Gültige Werte: "Kaffee", "Drink", "Sport", "Essen", "Zocken"
    @Published var activityCategoryFilter: String = ""
    /// Distanz-Filter im Umgebungs-Tab (Nähe/Viertel/Stadt).
    @Published var feedDistanceFilter: FeedDistanceFilter = .city
    /// „Heute Abend"-Filter im Umgebungs-Tab — zeigt nur Drops mit
    /// scheduledTime == "Heute Abend" oder solche die heute nach 17 Uhr starten.
    @Published var feedTonightOnly: Bool = false

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
    /// Cached Live-Activity-Filename des Host-Profilbilds (von Firebase vorab gedownloaded).
    /// Wird beim App-Start asynchron befüllt damit der Drop-Start nicht auf einen Download wartet.
    @Published var cachedLAProfileImageFilename: String = ""
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

    // MARK: - Beta-Badge (Early-Adopter)
    //
    // Eigenes Erstell-Datum aus RTDB. Wird einmalig beim ersten Settings-/
    // Profil-Open via fetchUserMeta nachgezogen und in der App gehalten,
    // damit alle UI-Touchpoints (Settings-Header, ParticipantDetailRow,
    // ProfileSheet) konsistent denselben Beta-Badge zeigen.
    @Published var ownCreatedAt: Date? = nil

    /// Stichtag: Nutzer ab 04.05.2026 00:00 Europe/Berlin bekommen kein
    /// Beta-Badge mehr. Frühere Nutzer (Early Adopter) behalten den Badge
    /// dauerhaft. Wenn `createdAt` nil ist (Datum noch nicht geladen oder
    /// fremder User ohne propagierten Wert) → false (kein Badge).
    static func qualifiesForBetaBadge(createdAt: Date?) -> Bool {
        guard let created = createdAt else { return false }
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Europe/Berlin")
        let cutoff = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return created < cutoff
    }

    /// Convenience: Eigenes Beta-Badge-Recht.
    var qualifiesForBetaBadge: Bool {
        Self.qualifiesForBetaBadge(createdAt: ownCreatedAt)
    }

    // MARK: - App Version Gate
    //
    // Steuert Force-Update (Hard) und Soft-Recommend-Banner. Config kommt
    // aus Firebase RTDB unter /config:
    //   - minRequiredVersion: Hard-Force, blockierender Vollbild
    //   - recommendedVersion: dezenter Banner, dismissibel
    enum AppVersionStatus: Equatable {
        case unknown                  // noch nicht geladen oder offline
        case ok                       // aktuelle Version >= recommended
        case updateRecommended(String)// recommended-Version-String
        case updateRequired(String)   // minRequired-Version-String
    }
    @Published var appVersionStatus: AppVersionStatus = .unknown

    /// App-Store-ID für den Update-Link. Wird aus dem Sheet als `itms-apps://`
    /// URL geöffnet → springt direkt in den App-Store.
    /// Drops – Triff Leute (https://apps.apple.com/de/app/drops-triff-leute/id6762097493)
    static let appStoreID: String = "6762097493"

    /// User hat den Soft-Recommend-Banner für diese Version weggewischt.
    /// Persistiert in UserDefaults damit er nicht nach jedem App-Start
    /// erneut aufpoppt. Der Banner kommt nur wieder wenn eine NEUE
    /// recommendedVersion als die zuletzt dismissed höher ist.
    @AppStorage("ud_dismissedRecommendVersion") private var dismissedRecommendVersion: String = ""

    /// Gibt die installierte App-Version zurück (z.B. "1.0.2").
    var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Lädt Version-Config + setzt appVersionStatus. Idempotent OK aufrufbar
    /// auch beim Foregrounding (re-evaluiert mit aktuellem RTDB-Stand).
    func refreshAppVersionStatus() {
        let current = currentAppVersion
        RealtimeDBManager.shared.fetchAppVersionConfig { [weak self] minReq, rec in
            guard let self = self else { return }
            // Min-Required hat Vorrang
            if let minReq = minReq, !minReq.isEmpty,
               Self.compareVersions(current, minReq) < 0 {
                self.appVersionStatus = .updateRequired(minReq)
                return
            }
            // Recommended (nur wenn der User nicht schon dismisst hat)
            if let rec = rec, !rec.isEmpty,
               Self.compareVersions(current, rec) < 0,
               Self.compareVersions(self.dismissedRecommendVersion, rec) < 0 {
                self.appVersionStatus = .updateRecommended(rec)
                return
            }
            self.appVersionStatus = .ok
        }
    }

    /// User hat den Soft-Recommend-Banner für diese Version weggewischt.
    func dismissRecommendBanner(forVersion version: String) {
        dismissedRecommendVersion = version
        if case .updateRecommended = appVersionStatus {
            appVersionStatus = .ok
        }
    }

    /// Vergleicht zwei Versions-Strings im "1.2.3"-Format. Liefert -1 / 0 / 1.
    /// Robuster als String-Compare: "1.10.0" > "1.9.0".
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let parts1 = a.split(separator: ".").map { Int($0) ?? 0 }
        let parts2 = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(parts1.count, parts2.count)
        for i in 0 ..< count {
            let v1 = i < parts1.count ? parts1[i] : 0
            let v2 = i < parts2.count ? parts2[i] : 0
            if v1 != v2 { return v1 < v2 ? -1 : 1 }
        }
        return 0
    }

    /// Lädt das eigene createdAt einmalig aus RTDB. Idempotent — mehrfache
    /// Aufrufe haben keine zusätzliche Wirkung wenn schon geladen.
    func loadOwnCreatedAtIfNeeded() {
        guard ownCreatedAt == nil,
              let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        RealtimeDBManager.shared.fetchUserMeta(uid: uid) { [weak self] created, _ in
            DispatchQueue.main.async { self?.ownCreatedAt = created }
        }
    }

    // MARK: - Points-Toast
    //
    // Zeigt eine kleine animierte Pille mit "+X Punkte" wann immer der
    // ReliabilityScore steigt. Die Pille wird per Combine-Observer auf
    // `reliabilityScore.points` angefangen — so erfasst er ALLE Punkte-
    // Events (Show-Up, Streak, Boost, Power-Hour, Invite, etc.) ohne
    // dass jede einzelne Score-Update-Stelle den Toast manuell triggern
    // muss.
    struct PointsToast: Identifiable, Equatable {
        let id = UUID()
        let delta: Int
        /// Nur wahr wenn der Punkt-Push aus einer aktiven Power-Hour kam.
        /// Steuert eine kleine Bolt-Variation in der Toast-UI.
        let isPowerHour: Bool
    }
    @Published var pointsToast: PointsToast? = nil

    /// Letzter beobachteter Punktestand. Initial bei loadAll() gesetzt,
    /// damit die Hydration aus UserDefaults/Firebase keinen Toast triggert.
    private var lastObservedPoints: Int = ReliabilityScore.startingPoints
    /// Toast-Observer ist erst aktiv NACH initialer Score-Hydration.
    private var pointsToastReady: Bool = false
    private var pointsToastCancellable: AnyCancellable? = nil

    /// Eingehende Beitrittsanfragen für den eigenen Drop (Host-Ansicht)
    @Published var pendingJoinRequests: [IncomingJoinRequest] = []

    /// Wahr wenn WEDER Standort NOCH Bluetooth autorisiert sind — dann blockt die App,
    /// weil ohne beides kein Drop-Matching/-Erkennen funktioniert. MainTabView
    /// rendert dann einen Permission-Gate-Sheet mit Settings-Link.
    @Published var needsCorePermissions: Bool = false


    /// Viewers des eigenen aktiven Drops (Drops+ „wer hat geschaut"-Feature).
    /// Key = dropID.uuidString → Liste aller Viewer sortiert nach viewedAt (neueste zuerst).
    @Published var dropViewersByDropID: [String: [RealtimeDBManager.DropViewerSnapshot]] = [:]
    /// Handles der Firebase-Observer (pro Drop) — zum sauberen Abmelden.
    private var dropViewsObserverHandles: [String: DatabaseHandle] = [:]
    /// Drop-IDs die in der aktuellen App-Session bereits „gezählt" wurden —
    /// verhindert dass mehrfaches Öffnen des Sheets mehrfach feuert.
    private var viewedDropIDsThisSession: Set<String> = []

    /// Live-Observer-Handle für `friends/{myUID}`.
    private var friendsObserverHandle: DatabaseHandle?
    private var friendsObservedUID: String?
    /// UIDs der Freunde, die wir bei der letzten Observer-Feuerung schon hatten.
    /// Damit können wir NEUE Freundschafts-Adds erkennen und Push auslösen.
    private var knownFriendUIDs: Set<String> = []
    /// Erste Observer-Feuerung initialisiert nur die Baseline — ohne Push.
    private var friendsObserverInitialized = false

    // MARK: - Friend Requests
    /// Eingehende Freundschaftsanfragen — werden im Freunde-Tab als Section
    /// ganz oben mit Annehmen/Ablehnen-Buttons angezeigt.
    @Published var incomingFriendRequests: [FriendRequestSnapshot] = []
    private var friendRequestsObserverHandle: DatabaseHandle?
    private var friendRequestsObserverInitialized = false

    /// Sheet: aktuell angezeigte Anfrage
    @Published var activeIncomingRequest: IncomingJoinRequest? = nil

    /// Status der eigenen Anfrage als Joiner: "pending" | "accepted" | "declined"
    @Published var myJoinRequestStatus: String = ""

    private var joinRequestObserverHandle: DatabaseHandle?
    private var myJoinStatusObserverHandle: DatabaseHandle?
    private var autoAcceptTimer: Timer?

    // MARK: - Init

    init() {
        // DIAGNOSTIC: wenn du diese Zeile in der Console siehst, läuft init().
        print("🚀🚀🚀 [AppStore.init] START — args=\(CommandLine.arguments)")

        // Singleton-Referenz IMMEDIATELY setzen — vor jedem AppDelegate-Hook.
        // AppDelegate.routeQuickAction prüft AppStore.shared, daher muss die
        // Referenz vor `application(_:didFinishLaunchingWithOptions:)` da sein.
        Self.shared = self

        // ── Firebase-Session beim App-Start wiederherstellen ──────────────
        // isAuthenticated startet als false. Wenn Firebase einen gültigen User
        // hat UND das Onboarding abgeschlossen wurde, direkt in die App.
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")

        // Nach Deinstallation persistiert die Firebase-Session im Keychain.
        // UserDefaults ist normalerweise leer → hasOnboarded=false → Logout.
        // ABER: iCloud-Backup restauriert manchmal UserDefaults → hasOnboarded
        // wäre irreführend true. Deshalb zusätzlich prüfen ob der Name wirklich
        // gesetzt ist — wenn nicht, ist der State korrupt, wir loggen aus.
        //
        // AUSNAHME: nach normalem In-App-Logout ist `userName` leer aber
        // `ud_lastLoginName` gesetzt — das ist KEIN korrupter State, sondern
        // eine bewusste Logout-Situation, in der wir die Firebase-Session
        // **erhalten** wollen damit Quick-Login ohne Apple-Sheet funktioniert.
        let hasNameStored = !(UserDefaults.standard.string(forKey: UDKey.userName) ?? "").isEmpty
        let hasLastLoginName = !(UserDefaults.standard.string(forKey: "ud_lastLoginName") ?? "").isEmpty
        let isPostLogoutState = hasOnboarded && !hasNameStored && hasLastLoginName
        if FirebaseAuth.Auth.auth().currentUser != nil
            && (!hasOnboarded || !hasNameStored)
            && !isPostLogoutState {
            try? FirebaseAuth.Auth.auth().signOut()
            UserDefaults.standard.set(false, forKey: "hasOnboarded")
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }

        if FirebaseAuth.Auth.auth().currentUser != nil && hasOnboarded && hasNameStored {
            isAuthenticated = true
            // Returning User → Welcome-Sheet skippen. Auch falls UserDefaults
            // inkonsistent ist (z.B. iCloud-Teilrestore), ist jemand mit
            // gültigem Firebase-User + Name definitiv kein Neuling.
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
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
            let authPhone = FirebaseAuth.Auth.auth().currentUser?.phoneNumber ?? ""
            let authEmail = (FirebaseAuth.Auth.auth().currentUser?.email ?? "").lowercased()
            // Apple Relay-Email wird nur beim ersten Login gesendet → aus UserDefaults laden
            let storedAppleEmail = (UserDefaults.standard.string(forKey: UDKey.appleEmail) ?? "").lowercased()
            if AdminConfig.isBootstrapAdmin(authEmail: authEmail, authPhone: authPhone, storedAppleEmail: storedAppleEmail) {
                isAdmin = true
            }

            // Verwaiste eigene Drops in Firebase aufräumen (z.B. nach App-Crash)
            let cleanupUID = FirebaseAuth.Auth.auth().currentUser?.uid
                ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID) ?? ""
            if !cleanupUID.isEmpty {
                let activeIDs = Set(activeDrops.map { $0.id.uuidString })
                RealtimeDBManager.shared.cleanupOrphanedDrops(ownerUID: cleanupUID, activeDropIDs: activeIDs)
            }

            // FCM-Token sicherstellen — damit Cloud-Function-Pushes den User erreichen.
            // AppDelegate schreibt bereits bei Token-Refresh, aber wenn der Token aus einer
            // früheren Session gecacht ist und kein Refresh in dieser Session feuert, bleibt
            // Firebase sonst ohne Token-Zuordnung.
            if let uid = FirebaseAuth.Auth.auth().currentUser?.uid,
               let token = UserDefaults.standard.string(forKey: "fcmToken"),
               !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token, uid: uid)
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

                        if let name = p.name, !name.isEmpty {
                            self.currentUser.name = name
                        }
                        // Geburtsdatum + Geschlecht auch aus Firebase zurückholen —
                        // sonst fehlen sie nach Reinstall / Session-Restore, obwohl sie
                        // beim Onboarding einmal gesetzt wurden.
                        if let bd = p.birthdate {
                            self.userBirthdate = bd
                            UserDefaults.standard.set(bd.timeIntervalSinceReferenceDate,
                                                       forKey: UDKey.userBirthdate)
                        }
                        if let gender = p.gender, !gender.isEmpty {
                            self.userGender = gender
                            UserDefaults.standard.set(gender, forKey: UDKey.userGender)
                        }
                        // Benutzer-Einstellungen aus Firebase wiederherstellen
                        // (Radius, Altersfilter, Interests, Blocklist etc.)
                        self.applyRemoteUserSettings(p.settings)
                        // profileImageURL kommt aus Firestore (loadProfileImageURL)
                        self.loadProfileImageURL()
                    }
                }
            }
        }

        loadAll()

        // Points-Toast-Observer NACH Hydration starten — sonst triggert
        // die Score-Initialisierung aus UserDefaults selbst einen Toast.
        startPointsToastObserver()

        // Eigenes createdAt für Beta-Badge laden (idempotent)
        loadOwnCreatedAtIfNeeded()

        // App-Version-Status laden (Force-Update / Recommend-Banner)
        refreshAppVersionStatus()

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
                    self.startObservingDropViews(forDropID: snap.dropID)
                }
            }
        }

        // ── Freundesliste live aus Firebase observieren ───────────────────
        // friends/{myUID} wird beobachtet: Adds auf anderen Geräten,
        // Re-Hydrates nach App-Neustart etc. feuern alle über denselben Weg.
        // Avatare kommen aus users/{theirUID}/profileImageURL (RTDB-Cache).
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            startObservingFriends(ownerUID: uid)
        }

        // ── Veraltete Drop-Benachrichtigungen aus vorherigen Sessions löschen ─
        // Alte UNCalendarNotificationTrigger würden sonst feuern; neue werden nach
        // der Rehydration oben bzw. bei createDrop/joinDrop neu eingeplant.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        // ── Live Activities aus früheren Sessions behandeln ───────────────
        // ActivityKit hält Activities über App-Neustarts hinweg am Leben.
        // Strategie:
        //  1. Pending-End-Marker: Activities die der User in der letzten Session
        //     beenden wollte, bei denen der Network-Call aber nicht durchkam
        //     → garantiert jetzt beenden.
        //  2. Noch nicht abgelaufene Activities BEHALTEN und als currentLiveActivity
        //     referenzieren — Drop-Rehydration erfolgt ggf. noch async,
        //     aber die User-sichtbare Activity bleibt durchgängig.
        //  3. Wirklich abgelaufene (expiresAt < jetzt) werden beendet.
        let pendingEndIDs = Set(UserDefaults.standard.stringArray(forKey: "ud_liveActivitiesPendingEnd") ?? [])
        Task { [weak self] in
            guard let self = self else { return }
            let now = Date()
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                // Priorität 1: Pending-End aus letzter Session durchziehen
                if pendingEndIDs.contains(activity.id) {
                    await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                    continue
                }
                let expiresAt = activity.content.state.expiresAt
                if expiresAt > now {
                    // Noch laufend — Referenz übernehmen (erste nehmen, falls mehrere)
                    await MainActor.run {
                        if self.currentLiveActivity == nil {
                            self.currentLiveActivity = activity
                        }
                    }
                } else {
                    // Wirklich abgelaufen → Zombie beenden
                    await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                }
            }
            // Pending-End-Marker sauber räumen — alle bekannten Zombies sind durch
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "ud_liveActivitiesPendingEnd")
            }
        }

        startExpiryTimer()

        // Stale Demo-UserDefaults aus früheren Builds aufräumen — falls jemand
        // diese Keys noch von der Beta-Phase im UserDefaults stehen hat.
        UserDefaults.standard.removeObject(forKey: "dropsDemoSeed")
        UserDefaults.standard.removeObject(forKey: "dropsDemoOff")

        // ── Drops+ Entitlements prüfen ────────────────────────────────────
        Task {
            await DropsStoreManager.shared.refreshEntitlements()
            // NUR auf true hochsetzen — nie überschreiben.
            // Sonst würde der Admin-gewährte Plus-Status (aus Firebase, ohne StoreKit-Purchase)
            // vom refreshEntitlements()-Callback auf false zurückgesetzt.
            if DropsStoreManager.shared.isPlusUser {
                self.isPlusUser = true
            }
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
            // Trotz queue: .main verlangt Swift 6 explizites MainActor-Hopping.
            Task { @MainActor in self.isPlusUser = isPlus }
        }

        // Benachrichtigungs-, Standort- und Bluetooth-Berechtigungen werden NICHT
        // beim App-Start angefragt — das passiert im Onboarding (AppIntroStep /
        // Permission-Schritte) im richtigen Kontext, damit der User versteht wofür.
        // Nach Login triggert requestPermissionsIfNeeded() in LinkUpApp.swift
        // ggf. Nachfragen falls der User im Onboarding abgelehnt hat.
        // Abgelaufene Begegnungen ohne Bestätigung → No-Show werten
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.processExpiredEncounters()
        }

        // Auth-Listener: reagiert auf Logout/Token-Ablauf zur Laufzeit
        _ = FirebaseAuth.Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                let onboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
                if user == nil && onboarded && self?.isAuthenticated == true {
                    // User wurde extern ausgeloggt oder Token ungültig
                    print("[auth] stateDidChange: user=nil while onboarded — setting isAuthenticated=false")
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
    /// Prüft Permissions + ob der Firebase-Account noch existiert.
    /// Session-Lock mit Face ID wurde entfernt — zu unterbrechend für die UX.
    func checkSessionTimeout() {
        let ud = UserDefaults.standard
        evaluateCorePermissions()
        // Auch ohne Timeout: Firebase-Konto prüfen (z.B. extern gelöscht)
        validateFirebaseAccount()
        // Alten Timestamp räumen falls vorhanden (Legacy-Daten aus früheren Versionen)
        ud.removeObject(forKey: UDKey.backgroundedAt)
    }

    /// Prüft ob Standort- UND Bluetooth-Berechtigung verweigert sind.
    /// Setzt `needsCorePermissions = true` wenn beide weg sind; sonst false.
    /// MainTabView reagiert darauf mit einem blockierenden Settings-Sheet.
    func evaluateCorePermissions() {
        let locStatus = CLLocationManager().authorizationStatus
        let locDenied = (locStatus == .denied || locStatus == .restricted)

        // Bluetooth: .notDetermined → noch nicht gefragt (nicht blocken), .denied → blockieren
        let btAuth = CBCentralManager.authorization
        let btDenied = (btAuth == .denied || btAuth == .restricted)

        let bothDenied = locDenied && btDenied
        if needsCorePermissions != bothDenied {
            needsCorePermissions = bothDenied
        }
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
                        print("[auth] validateFirebaseAccount: account gone (code=\(code?.rawValue ?? -1)) → clearLocalData")
                        self.clearLocalData()
                    } else {
                        print("[auth] validateFirebaseAccount: non-fatal error \(nsError.code) — keeping session")
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
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
            // Quick-Login-Daten weg — sonst würde der Name nach Löschung
            // im Welcome-Screen noch auftauchen.
            UserDefaults.standard.removeObject(forKey: "ud_lastLoginName")
            UserDefaults.standard.removeObject(forKey: "ud_lastProfileImageURL")
            // Apple-Given-Name + Relay-Email auch entfernen — sonst wird der
            // alte Apple-Vorname beim Re-Register vorgeblendet im Namensfeld.
            // Apple sendet beides nur beim ALLERERSTEN Sign-In, also haben
            // wir nach Re-Register beide nicht mehr — User gibt frischen
            // Namen ein, ohne alte Defaults.
            UserDefaults.standard.removeObject(forKey: "ud_appleGivenName")
            UserDefaults.standard.removeObject(forKey: "ud_appleEmail")
            // Heimzone (persönliche Standort-Präferenz) wird beim normalen
            // Logout absichtlich behalten — nur bei Account-Löschung weg.
            self.homeZoneCoordinate = nil
            self.homeZoneRadius     = 150
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneLat)
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneLng)
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneRadius)
            // Erst-Host-Bonus-Flag zurücksetzen, damit ein wiederkehrender
            // User (Re-Register nach Account-Löschung) den +10-Bonus
            // erneut beim ersten erfolgreichen Hosten bekommen kann.
            UserDefaults.standard.removeObject(forKey: UDKey.firstHostBonusReceived)
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

    /// Meldet den User ab — clears alle lokalen Daten, **behält aber die
    /// Firebase-Auth-Session**. So kann der Quick-Login-Button beim nächsten
    /// Start direkt re-authentifizieren ohne das Apple-System-Sheet zu öffnen.
    func logout() {
        clearLocalData(signOutFirebase: false)
    }

    /// Löscht alle lokalen Daten. Firebase-Logout ist optional — wird beim
    /// `deleteAccount`-Pfad gebraucht (true), beim normalen Logout NICHT (false),
    /// damit Quick-Login schnell und ohne Apple-Sheet funktioniert.
    func clearLocalData(signOutFirebase: Bool = true) {
        // Friends-Observer abmelden, damit er beim nächsten User nicht auf der
        // alten UID hängen bleibt
        stopObservingFriends()
        friends = []
        knownFriendUIDs = []

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

        // ── 2. Selfie-Datei löschen + Image-Cache räumen ──────────────────
        try? FileManager.default.removeItem(at: selfieURL)
        // ProfileImageCache cached Bilder per URL — sonst kommt beim Re-Login
        // mit demselben UID das alte Profilbild zurück (Cache-Hit).
        ProfileImageCache.shared.clear()
        // Live-Activity-Cache (App-Group-Container) auch räumen, damit der
        // Drop-Widget kein altes Profilbild zeigt.
        cachedLAProfileImageFilename = ""

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
        // Heimzone bleibt erhalten — sie ist eine persönliche Standort-
        // Präferenz, kein Session-Datum. Beim normalen Logout (Re-Login auf
        // demselben Gerät) soll der User seinen Heim-Anker behalten. Erst
        // bei Account-Löschung entfernt deleteAccount() sie explizit.
        profileImageURL           = nil
        geocodedDropLocationTitle = ""

        // ── 4. Dynamic Island beenden ─────────────────────────────────────
        endDropLiveActivity()

        // ── 5. Firebase ausloggen (optional) + Session beenden ────────────
        // Quick-Login soll ohne Apple-Sheet funktionieren — dafür muss
        // Firebase-Auth aktiv bleiben. Nur bei echter Account-Löschung
        // wirklich aus Firebase ausloggen.
        print("[auth] clearLocalData → signOutFirebase=\(signOutFirebase), isAuthenticated=false (caller: \(Thread.callStackSymbols.dropFirst(1).first ?? ""))")
        if signOutFirebase {
            try? FirebaseAuth.Auth.auth().signOut()
        }
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
        ud.set(feedDistanceFilter.rawValue, forKey: UDKey.feedDistanceFilter)
        ud.set(feedTonightOnly,      forKey: UDKey.feedTonightOnly)
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
        ud.set(reliabilityScore.totalCommits,      forKey: UDKey.reliabilityTotal)
        ud.set(reliabilityScore.showUps,           forKey: UDKey.reliabilityShows)
        ud.set(reliabilityScore.noShows,           forKey: UDKey.reliabilityNoShows)
        ud.set(reliabilityScore.hostSuccesses,     forKey: UDKey.reliabilityHostOK)
        ud.set(reliabilityScore.streakBonusPoints, forKey: UDKey.reliabilityStreakB)
        ud.set(reliabilityScore.firstArrivalPoints, forKey: UDKey.reliabilityFirstB)
        ud.set(reliabilityScore.dropInvitesPoints, forKey: UDKey.reliabilityInviteB)
        ud.set(reliabilityScore.newcomerHostPoints, forKey: UDKey.reliabilityNewcB)
        ud.set(reliabilityScore.appInvitesPoints,  forKey: UDKey.reliabilityAppInvB)
        ud.set(reliabilityScore.creationBonusPoints, forKey: UDKey.reliabilityCreateB)
        ud.set(reliabilityScore.boostBonusPoints, forKey: UDKey.reliabilityBoostB)
        ud.set(reliabilityScore.currentStreak,     forKey: UDKey.reliabilityStreak)
        // Drop-Verlauf persistieren — damit beendete Drops und die
        // Statistik einen App-Restart überleben.
        if let pastData = try? JSONEncoder().encode(pastDrops) {
            ud.set(pastData, forKey: UDKey.pastDrops)
        }
        saveSelfie()

        // Benutzer-Settings zusätzlich nach Firebase spiegeln — so überleben Radius,
        // Altersfilter, Interests etc. einen Logout/Re-Login oder Gerätewechsel.
        // (UserDefaults wird beim Logout bewusst geleert → Firebase ist die Truth-Source.)
        if FirebaseAuth.Auth.auth().currentUser != nil {
            RealtimeDBManager.shared.saveUserSettings(
                radiusFilter:           radiusFilter,
                ageFilterMin:           ageFilterMin,
                ageFilterMax:           ageFilterMax,
                selectedAgeGroups:      selectedAgeGroups.map { $0.rawValue },
                userInterests:          userInterests,
                blockedUsers:           Array(blockedUserNames),
                unavailabilityReason:   unavailabilityReason,
                genderFilterEnabled:    genderFilterEnabled,
                activityCategoryFilter: activityCategoryFilter
            )
        }
    }

    /// Wendet ein `UserSettingsSnapshot` aus Firebase auf den Store an.
    /// Nil-Felder werden ignoriert (lokaler Default bleibt stehen).
    /// Persistiert die Werte anschließend auch in UserDefaults, damit ein
    /// Offline-Start nicht wieder auf Default fällt.
    func applyRemoteUserSettings(_ s: UserSettingsSnapshot) {
        let ud = UserDefaults.standard
        if let r = s.radiusFilter, r > 0 {
            // Free-User dürfen max. 2 km — aber nur wenn Drops+ überhaupt
            // als Feature aktiv ist. Im Launch ohne Plus → kein Cap.
            let needsCap = FeatureFlags.dropsPlusEnabled && !isPlusUser
            let clamped = (needsCap && r > 2000) ? 2000 : r
            radiusFilter = clamped
            ud.set(clamped, forKey: UDKey.radiusFilter)
        }
        if let minA = s.ageFilterMin {
            ageFilterMin = minA
            ud.set(minA, forKey: UDKey.ageFilterMin)
        }
        if let maxA = s.ageFilterMax, maxA > 0 {
            ageFilterMax = maxA
            ud.set(maxA, forKey: UDKey.ageFilterMax)
        }
        if let groups = s.selectedAgeGroups, !groups.isEmpty {
            let parsed = groups.compactMap { AgeGroup(rawValue: $0) }
            if !parsed.isEmpty {
                selectedAgeGroups = parsed
                ud.set(groups, forKey: UDKey.selectedAgeGroups)
            }
        }
        if let interests = s.userInterests {
            userInterests = interests
            ud.set(interests, forKey: UDKey.userInterests)
        }
        if let blocked = s.blockedUsers {
            blockedUserNames = Set(blocked)
            ud.set(blocked, forKey: UDKey.blockedUsers)
        }
        if let reason = s.unavailabilityReason {
            unavailabilityReason = reason
            ud.set(reason, forKey: UDKey.unavailabilityReason)
        }
        if let g = s.genderFilterEnabled {
            genderFilterEnabled = g
            ud.set(g, forKey: UDKey.genderFilterEnabled)
        }
        if let cat = s.activityCategoryFilter {
            activityCategoryFilter = cat
            ud.set(cat, forKey: UDKey.activityCategoryFilter)
        }
    }

    /// Schreibt den aktuellen Zuverlässigkeits-Score in Firestore,
    /// damit andere User den echten Wert sehen können.
    /// Zusätzlich wird die kompakte `reliabilityPoints`-Zahl in die RTDB
    /// unter `users/{uid}/reliabilityPoints` gespiegelt — so können
    /// Freunde-Observer + Drop-Pins den echten Score ohne Firestore-Call lesen.
    private func pushReliabilityScoreToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let points = reliabilityScore.points
        Firestore.firestore()
            .collection("users").document(uid)
            .setData([
                "reliabilityTotal":        reliabilityScore.totalCommits,
                "reliabilityShows":        reliabilityScore.showUps,
                "reliabilityNoShows":      reliabilityScore.noShows,
                "reliabilityHostOK":       reliabilityScore.hostSuccesses,
                "reliabilityStreakBonus":  reliabilityScore.streakBonusPoints,
                "reliabilityFirstBonus":   reliabilityScore.firstArrivalPoints,
                "reliabilityInviteBonus":  reliabilityScore.dropInvitesPoints,
                "reliabilityNewcomerBonus": reliabilityScore.newcomerHostPoints,
                "reliabilityAppInviteBonus": reliabilityScore.appInvitesPoints,
                "reliabilityCreationBonus": reliabilityScore.creationBonusPoints,
                "reliabilityBoostBonus":   reliabilityScore.boostBonusPoints,
                "reliabilityCurrentStreak": reliabilityScore.currentStreak,
                "reliabilityPoints":       points
            ], merge: true)
        // Mirror in RTDB (read-path für Freundes-Observer + Drop-Pin-Badges)
        RealtimeDBManager.shared.setMyReliabilityPoints(points)
    }

    func saveSelfie() {
        guard let img = selfieImage,
              let data = img.jpegData(compressionQuality: 0.75) else {
            print("[selfie] saveSelfie: selfieImage ist nil oder JPEG-Encoding fehlgeschlagen")
            return
        }
        print("[selfie] saveSelfie: \(data.count) bytes, lokal speichern…")
        // 1. Lokal speichern
        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drops_selfie.jpg")
        try? data.write(to: localURL)
        // 2. Firebase Storage Upload → URL in Firestore speichern
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[selfie] saveSelfie: kein Auth-User → Upload übersprungen")
            return
        }
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        ref.putData(data, metadata: meta) { [weak self] _, error in
            if let error = error {
                print("[selfie] Storage putData ✗: \(error.localizedDescription)")
                return
            }
            print("[selfie] Storage putData ✓ — hole downloadURL…")
            ref.downloadURL { url, error in
                guard let self = self, let url = url, error == nil else {
                    print("[selfie] downloadURL ✗: \(error?.localizedDescription ?? "kein URL")")
                    return
                }
                let urlString = url.absoluteString
                print("[selfie] Upload ✓ → \(urlString)")
                // Firestore: users/{uid} → profileImageURL (für den eigenen Profil-Load)
                Firestore.firestore()
                    .collection("users").document(uid)
                    .setData(["profileImageURL": urlString], merge: true)
                // Realtime DB: users/{uid}/profileImageURL — damit Freunde-Avatare
                // mit einem einzigen Query gleich den URL mitbekommen.
                RealtimeDBManager.shared.setMyProfileImageURL(urlString)
                DispatchQueue.main.async {
                    self.profileImageURL = urlString
                }
                // Persistiert für den Quick-Login-Button auf Welcome-Screen
                UserDefaults.standard.set(urlString, forKey: "ud_lastProfileImageURL")
            }
        }
    }

    func loadProfileImageURL(retriesLeft: Int = 4) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[selfie] loadProfileImageURL: kein Auth-User")
            // Direkt nach einem signOut/re-signIn kann currentUser kurz nil sein —
            // einmal kurz warten und erneut versuchen.
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.loadProfileImageURL(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        Firestore.firestore()
            .collection("users").document(uid)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    let ns = error as NSError
                    // Bei ALLEN transienten Firestore-Fehlern retryen, nicht nur "offline".
                    // Direkt nach Re-Auth kann der Token noch nicht propagiert sein
                    // → permission-denied (7) oder unauthenticated (16). Ein kurzer
                    // Backoff löst das fast immer.
                    let transientCodes: Set<Int> = [
                        4,   // deadline-exceeded
                        7,   // permission-denied (oft direkt nach re-auth)
                        8,   // unavailable / offline
                        13,  // internal
                        14,  // unavailable (alt)
                        16   // unauthenticated
                    ]
                    let isTransient = ns.domain == "FIRFirestoreErrorDomain"
                        && transientCodes.contains(ns.code)
                    if isTransient && retriesLeft > 0 {
                        let delay = 2.0 + Double(4 - retriesLeft) * 1.0   // 2s, 3s, 4s, 5s
                        print("[selfie] loadProfileImageURL transient (\(ns.code)) — retry in \(delay)s (noch \(retriesLeft) Versuche)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.loadProfileImageURL(retriesLeft: retriesLeft - 1)
                        }
                    } else {
                        print("[selfie] loadProfileImageURL Firestore-Fehler (\(ns.code)): \(error.localizedDescription)")
                        // Harter Fehler → RTDB als Fallback (dort liegt die URL auch)
                        DispatchQueue.main.async { self.loadProfileImageURLFromRTDBFallback() }
                    }
                    return
                }
                let data = snapshot?.data()
                if let url = data?["profileImageURL"] as? String, !url.isEmpty {
                    print("[selfie] loadProfileImageURL ✓ URL: \(url.prefix(80))")
                    DispatchQueue.main.async { self.profileImageURL = url }
                    // Persistiert für den Quick-Login-Button — überlebt Logout
                    UserDefaults.standard.set(url, forKey: "ud_lastProfileImageURL")
                    // Sofort für Live Activity vorbereiten — Download in den
                    // App-Group-Container, damit das Widget beim nächsten Drop
                    // das Profilbild synchron hat (kein Race mehr).
                    Task {
                        let filename = await LiveActivityImageCache.shared.cacheImage(urlString: url)
                        if !filename.isEmpty {
                            await MainActor.run { self.cachedLAProfileImageFilename = filename }
                        }
                    }
                } else {
                    print("[selfie] loadProfileImageURL: keine profileImageURL im Firestore-Dokument — RTDB-Fallback")
                    DispatchQueue.main.async { self.loadProfileImageURLFromRTDBFallback() }
                }
                if let phone = data?["phoneNumber"] as? String, !phone.isEmpty {
                    DispatchQueue.main.async {
                        self.userPhone = phone
                        UserDefaults.standard.set(phone, forKey: UDKey.userPhone)
                    }
                }
            }
    }

    /// Holt die Profilbild-URL aus der Realtime DB als Fallback, wenn Firestore
    /// leer/unzugänglich ist. Beim `saveSelfie` schreiben wir beide Stores parallel,
    /// hier lesen wir daher mit hoher Wahrscheinlichkeit einen Treffer.
    private func loadProfileImageURLFromRTDBFallback() {
        RealtimeDBManager.shared.loadMyProfileImageURL { [weak self] url in
            guard let self = self, let url = url, !url.isEmpty else {
                print("[selfie] RTDB-Fallback: keine profileImageURL gefunden")
                return
            }
            print("[selfie] RTDB-Fallback ✓ URL: \(url.prefix(80))")
            self.profileImageURL = url
            Task {
                let filename = await LiveActivityImageCache.shared.cacheImage(urlString: url)
                if !filename.isEmpty {
                    await MainActor.run { self.cachedLAProfileImageFilename = filename }
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
        if let name = ud.string(forKey: UDKey.userName), !name.isEmpty  {
            currentUser.name  = name
        }
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
        if let raw = ud.string(forKey: UDKey.feedDistanceFilter),
           let v = FeedDistanceFilter(rawValue: raw) {
            feedDistanceFilter = v
        }
        feedTonightOnly = ud.bool(forKey: UDKey.feedTonightOnly)
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
                noShows:      savedNoShows,
                hostSuccesses:      ud.integer(forKey: UDKey.reliabilityHostOK),
                streakBonusPoints:  ud.integer(forKey: UDKey.reliabilityStreakB),
                firstArrivalPoints: ud.integer(forKey: UDKey.reliabilityFirstB),
                dropInvitesPoints:  ud.integer(forKey: UDKey.reliabilityInviteB),
                newcomerHostPoints: ud.integer(forKey: UDKey.reliabilityNewcB),
                appInvitesPoints:   ud.integer(forKey: UDKey.reliabilityAppInvB),
                creationBonusPoints:ud.integer(forKey: UDKey.reliabilityCreateB),
                boostBonusPoints:   ud.integer(forKey: UDKey.reliabilityBoostB),
                currentStreak:      ud.integer(forKey: UDKey.reliabilityStreak)
            )
        }
        // Selfie vom Disk laden
        if let data = try? Data(contentsOf: selfieURL),
           let img = UIImage(data: data) {
            selfieImage = img
        }
        // Drop-Verlauf laden — JSON aus UserDefaults
        if let data = ud.data(forKey: UDKey.pastDrops),
           let decoded = try? JSONDecoder().decode([PastDrop].self, from: data) {
            pastDrops = decoded
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
        // Service-Zone-Gate: User muss in einer der 5 Launch-Städte sein um zu joinen.
        guard !BetaConfig.cityRestrictionEnabled
                || ServiceCities.isInside(currentUser.coordinate)
        else { return false }
        // Cooldown prüfen: nach Verlassen 10 Min sperren
        if let leftAt = dropLeaveTimes[drop.id],
           Date().timeIntervalSince(leftAt) < AppStore.joinCooldown {
            return false
        }
        // Drop-Invite-Tracking: wenn der User via Universal Link hierher kam
        // und genau diesen Drop öffnet, wird's als Invite-Join markiert.
        // Der Host kriegt +5 sobald der ShowUp bestätigt ist.
        if pendingDropID == drop.id {
            markJoinAsInviteBased(dropID: drop.id, hostUID: drop.hostUID)
            pendingDropID = nil
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
            joinerEmoji: currentUser.emoji,
            joinerAge: userAge,
            joinerLat: currentUser.coordinate.latitude,
            joinerLng: currentUser.coordinate.longitude
        )
        // Auf DropIns des Hosts hören (falls der Host derselbe User auf anderem Gerät ist – Schutz)
        startObservingDropIns(forDropID: drop.id.uuidString)

        // First-Drop-Celebration: nur beim allerersten Join.
        maybeCelebrateFirstDrop(.joined)
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
                // Score-Schutz für Drops+ ist als Feature angekündigt aber noch nicht aktiv
                reliabilityScore.noShows += 1   // Mitten drin abgebrochen = No-Show
                breakStreak()
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

    // MARK: - Freunde entfernen

    /// Entfernt die Freundschaft mit dem User `theirUID` — beidseitig in Firebase.
    /// Lokal wird der Freund sofort aus `friends` genommen, damit die UI nicht auf
    /// die Observer-Aktualisierung warten muss.
    func removeFriend(theirUID: String) {
        guard !theirUID.isEmpty else { return }
        friends.removeAll { $0.firebaseUID == theirUID }
        knownFriendUIDs.remove(theirUID)
        RealtimeDBManager.shared.removeFriend(theirUID: theirUID)
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
            applyStreakBonus()
            // Boost: +5 wenn die Umgebung gerade leer ist
            applyBoostBonusIfActive(reason: "Treffen bestätigt")
            saveAll()                           // Score lokal persistieren
            pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
            maybeAskForReview()                 // Review nach guten Show-Up-Meilensteinen
        }
    }

    /// Erhöht den Streak-Counter und vergibt +20 bei jedem 5er-Block.
    /// Aufrufen wenn ein ShowUp gezählt wird (confirmEncounter / BLE-Arrival / Host-Success).
    private func applyStreakBonus() {
        reliabilityScore.currentStreak += 1
        if reliabilityScore.currentStreak % 5 == 0 {
            reliabilityScore.streakBonusPoints += 30
        }
    }

    /// Bricht den Streak bei einem No-Show.
    private func breakStreak() {
        reliabilityScore.currentStreak = 0
    }

    // MARK: - Points-Toast Observer

    /// Startet den Combine-Observer, der bei jedem Anstieg des ReliabilityScores
    /// einen Toast emittiert. Wird einmalig nach `loadAll()` in `init` aufgerufen.
    private func startPointsToastObserver() {
        guard pointsToastCancellable == nil else { return }
        lastObservedPoints = reliabilityScore.points
        pointsToastReady = true

        pointsToastCancellable = $reliabilityScore
            .map(\.points)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPoints in
                guard let self = self, self.pointsToastReady else { return }
                let delta = newPoints - self.lastObservedPoints
                self.lastObservedPoints = newPoints
                guard delta > 0 else { return }
                // Letzter Toast wird durch neuen ersetzt — neue ID damit
                // SwiftUI ein .transition triggert.
                self.pointsToast = PointsToast(
                    delta: delta,
                    isPowerHour: self.isPowerHourActive
                )
            }
    }

    // MARK: - Boost-Phase (Umgebungs-Tab leer → +Bonus)
    //
    // Wenn weniger als 5 Drops in der näheren Umgebung des Users sind, ist
    // die App "leer" — wir incentivieren in dem Moment Aktionen mit einem
    // Punkte-Bonus: einmal beim Erstellen, einmal beim Bestätigen eines
    // Treffens (entweder als Joiner via confirmEncounter oder als Host via
    // recordHostSuccess).
    //
    // Power-Hour: zu festgelegten Stoßzeiten verdoppelt sich der Boost-Bonus
    // (von +15 auf +25). Die Logik bleibt: BOOST-Bedingung muss erfüllt sein
    // (leere Umgebung). Power-Hour ist nur ein höherer Multiplikator on-top.
    static let boostThreshold = 5
    static let boostBonus     = 15
    static let powerHourBonus = 25

    /// Definition eines Power-Hour-Zeitfensters: Wochentage + Uhrzeit-Spanne.
    /// `weekdays` nutzt die Apple-Convention (1 = Sonntag … 7 = Samstag).
    /// `endHour` ist exklusiv (z.B. 18..<20 = 18:00 bis 19:59).
    struct PowerHourWindow {
        let weekdays: Set<Int>
        let startHour: Int
        let endHour: Int
        let label: String
    }

    static let powerHourWindows: [PowerHourWindow] = [
        // Werktag-Abend: Mo–Do 18–20 Uhr
        PowerHourWindow(weekdays: [2, 3, 4, 5], startHour: 18, endHour: 20,
                        label: "Werktag-Abend"),
        // Weekend Prime: Fr–Sa 19–23 Uhr
        PowerHourWindow(weekdays: [6, 7], startHour: 19, endHour: 23,
                        label: "Weekend Prime"),
        // Sonntag-Brunch: So 11–14 Uhr
        PowerHourWindow(weekdays: [1], startHour: 11, endHour: 14,
                        label: "Sonntag-Brunch"),
    ]

    /// True wenn aktuell weniger als `boostThreshold` Drops in Reichweite des
    /// Users sind. Quelle: `allMapAnnotations` gefiltert auf den Radius-Filter
    /// — gleiche Logik wie die Karte/Feed sieht. Eigene Drops zählen mit (Host
    /// macht für die Region trotzdem Aktivität sichtbar).
    var isBoostPhaseActive: Bool {
        let visible = allMapAnnotations.filter { isWithinRadius($0.coordinate) }
        return visible.count < Self.boostThreshold
    }

    /// Admin-Debug-Override: zwingt Power-Hour permanent an, unabhängig von
    /// Wochentag/Uhrzeit. Wird im Admin-Panel umgeschaltet (debugSection)
    /// damit Tests nicht erst auf 18 Uhr warten müssen. Persistiert
    /// in UserDefaults, damit der Modus über App-Restarts hält.
    @Published var debugForcePowerHour: Bool = UserDefaults.standard.bool(forKey: "ud_debugForcePowerHour") {
        didSet {
            UserDefaults.standard.set(debugForcePowerHour, forKey: "ud_debugForcePowerHour")
        }
    }

    /// True wenn gerade ein Power-Hour-Zeitfenster läuft. Unabhängig von der
    /// Boost-Bedingung — die UI kann beide Flags kombinieren um den richtigen
    /// Banner-Text und Bonus-Wert anzuzeigen. Admin-Debug-Override gewinnt.
    var isPowerHourActive: Bool {
        if debugForcePowerHour { return true }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        return Self.powerHourWindows.contains { window in
            window.weekdays.contains(weekday)
                && hour >= window.startHour
                && hour < window.endHour
        }
    }

    /// Aktueller Bonus-Wert (15 oder 25). UI nutzt das, der Code unten auch.
    var currentBoostBonus: Int {
        isPowerHourActive ? Self.powerHourBonus : Self.boostBonus
    }

    /// Countdown-Info für die Map-UI. Drei Phasen:
    ///   - .startingSoon: ≤60 Min vor Start des nächsten Slots heute
    ///   - .running:      mittendrin im Slot, noch >60 Min Zeit
    ///   - .endingSoon:   in den letzten 60 Min eines aktiven Slots
    /// Außerhalb aller Slots (oder >60 Min vor Start): nil.
    struct PowerHourCountdown {
        enum Phase { case startingSoon, running, endingSoon }
        let phase: Phase
        let minutesRemaining: Int
        let windowLabel: String
    }

    static func powerHourCountdown(at date: Date) -> PowerHourCountdown? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let nowMin = hour * 60 + minute

        // 1) Aktiver Slot? → immer Countdown zeigen (running oder endingSoon)
        for w in powerHourWindows where w.weekdays.contains(weekday) {
            if hour >= w.startHour && hour < w.endHour {
                let endMin = w.endHour * 60
                let remaining = endMin - nowMin
                guard remaining > 0 else { return nil }
                let phase: PowerHourCountdown.Phase = remaining <= 60 ? .endingSoon : .running
                return PowerHourCountdown(
                    phase: phase,
                    minutesRemaining: remaining,
                    windowLabel: w.label
                )
            }
        }

        // 2) Heutiger upcoming Slot in den nächsten 60 Min?
        for w in powerHourWindows where w.weekdays.contains(weekday) {
            if hour < w.startHour {
                let startMin = w.startHour * 60
                let untilStart = startMin - nowMin
                if untilStart > 0 && untilStart <= 60 {
                    return PowerHourCountdown(
                        phase: .startingSoon,
                        minutesRemaining: untilStart,
                        windowLabel: w.label
                    )
                }
            }
        }

        return nil
    }

    /// Vergibt den Boost-Bonus. Zwei unabhängige Trigger:
    ///   1. Boost-Phase: Umgebung gerade leer (<5 Drops) → +15
    ///   2. Power-Hour: konfiguriertes Zeitfenster läuft → +25
    /// Wenn beide zutreffen gewinnt Power-Hour (höherer Wert).
    /// Außerhalb beider Bedingungen: kein Bonus.
    /// Wird von createDrop / confirmEncounter / recordHostSuccess aufgerufen.
    /// Persistierung + Firestore-Push übernimmt der Aufrufer (saveAll).
    fileprivate func applyBoostBonusIfActive(reason: String) {
        let powerHour = isPowerHourActive
        let boost     = isBoostPhaseActive
        guard powerHour || boost else { return }

        let bonus  = powerHour ? Self.powerHourBonus : Self.boostBonus
        let prefix = powerHour ? "Power-Hour: " : "Boost: "
        reliabilityScore.boostBonusPoints += bonus
        Task { @MainActor in
            PushNotificationManager.shared.notifyPointsEarned(
                delta: bonus,
                totalPoints: reliabilityScore.points,
                reason: prefix + reason
            )
        }
    }

    // MARK: - Drop-Invite-Bonus-Tracking
    // Set von Drop-IDs (UUID-Strings) die via Invite-Link gejoint wurden.
    // Beim ShowUp wird der Eintrag verbraucht und der Host bekommt +5 Punkte.
    // Persistiert in UserDefaults damit's App-Restart überlebt.
    private static let invitedDropJoinsKey = "ud_invitedDropJoins"

    private func markJoinAsInviteBased(dropID: UUID, hostUID: String?) {
        let ud = UserDefaults.standard
        var set = Set(ud.stringArray(forKey: Self.invitedDropJoinsKey) ?? [])
        set.insert(dropID.uuidString)
        ud.set(Array(set), forKey: Self.invitedDropJoinsKey)
        // Host-UID separat merken (pro Drop), damit wir beim ShowUp korrekt crediten können
        if let host = hostUID, !host.isEmpty {
            ud.set(host, forKey: "ud_inviteDropHost_\(dropID.uuidString)")
        }
    }

    /// Löst den Drop-Invite-Bonus aus wenn der ShowUp für einen invite-gejointen Drop war.
    /// Aufrufen direkt nach applyStreakBonus/maybeAwardFirstArrivalBonus im Arrival-Flow.
    private func maybeAwardDropInviteBonusToHost() {
        guard let dropID = activeJoinedDropID else { return }
        let ud = UserDefaults.standard
        var set = Set(ud.stringArray(forKey: Self.invitedDropJoinsKey) ?? [])
        guard set.remove(dropID.uuidString) != nil else { return }
        ud.set(Array(set), forKey: Self.invitedDropJoinsKey)
        // Host-UID laden und Bonus schreiben
        let key = "ud_inviteDropHost_\(dropID.uuidString)"
        let hostUID = ud.string(forKey: key) ?? ""
        ud.removeObject(forKey: key)
        guard !hostUID.isEmpty else { return }
        RealtimeDBManager.shared.creditDropInviteBonus(hostUID: hostUID)
    }

    /// Vergibt +5 Bonus wenn der User als Erster Joiner vor Ort ist — außer er ist Host.
    /// Heuristik: wenn BLE noch keine anderen Teilnehmer bestätigt hat, sind wir der Erste.
    private func maybeAwardFirstArrivalBonus() {
        guard activeJoinedDropID != nil else { return }           // Nur bei gejointem Drop
        guard bluetoothMeetup.confirmedTokens.isEmpty else { return } // Schon jemand anderes da
        reliabilityScore.firstArrivalPoints += 10
    }

    /// Wird aufgerufen wenn ein eigener Drop zustande gekommen ist (min. 1 weiterer Teilnehmer
    /// war vor Ort). +12 Host-Bonus + Prüfung Neuling-Host-Bonus (+5 pro Drop-Entdecker).
    func recordHostSuccess(arrivedParticipants: [DropParticipant]) {
        reliabilityScore.hostSuccesses += 1
        reliabilityScore.totalCommits += 1
        reliabilityScore.showUps += 1
        applyStreakBonus()
        // Neuling-Bonus: für jeden gejointen Drop-Entdecker (<200 Pkt) +5
        let newcomers = arrivedParticipants.filter {
            ReliabilityScore.badge(forPoints: $0.reliabilityScore) == "Drop-Entdecker"
                || ReliabilityScore.badge(forPoints: $0.reliabilityScore) == "Neustart"
        }
        reliabilityScore.newcomerHostPoints += newcomers.count * 5
        // Erst-Host-Bonus: einmaliger +10 wenn der erste eigene Drop
        // tatsächlich Teilnehmer hatte. Belohnt erfolgreiches Hosten ohne
        // farmbar zu sein — kann genau einmal pro User vergeben werden.
        let ud = UserDefaults.standard
        if !arrivedParticipants.isEmpty,
           !ud.bool(forKey: UDKey.firstHostBonusReceived) {
            reliabilityScore.creationBonusPoints += 10
            ud.set(true, forKey: UDKey.firstHostBonusReceived)
        }
        // Boost: +5 wenn die Umgebung gerade leer ist
        applyBoostBonusIfActive(reason: "Drop gehostet")
        saveAll()
        pushReliabilityScoreToFirestore()
        maybeAskForReview()
    }

    /// Wird aufgerufen wenn jemand den Drop via deiner Einladung gejoint hat.
    /// Aufrufer muss sicherstellen, dass der Joiner via Link vom aktuellen User kam.
    func recordDropInviteJoined() {
        reliabilityScore.dropInvitesPoints += 10
        saveAll()
        pushReliabilityScoreToFirestore()
    }

    /// Wird aufgerufen wenn ein von diesem User eingeladener Freund Drops neu installiert
    /// und das Onboarding abgeschlossen hat (via deeplink-Zuordnung).
    func recordAppInviteCompleted() {
        reliabilityScore.appInvitesPoints += 25
        saveAll()
        pushReliabilityScoreToFirestore()
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
            // Score-Schutz für Drops+ ist als Feature angekündigt aber noch nicht aktiv
            reliabilityScore.noShows += 1
            breakStreak()
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
        dropInObserverHandle = RealtimeDBManager.shared.observeDropIns(dropID: dropID) { [weak self] name, emoji, _ in
            guard let self = self else { return }
            // Nur den Host benachrichtigen — Joiner sollen keine eigene Notification bekommen
            guard !self.activeDrops.isEmpty else { return }
            PushNotificationManager.shared.notifyDropIn(joinerName: "\(emoji) \(name)".trimmingCharacters(in: .whitespaces),
                                                         activityName: activityName)
            // Live-Activity aktualisieren damit der neue Teilnehmer erscheint
            self.refreshLiveActivityParticipants()
        }
        // Zusätzlich: Live-Positions-Updates der Joiner beobachten → Pins auf der Karte
        joinerLocationObserverHandle = RealtimeDBManager.shared.observeJoinerLocations(
            dropID: dropID
        ) { [weak self] joinerID, lat, lng in
            guard let self = self else { return }
            self.joinerLiveCoordinates[joinerID] = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    /// Live-Koordinaten der Joiner pro UID — wird von observeJoinerLocations befüllt.
    /// Die Kartendarstellung pickt sich daraus die Pins. Wird beim Drop-Ende gecleart.
    @Published var joinerLiveCoordinates: [String: CLLocationCoordinate2D] = [:]
    private var joinerLocationObserverHandle: DatabaseHandle? = nil

    // MARK: - Drop Views („wer hat geschaut")

    /// Wird aufgerufen wenn der User ein öffentliches Drop-Detail öffnet.
    /// Eigener Drop wird nicht als View gezählt (item.type .stranger filtert bereits).
    func viewDrop(_ item: MapAnnotationItem) {
        guard item.type == .stranger else { return }
        // Safety: nicht zweimal in derselben Session für denselben Drop schreiben
        let dropKey = item.id.uuidString
        guard viewedDropIDsThisSession.insert(dropKey).inserted else { return }
        RealtimeDBManager.shared.recordDropView(
            dropID: dropKey,
            viewerName: currentUser.name,
            viewerEmoji: currentUser.emoji,
            viewerAge: userAge,
            viewerProfileImageURL: profileImageURL
        )
    }

    /// Startet den Live-Observer für die Viewer eines eigenen Drops.
    func startObservingDropViews(forDropID dropID: String) {
        stopObservingDropViews(forDropID: dropID)
        let handle = RealtimeDBManager.shared.observeDropViews(dropID: dropID) { [weak self] viewers in
            self?.dropViewersByDropID[dropID] = viewers
        }
        dropViewsObserverHandles[dropID] = handle
    }

    func stopObservingDropViews(forDropID dropID: String) {
        if let handle = dropViewsObserverHandles[dropID] {
            RealtimeDBManager.shared.removeDropViewsObserver(handle, dropID: dropID)
            dropViewsObserverHandles.removeValue(forKey: dropID)
        }
    }

    // MARK: - Freunde live synchronisieren

    /// Startet den Live-Observer auf `friends/{uid}` — adds auf anderen Geräten
    /// landen automatisch in store.friends. Neue Adds lösen einen Notification-
    /// Push aus (Freundschafts-Event). Gleichzeitig startet der Observer auf
    /// `friendRequests/{uid}` für eingehende Anfragen.
    func startObservingFriends(ownerUID: String) {
        stopObservingFriends()
        friendsObservedUID = ownerUID
        friendsObserverInitialized = false
        friendsObserverHandle = RealtimeDBManager.shared.observeMyFriends(ownerUID: ownerUID) { [weak self] snapshots in
            guard let self = self else { return }
            self.applyFriendSnapshots(snapshots)
        }
        // Eingehende Freundschaftsanfragen — separater Observer
        friendRequestsObserverHandle = RealtimeDBManager.shared.observeIncomingFriendRequests { [weak self] requests in
            guard let self = self else { return }
            // Neue Requests (UID war vorher nicht in der Liste) → lokaler Push
            let oldUIDs = Set(self.incomingFriendRequests.map { $0.fromUID })
            let newRequests = requests.filter { !oldUIDs.contains($0.fromUID) }
            self.incomingFriendRequests = requests
            for req in newRequests where self.friendRequestsObserverInitialized {
                self.notifyFriendRequestReceived(from: req.fromName)
            }
            self.friendRequestsObserverInitialized = true
        }
    }

    func stopObservingFriends() {
        if let handle = friendsObserverHandle, let uid = friendsObservedUID {
            RealtimeDBManager.shared.removeFriendsObserver(handle, ownerUID: uid)
        }
        friendsObserverHandle = nil
        friendsObservedUID = nil
        friendsObserverInitialized = false
        if let handle = friendRequestsObserverHandle {
            RealtimeDBManager.shared.removeFriendRequestsObserver(handle)
        }
        friendRequestsObserverHandle = nil
        friendRequestsObserverInitialized = false
        incomingFriendRequests = []
    }

    /// Lokale Push-Notification bei neuer Freundschaftsanfrage.
    /// (Cloud Function schickt separat die Remote-Push — aber falls sie
    /// nicht deployed ist oder der User gerade die App offen hat, zeigen
    /// wir auch lokal einen Hinweis als Banner.)
    private func notifyFriendRequestReceived(from name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Neue Freundschaftsanfrage"
        content.body  = "\(name) möchte mit dir befreundet sein."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "friendRequest_\(name)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Friend Request Actions

    /// Schickt eine Freundschaftsanfrage an `theirUID`.
    /// Clientseitig kein Auto-Add mehr — der Empfänger muss annehmen.
    func sendFriendRequest(to theirUID: String) {
        guard !theirUID.isEmpty else { return }
        RealtimeDBManager.shared.sendFriendRequest(
            theirUID: theirUID,
            myName: currentUser.name,
            myProfileImageURL: profileImageURL
        )
    }

    func acceptFriendRequest(fromUID: String) {
        RealtimeDBManager.shared.acceptFriendRequest(fromUID: fromUID)
        // Observer updated incomingFriendRequests automatisch
    }

    func rejectFriendRequest(fromUID: String) {
        RealtimeDBManager.shared.rejectFriendRequest(fromUID: fromUID)
    }

    /// Merged eine frische Snapshot-Liste in store.friends. Dedup per Name
    /// (wie bisher), ergänzt fehlende Einträge, entfernt nicht mehr vorhandene
    /// (nur wenn sie via Friend-Snapshot-Liste ursprünglich kamen).
    /// Bei neuen UIDs (echte Freundschafts-Adds) wird ein lokaler Push ausgelöst.
    private func applyFriendSnapshots(_ snapshots: [RealtimeDBManager.FriendSnapshot]) {
        let currentUIDs = Set(snapshots.map { $0.uid })

        // Adds erkennen
        if friendsObserverInitialized {
            let newUIDs = currentUIDs.subtracting(knownFriendUIDs)
            for newUID in newUIDs {
                if let snap = snapshots.first(where: { $0.uid == newUID }) {
                    notifyFriendshipAdded(name: snap.name)
                }
            }
        }

        // Online-Status: ein Freund gilt als online wenn sein letzter Heartbeat
        // weniger als 5 Minuten her ist. Daraus ableiten wir `isAvailable`.
        let now = Date().timeIntervalSince1970
        let onlineWindow: TimeInterval = 5 * 60
        func isOnline(_ last: TimeInterval?) -> Bool {
            guard let last = last else { return false }
            return (now - last) < onlineWindow
        }

        // Vorhandene Einträge aktualisieren / fehlende hinzufügen — Dedup primär
        // per Firebase-UID (stabil), Name-Fallback für Legacy-Einträge.
        for snap in snapshots {
            let existingIdx: Int?
            if let byUID = friends.firstIndex(where: { $0.firebaseUID == snap.uid }) {
                existingIdx = byUID
            } else if let byName = friends.firstIndex(where: { $0.firebaseUID == nil && $0.name == snap.name }) {
                existingIdx = byName
            } else {
                existingIdx = nil
            }

            let online = isOnline(snap.lastActiveAt)

            if let idx = existingIdx {
                // Legacy-Eintrag mit UID/Name/Avatar/Online-Status/Score auffrischen
                if friends[idx].firebaseUID != snap.uid    { friends[idx].firebaseUID = snap.uid }
                if friends[idx].name != snap.name          { friends[idx].name = snap.name }
                if friends[idx].profileImageURL != snap.profileImageURL {
                    friends[idx].profileImageURL = snap.profileImageURL
                }
                if friends[idx].isAvailable != online {
                    friends[idx].isAvailable = online
                }
                if friends[idx].reliabilityPoints != snap.reliabilityPoints {
                    friends[idx].reliabilityPoints = snap.reliabilityPoints
                }
            } else {
                friends.append(User(
                    name: snap.name,
                    emoji: "👋",
                    isAvailable: online,
                    statusMessage: "",
                    profileImageURL: snap.profileImageURL,
                    firebaseUID: snap.uid,
                    reliabilityPoints: snap.reliabilityPoints
                ))
            }
        }

        // Lokale Einträge entfernen, deren UID nicht mehr in der Snapshot-Liste ist
        // (Freund wurde gelöscht, auf anderem Gerät entfreundet etc.). Legacy-Einträge
        // ohne UID lassen wir in Ruhe — Server ist nicht authoritativ über sie.
        friends.removeAll { user in
            guard let uid = user.firebaseUID else { return false }
            return !currentUIDs.contains(uid)
        }

        knownFriendUIDs = currentUIDs
        friendsObserverInitialized = true
    }

    /// Die eigentliche Push-Benachrichtigung kommt vom Cloud-Function-Trigger
    /// `onFriendshipAdded` — lokal machen wir nichts mehr, um Doppel-Pushes zu
    /// vermeiden. Wenn die Cloud Function noch nicht deployed ist, sieht der User
    /// den neuen Kontakt trotzdem sofort in der Liste (Live-Observer).
    private func notifyFriendshipAdded(name: String) {
        // Intentionally left blank — siehe functions/src/index.ts onFriendshipAdded
        _ = name
    }

    func stopObservingDropIns() {
        if let handle = joinerLocationObserverHandle, let dropID = dropInObservedDropID {
            RealtimeDBManager.shared.removeJoinerLocationObserver(handle, dropID: dropID)
        }
        joinerLocationObserverHandle = nil
        joinerLiveCoordinates.removeAll()
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
        ) { [weak self] joinerID, name, emoji, age, imageURL, points, isPlus, requestedAt in
            guard let self = self else { return }
            // Keine doppelten Einträge
            guard !self.pendingJoinRequests.contains(where: { $0.id == joinerID }) else { return }
            let req = IncomingJoinRequest(
                id: joinerID, dropID: dropID,
                joinerName: name, joinerEmoji: emoji,
                joinerAge: age,
                joinerProfileImageURL: imageURL,
                joinerReliabilityPoints: points,
                joinerIsPlus: isPlus,
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
        // Service-Zone-Gate: User muss in einer der 5 Launch-Städte sein um zu joinen.
        guard !BetaConfig.cityRestrictionEnabled
                || ServiceCities.isInside(currentUser.coordinate)
        else { return }
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
            joinerAge: userAge,
            profileImageURL: profileImageURL,
            reliabilityPoints: reliabilityScore.points,
            isPlus: isDropsPlusActive
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
            joinerName: currentUser.name, joinerEmoji: currentUser.emoji,
            joinerAge: userAge,
            joinerLat: currentUser.coordinate.latitude,
            joinerLng: currentUser.coordinate.longitude
        )

        // First-Drop-Celebration: nur beim allerersten Join.
        maybeCelebrateFirstDrop(.joined)
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
                // GPS bestätigt Anwesenheit → Show-up (Joiner-Ankunft)
                reliabilityScore.totalCommits += 1
                reliabilityScore.showUps += 1
                applyStreakBonus()
                maybeAwardFirstArrivalBonus()
                maybeAwardDropInviteBonusToHost()
                saveAll()
                pushReliabilityScoreToFirestore()
                return
            }

            // Weit weg → No-Show
            reliabilityScore.totalCommits += 1
            // Score-Schutz für Drops+ ist als Feature angekündigt aber noch nicht aktiv
            reliabilityScore.noShows += 1
            breakStreak()
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
            applyStreakBonus()
            maybeAwardFirstArrivalBonus()
            maybeAwardDropInviteBonusToHost()
            generateFriendSuggestions(from: encounters[idx])
        } else {
            // Kein Encounter-Eintrag vorhanden (z.B. spontaner Stranger-Drop) →
            // Score direkt gutschreiben
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            applyStreakBonus()
            maybeAwardFirstArrivalBonus()
            maybeAwardDropInviteBonusToHost()
        }
        saveAll()                           // Score lokal persistieren
        pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
    }

    @Published var reliabilityScore = ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0) {
        didSet {
            // Erster ShowUp eines Users → höflicher Push-Reask-Sheet falls er
            // im Onboarding abgelehnt hatte. Apple erlaubt keinen zweiten
            // System-Dialog, der Sheet leitet ihn dann zu den Einstellungen.
            if reliabilityScore.showUps == 1 && oldValue.showUps == 0 {
                maybeShowPushReask()
            }

            // Notification bei Punkt-Gewinn (Show-Up = +5, etc.).
            // Skip beim allerersten Set (App-Start mit 0:0:0 Default).
            let delta = reliabilityScore.points - oldValue.points
            if delta > 0 && oldValue.totalCommits > 0 {
                let reason: String
                if reliabilityScore.showUps > oldValue.showUps {
                    reason = "Drop besucht"
                } else if reliabilityScore.totalCommits > oldValue.totalCommits {
                    reason = "Drop verbindlich erstellt"
                } else {
                    reason = "Aktivität bestätigt"
                }
                PushNotificationManager.shared.notifyPointsEarned(
                    delta: delta,
                    totalPoints: reliabilityScore.points,
                    reason: reason
                )
            }
        }
    }

    /// Steuert das Push-Reask-Sheet (siehe `maybeShowPushReask()`).
    @Published var showPushReaskSheet: Bool = false

    /// Trigger-Flag für das native In-App-Review-Sheet (StoreKit `requestReview`).
    /// Wird gesetzt nach „guten Momenten" (3./10./25. Show-Up). LinkUpApp's
    /// ReviewPromptModifier reagiert darauf und ruft `requestReview()` auf.
    @Published var shouldShowReviewPrompt: Bool = false

    /// Wird intern aufgerufen wenn ein guter Moment vorbei ist (Show-Up bestätigt etc.).
    /// Trigger-Schwelle: showUps ∈ {3, 10, 25} und letzte Anfrage ≥90 Tage her.
    /// Apple's StoreKit limitiert intern auf 3× pro 365 Tage — falls schon erreicht
    /// ist `requestReview()` ein No-Op.
    func maybeAskForReview() {
        let triggerCounts: Set<Int> = [3, 10, 25]
        guard triggerCounts.contains(reliabilityScore.showUps) else { return }

        let last = UserDefaults.standard.double(forKey: "ud_lastReviewRequestedAt")
        if last > 0 {
            let daysAgo = (Date().timeIntervalSince1970 - last) / 86_400
            guard daysAgo >= 90 else { return }
        }
        // 0.8s Delay damit Confetti / Erfolgs-Toast erst zu Ende läuft, dann Sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shouldShowReviewPrompt = true
        }
    }

    /// Steuert das First-Drop-Celebration-Sheet — Konfetti + Welcome-Text
    /// wenn der User seinen ersten Drop erstellt oder beigetreten ist.
    /// Wert: nil = nicht zeigen, "created" / "joined" für Variante.
    @Published var firstDropCelebrationKind: FirstDropCelebration? = nil

    /// Triggert das First-Drop-Celebration-Sheet einmalig pro Variante
    /// (created / joined). Wird in UserDefaults persistiert.
    func maybeCelebrateFirstDrop(_ kind: FirstDropCelebration) {
        let ud = UserDefaults.standard
        let key = "ud_firstDrop_\(kind.rawValue)"
        guard !ud.bool(forKey: key) else { return }
        ud.set(true, forKey: key)
        firstDropCelebrationKind = kind
    }

    /// Zeigt den Reask-Sheet einmalig nach dem ersten ShowUp wenn Push nicht
    /// authorisiert ist. Der Trigger wird in UserDefaults persistiert, damit
    /// er pro User nur einmal erscheint — egal wie viele ShowUps folgen.
    private func maybeShowPushReask() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: "ud_pushReaskShown") else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized,
                  settings.authorizationStatus != .provisional
            else { return }
            DispatchQueue.main.async {
                self.showPushReaskSheet = true
                ud.set(true, forKey: "ud_pushReaskShown")
            }
        }
    }

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
                                                     reliabilityScore: reliabilityScore.points,
                                                     reliabilityCommits: reliabilityScore.totalCommits,
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
                                                         liveCoordinate: friend.coordinate,
                                                         firebaseUID: friend.firebaseUID))
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
        // Wenn keine Live-Drops da sind → lokaler Cache (kann leer sein in Production)
        if liveStrangerDrops.isEmpty {
            items += strangerDropsCache.filter {
                !blockedUserNames.contains($0.name)
                    && !$0.isFull
                    && ($0.creatorAgeGroup.map { $0.minAge <= ageFilterMax && $0.maxAge >= ageFilterMin } ?? true)
            }
        } else {
            let friendUIDs = Set(friends.compactMap { $0.firebaseUID })
            items += liveStrangerDrops
                .filter { !blockedUserNames.contains($0.displayName) }
                .map { drop in
                    // Stabile UUID aus dem Firebase-Key — damit joinRequests
                    // auch nach Map-Rerendering korrekt matchen
                    let stableID = UUID(uuidString: drop.id) ?? UUID()
                    let isFriendHost = friendUIDs.contains(drop.ownerID)
                    // Freunde: echter Standort + kein Fuzz + normale Anzeige (kein Lock-Look).
                    // Fremde: zufälliger Versatz 800m–1km, unscharfe Anzeige bis Join.
                    // Der `.stranger` Typ bleibt in beiden Fällen (damit der Drop in der
                    // Feed-Section „Öffentliche Drops" auftaucht), aber isFuzzy wird
                    // bei Freunden abgeschaltet.
                    let displayCoord = isFriendHost
                        ? drop.coordinate
                        : Self.fuzzyCoordinate(drop.coordinate, minMeters: 800, maxMeters: 1000, seed: drop.id)
                    return MapAnnotationItem(id: stableID, name: drop.displayName, emoji: drop.emoji,
                                            activity: drop.activityName, coordinate: displayCoord,
                                            type: .stranger, scheduledTime: drop.scheduledTime,
                                            maxParticipants: drop.maxParticipants,
                                            isFuzzy: !isFriendHost,
                                             realCoordinate: drop.coordinate, hostGender: drop.hostGender,
                                             isBoosted: drop.isBoosted,
                                             hostUID: drop.ownerID)
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
        // ── Host-Sicht: Joiner-Pins basierend auf Firebase-Live-Koordinaten ──
        // joinerLiveCoordinates wird durch observeJoinerLocations befüllt.
        // Pro Joiner einen Pin an seiner echten Position.
        if let activeDrop = activeDrops.first {
            for (joinerUID, coord) in joinerLiveCoordinates {
                // Name + Emoji aus participants-Liste ziehen falls vorhanden
                let match = activeDrop.participants.first(where: { $0.firebaseUID == joinerUID })
                let pinName  = match?.name  ?? "Joiner"
                let pinEmoji = match?.emoji ?? "👤"
                // Stabile UUID aus dem UID-Hash, damit SwiftUI nicht jedes Mal neu rendert
                let id = UUID(uuidString: joinerUID) ?? UUID()
                items.append(MapAnnotationItem(
                    id: id,
                    name: pinName,
                    emoji: pinEmoji,
                    activity: "→ \(activeDrop.activity.emoji) \(activeDrop.activity.name)",
                    coordinate: coord,
                    type: .joiner
                ))
            }
        }
        return items
    }

    func placeStrangerDrops(around center: CLLocationCoordinate2D) {
        // Reguläre Logik: Drops kommen live aus Firebase, Cache bleibt leer.
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
        // Spezialfall: wenn User den Max-Radius gewählt hat (≥ 50km),
        // zeigen wir ALLE Drops innerhalb seiner aktuellen Service-Stadt.
        // Das entspricht dem User-Wunsch: "in München bei Max = alle München-Drops".
        if radiusFilter >= 50000 {
            if let myCity = ServiceCities.city(for: currentUser.coordinate) {
                return myCity.contains(coordinate)
            }
        }
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

        // Wenn wir gerade einem fremden Drop beigetreten sind → Live-Position
        // nach Firebase pushen, damit der Host unseren Pin auf der Karte sieht.
        if let joinedDropID = activeJoinedDropID,
           let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            RealtimeDBManager.shared.updateJoinerLiveLocation(
                dropID: joinedDropID.uuidString,
                joinerID: uid,
                lat: coord.latitude,
                lng: coord.longitude
            )
        }

        // Last-Known-Location für „Drop in der Nähe"-Pushes (Cloud Function).
        // Throttled auf 1× pro 10 Min, gerundet auf ~100m (3 Nachkommastellen) für Privacy.
        RealtimeDBManager.shared.maybeUpdateLastKnownLocation(coord: coord)

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
        // Profilbild SOFORT synchron verfügbar machen.
        // Priorität: 1) vorab gecachtes Firebase-Bild, 2) lokales Selfie.
        // Dadurch zeigt die Live Activity von Anfang an das Host-Profilbild.
        var initialFilenames = Array(repeating: "", count: arrivedEmojis.count)
        if !initialFilenames.isEmpty {
            if !cachedLAProfileImageFilename.isEmpty {
                initialFilenames[0] = cachedLAProfileImageFilename
            } else if let selfie = self.selfieImage {
                let key = self.currentUser.id.uuidString
                initialFilenames[0] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
            }
        }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: drop.participants.count,
            maxParticipants: drop.maxParticipants,
            expiresAt: drop.expiresAt,
            locationTitle: drop.location.title,   // Wird sofort async überschrieben
            arrivedEmojis: arrivedEmojis,
            arrivedNames: arrivedNames,
            arrivedImageFilenames: initialFilenames,
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
    ///
    /// **Persistence-Marker:** `await activity.end(...)` ist ein Netzwerk-Call an Apple.
    /// Wenn die App nach dem User-Tap auf "Drop beenden" schnell suspendiert
    /// (Apple Watch-Szenario), kann der Task unterbrochen werden und die Activity
    /// bleibt zombiehaft aktiv. Deshalb merken wir die pending Activity-IDs in
    /// UserDefaults — beim nächsten App-Start werden sie garantiert beendet.
    func endDropLiveActivity() {
        let pendingIDs = ActivityKit.Activity<DropLiveActivityAttributes>.activities.map { $0.id }
        if !pendingIDs.isEmpty {
            UserDefaults.standard.set(pendingIDs, forKey: "ud_liveActivitiesPendingEnd")
        }
        currentLiveActivity = nil

        Task {
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
            // Alle durch → Marker räumen
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "ud_liveActivitiesPendingEnd")
            }
        }
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
        // KEINE Punkte mehr fürs reine Erstellen — alle Boni (creation,
        // boost, power-hour) müssen erarbeitet werden:
        //   - jemand kommt zu meinem Drop → recordHostSuccess
        //   - ich treffe jemanden bei fremdem Drop → confirmEncounter
        // Sonst wäre Punkte-Farming durch Erstellen + sofortiges Beenden
        // möglich. `creationBonusPoints` bleibt als Feld erhalten damit
        // alte gespeicherte Werte nicht verloren gehen, wird aber nicht
        // mehr inkrementiert.
        saveAll()
        pushReliabilityScoreToFirestore()
        DropNotificationManager.requestPermission()   // Lazy: erst beim ersten Drop fragen
        DropNotificationManager.scheduleExpiryReminders(for: drop)
        startDropLiveActivity(drop: drop, isHost: true)
        Task { @MainActor in PushNotificationManager.shared.trackAction() }

        // First-Drop-Celebration: nur beim allerersten eigenen Drop.
        maybeCelebrateFirstDrop(.created)

        // Host beobachtet eingehende DropIns (nach Accept) und neue Join-Requests
        startObservingDropIns(forDropID: drop.id.uuidString)
        startObservingJoinRequests(forDropID: drop.id.uuidString)
        startObservingDropViews(forDropID: drop.id.uuidString)

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
        // Drei Fälle bei Host-Cancel:
        //   1) ≥2 Teilnehmer da → Host-Erfolg (+8) + Neuling-Bonus
        //   2) Pending Joiner wartet ≥12 min → Host-No-Show (-25)
        //   3) Sonst (kein Joiner, oder noch frische Anfrage <12 min) → KEINE Buchung
        //
        // Launch-Phase-Toleranz: solange kein Joiner unterwegs war, wird ein Cancel
        // gar nicht in der Quote sichtbar. Verhindert dass User in Städten mit wenig
        // Aktivität durch reines Trying „bestraft" werden.
        if let drop = activeDrops.first(where: { $0.id == id }) {
            let pendingForThisDrop = pendingJoinRequests.filter { $0.dropID == id.uuidString }
            let hasOldPending = pendingForThisDrop.contains {
                Date().timeIntervalSince($0.requestedAt) >= 12 * 60
            }

            if drop.participants.count >= 2 {
                // (1) Erfolg
                let others = Array(drop.participants.dropFirst())
                let asDropParts = others.map { user in
                    DropParticipant(name: user.name, emoji: user.emoji,
                                    reliabilityScore: 100,  // Tatsächliche Punkte unbekannt — neutral
                                    reliabilityCommits: 0)
                }
                recordHostSuccess(arrivedParticipants: asDropParts)
            } else if hasOldPending {
                // (2) Host-No-Show: jemand wartet schon ≥12 min, Host bricht ab
                reliabilityScore.totalCommits += 1
                reliabilityScore.noShows += 1
                breakStreak()
                saveAll()
                pushReliabilityScoreToFirestore()
            }
            // (3) Sonst: clean cancel, keine Buchung — egal wie lange der Drop offen war.

            // Drop in den persistierten Drop-Verlauf übernehmen — egal ob
            // Erfolg, No-Show oder Clean Cancel. Sonst sind beendete Drops
            // weder in der Statistik noch im Verlauf sichtbar.
            let pastParticipants: [PastDropParticipant] = drop.participants.map { p in
                PastDropParticipant(
                    name: p.name,
                    emoji: p.emoji,
                    reliabilityScore: p.reliabilityPoints,
                    wasHost: p.name == currentUser.name,
                    didShowUp: true
                )
            }
            let past = PastDrop(
                activityEmoji: drop.activity.emoji,
                activityName: drop.activity.name,
                locationName: drop.location.title,
                date: drop.createdAt,
                wasHost: true,
                participants: pastParticipants
            )
            pastDrops.insert(past, at: 0)
        }
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
    /// Bilder werden auf 256x256 runterskaliert — das Widget hat nur ~30MB Speicher,
    /// original hochauflösende Profilbilder würden den Extension-Prozess crashen.
    func cacheImage(urlString: String) async -> String {
        guard !urlString.isEmpty else { return "" }
        let filename = stableFilename(for: urlString)
        guard let folder = avatarsFolderURL else { return "" }
        let fileURL = folder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) { return filename }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return "" }
        let resized = Self.downscale(image, maxDim: 256)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return "" }
        try? jpeg.write(to: fileURL, options: .atomic)
        return filename
    }

    /// Skaliert ein UIImage proportional runter, sodass die längere Kante ≤ maxDim ist.
    /// Wichtig für Widget-Speicherlimit — Original-Fotos sind oft 4000x4000.
    static func downscale(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard max(w, h) > maxDim else { return image }
        let scale = maxDim / max(w, h)
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1   // 1x statt Screen-Scale — Widget braucht kein @3x
            f.opaque = true
            return f
        }())
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
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
    /// Bild wird auf 256px runterskaliert für Widget-Speichersicherheit.
    @discardableResult
    func cacheSelfie(_ image: UIImage, key: String) -> String {
        let filename = stableFilename(for: "selfie_\(key)") // deterministisch pro User
        guard let folder = avatarsFolderURL else { return "" }
        let resized = Self.downscale(image, maxDim: 256)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return "" }
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
