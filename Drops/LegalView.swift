import SwiftUI

// MARK: - Legal Document Type

enum LegalDocumentType {
    case privacy, terms, impressum
}

// MARK: - Legal View (Container)

struct LegalView: View {
    let type: LegalDocumentType
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Environment(\.dismiss) private var dismiss

    var title: String {
        switch type {
        case .privacy:   return "Datenschutzerklärung"
        case .terms:     return "Nutzungsbedingungen"
        case .impressum: return "Impressum"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgSecondary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch type {
                        case .privacy:   PrivacyContent()
                        case .terms:     TermsContent()
                        case .impressum: ImpressumContent()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(tr("common.close")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
        }
    }
}

// MARK: - Shared Components

private struct LegalSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.bgPrimary)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(UIColor.separator).opacity(0.4), lineWidth: 0.5))
        .padding(.bottom, 10)
    }
}

private struct LegalHeader: View {
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.bottom, 6)
    }
}

// MARK: - Privacy Policy Content

private struct PrivacyContent: View {
    var body: some View {
        Group {
            LegalHeader(
                icon: "lock.shield.fill",
                color: Color(UIColor.systemBlue),
                subtitle: "Zuletzt aktualisiert: April 2026"
            )

            LegalSection(
                title: "1. Verantwortlicher",
                text: "Verantwortlich für die Verarbeitung personenbezogener Daten im Sinne der DSGVO ist:\n\nDrops App · drops-app.de\nEntwickler: Dennis Gundermann\nLechstr. 19, 80638 München\n\nKontakt: contact@drops-app.de\n\nBei Fragen zum Datenschutz kannst du uns jederzeit per E-Mail kontaktieren."
            )

            LegalSection(
                title: "2. Welche Daten wir erheben",
                text: """
• Telefonnummer (zur Authentifizierung via Firebase)
• Standortdaten (GPS, nur während der App-Nutzung)
• Profilbild (optional — lokal als Selfie und/oder als Upload in Firebase Storage)
• Vorname (bei Ausweis-Verifizierung aus MRZ gelesen)
• Geburtsdatum (bei Ausweis-Verifizierung, nur für Altersberechnung)
• Verifizierungsstatus (ob Ausweis-Verifizierung erfolgreich war oder manuell durch einen Admin bestätigt wurde)
• Aktivitätsdaten (erstellte Drops, Begegnungen, Beitritte)
• Notfallkontakt (nur lokal auf deinem Gerät)
• FCM-Token (für Push-Benachrichtigungen)
• Technische Daten (Geräte-ID, Betriebssystem, App-Version)

NICHT gespeichert werden:
• Das Foto deines Ausweises
• Die Ausweis- oder Passnummer
• Biometrische Rohdaten jeglicher Art
"""
            )

            LegalSection(
                title: "2b. Live Activity & Dynamic Island",
                text: """
Wenn du einen aktiven Drop hast, nutzt Drops Apples ActivityKit, um Echtzeit-Informationen auf dem Sperrbildschirm und in der Dynamic Island anzuzeigen.

WELCHE DATEN ANGEZEIGT WERDEN:
• Aktivitätsname und Emoji des Drops
• Anzahl der Teilnehmer
• Adresse des Drop-Standorts (wird einmalig per Apple CLGeocoder aus GPS-Koordinaten ermittelt)
• Emojis, Namen und Profilbilder der Teilnehmer

LOKALE ZWISCHENSPEICHERUNG:
Profilbilder werden temporär in einem gemeinsam genutzten App-Bereich (App Group: group.com.dennis.drops) zwischen der Haupt-App und der Widget-Erweiterung geteilt. Diese Daten verlassen dein Gerät nicht und werden beim Beenden des Drops automatisch nicht mehr aktualisiert.

ADRESSERMITTLUNG:
Die Drop-Adresse wird über Apples CLGeocoder-Dienst aus den GPS-Koordinaten des Drop-Standorts ermittelt. Dabei werden die Koordinaten kurzzeitig an Apple-Server übertragen. Apple's Datenschutzrichtlinien gelten: apple.com/privacy
"""
            )

            LegalSection(
                title: "2a. Ausweis-Verifizierung",
                text: """
Drops bietet eine freiwillige Identitätsverifizierung an, um echte Begegnungen unter verifizierten Personen zu ermöglichen. Die Verifizierung kann auf zwei Wegen erfolgen:

WEG 1 – AUSWEIS-SCAN (automatisch):
Die maschinenlesbare Zone (MRZ) deines Personalausweises oder Reisepasses wird per OCR lokal auf deinem Gerät ausgelesen. Dabei werden ausschließlich dein Vorname und dein Geburtsdatum erfasst.

WEG 2 – MANUELLE VERIFIZIERUNG:
Drops-Administratoren können den Verifizierungsstatus eines Accounts manuell bestätigen, z.B. nach persönlicher Identitätsprüfung.

WAS GESPEICHERT WIRD:
Nur: Vorname, Geburtsdatum und ob die Verifizierung erfolgreich war (Ja/Nein). Das Ausweisfoto, die Ausweis- oder Passnummer und alle weiteren Daten werden weder gespeichert noch übertragen.

VERARBEITUNG NUR AUF DEINEM GERÄT:
Der gesamte OCR-Prozess findet ausschließlich auf deinem iPhone statt. Keine Bilddaten verlassen dein Gerät.

RECHTSGRUNDLAGE:
Die Verarbeitung erfolgt auf Basis deiner ausdrücklichen Einwilligung (Art. 6 Abs. 1 lit. a DSGVO). Du kannst diese Einwilligung jederzeit widerrufen, indem du dein Konto löschst. Dabei werden alle gespeicherten Daten sofort und vollständig gelöscht.
"""
            )

            LegalSection(
                title: "3. Zweck der Datenverarbeitung",
                text: """
Wir verarbeiten deine Daten ausschließlich für folgende Zwecke:

• Authentifizierung und Kontoverwaltung (Art. 6 Abs. 1 lit. b DSGVO)
• Bereitstellung der Kernfunktionen der App (Drops erstellen, Karte, Begegnungen)
• Echtzeit-Standortfreigabe im Umgebungsbereich (nur bei aktiviertem Drop)
• SOS-Notfallfunktion (Standortübermittlung an Notfallkontakt)
• Push-Benachrichtigungen zu Drops in deiner Nähe und Re-Engagement-Hinweise
• Anzeige von Drop-Informationen auf dem Sperrbildschirm (Live Activity)
• Verbesserung der App (nur mit deiner Zustimmung)
"""
            )

            LegalSection(
                title: "4. Standortdaten",
                text: "Drops erhebt deinen Standort nur, wenn du die App aktiv verwendest (\"Nur während der Nutzung\"). Dein Standort wird temporär an Firebase Realtime Database übertragen, solange du einen aktiven Drop hast oder die SOS-Funktion aktiviert ist. Nach Deaktivierung werden Standortdaten sofort gelöscht. Wir speichern keine historischen Bewegungsprofile."
            )

            LegalSection(
                title: "5. Drittanbieter & Auftragsverarbeiter",
                text: """
GOOGLE LLC (USA) — EU-US Data Privacy Framework zertifiziert, AVV abgeschlossen:
• Firebase Authentication – Telefonnummer-Verifizierung
• Firebase Realtime Database – Live-Daten (Drops, Standorte, SOS)
• Firebase Cloud Messaging – Push-Benachrichtigungen
• Firebase Storage – Profilbilder (optional, nur wenn du ein Foto hochlädst)
• Firebase Firestore – Profildaten (Name, Verifizierungsstatus, Profilbild-URL)

Weitere Informationen: policies.google.com/privacy

APPLE INC. (USA):
• CLGeocoder / Apple Maps – Einmalige Umwandlung von GPS-Koordinaten in lesbare Adressen für die Live Activity. Es werden nur die Koordinaten des Drop-Standorts übertragen, keine personenbezogenen Daten.
• ActivityKit / WidgetKit – Darstellung von Drop-Informationen auf dem Sperrbildschirm

Apples Datenschutzrichtlinien: apple.com/privacy
"""
            )

            LegalSection(
                title: "6. Speicherdauer",
                text: "Kontodaten werden gelöscht, sobald du dein Konto löschst. Aktive Drops werden nach ihrer Beendigung automatisch aus der Datenbank entfernt. SOS-Einträge werden nach maximal 30 Minuten automatisch gelöscht. Logs werden nach 90 Tagen automatisch bereinigt."
            )

            LegalSection(
                title: "7. Deine Rechte",
                text: """
Du hast das Recht auf:

• Auskunft über gespeicherte Daten (Art. 15 DSGVO)
• Berichtigung unrichtiger Daten (Art. 16 DSGVO)
• Löschung deiner Daten (Art. 17 DSGVO)
• Einschränkung der Verarbeitung (Art. 18 DSGVO)
• Datenübertragbarkeit (Art. 20 DSGVO)
• Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)
• Beschwerde bei einer Aufsichtsbehörde (Art. 77 DSGVO)

Zur Ausübung deiner Rechte: contact@drops-app.de
"""
            )

            LegalSection(
                title: "8. Datensicherheit",
                text: "Alle Daten werden verschlüsselt übertragen (TLS 1.3). Firebase-Sicherheitsregeln stellen sicher, dass Nutzer nur auf ihre eigenen Daten zugreifen können. Telefonnummern werden von Firebase gehasht gespeichert und nicht im Klartext übertragen."
            )

            LegalSection(
                title: "9. Minderjährige",
                text: "Drops ist nicht für Personen unter 16 Jahren bestimmt. Wir erheben wissentlich keine Daten von Minderjährigen. Falls du Kenntnis davon hast, dass ein Kind unter 16 Jahren Drops nutzt, wende dich bitte an contact@drops-app.de."
            )

            LegalSection(
                title: "10. Änderungen",
                text: "Wir behalten uns vor, diese Datenschutzerklärung anzupassen. Über wesentliche Änderungen wirst du per Push-Benachrichtigung oder beim nächsten App-Start informiert. Das Datum der letzten Aktualisierung ist oben angegeben."
            )
        }
    }
}

// MARK: - Impressum Content

private struct ImpressumContent: View {
    var body: some View {
        Group {
            LegalHeader(
                icon: "building.columns.fill",
                color: Color(UIColor.systemOrange),
                subtitle: "Angaben gemäß § 5 TMG"
            )

            LegalSection(
                title: "Anbieter",
                text: "Dennis Gundermann\nLechstr. 19\n80638 München\n\nE-Mail: contact@drops-app.de\nWebsite: drops-app.de\n\nDiese App wird von einer Privatperson entwickelt und betrieben. Es besteht keine Pflicht zur Umsatzsteuer-Identifikationsnummer."
            )

            LegalSection(
                title: "Verantwortlich für den Inhalt",
                text: "Dennis Gundermann (Anschrift wie oben)\n\nDie Drops App ist ein privates Nebenprojekt und wird nicht gewerblich betrieben."
            )

            LegalSection(
                title: "Streitschlichtung",
                text: "Die Europäische Kommission stellt eine Plattform zur Online-Streitbeilegung (OS) bereit:\nhttps://ec.europa.eu/consumers/odr\n\nWir sind nicht bereit oder verpflichtet, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen."
            )

            LegalSection(
                title: "Haftung für Inhalte",
                text: "Als Diensteanbieter sind wir gemäß § 7 Abs. 1 TMG für eigene Inhalte verantwortlich. Wir sind jedoch nicht verpflichtet, übermittelte oder gespeicherte fremde Informationen zu überwachen. Nutzer-generierte Inhalte (Drop-Beschreibungen) liegen in der Verantwortung der jeweiligen Nutzer."
            )

            LegalSection(
                title: "Urheberrecht",
                text: "Die durch uns erstellten Inhalte und Werke unterliegen dem deutschen Urheberrecht. Die Vervielfältigung, Bearbeitung, Verbreitung und jede Art der Verwertung außerhalb der Grenzen des Urheberrechts bedürfen der schriftlichen Zustimmung des Erstellers."
            )
        }
    }
}

// MARK: - Terms of Use Content

private struct TermsContent: View {
    var body: some View {
        Group {
            LegalHeader(
                icon: "doc.text.fill",
                color: Color(UIColor.systemIndigo),
                subtitle: "Zuletzt aktualisiert: April 2026"
            )

            LegalSection(
                title: "1. Geltungsbereich",
                text: "Diese Nutzungsbedingungen gelten für die Nutzung der mobilen App \"Drops\" (nachfolgend \"App\") und alle damit verbundenen Dienste. Mit der Nutzung der App erklärst du dich mit diesen Bedingungen einverstanden."
            )

            LegalSection(
                title: "2. Nutzungsvoraussetzungen",
                text: """
• Du musst mindestens 16 Jahre alt sein
• Du benötigst eine gültige Telefonnummer zur Registrierung
• Du benötigst ein Gerät mit iOS 16.0 oder neuer
• Eine aktive Internetverbindung ist für die meisten Funktionen erforderlich
• Du bist verantwortlich für alle Aktivitäten unter deinem Account
"""
            )

            LegalSection(
                title: "3. Erlaubte Nutzung",
                text: "Drops dient ausschließlich dazu, echte Begegnungen und spontane Treffen zwischen Menschen zu ermöglichen. Du verpflichtest dich, die App nur für persönliche, nicht-kommerzielle Zwecke zu verwenden und dabei alle geltenden Gesetze zu beachten."
            )

            LegalSection(
                title: "4. Verbotene Aktivitäten",
                text: """
Folgende Aktivitäten sind untersagt:

• Erstellung falscher oder irreführender Drops
• Belästigung, Bedrohung oder Nötigung anderer Nutzer
• Spam oder automatisierte Massenanfragen
• Umgehung von Sicherheitsmaßnahmen
• Kommerzielle Werbung oder Promotion
• Verwendung der App für illegale Aktivitäten jeglicher Art
• Missbrauch der SOS-Notfallfunktion
• Erstellung mehrerer Accounts zur Umgehung von Sperren
"""
            )

            LegalSection(
                title: "5. Drops erstellen",
                text: "Öffentliche Drops sind für alle Nutzer in deiner Nähe sichtbar. Du bist verantwortlich für den Inhalt deiner Drops. Drops, die gegen diese Bedingungen verstoßen, können ohne Vorankündigung gelöscht werden. Drops werden automatisch beendet, wenn du sie deaktivierst oder die App schließt."
            )

            LegalSection(
                title: "6. SOS-Notfallfunktion",
                text: "Die SOS-Funktion ist ausschließlich für echte Notfallsituationen bestimmt. Der Missbrauch der SOS-Funktion kann zur sofortigen Sperrung deines Accounts führen. Im Notfall zögere nicht — die Funktion ruft automatisch den Notruf 112 an und benachrichtigt deinen Notfallkontakt sowie Drops-Nutzer in der Nähe."
            )

            LegalSection(
                title: "7. Geistiges Eigentum",
                text: "Alle Rechte an der App, dem Design, dem Logo und dem Code liegen beim Anbieter. Du erhältst eine nicht übertragbare, nicht-exklusive Lizenz zur persönlichen Nutzung der App. Du darfst die App weder kopieren, modifizieren, dekompilieren noch für andere Zwecke verwenden."
            )

            LegalSection(
                title: "8. Haftungsbeschränkung",
                text: "Drops vermittelt lediglich die Möglichkeit zur Begegnung zwischen Nutzern und ist nicht verantwortlich für das Verhalten der Nutzer. Wir haften nicht für Schäden, die aus der Nutzung der App entstehen, sofern diese nicht auf grober Fahrlässigkeit oder Vorsatz beruhen. Die Nutzung der SOS-Funktion ersetzt nicht den Notruf bei Behörden."
            )

            LegalSection(
                title: "9. Verfügbarkeit",
                text: "Wir bemühen uns um eine hohe Verfügbarkeit der App, können diese aber nicht garantieren. Wartungsarbeiten, technische Störungen oder höhere Gewalt können zu vorübergehenden Ausfällen führen. Wir behalten uns das Recht vor, Funktionen jederzeit zu ändern oder einzustellen."
            )

            LegalSection(
                title: "10. Account-Sperrung",
                text: "Wir behalten uns vor, Accounts bei Verstößen gegen diese Bedingungen zu sperren oder zu löschen. Bei schwerwiegenden Verstößen erfolgt eine Sperrung ohne Vorankündigung. Du kannst dein Konto jederzeit selbst in den Einstellungen löschen."
            )

            LegalSection(
                title: "11. Änderungen",
                text: "Wir können diese Nutzungsbedingungen jederzeit anpassen. Über wesentliche Änderungen wirst du vorab informiert. Die weitere Nutzung der App nach Inkrafttreten der Änderungen gilt als Zustimmung."
            )

            LegalSection(
                title: "12. Anwendbares Recht",
                text: "Es gilt das Recht der Bundesrepublik Deutschland. Gerichtsstand ist, soweit gesetzlich zulässig, der Sitz des Anbieters. Bei Streitigkeiten steht dir auch der Weg zur Online-Streitbeilegung der EU-Kommission offen: ec.europa.eu/consumers/odr"
            )

            LegalSection(
                title: "13. Kontakt",
                text: "Bei Fragen zu diesen Nutzungsbedingungen wende dich an:\n\ncontact@drops-app.de\ndrops-app.de\n\nWir sind bemüht, deine Anfrage innerhalb von 5 Werktagen zu beantworten."
            )
        }
    }
}
