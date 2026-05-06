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
        static let homeZone     = "drops_homezone"
        /// Prefix für die mehreren wiederholenden Power-Hour-Trigger
        /// (pro Wochentag × Window-Startzeit ein eigener Identifier).
        static let powerHourPrefix = "drops_powerhour_"
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

        // Marketing-Copy mit Curiosity, Pain-Points & FOMO. Bewusst kein
        // Hinweis auf konkrete Drops in der Nähe (würde sonst falsche
        // Erwartung wecken — das macht checkNearbyDrops separat).
        let messages: [(title: String, body: String)] = [
            ("Während du scrollst… 📱",
             "…läuft 200m weg jemand mit Kaffee an dir vorbei. Drop reicht."),
            ("Schon wieder \"lass mal\"? 🙄",
             "Hier antwortet keiner mit \"bald\". Drop's, wer Bock hat kommt."),
            ("Geht in 60 Sekunden raus 🚪",
             "Aktivität droppen, jemand kommt, fertig. Echt so einfach."),
            ("Deine Stadt schläft nicht 🌃",
             "Bier, Park, Spaziergang. Drop, und es ist sofort sichtbar."),
            ("Spontan oder nie ⚡️",
             "Heute Abend? In 10 Min kannst du draußen sein. Probier's."),
            ("Chat oder Treffen? 💬 → 🤝",
             "Drops überspringt den Chat. Drop, hin, fertig."),
            ("Jeder hier hat grad Bock 👀",
             "Ein Tap und du siehst wer in deiner Stadt jetzt was startet."),
            ("Spontan ist das neue Geplant 🎯",
             "Während andere planen, droppst du. Karte auf, hingehen, fertig."),
            ("Spontan ist das neue Geplant ✨",
             "Wer wartet bis Donnerstag, verpasst Sonntag. Drop's einfach."),
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

    // MARK: - Power-Hour Notifications
    //
    // Planen wir wiederkehrend lokal: pro Power-Hour-Window × Wochentag wird
    // ein eigener UNCalendarNotificationTrigger angelegt. iOS feuert die
    // automatisch jede Woche zur passenden Uhrzeit, ohne dass die App
    // running sein muss. Beim App-Start räumen wir alte Power-Hour-Pushs
    // weg und planen sie frisch — so bleiben Änderungen am Window-Schema
    // automatisch in Sync.
    //
    // Texte sind variabel ausgewählt aus einem kleinen Pool, damit der
    // User nicht jede Woche exakt denselben Wortlaut sieht (Push-Müdigkeit).
    func schedulePowerHourNotifications() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            // 1. Alte Power-Hour-Requests entfernen (Prefix-basiert)
            let pending = await center.pendingNotificationRequests()
            let staleIDs = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix(ID.powerHourPrefix) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }

            // 2. Drei Notification-Typen pro Window + Weekday:
            //    a) "Pre" — 1h vor Start ("Power-Hour startet bald")
            //    b) "Start" — exakt zum Start
            //    c) "End-Warn" — 1h vor Ende ("letzte Chance")
            //
            // Texte sind variabel ausgewählt aus einem kleinen Pool, damit der
            // User nicht jede Woche exakt denselben Wortlaut sieht.
            let startMessages: [(title: String, body: String)] = [
                ("⚡ Power-Hour startet",
                 "Doppelter Boost-Bonus aktiv — +25 Punkte für jeden Drop, den du jetzt erstellst oder triffst."),
                ("⚡ Bonus-Zeit läuft",
                 "Wer jetzt einen Drop startet, bekommt +25 Punkte — sieh wer in der Nähe Lust auf was hat."),
                ("⚡ Drops Power-Hour",
                 "Mehr Punkte als sonst (+25 statt +15). Perfekter Moment für nen Spontan-Drop."),
            ]
            let preMessages: [(title: String, body: String)] = [
                ("⚡ Power-Hour in 1 Stunde",
                 "Gleich gibt's +25 Punkte für jeden Drop — bereite dich vor."),
                ("Bald Power-Hour",
                 "In einer Stunde startet der doppelte Boost-Bonus."),
                ("⚡ 1 Stunde bis Power-Hour",
                 "Plan deinen Drop — gleich gibt's +25 statt +15 Punkte."),
            ]
            let endMessages: [(title: String, body: String)] = [
                ("⚡ Power-Hour endet in 1 Stunde",
                 "Letzte Chance auf +25 Punkte — wer jetzt noch einen Drop startet, kassiert den Bonus."),
                ("Letzte Stunde Bonus",
                 "Power-Hour läuft noch 60 Minuten. Jetzt einen Drop erstellen lohnt sich extra."),
                ("⚡ Endspurt",
                 "Eine Stunde übrig für den Power-Hour-Bonus."),
            ]

            for window in AppStore.powerHourWindows {
                for weekday in window.weekdays {
                    // a) Pre-Notification 1h vor Start
                    let preHour = window.startHour - 1
                    if preHour >= 0 {
                        try? await scheduleRecurring(
                            on: center,
                            id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_pre",
                            weekday: weekday, hour: preHour, minute: 0,
                            messages: preMessages,
                            type: "powerhour_pre",
                            windowLabel: window.label
                        )
                    }

                    // b) Start-Notification
                    try? await scheduleRecurring(
                        on: center,
                        id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_start",
                        weekday: weekday, hour: window.startHour, minute: 0,
                        messages: startMessages,
                        type: "powerhour_start",
                        windowLabel: window.label
                    )

                    // c) End-Warn-Notification 1h vor Ende
                    let endWarnHour = window.endHour - 1
                    if endWarnHour > window.startHour {
                        try? await scheduleRecurring(
                            on: center,
                            id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_endwarn",
                            weekday: weekday, hour: endWarnHour, minute: 0,
                            messages: endMessages,
                            type: "powerhour_endwarn",
                            windowLabel: window.label
                        )
                    }
                }
            }
        }
    }

    /// Helper: legt einen wiederkehrenden Calendar-Trigger an.
    private func scheduleRecurring(
        on center: UNUserNotificationCenter,
        id: String,
        weekday: Int, hour: Int, minute: Int,
        messages: [(title: String, body: String)],
        type: String,
        windowLabel: String
    ) async throws {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour    = hour
        comps.minute  = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let pick = messages[Int.random(in: 0 ..< messages.count)]
        let content = UNMutableNotificationContent()
        content.title = pick.title
        content.body  = pick.body
        content.sound = .default
        content.userInfo = ["type": type, "window": windowLabel]

        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(req)
    }

    /// Entfernt alle geplanten Power-Hour-Pushs. Praktisch beim Logout
    /// oder wenn der User Push-Benachrichtigungen abschaltet.
    func cancelAllPowerHourNotifications() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let ids = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix(ID.powerHourPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
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

    // MARK: - Reliability-Punkte erhalten

    /// Wird bei jedem Punktgewinn gefeuert (Show-Up, Drop-Beitritt etc.).
    /// reason: kurzer Kontext-Text (z.B. "Dein Drop wurde besucht").
    func notifyPointsEarned(delta: Int, totalPoints: Int, reason: String) {
        guard delta > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "✨ +\(delta) Punkte"
        content.body  = "\(reason) · jetzt \(totalPoints) Punkte gesamt"
        content.sound = .default
        content.userInfo = ["type": "points_earned", "delta": delta, "total": totalPoints]
        schedule(content, id: "points_\(Date().timeIntervalSince1970)")
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
