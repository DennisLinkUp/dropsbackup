import SwiftUI
import CoreLocation
import UserNotifications

@main
struct LinkUpApp: App {

    // AppDelegate übernimmt Firebase.configure() + APNs-Setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var store = AppStore()
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
                    .onOpenURL { url in handleUniversalLink(url) }
                    .onAppear { requestPermissionsIfNeeded() }
            } else {
                OnboardingView()
                    .environmentObject(store)
                    .preferredColorScheme(preferredScheme)
                    .onOpenURL { url in
                        handleUniversalLink(url)
                    }
            }
        }
        .onChange(of: scenePhase) { phase in
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
}
