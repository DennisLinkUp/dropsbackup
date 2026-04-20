import Foundation

// MARK: - Admin Bootstrap Credentials
//
// ⚠️ SICHERHEIT: Diese Datei enthält die E-Mails/Telefonnummern, die beim
// Login automatisch als Admin freigeschaltet werden. Sie dient nur als
// Bootstrap — nachdem ein Admin einmal im users/{uid}/isAdmin-Flag steht,
// ist die Datenbank die Ground Truth (siehe AdminPanelView).
//
// VOR PUBLIC-RELEASE:
//   • Einträge in Firebase Remote Config verschieben ODER
//   • Diese Datei ins .gitignore aufnehmen und als Template
//     `AdminConfig.swift.example` committen
//
// Solange das Repo privat ist, ist das zentrale Halten hier akzeptabel.

enum AdminConfig {
    /// E-Mails die beim Login automatisch Admin-Status erhalten
    /// (Apple-Private-Relay-E-Mail).
    static let bootstrapEmails: Set<String> = [
        "ww688nmjp8@privaterelay.appleid.com"
    ]

    /// Telefonnummern (E.164-Format) die beim Login automatisch Admin-Status erhalten.
    static let bootstrapPhones: Set<String> = [
        "+4915771677000"
    ]

    /// Prüft ob die gegebenen Credentials einen Bootstrap-Admin matchen.
    /// Alle String-Parameter dürfen leer sein — werden dann ignoriert.
    static func isBootstrapAdmin(
        authEmail: String = "",
        authPhone: String = "",
        storedAppleEmail: String = "",
        savedPhone: String = ""
    ) -> Bool {
        let emailLower = authEmail.lowercased()
        let appleLower = storedAppleEmail.lowercased()
        if !emailLower.isEmpty && bootstrapEmails.contains(emailLower) { return true }
        if !appleLower.isEmpty && bootstrapEmails.contains(appleLower) { return true }
        if !authPhone.isEmpty && bootstrapPhones.contains(authPhone) { return true }
        if !savedPhone.isEmpty && bootstrapPhones.contains(savedPhone) { return true }
        return false
    }

    /// Shortcut nur für den E-Mail-Fall (z.B. in saveUserProfile).
    static func isBootstrapAdminEmail(_ email: String) -> Bool {
        bootstrapEmails.contains(email.lowercased())
    }
}
