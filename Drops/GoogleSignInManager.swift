import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI
import UIKit

// MARK: - Google Sign In Manager

class GoogleSignInManager: NSObject, ObservableObject {

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    /// E-Mail des eingeloggten Google-Accounts (nur nach erfolgreichem Sign-In verfügbar)
    private(set) var lastGoogleEmail: String? = nil

    func signIn(completion: @escaping (Bool, Bool) -> Void) {
        isLoading = true
        errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Google Sign-In konnte nicht initialisiert werden."
                completion(false, false)
            }
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = topViewController() else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Kein aktives Fenster gefunden."
                completion(false, false)
            }
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            guard let self else { return }

            if let error = error {
                let nsError = error as NSError
                DispatchQueue.main.async {
                    self.isLoading = false
                    // Code 1 = User hat abgebrochen — kein Fehler anzeigen
                    if nsError.code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = "Google Sign-In fehlgeschlagen. Bitte nochmal versuchen."
                    }
                    completion(false, false)
                }
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Google Sign-In fehlgeschlagen. Bitte nochmal versuchen."
                    completion(false, false)
                }
                return
            }

            self.lastGoogleEmail = user.profile?.email

            // Vornamen persistieren — für Quick-Login-Button + Profil-Pre-fill
            if let given = user.profile?.givenName, !given.isEmpty {
                UserDefaults.standard.set(given, forKey: "ud_appleGivenName")
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Task {
                do {
                    if Auth.auth().currentUser != nil {
                        try? Auth.auth().signOut()
                    }
                    let authResult = try await Auth.auth().signIn(with: credential)
                    let isNew = authResult.additionalUserInfo?.isNewUser ?? false
                    await MainActor.run {
                        self.isLoading = false
                        completion(true, isNew)
                    }
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "Google Login fehlgeschlagen. Bitte nochmal versuchen."
                        completion(false, false)
                    }
                }
            }
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

// MARK: - Google G Logo

/// Offizielles Google-G SVG aus dem Asset-Catalog. Punkt.
struct GoogleGLogo: View {
    let size: CGFloat
    var body: some View {
        Image("google_g")
            .resizable()
            .renderingMode(.original)
            .frame(width: size, height: size)
    }
}
