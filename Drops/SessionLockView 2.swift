import SwiftUI
import LocalAuthentication

// MARK: - Session Lock Screen
// Wird angezeigt wenn die App nach Timeout aus dem Hintergrund zurückkommt.
// Der User ist noch eingeloggt — nur Face ID / Touch ID erforderlich zum Entsperren.

struct SessionLockView: View {
    @EnvironmentObject var store: AppStore
    @State private var failCount   = 0
    @State private var errorMsg: String? = nil
    @State private var isAuthenticating = false

    private var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    private var biometricIcon: String {
        biometricType == .faceID ? "faceid" : "touchid"
    }

    private var biometricLabel: String {
        biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    var body: some View {
        ZStack {
            // Hintergrund
            AppAuroraBackground().ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App-Icon / Branding
                VStack(spacing: 12) {
                    Text("💧")
                        .font(.system(size: 64))
                    Text("Drops")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Entsperre die App mit \(biometricLabel)")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // Face ID Button
                Button {
                    authenticate()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, isActive: isAuthenticating)
                        Text(biometricLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 140, height: 140)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .disabled(isAuthenticating)

                // Fehlermeldung
                if let err = errorMsg {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                Spacer()

                // Ausloggen als Notfallausweg
                Button {
                    store.isSessionLocked = false
                    store.clearLocalData()
                } label: {
                    Text("Abmelden")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear { authenticate() }
    }

    // MARK: - Biometric Auth

    private func authenticate() {
        let ctx = LAContext()
        var authError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                    error: &authError) else {
            // Kein Biometrik verfügbar → PIN-Fallback via deviceOwnerAuthentication
            authenticateWithPasscode()
            return
        }

        isAuthenticating = true
        errorMsg = nil

        ctx.evaluatePolicy(
            .deviceOwnerAuthentication,   // erlaubt auch Passcode-Fallback
            localizedReason: "Drops entsperren"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    failCount = 0
                    errorMsg  = nil
                    withAnimation { store.isSessionLocked = false }
                } else {
                    failCount += 1
                    if failCount >= 3 {
                        // 3 Fehlversuche → abmelden
                        store.isSessionLocked = false
                        store.clearLocalData()
                    } else {
                        errorMsg = "\(biometricLabel) fehlgeschlagen. Noch \(3 - failCount) Versuch\(3 - failCount == 1 ? "" : "e")."
                    }
                }
            }
        }
    }

    private func authenticateWithPasscode() {
        let ctx = LAContext()
        isAuthenticating = true
        ctx.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Drops entsperren"
        ) { success, _ in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success { withAnimation { store.isSessionLocked = false } }
                else {
                    failCount += 1
                    if failCount >= 3 {
                        store.isSessionLocked = false
                        store.clearLocalData()
                    } else {
                        errorMsg = "Authentifizierung fehlgeschlagen."
                    }
                }
            }
        }
    }
}
