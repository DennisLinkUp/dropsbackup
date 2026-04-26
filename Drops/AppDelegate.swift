import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import FirebaseCrashlytics
import UserNotifications

// MARK: - AppDelegate
// Notwendig für Firebase Phone Auth auf echtem Gerät.
// Firebase braucht APNs-Token zur Device-Verifikation (stiller Push).
// FCM-Token wird separat für Push Notifications (SOS, DropIn) verwendet.

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase so früh wie möglich konfigurieren – vor dem ersten SwiftUI-Frame.
        FirebaseApp.configure()

        // Crashlytics aktivieren (wird automatisch durch FirebaseApp.configure() gestartet).
        // In Debug-Builds unterdrücken wir das Senden von Crashes an Firebase,
        // damit Entwicklungs-Crashes keine Production-Metriken verfälschen.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif

        // Falls beim letzten App-Start ein Crash war, frühzeitig loggen damit wir
        // sehen welcher User betroffen war.
        if Crashlytics.crashlytics().didCrashDuringPreviousExecution() {
            Crashlytics.crashlytics().log("⚠️ Previous session ended with a crash")
        }

        // User-ID zuordnen sobald bekannt — Crashlytics kann dann pro User filtern.
        if let uid = Auth.auth().currentUser?.uid {
            Crashlytics.crashlytics().setUserID(uid)
        }

        // FCM Delegate setzen
        Messaging.messaging().delegate = self

        // Notification Center Delegate
        UNUserNotificationCenter.current().delegate = self

        // Gerät für Remote Notifications registrieren — OHNE User-Dialog.
        // Firebase Phone Auth braucht den APNs-Token für stille Verifikations-Pushes.
        // Der User-sichtbare Notification-Dialog wird am Ende des Onboardings angefragt
        // (AppIntroStep), damit er im richtigen Kontext erscheint.
        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }
        return true
    }

    // MARK: - APNs Token → Firebase weiterleiten

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Firebase Phone Auth braucht das für silent push verification
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        // FCM bekommt ebenfalls den APNs Token
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Gerät hat kein APNs (z.B. Simulator) – Firebase fällt auf reCAPTCHA zurück
        print("Drops: APNs nicht verfügbar – \(error.localizedDescription)")
    }

    // MARK: - Remote Notifications (Phone Auth silent push)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Firebase Phone Auth: stille Pushes abfangen
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }

    // MARK: - FCM Token (MessagingDelegate)

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("Drops FCM Token: \(token)")
        // Token im UserDefaults speichern → AppStore kann ihn für Notifications nutzen
        UserDefaults.standard.set(token, forKey: "fcmToken")
        // Token nach Firebase schreiben, damit Cloud-Functions (z.B. Friendship-Push)
        // den Empfänger gezielt adressieren können.
        Task { @MainActor in
            RealtimeDBManager.shared.setMyFCMToken(token)
        }
        // Notification aussenden damit AppStore reagieren kann
        NotificationCenter.default.post(
            name: Notification.Name("FCMTokenDidRefresh"),
            object: nil,
            userInfo: ["token": token]
        )
    }

    // MARK: - Vordergrund-Notifications anzeigen (UNUserNotificationCenterDelegate)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Notifications auch im Vordergrund anzeigen (für SOS, DropIn-Alerts)
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        // Deep Link: bei SOS-Notification zur Karte navigieren
        if let type = userInfo["type"] as? String {
            NotificationCenter.default.post(
                name: Notification.Name("DropsNotificationTapped"),
                object: nil,
                userInfo: ["type": type, "data": userInfo]
            )
        }
        completionHandler()
    }
}
