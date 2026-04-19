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
                text: """
Verantwortlich für die Verarbeitung personenbezogener Daten im Sinne der DSGVO ist:

Dennis Gundermann · Lechstr. 19, 80638 München · drops-app.de

Kontakt: contact@drops-app.de

Bei Fragen zum Datenschutz kannst du uns jederzeit per E-Mail kontaktieren.
"""
            )

            LegalSection(
                title: "2. Welche Daten wir erheben",
                text: """
KONTO & AUTHENTIFIZIERUNG
• Sign in with Apple – Apple User ID, Nonce (SHA256-Hash), optional E-Mail, Authorization Code (für Token-Widerrufung bei Kontolöschung)
• Handynummer (Pflichtangabe bei Registrierung — damit dich deine Kontakte finden können)

PROFIL
• Name (frei wählbar)
• Geburtsdatum (Selbstangabe, zur Altersprüfung ≥ 16)
• Geschlecht (optional)
• E-Mail (nur bei Sign in with Apple, falls freigegeben)
• Profilbild (optional, auf Firebase Storage)
• Zuverlässigkeits-Score (Anzahl bestätigter / nicht eingehaltener Treffen)

NUTZUNG DER APP
• Standortdaten (GPS, nur bei aktivem Drop – siehe Abschnitt 4)
• Erstellte Drops (Koordinaten, Emoji, Aktivitätsname, Ablaufzeit)
• Beitritte, Beitrittsanfragen, aufgezeichnete Begegnungen
• Freundschaftsbeziehungen (reine Verknüpfung, keine Inhalte)

DISCOVERY-INDIZES
• Normalisierte Telefonnummer (E.164-Format) und E-Mail (normalisiert) als Suchindex, damit Freunde dich finden können

TECHNIK & KOMMUNIKATION
• FCM-Token (für Push-Benachrichtigungen, nur lokal)
• Bluetooth-Proximity-Token (anonyme 8-Zeichen-Kennung, siehe Abschnitt 5)
• Live-Activity-Daten (Name, Emoji, Profilbild, Teilnehmerzahl)
• Drops+ Kauf-Status
• Gerätetyp, Betriebssystem, App-Version

LOKAL (verlässt dein Gerät nicht)
• BLE-Bestätigungshistorie (zur Missbrauchs-Vermeidung)
• Push-Benachrichtigungs-Zeitstempel (zur Rate-Limitierung)

NICHT gespeichert: Ausweisdaten, biometrische Rohdaten, dein Adressbuch. Der Kontakt-Abgleich findet ausschließlich auf deinem Gerät statt.
"""
            )

            LegalSection(
                title: "3. Zweck & Rechtsgrundlage",
                text: """
Wir verarbeiten deine Daten für folgende Zwecke:

• Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO): Authentifizierung, Kontoverwaltung, Drop-Erstellung, Karte, Begegnungen, Bluetooth-Proximity, Push-Benachrichtigungen, Drops+

• Einwilligung (Art. 6 Abs. 1 lit. a DSGVO): Kontakt-Abgleich, Profilbild-Upload

• Berechtigtes Interesse (Art. 6 Abs. 1 lit. f DSGVO): Moderation & Missbrauchs-Vermeidung (Admin-Panel, Sperren, Zuverlässigkeits-Score), Sicherheit der Plattform

Einwilligungen kannst du jederzeit über die App-Einstellungen oder durch Kontolöschung widerrufen.
"""
            )

            LegalSection(
                title: "4. Standortdaten",
                text: """
Drops erhebt deinen Standort NUR, wenn mindestens eine dieser Bedingungen erfüllt ist:
• Du hast einen aktiven Drop erstellt
• Du bist einem Drop beigetreten

GENAUIGKEIT: GPS mit bester Auflösung. Auf der Karte für andere Nutzer wird der Standort durch den Drop-Radius maskiert.

HINTERGRUND-MODUS: Damit Drops auch im Hintergrund aktualisiert werden, läuft Location-Tracking weiter, solange ein Drop aktiv ist. Ohne aktiven Drop werden sofort keine Standortdaten mehr erhoben oder übertragen.

SPEICHERUNG: Der aktuelle Standort wird live an die Firebase Realtime Database (EU-Region, Frankfurt) übertragen und bei Drop-Beendigung sofort gelöscht. Wir speichern KEINE historischen Bewegungsprofile.
"""
            )

            LegalSection(
                title: "5. Bluetooth & automatische Treffen-Bestätigung",
                text: """
Drops nutzt Bluetooth Low Energy (BLE), um tatsächliche Treffen zwischen Drop-Teilnehmern automatisch zu erkennen — ohne dass du manuell bestätigen musst.

ÜBERTRAGEN WIRD:
• Eine anonyme 8-Zeichen-Kennung (abgeleitet aus deiner internen Nutzer-ID, NICHT deine Telefonnummer oder E-Mail)
• Eine drop-spezifische Service-UUID
• Keine Namen, keine Profilbilder, keine Standortdaten, keine MAC-Adressen

MISSBRAUCHS-VERMEIDUNG (drei Schutzebenen):
1. Mindestdauer: Frühestens 5 Minuten nach Drop-Beitritt kann eine Begegnung registriert werden
2. Partner-Cooldown: Dieselbe Person wird maximal alle 6 Stunden bestätigt
3. Tages-Limit: Maximal 4 Bluetooth-Bestätigungen pro Tag

ENTFERNUNG: Eine Begegnung wird nur registriert, wenn das Signal stärker als -72 dBm ist (ca. 5-10 Meter).

HINTERGRUND-MODUS: BLE läuft im Hintergrund, solange ein Drop aktiv ist. Ohne aktiven Drop wird Bluetooth nicht genutzt.

SPEICHERUNG: Die BLE-Bestätigungshistorie wird AUSSCHLIESSLICH lokal auf deinem Gerät gespeichert und verlässt dein iPhone nicht. Nur die eigentliche Begegnung wird in der Realtime DB als Verknüpfung zwischen den beiden Nutzer-IDs gespeichert.

RECHTSGRUNDLAGE: Art. 6 Abs. 1 lit. b DSGVO (Kernfunktion von Drops).
"""
            )

            LegalSection(
                title: "6. Kontakt-Abgleich (optional)",
                text: """
Wenn du die Funktion „Freunde finden" nutzt, kannst du Drops dein Adressbuch durchsuchen lassen, um Kontakte zu entdecken, die ebenfalls Drops nutzen.

ABLAUF:
• Telefonnummern werden zu E.164-Format normalisiert, E-Mails werden normalisiert
• Jede normalisierte Adresse wird mit dem Firebase-Discovery-Index verglichen
• Bei Treffer wird dir der entsprechende Drops-Nutzer zur Freundschaftsanfrage angeboten

NICHT GESPEICHERT: Dein Adressbuch wird weder an unsere Server übertragen noch lokal dauerhaft kopiert. Nur die Übereinstimmungen, die du aktiv als Freund hinzufügst, werden gespeichert.

RECHTSGRUNDLAGE: Ausdrückliche Einwilligung (Art. 6 Abs. 1 lit. a DSGVO). Widerruf über iOS-Systemeinstellungen (Einstellungen → Drops → Kontakte).
"""
            )

            LegalSection(
                title: "7. Push-Benachrichtigungen",
                text: """
Mit deiner Zustimmung senden wir Push-Benachrichtigungen über Apple Push Notification Service (APNs) und Firebase Cloud Messaging (FCM).

ARTEN:
• Drops in deiner Nähe (max. 1× alle 30 Minuten)
• Warnung bei Drops in deiner Heimzone (max. 1× alle 60 Minuten)
• Beitrittsanfragen zu deinem Drop
• Automatische Bestätigung abgelaufener Beitrittsanfragen
• Jemand ist deinem Drop beigetreten
• Neue aufgezeichnete Begegnungen
• Freund startet Drop in deiner Nähe
• Re-Engagement-Hinweise bei längerer Inaktivität

FCM-TOKEN: Das Gerät-Token wird nur lokal in den App-Einstellungen gespeichert, nicht in der Datenbank. Du kannst Push jederzeit über iOS-Systemeinstellungen deaktivieren.
"""
            )

            LegalSection(
                title: "8. Live Activity (Dynamic Island & Sperrbildschirm)",
                text: """
Sobald du einem Drop beitrittst oder einen startest, zeigt iOS im Dynamic Island und auf dem Sperrbildschirm eine Live-Übersicht.

ANGEZEIGTE DATEN: Drop-Name, Emoji, Teilnehmerzahl, Ablaufzeit, Vornamen und Profilbilder der Teilnehmer sowie deren voraussichtliche Ankunftszeit.

TECHNISCH: Die Live-Activity läuft über Apples ActivityKit LOKAL auf deinem Gerät. APNs wird nur als Trigger-Kanal für Aktualisierungen genutzt — keine Nutzerdaten werden an Apple übertragen.

ADRESSERMITTLUNG: Die Drop-Adresse wird über Apples CLGeocoder-Dienst aus den GPS-Koordinaten ermittelt. Dabei werden die Koordinaten kurzzeitig an Apple-Server übertragen. Apples Datenschutzrichtlinien: apple.com/privacy
"""
            )

            LegalSection(
                title: "9. Drops+ (In-App-Kauf)",
                text: """
Drops+ ist ein optionales kostenpflichtiges Zusatz-Feature (z.B. Drop-Hervorhebung auf der Karte, größerer Suchradius, Score-Schutz).

ZAHLUNGSABWICKLUNG: Der Kauf läuft ausschließlich über Apples App Store mit deiner Apple-ID. Wir erhalten keine Zahlungsdaten, keine Apple-ID und keine Kreditkarteninformationen.

WAS DROPS SPEICHERT: Nur die Information, dass du Drops+ freigeschaltet hast (Flag isPlusUser: true in deinem Nutzerprofil).

SPEICHERDAUER: Bis zur Kontolöschung. Rückerstattung über Apple.
"""
            )

            LegalSection(
                title: "10. Moderation & Admin-Funktionen",
                text: """
Zur Sicherung der Plattform gegen Missbrauch existiert ein Admin-Bereich mit eingeschränktem Zugriff.

WER HAT ZUGRIFF: Ausschließlich der Betreiber (Dennis Gundermann) sowie ggf. manuell benannte Moderatoren.

WAS ADMINS EINSEHEN KÖNNEN:
• Nutzerliste mit Name, E-Mail, Registrierungsdatum, Sperr- und Drops+-Status
• Aktive Drops (Aktivitätsname, Emoji)
• Aggregierte Statistiken

WAS ADMINS TUN KÖNNEN: Nutzer sperren/entsperren, Drops vorzeitig beenden, Accounts löschen (bei Verstößen), Drops+-Status manuell setzen.

RECHTSGRUNDLAGE: Berechtigtes Interesse an einer sicheren Plattform (Art. 6 Abs. 1 lit. f DSGVO).
"""
            )

            LegalSection(
                title: "11. Drittanbieter & Auftragsverarbeiter",
                text: """
GOOGLE LLC / GOOGLE IRELAND LTD.:
• Firebase Authentication – Apple-Sign-In-Verifizierung
• Firebase Realtime Database (Region europe-west1, Frankfurt) – Live-Daten (Drops, Standort, Begegnungen)
• Firebase Storage – Profilbilder
• Firebase Firestore – Profilergänzungen (Zuverlässigkeits-Score, Profilbild-URL)
• Firebase Cloud Messaging – Push-Zustellung

Google LLC ist unter dem EU-US Data Privacy Framework zertifiziert. Eine Auftragsverarbeitungsvereinbarung (AVV) nach Art. 28 DSGVO ist abgeschlossen. Details: policies.google.com/privacy

APPLE INC.:
• Sign in with Apple (optional)
• Apple Push Notification Service (APNs)
• App Store / StoreKit – Drops+ Kaufabwicklung
• CLGeocoder – Koordinaten → Adresse (für Live Activity)

Details: apple.com/legal/privacy

KEINE WEITEREN DRITTANBIETER. Drops nutzt keine Werbe-SDKs, keine externen Analyse-Tools (z.B. Google Analytics, Firebase Analytics, Mixpanel, Facebook SDK) und kein Tracking für Marketingzwecke.
"""
            )

            LegalSection(
                title: "12. Speicherdauer",
                text: """
• Kontodaten: Bis zur Kontolöschung
• Profilbild: Bis zur Kontolöschung oder manuellem Entfernen
• Drops: Bis zur Beendigung durch dich oder automatischem Ablauf
• Beitritte/Anfragen: Automatisch mit Drop-Ende gelöscht
• Standort: Live, sofortige Löschung nach Drop-Ende
• Aufgezeichnete Begegnungen: Bis zur Kontolöschung
• Discovery-Indizes (Telefon/E-Mail): Bis zur Kontolöschung
• BLE-Bestätigungshistorie (lokal): Tägliche Liste zurückgesetzt um Mitternacht; Partner-Cooldown bis App-Deinstallation
• FCM-Token (lokal): Bis App-Deinstallation
"""
            )

            LegalSection(
                title: "13. Deine Rechte",
                text: """
Du hast das Recht auf:

• Auskunft über gespeicherte Daten (Art. 15 DSGVO)
• Berichtigung unrichtiger Daten (Art. 16 DSGVO)
• Löschung deiner Daten (Art. 17 DSGVO) – direkt in der App möglich
• Einschränkung der Verarbeitung (Art. 18 DSGVO)
• Datenübertragbarkeit (Art. 20 DSGVO)
• Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)
• Widerruf erteilter Einwilligungen (Art. 7 Abs. 3 DSGVO)
• Beschwerde bei einer Aufsichtsbehörde (Art. 77 DSGVO)

Zur Ausübung deiner Rechte: contact@drops-app.de

Zuständige Aufsichtsbehörde: Bayerisches Landesamt für Datenschutzaufsicht (BayLDA), Promenade 18, 91522 Ansbach
"""
            )

            LegalSection(
                title: "14. Datensicherheit",
                text: """
• Alle Übertragungen erfolgen TLS-verschlüsselt
• Firebase-Sicherheitsregeln stellen sicher, dass jeder Nutzer nur auf seine eigenen Daten schreibend zugreifen kann
• Drop-Standorte sind nur über den vom Host definierten Sichtbarkeits-Radius zugänglich
• Der Zuverlässigkeits-Score ist für andere Nutzer nicht sichtbar
"""
            )

            LegalSection(
                title: "15. Minderjährige",
                text: "Drops ist nicht für Personen unter 18 Jahren bestimmt. Bei der Registrierung wird das Geburtsdatum abgefragt und Accounts unter 18 werden blockiert. Falls du Kenntnis davon hast, dass eine minderjährige Person Drops nutzt, wende dich bitte an contact@drops-app.de."
            )

            LegalSection(
                title: "16. Änderungen dieser Erklärung",
                text: "Wir behalten uns vor, diese Datenschutzerklärung anzupassen, um rechtliche oder technische Änderungen abzubilden. Bei wesentlichen Änderungen informieren wir dich per Push-Benachrichtigung oder beim nächsten App-Start. Maßgebend ist die jeweils aktuelle Version, die auf drops-app.de/datenschutz abrufbar ist. Das Datum der letzten Aktualisierung findest du oben."
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
                text: "Diese Nutzungsbedingungen gelten für die Nutzung der mobilen App „Drops" und alle damit verbundenen Dienste. Mit der Nutzung der App erklärst du dich mit diesen Bedingungen einverstanden."
            )

            LegalSection(
                title: "2. Nutzungsvoraussetzungen",
                text: """
• Du musst mindestens 18 Jahre alt sein
• Du benötigst eine Apple-ID für „Sign in with Apple"
• Du musst eine gültige Handynummer hinterlegen, damit dich deine Kontakte finden können
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
• Erstellung mehrerer Accounts zur Umgehung von Sperren
"""
            )

            LegalSection(
                title: "5. Drops erstellen",
                text: "Öffentliche Drops sind für alle Nutzer in deiner Nähe sichtbar. Du bist verantwortlich für den Inhalt deiner Drops. Drops, die gegen diese Bedingungen verstoßen, können ohne Vorankündigung gelöscht werden. Drops werden automatisch beendet, wenn du sie deaktivierst oder die App schließt."
            )

            LegalSection(
                title: "6. Drops+ (In-App-Kauf)",
                text: "Drops+ ist ein optionales kostenpflichtiges Zusatz-Feature. Der Kauf wird über den Apple App Store abgewickelt. Für Widerruf, Rückerstattung und Laufzeit gelten die Bedingungen von Apple. Drops+ schaltet ausschließlich Zusatzfunktionen frei und ändert nichts an den grundlegenden Pflichten aus diesen Nutzungsbedingungen."
            )

            LegalSection(
                title: "7. Geistiges Eigentum",
                text: "Alle Rechte an der App, dem Design, dem Logo und dem Code liegen beim Anbieter. Du erhältst eine nicht übertragbare, nicht-exklusive Lizenz zur persönlichen Nutzung der App. Du darfst die App weder kopieren, modifizieren, dekompilieren noch für andere Zwecke verwenden."
            )

            LegalSection(
                title: "8. Haftungsbeschränkung",
                text: "Drops vermittelt lediglich die Möglichkeit zur Begegnung zwischen Nutzern und ist nicht verantwortlich für das Verhalten der Nutzer. Wir haften nicht für Schäden, die aus der Nutzung der App entstehen, sofern diese nicht auf grober Fahrlässigkeit oder Vorsatz beruhen."
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
