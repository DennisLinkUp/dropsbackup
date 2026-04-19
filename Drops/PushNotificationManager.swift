import Foundation
import UserNotifications
import CoreLocation

// MARK: - Push / Local Notification Manager

@MainActor
final class PushNotificationManager {

    static let shared = PushNotificationManager()
    private init() {}

    // MARK: - Notification IDs
    private enum ID {
        static let reEngagement = "drops_reengagement"
        static let nearbyDrops  = "drops_nearby"
        static let dropin       = "dropin"
        static let encounter    = "encounter"
        static let friendDrop   = "friend_drop"
        static let homeZone     = "drops_homezone"
    }

    // MARK: - UserDefaults Keys
    private enum UDKey {
        static let lastNearbyNotif   = "pn_last_nearby_notif"
        static let sessionHadAction  = "pn_session_had_action"
        static let lastReEngageNotif = "pn_last_reengage_notif"
        static let lastHomeZoneNotif = "pn_last_homezone_notif"
    }

    // MARK: - Session State
    private var sessionHadAction = false

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    /// Fragt nur wenn der User noch nie gefragt wurde (notDetermined).
    /// Sicher mehrfach aufrufbar — keine doppelten Dialoge.
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async { self.requestPermission() }
        }
    }

    // MARK: - Session Action Tracking
    // Ruf das auf wenn der User etwas sinnvolles tut (Drop erstellen, beitreten, Detail öffnen)

    func trackAction() {
        sessionHadAction = true
    }

    func resetSession() {
        sessionHadAction = false
    }

    // MARK: - Re-Engagement Notification
    // Wird beim App-Backgrounding geplant wenn kein sinnvoller Schritt gemacht wurde.

    func scheduleReEngagementIfNeeded() {
        guard !sessionHadAction else {
            cancelReEngagementNotification()
            return
        }

        // Nicht spammen: mindestens 2 Stunden zwischen zwei Re-Engagement-Pushs
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastReEngageNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            guard elapsed > 2 * 3600 else { return }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "reengagement"]

        // Abwechslungsreiche Texte — kein falscher Hinweis auf Drops in der Nähe
        let messages: [(title: String, body: String)] = [
            ("Drops wartet auf dich 👋",
             "Du hast die App noch nicht genutzt — starte oder tritt einem Drop bei."),
            ("Spontan ist das neue Geplant ⚡️",
             "Einfach Drop erstellen und schauen wer kommt."),
            ("Wann triffst du dich das nächste Mal? 🤔",
             "Öffne Drops und starte etwas — spontan, ohne Planung."),
            ("Nicht schüchtern sein 🙌",
             "Erstelle einen Drop und lass andere zu dir kommen."),
            ("Noch nichts gemacht heute? 😄",
             "Öffne Drops und sieh was möglich ist."),
        ]
        let pick = messages[Int.random(in: 0 ..< messages.count)]
        content.title = pick.title
        content.body  = pick.body

        // Nach 18 Minuten feuern
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 18 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: ID.reEngagement,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        // Vorherige ersetzen
        center.removePendingNotificationRequests(withIdentifiers: [ID.reEngagement])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastReEngageNotif)
    }

    func cancelReEngagementNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [ID.reEngagement])
    }

    // MARK: - Nearby Drops Notification
    // Prüft ob Drops in der Nähe sind und benachrichtigt ggf. — max. 1x pro 30 Min.

    func checkNearbyDrops(_ drops: [MapAnnotationItem], userLocation: CLLocationCoordinate2D) {
        // Nur wenn kein eigener aktiver Drop läuft
        let nearbyRadius: Double = 600  // Meter

        let nearby = drops.filter { $0.isNearby(from: userLocation, maxMeters: nearbyRadius) }
        guard !nearby.isEmpty else { return }

        // Throttle: max 1x alle 30 Min
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastNearbyNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            guard elapsed > 30 * 60 else { return }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "nearby_drops"]

        if nearby.count == 1, let drop = nearby.first {
            let dist = Int(drop.distance(from: userLocation))
            let distStr = dist >= 1000
                ? String(format: "%.1f km", Double(dist) / 1000)
                : "\(dist) m"
            content.title = "\(drop.emoji) \(drop.activity) in der Nähe"
            content.body  = "\(drop.name) ist gerade aktiv — nur \(distStr) entfernt."
        } else {
            let closest = nearby.sorted { $0.distance(from: userLocation) < $1.distance(from: userLocation) }
            let top = closest.prefix(2).map { "\($0.emoji) \($0.activity)" }.joined(separator: ", ")
            content.title = "\(nearby.count) Drops in deiner Nähe 📍"
            content.body  = "\(top) und mehr — schau auf die Karte."
        }

        // Sofort (nil trigger = wird direkt zugestellt wenn App im Hintergrund)
        let request = UNNotificationRequest(
            identifier: ID.nearbyDrops,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ID.nearbyDrops])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastNearbyNotif)
    }

    // MARK: - Home Zone Warning Notification
    // Feuert wenn der User seine Heimzone betritt und fremde Drops in der Nähe sind.
    // Max. 1x alle 60 Minuten um Spam zu vermeiden.

    func notifyHomeZoneWarning(nearbyDropCount: Int) {
        // Throttle: max 1x pro 60 Min
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastHomeZoneNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            guard elapsed > 60 * 60 else { return }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "homezone_warning"]

        let messages: [(title: String, body: String)] = [
            ("🏠 Du bist in deiner Heimzone",
             nearbyDropCount > 1
             ? "\(nearbyDropCount) Drops sind gerade in deiner Nähe — andere könnten deinen Standort sehen."
             : "Ein Drop ist gerade in deiner Nähe — andere könnten deinen Standort sehen."),
            ("🔒 Heimzone betreten",
             "Drops in der Nähe können deinen ungefähren Wohnort sichtbar machen. Sei vorsichtig."),
            ("🏠 Privatsphäre-Hinweis",
             "Du bist nahe deiner Heimzone und es gibt aktive Drops. Möchtest du wirklich beitreten?"),
        ]
        let pick = messages[Int.random(in: 0 ..< messages.count)]
        content.title = pick.title
        content.body  = pick.body

        let request = UNNotificationRequest(
            identifier: ID.homeZone,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ID.homeZone])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastHomeZoneNotif)
    }

    // MARK: - Join Request Notifications

    /// Push wenn Host NICHT in der App ist und jemand beitreten will
    func notifyIncomingJoinRequest(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = "👋 Jemand möchte mitmachen"
        content.body  = "\(joinerName) möchte deinem \"\(activityName)\" beitreten. Bestätige in der App."
        content.sound = .default
        content.userInfo = ["type": "join_request"]
        schedule(content, id: "join_request_\(Date().timeIntervalSince1970)")
    }

    /// Push an Host wenn Auto-Accept ausgelöst wurde
    func notifyAutoAccepted(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Automatisch bestätigt"
        content.body  = "\(joinerName) wurde automatisch zu \"\(activityName)\" hinzugefügt, da keine Antwort kam."
        content.sound = .default
        content.userInfo = ["type": "auto_accept"]
        schedule(content, id: "auto_accept_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Drop-In Notification (jemand tritt eigenem Drop bei)

    func notifyDropIn(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = "📍 Jemand ist eingeDroppt!"
        content.body  = "\(joinerName) ist deinem Drop \"\(activityName)\" beigetreten."
        content.sound = .default
        content.userInfo = ["type": "dropin"]
        content.badge = 1
        schedule(content, id: "\(ID.dropin)_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Begegnung

    func notifyNewEncounter(withName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = "👋 Neue Begegnung"
        content.body  = "Warst du gerade bei \"\(activityName)\" mit \(withName)?"
        content.sound = .default
        content.userInfo = ["type": "encounter"]
        schedule(content, id: "\(ID.encounter)_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Freund in der Nähe

    func notifyFriendNearby(friendName: String, emoji: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(emoji) \(friendName) ist aktiv!"
        content.body  = "\(friendName) hat einen Drop gestartet: \(activityName)"
        content.sound = .default
        content.userInfo = ["type": "friend_drop"]
        schedule(content, id: "\(ID.friendDrop)_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Ablauf-Erinnerungen (bestehende Logik, jetzt hier zentralisiert)
    // Werden von DropNotificationManager in Models.swift gesteuert.

    // MARK: - Helpers

    var currentFCMToken: String? {
        UserDefaults.standard.string(forKey: "fcmToken")
    }

    private func schedule(_ content: UNMutableNotificationContent,
                          id: String,
                          trigger: UNNotificationTrigger? = nil) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
