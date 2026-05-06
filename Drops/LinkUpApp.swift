import SwiftUI
import CoreLocation
import UserNotifications
import StoreKit

@main
struct LinkUpApp: App {

    // AppDelegate übernimmt Firebase.configure() + APNs-Setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var store: AppStore = {
        let s = AppStore()
        AppStore.shared = s
        return s
    }()
    @AppStorage("mapStyleMode") private var mapStyleModeRaw = MapStyleMode.auto.rawValue
    @Environment(\.scenePhase) private var scenePhase

    // Hält den CLLocationManager am Leben bis der Dialog bestätigt ist
    @State private var permLocManager: CLLocationManager? = nil

    /// Fragt Standort- und Push-Berechtigungen an — nur wenn noch nicht bestimmt.
    /// Läuft auf dem Main-Thread, wird nach Login aufgerufen.
    private func requestPermissionsIfNeeded() {
        // Push Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                ) { granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            }
        }
        // Standort
        let mgr = CLLocationManager()
        permLocManager = mgr
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Universal Link Handler
    // Erwartet: https://drops-app.de/drop/{UUID}
    //           https://drops-app.de/invite/{inviterUID}
    private func handleUniversalLink(_ url: URL) {
        guard url.host == "drops-app.de",
              url.pathComponents.count >= 3 else { return }

        let section = url.pathComponents[1]
        let param   = url.pathComponents[2]

        if section == "drop", let dropID = UUID(uuidString: param) {
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.pendingDropID = dropID
            }
        } else if section == "invite" {
            // Einladungslink: Freund-Profil suchen / Freund hinzufügen
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.pendingInviteUsername = param
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch MapStyleMode(rawValue: mapStyleModeRaw) ?? .auto {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            // Altersschutz beim App-Start erzwingen (Schutz vor manipulierten Daten)
            let _ = store.enforceAgeGuard()

            if store.isAuthenticated {
                MainTabView()
                    .environmentObject(store)
                    .preferredColorScheme(preferredScheme)
                    .reviewPromptHandler(store: store)
                    .onOpenURL { url in handleUniversalLink(url) }
                    .onAppear {
                        requestPermissionsIfNeeded()
                        // Cold-Start: scenePhase = .active feuert kein onChange.
                        // Hier nochmal pollen falls AppDelegate ein Pending hat.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            if let pending = UserDefaults.standard.string(forKey: "ud_pendingQuickAction") {
                                UserDefaults.standard.removeObject(forKey: "ud_pendingQuickAction")
                                handlePendingQuickAction(pending)
                            }
                        }
                    }
            } else {
                OnboardingView()
                    .environmentObject(store)
                    .preferredColorScheme(preferredScheme)
                    .onOpenURL { url in
                        handleUniversalLink(url)
                    }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.isAppActive = false
                store.recordBackgrounded()
                // Nur für eingeloggte User — kein Push an Onboarding-Nutzer
                guard store.isAuthenticated else { break }
                Task { @MainActor in PushNotificationManager.shared.scheduleReEngagementIfNeeded() }
            case .active:
                store.isAppActive = true
                store.checkSessionTimeout()
                // Quick-Action vom AppDelegate konsumieren (Cold-Start oder
                // Background→Foreground). Kleine Verzögerung damit MainTabView
                // sicher gerendert ist.
                if store.isAuthenticated,
                   let pending = UserDefaults.standard.string(forKey: "ud_pendingQuickAction") {
                    UserDefaults.standard.removeObject(forKey: "ud_pendingQuickAction")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        handlePendingQuickAction(pending)
                    }
                }
                // Permissions + Session-Reset nur nach Login
                guard store.isAuthenticated else { break }
                Task { @MainActor in
                    PushNotificationManager.shared.cancelReEngagementNotification()
                    PushNotificationManager.shared.resetSession()
                    PushNotificationManager.shared.requestPermissionIfNeeded()
                }
                // Online-Heartbeat für Freundes-Anzeige (users/{uid}/lastActiveAt)
                RealtimeDBManager.shared.markOnlineHeartbeat()
            default:
                break
            }
        }
    }

    /// Routet eine Home-Screen Quick Action auf den entsprechenden Tab/Sheet.
    /// Setzt selectedTab direkt am Store + postet zusätzlich Notification damit
    /// MainTabView (für Create-Sheet) reagieren kann.
    private func handlePendingQuickAction(_ type: String) {
        switch type {
        case "com.dennis.drops.shortcut.create":
            store.selectedTab = .map
            NotificationCenter.default.post(
                name: Notification.Name("DropsQuickAction"),
                object: nil,
                userInfo: ["type": type]
            )
        case "com.dennis.drops.shortcut.map":
            store.selectedTab = .map
        case "com.dennis.drops.shortcut.feed":
            store.selectedTab = .feed
        case "com.dennis.drops.shortcut.profile":
            store.selectedTab = .profile
        default:
            break
        }
    }
}

// MARK: - In-App Review Prompt
//
// Apple-Limit: max 3 Prompts pro User pro 365 Tage. Beste Trigger sind „positive
// Momente" — wir feuern bei meaningful Show-Up-Counts (3, 10, 25). System-Sheet
// erscheint nur wenn das Limit nicht erreicht ist; sonst ist der Aufruf ein No-Op.
private struct ReviewPromptModifier: ViewModifier {
    @ObservedObject var store: AppStore
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            .onChange(of: store.shouldShowReviewPrompt) { _, newValue in
                guard newValue else { return }
                requestReview()
                // Persistiere Zeitpunkt damit AppStore das nicht zu schnell wieder triggert
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                          forKey: "ud_lastReviewRequestedAt")
                store.shouldShowReviewPrompt = false
            }
    }
}

extension View {
    func reviewPromptHandler(store: AppStore) -> some View {
        modifier(ReviewPromptModifier(store: store))
    }
}
