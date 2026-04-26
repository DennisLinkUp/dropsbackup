import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Firebase Phone Auth Manager

@MainActor
class FirebaseAuthManager: ObservableObject {

    enum PhoneAuthState: Equatable {
        case idle
        case sendingSMS
        case smsSent(verificationID: String)
        case verifying
        case success
        case error(String)

        static func == (lhs: PhoneAuthState, rhs: PhoneAuthState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.sendingSMS, .sendingSMS),
                 (.verifying, .verifying), (.success, .success): return true
            case (.smsSent(let a), .smsSent(let b)): return a == b
            case (.error(let a), .error(let b)):     return a == b
            default: return false
            }
        }
    }

    @Published var state: PhoneAuthState = .idle

    // Als Property halten damit ARC es nicht während des await freigibt
    private var uiDelegate: FirebaseUIDelegate? = nil

    // MARK: - Beta Dev Bypass

    /// Meldet den User anonym bei Firebase an (kein SMS, kein reCAPTCHA).
    /// Nur in Beta-Builds wenn BetaConfig.skipIDVerification == true.
    func signInAnonymously() async -> Bool {
        state = .sendingSMS
        do {
            try await Auth.auth().signInAnonymously()
            state = .success
            return true
        } catch {
            state = .error("Beta-Login fehlgeschlagen: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Live Firebase Phone Auth

    /// Sendet SMS über Firebase – erwartet vollständige Nummer z.B. "+4915771677000"
    func sendVerificationCode(to phoneNumber: String) async {
        state = .sendingSMS
        guard FirebaseApp.app() != nil else {
            state = .error("Firebase nicht konfiguriert. Bitte App neu starten.")
            return
        }

        // UIDelegate initialisieren damit Firebase reCAPTCHA als In-App-Sheet
        // presentieren kann (statt externem Browser) und der Callback zuverlässig
        // aufgerufen wird. Ohne Delegate bleibt die Continuation manchmal hängen.
        let delegate = FirebaseUIDelegate()
        self.uiDelegate = delegate   // ARC: Referenz halten bis Callback kommt

        await withCheckedContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: delegate) { [weak self] verificationID, error in
                Task { @MainActor [weak self] in
                    self?.uiDelegate = nil   // freigeben
                    if let error = error {
                        self?.state = .error(self?.friendlyError(error) ?? error.localizedDescription)
                    } else if let verificationID = verificationID {
                        self?.state = .smsSent(verificationID: verificationID)
                    } else {
                        self?.state = .error("SMS konnte nicht gesendet werden. Bitte nochmal versuchen.")
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Verifiziert den 6-stelligen SMS-Code gegen Firebase
    func verifyCode(_ code: String) async -> Bool {
        guard case .smsSent(let verificationID) = state else { return false }
        state = .verifying
        do {
            // Sicherstellen dass kein veralteter User eingeloggt ist (z.B. nach Konto-Löschung)
            if Auth.auth().currentUser != nil {
                try? Auth.auth().signOut()
            }
            let credential = PhoneAuthProvider.provider()
                .credential(withVerificationID: verificationID, verificationCode: code)
            try await Auth.auth().signIn(with: credential)
            state = .success
            return true
        } catch {
            state = .error(friendlyError(error))
            return false
        }
    }

    func reset() { state = .idle }

    // MARK: - Lesbare deutsche Fehlermeldungen

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        let code = nsError.code
        if code == AuthErrorCode.invalidPhoneNumber.rawValue {
            return "Ungültige Telefonnummer. Bitte mit Ländervorwahl eingeben."
        } else if code == AuthErrorCode.quotaExceeded.rawValue {
            return "Zu viele Versuche. Bitte etwas später nochmal probieren."
        } else if code == AuthErrorCode.sessionExpired.rawValue {
            return "Code abgelaufen. Bitte neuen Code anfordern."
        } else if code == AuthErrorCode.invalidVerificationCode.rawValue {
            return "Falscher Code. Bitte nochmal prüfen."
        } else if code == AuthErrorCode.missingPhoneNumber.rawValue {
            return "Bitte Telefonnummer eingeben."
        } else if code == AuthErrorCode.tooManyRequests.rawValue {
            return "Zu viele Versuche mit dieser Nummer. Bitte einige Stunden warten."
        } else if code == AuthErrorCode.networkError.rawValue {
            return "Netzwerkfehler. Bitte Internetverbindung prüfen."
        } else if code == AuthErrorCode.appNotAuthorized.rawValue {
            return "App nicht autorisiert. Firebase-Konfiguration prüfen."
        } else if code == AuthErrorCode.userNotFound.rawValue {
            return "Konto nicht gefunden. Bitte neu registrieren."
        } else if code == AuthErrorCode.userDisabled.rawValue {
            return "Dieses Konto wurde deaktiviert. Bitte Support kontaktieren."
        } else if code == AuthErrorCode.userTokenExpired.rawValue || code == AuthErrorCode.invalidUserToken.rawValue {
            return "Sitzung abgelaufen. Bitte nochmal anmelden."
        }
        return nsError.localizedDescription
    }
}

// MARK: - Firebase reCAPTCHA UI Delegate

/// Eigene AuthUIDelegate-Implementierung, damit Firebase das reCAPTCHA-Sheet
/// presentieren kann wenn kein APNs-Silent-Push verfügbar ist (Development-Build).
final class FirebaseUIDelegate: NSObject, AuthUIDelegate {

    func present(_ viewControllerToPresent: UIViewController,
                 animated flag: Bool,
                 completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.topViewController()?.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.topViewController()?.dismiss(animated: flag, completion: completion)
        }
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Apple Sign In Manager

/// Kümmert sich um den kompletten Sign-In-with-Apple + Firebase-Flow (Nonce, SHA256, Credential).
/// Verwendet manuelle ASAuthorizationController-Präsentation, um das automatische
/// iOS-System-Credential-Sheet (doppelter Button in iOS 26) zu verhindern.
class AppleSignInManager: NSObject, ObservableObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    static let shared = AppleSignInManager()

    private var currentNonce: String?
    // (success, isNewUser)
    private var pendingCompletion: ((Bool, Bool) -> Void)?
    /// Callback für Reauth-Flow (nur Bool — kein isNewUser)
    private var pendingReauthCompletion: ((Bool) -> Void)?
    // ARC: Controller als Property halten damit er nicht vor dem Delegate-Callback freigegeben wird
    private var currentController: ASAuthorizationController?
    /// E-Mail vom letzten Apple Sign-In (nur beim ersten Login verfügbar)
    private(set) var lastAppleEmail: String? = nil
    /// Apple User ID — stabil, immer verfügbar
    private(set) var lastAppleUserID: String? = nil
    /// Authorization Code vom letzten Apple Sign-In — wird für Token-Widerruf bei Konto-Löschung benötigt
    private(set) var lastAuthorizationCode: String? = nil

    // MARK: - Manueller Sign-In (verhindert System-Credential-Overlay)

    /// Startet den Apple-Sign-In-Flow manuell über ASAuthorizationController.
    /// Im Gegensatz zu SignInWithAppleButton wird kein automatisches System-Sheet präsentiert.
    func signIn(completion: @escaping (Bool, Bool) -> Void) {
        isLoading = true
        errorMessage = nil
        pendingCompletion = completion

        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        // Referenz halten damit ARC den Controller nicht vor dem Delegate-Callback freigibt
        currentController = controller
        controller.performRequests()
    }

    /// Re-Authentifizierung mit Apple — nötig vor dem Löschen des Accounts (requiresRecentLogin).
    func reauthenticate(completion: @escaping (Bool) -> Void) {
        pendingReauthCompletion = completion
        pendingCompletion = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = []     // keine Scopes nötig — nur Token zum Re-Auth
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        currentController = controller
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return UIWindow()
        }
        return window
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let tokenData = appleIDCredential.identityToken,
            let tokenString = String(data: tokenData, encoding: .utf8)
        else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Apple Sign-In fehlgeschlagen. Bitte nochmal versuchen."
                self.pendingCompletion?(false, false)
                self.pendingCompletion = nil
            }
            return
        }

        // E-Mail + Apple User ID merken
        if let email = appleIDCredential.email, !email.isEmpty {
            lastAppleEmail = email.lowercased()
        }
        // Apple User ID ist stabil und immer verfügbar — als Admin-Fallback
        lastAppleUserID = appleIDCredential.user
        // Authorization Code für späteres Token-Revoke bei Konto-Löschung merken
        if let codeData = appleIDCredential.authorizationCode,
           let codeString = String(data: codeData, encoding: .utf8) {
            lastAuthorizationCode = codeString
        }
        // Vorname aus Apple-Credential — WICHTIG: Apple liefert fullName
        // nur beim ALLERERSTEN Authorization-Request je User/App-Kombination.
        // Danach ist das Feld nil — wir müssen ihn also sofort persistieren.
        if let given = appleIDCredential.fullName?.givenName, !given.isEmpty {
            UserDefaults.standard.set(given, forKey: "ud_appleGivenName")
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        Task {
            // ── Re-Authentifizierungs-Pfad (für Konto-Löschung) ──────────────
            if let reauth = pendingReauthCompletion {
                do {
                    try await Auth.auth().currentUser?.reauthenticate(with: credential)
                    await MainActor.run {
                        self.currentController = nil
                        self.pendingReauthCompletion = nil
                        reauth(true)
                    }
                } catch {
                    await MainActor.run {
                        self.currentController = nil
                        self.pendingReauthCompletion = nil
                        reauth(false)
                    }
                }
                return
            }

            // ── Normaler Sign-In-Pfad ─────────────────────────────────────────
            do {
                // Sicherstellen dass kein anderer User eingeloggt ist (z.B. nach Konto-Löschung)
                if Auth.auth().currentUser != nil {
                    try? Auth.auth().signOut()
                }
                let result = try await Auth.auth().signIn(with: credential)
                let isNew = result.additionalUserInfo?.isNewUser ?? false
                // Fallback-Namenserfassung: Apple sendet fullName nur beim allerersten
                // Sign-In. Falls wir ihn dort nicht bekommen haben, ziehen wir als
                // Notnagel Firebase's displayName (wird aus Apple fullName gesetzt wenn
                // vorhanden) oder den PersonNameComponents.formatted String.
                let existingGiven = UserDefaults.standard.string(forKey: "ud_appleGivenName") ?? ""
                if existingGiven.isEmpty {
                    if let display = result.user.displayName,
                       let firstWord = display.split(separator: " ").first,
                       !firstWord.isEmpty {
                        UserDefaults.standard.set(String(firstWord), forKey: "ud_appleGivenName")
                    } else if let components = appleIDCredential.fullName {
                        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
                        if let firstWord = formatted.split(separator: " ").first, !firstWord.isEmpty {
                            UserDefaults.standard.set(String(firstWord), forKey: "ud_appleGivenName")
                        }
                    }
                }
                await MainActor.run {
                    self.currentController = nil
                    self.isLoading = false
                    self.pendingCompletion?(true, isNew)
                    self.pendingCompletion = nil
                }
            } catch {
                await MainActor.run {
                    self.currentController = nil
                    self.isLoading = false
                    self.errorMessage = "Apple Login fehlgeschlagen. Bitte nochmal versuchen."
                    self.pendingCompletion?(false, false)
                    self.pendingCompletion = nil
                }
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        DispatchQueue.main.async {
            self.currentController = nil
            self.isLoading = false
            if let reauth = self.pendingReauthCompletion {
                self.pendingReauthCompletion = nil
                reauth(false)
                return
            }
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                self.errorMessage = "Apple Sign-In fehlgeschlagen. Bitte nochmal versuchen."
            }
            self.pendingCompletion?(false, false)
            self.pendingCompletion = nil
        }
    }

    // MARK: – Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Drops: Nonce konnte nicht generiert werden – \(errorCode)")
        }
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// AppleSignInButtonView is defined in OnboardingView.swift (requires SwiftUI import)
