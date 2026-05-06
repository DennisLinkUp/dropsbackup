import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import CoreLocation

extension Notification.Name {
    static let dropsPlusStatusChanged = Notification.Name("DropsPlusStatusChanged")
}

// MARK: - Admin Bootstrap Credentials
//
// ⚠️ SICHERHEIT: Die E-Mails/Telefonnummern hier werden beim Login automatisch
// als Admin freigeschaltet. Nachdem ein Admin einmal im users/{uid}/isAdmin-Flag
// steht, ist die Datenbank die Ground Truth (siehe AdminPanelView).
//
// VOR PUBLIC-RELEASE: In Firebase Remote Config verschieben.
//
// Liegt bewusst in RealtimeDBManager.swift (statt separater Datei), damit es
// garantiert im Xcode-Target enthalten ist ohne separate pbxproj-Registrierung.

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

// MARK: - Realtime Database Manager
// Verwaltet Live-Daten: SOS-Standorte, aktive Drops von Fremden, Begegnungen

@MainActor
class RealtimeDBManager: ObservableObject {

    static let shared = RealtimeDBManager()
    private let db = Database.database(url: "https://drops-858d1-default-rtdb.europe-west1.firebasedatabase.app").reference()

    // MARK: - Remote Config (Feature Flags)

    /// Hört auf Änderungen an `/config/cityRestrictionEnabled` in der RTDB
    /// und spiegelt den Wert in `BetaConfig.cityRestrictionEnabled`. Damit
    /// kann der Geo-Gate nach App-Store-Approval per Firebase Console
    /// aktiviert werden, ohne neuen Build hochladen zu müssen.
    ///
    /// Wert in Firebase Console anlegen:
    /// `/config/cityRestrictionEnabled` → Boolean → `true` (für Launch in DE)
    /// oder `false` (App-Store-Review-Build).
    func bootstrapRemoteFlags() {
        db.child("config").child("cityRestrictionEnabled").observe(.value) { snap in
            if let v = snap.value as? Bool {
                BetaConfig.cityRestrictionEnabled = v
            } else if let n = snap.value as? NSNumber {
                BetaConfig.cityRestrictionEnabled = n.boolValue
            }
        }
    }

    // MARK: - User Profile

    /// Legt ein Nutzerprofil an oder aktualisiert es.
    /// Wird am Ende des Onboardings aufgerufen (phone auth & Apple).
    func saveUserProfile(
        name: String,
        email: String? = nil,
        birthdate: Date? = nil,
        gender: String? = nil
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var payload: [String: Any] = [
            "name": name,
            "updatedAt": ServerValue.timestamp()
        ]
        if let email = email, !email.isEmpty  { payload["email"] = email }
        if let bd = birthdate                  { payload["birthdate"] = bd.timeIntervalSince1970 }
        if let gender = gender, !gender.isEmpty { payload["gender"] = gender }

        // Auto-Admin für Bootstrap-Credentials (siehe AdminConfig)
        let authEmail = (email ?? Auth.auth().currentUser?.email ?? "").lowercased()
        if AdminConfig.isBootstrapAdminEmail(authEmail) {
            payload["isAdmin"] = true
        }

        // updateChildValues überschreibt nur die angegebenen Felder
        db.child("users").child(uid).updateChildValues(payload)
        // createdAt nur beim ersten Schreiben setzen
        db.child("users").child(uid).child("createdAt").setValue(ServerValue.timestamp()) { _, _ in }
    }

    /// Lädt das Profil des aktuell eingeloggten Nutzers einmalig.
    func loadUserProfile(completion: @escaping (UserProfileSnapshot?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(nil); return }
        db.child("users").child(uid).observeSingleEvent(of: .value) { snapshot in
            guard let dict = snapshot.value as? [String: Any] else { completion(nil); return }
            let settings = dict["settings"] as? [String: Any] ?? [:]
            let profile = UserProfileSnapshot(
                name:            dict["name"]            as? String,
                email:           dict["email"]           as? String,
                birthdate:       (dict["birthdate"]      as? Double).map { Date(timeIntervalSince1970: $0) },
                gender:          dict["gender"]          as? String,
                isAdmin:         dict["isAdmin"]         as? Bool ?? false,
                isBanned:        dict["isBanned"]        as? Bool ?? false,
                isPlusUser:      dict["isPlusUser"]      as? Bool ?? false,
                profileImageURL: nil,  // wird aus Firestore geladen
                settings:        UserSettingsSnapshot(
                    radiusFilter:         settings["radiusFilter"]         as? Double,
                    ageFilterMin:         settings["ageFilterMin"]         as? Int,
                    ageFilterMax:         settings["ageFilterMax"]         as? Int,
                    selectedAgeGroups:    settings["selectedAgeGroups"]    as? [String],
                    userInterests:        settings["userInterests"]        as? [String],
                    blockedUsers:         settings["blockedUsers"]         as? [String],
                    unavailabilityReason: settings["unavailabilityReason"] as? String,
                    genderFilterEnabled:  settings["genderFilterEnabled"]  as? Bool,
                    activityCategoryFilter: settings["activityCategoryFilter"] as? String
                )
            )
            completion(profile)
        }
    }

    /// Persistiert die Nutzer-Einstellungen (Radius, Filter etc.) in der Realtime DB,
    /// damit sie einen Logout/Re-Login oder Gerätewechsel überleben.
    /// Wird aus `AppStore.saveAll()` getriggert.
    func saveUserSettings(
        radiusFilter: Double,
        ageFilterMin: Int,
        ageFilterMax: Int,
        selectedAgeGroups: [String],
        userInterests: [String],
        blockedUsers: [String],
        unavailabilityReason: String,
        genderFilterEnabled: Bool,
        activityCategoryFilter: String
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "radiusFilter":           radiusFilter,
            "ageFilterMin":           ageFilterMin,
            "ageFilterMax":           ageFilterMax,
            "selectedAgeGroups":      selectedAgeGroups,
            "userInterests":          userInterests,
            "blockedUsers":           blockedUsers,
            "unavailabilityReason":   unavailabilityReason,
            "genderFilterEnabled":    genderFilterEnabled,
            "activityCategoryFilter": activityCategoryFilter,
            "updatedAt":              ServerValue.timestamp()
        ]
        db.child("users").child(uid).child("settings").updateChildValues(payload)
    }

    /// Aktualisiert den Namen im Realtime Database Profil.
    func updateUserProfile(uid: String, name: String) {
        let data: [String: Any] = [
            "name": name,
            "updatedAt": ServerValue.timestamp()
        ]
        db.child("users").child(uid).updateChildValues(data)
    }

    /// Schreibt den Nutzer in phoneIndex, emailIndex und usernameIndex, damit andere ihn
    /// per Kontakt-Abgleich oder Invite-Link finden.
    /// Wird bei jedem Login aufgerufen — idempotent, schadet bei Mehrfachaufruf nicht.
    func registerInDiscoveryIndex(uid: String, name: String, phone: String?, email: String?) {
        let payload: [String: Any] = ["uid": uid, "name": name]
        if let phone = phone, !phone.isEmpty {
            let normalized = Self.normalizePhone(phone)
            if !normalized.isEmpty {
                db.child("phoneIndex").child(normalized).setValue(payload)
            }
        }
        if let email = email, !email.isEmpty {
            // E-Mail als Schlüssel: "@" und "." durch sichere Zeichen ersetzen
            let key = email.lowercased()
                .replacingOccurrences(of: ".", with: ",")
                .replacingOccurrences(of: "@", with: "-at-")
            db.child("emailIndex").child(key).setValue(payload)
        }
    }

    /// Aktualisiert die Telefonnummer im phoneIndex. Entfernt die alte Nummer
    /// (wenn unterschiedlich) und legt die neue an. Bei leerer neuer Nummer wird
    /// nur die alte entfernt (User hat seine Nummer gelöscht → soll nicht mehr findbar sein).
    func updatePhoneDiscoveryIndex(uid: String, name: String, oldPhone: String?, newPhone: String?) {
        let oldNorm = (oldPhone?.isEmpty == false) ? Self.normalizePhone(oldPhone!) : ""
        let newNorm = (newPhone?.isEmpty == false) ? Self.normalizePhone(newPhone!) : ""

        // Alte Nummer entfernen, wenn sie sich geändert hat oder gelöscht wurde
        if !oldNorm.isEmpty && oldNorm != newNorm {
            db.child("phoneIndex").child(oldNorm).removeValue()
        }
        // Neue Nummer eintragen (setValue überschreibt — idempotent)
        if !newNorm.isEmpty {
            let payload: [String: Any] = ["uid": uid, "name": name]
            db.child("phoneIndex").child(newNorm).setValue(payload)
        }
    }

    /// Sucht Kontakte in phoneIndex UND emailIndex und gibt alle Treffer zurück.
    func lookupContactsOnDrops(
        phones: [String],
        emails: [String] = [],
        completion: @escaping ([ContactMatchResult]) -> Void
    ) {
        let myUID = Auth.auth().currentUser?.uid ?? ""
        let normalizedPhones = Set(phones.map { Self.normalizePhone($0) }).filter { !$0.isEmpty }
        let normalizedEmails = Set(emails.map {
            $0.lowercased()
             .replacingOccurrences(of: ".", with: ",")
             .replacingOccurrences(of: "@", with: "-at-")
        }).filter { !$0.isEmpty }

        var results: [ContactMatchResult] = []
        var seenUIDs = Set<String>()
        let group = DispatchGroup()

        for phone in normalizedPhones {
            group.enter()
            db.child("phoneIndex").child(phone).observeSingleEvent(of: .value) { snapshot in
                defer { group.leave() }
                guard let dict = snapshot.value as? [String: Any],
                      let uid  = dict["uid"]  as? String, uid != myUID, !seenUIDs.contains(uid),
                      let name = dict["name"] as? String else { return }
                seenUIDs.insert(uid)
                results.append(ContactMatchResult(phone: phone, uid: uid, name: name))
            }
        }

        for emailKey in normalizedEmails {
            group.enter()
            db.child("emailIndex").child(emailKey).observeSingleEvent(of: .value) { snapshot in
                defer { group.leave() }
                guard let dict = snapshot.value as? [String: Any],
                      let uid  = dict["uid"]  as? String, uid != myUID, !seenUIDs.contains(uid),
                      let name = dict["name"] as? String else { return }
                seenUIDs.insert(uid)
                results.append(ContactMatchResult(phone: emailKey, uid: uid, name: name))
            }
        }

        group.notify(queue: .main) { completion(results) }
    }

    /// Prüft ob bereits ein anderer Account mit identischem Namen UND Geburtsdatum existiert.
    /// Verhindert Doppel-Konten über verschiedene Auth-Methoden (Telefon + Apple).
    /// completion(true) = Duplikat gefunden → Registrierung blockieren
    func checkDuplicateAccount(name: String, birthdate: Date, completion: @escaping (Bool) -> Void) {
        let timestamp = birthdate.timeIntervalSince1970
        let currentUID = Auth.auth().currentUser?.uid ?? ""
        let normalizedInput = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Alle User mit diesem exakten Geburtsdatum laden (Firebase-Index)
        db.child("users")
            .queryOrdered(byChild: "birthdate")
            .queryEqual(toValue: timestamp)
            .observeSingleEvent(of: .value) { snapshot in
                guard let dict = snapshot.value as? [String: Any] else {
                    completion(false); return
                }
                // Name-Vergleich (case-insensitive) gegen alle Treffer
                let duplicate = dict.contains { uid, value in
                    guard uid != currentUID,
                          let entry = value as? [String: Any],
                          let storedName = entry["name"] as? String
                    else { return false }
                    return storedName.lowercased().trimmingCharacters(in: .whitespaces) == normalizedInput
                }
                completion(duplicate)
            }
    }

    /// Prüft ob die aktuelle Firebase-UID bereits ein gespeichertes Profil hat (Wieder-Login via Apple).
    func hasExistingProfile(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(false); return }
        db.child("users").child(uid).child("name").observeSingleEvent(of: .value) { [weak self] snapshot in
            let exists = snapshot.exists()
            // Auto-Admin beim Login prüfen und ggf. nachrüsten
            if exists, let self = self {
                let email = (Auth.auth().currentUser?.email ?? "").lowercased()
                if AdminConfig.isBootstrapAdminEmail(email) {
                    self.db.child("users").child(uid).child("isAdmin").observeSingleEvent(of: .value) { flagSnap in
                        if !(flagSnap.value as? Bool ?? false) {
                            self.db.child("users").child(uid).updateChildValues(["isAdmin": true])
                        }
                    }
                }
            }
            completion(exists)
        }
    }

    /// Löscht alle Nutzerdaten aus Realtime DB, Firestore und Storage.
    /// MUSS aufgerufen werden BEVOR der Auth-Account gelöscht wird — danach blockieren
    /// die Security Rules jeglichen Zugriff.
    ///
    /// Bewusst NUR Direktpfade, keine Scans: Security Rules für `.read` auf Top-Level
    /// Collections wie `drops` oder `encounters` sind i.d.R. per-Element definiert,
    /// wodurch ein `getData()` auf die ganze Collection hängen oder scheitern kann.
    /// Deshalb räumen wir hier nur Pfade ab, bei denen der User garantiert
    /// Schreibrechte hat. Verwaiste Drop-/Encounter-Einträge werden durch den
    /// Admin-Cleanup bzw. `cleanupOrphanedDrops` bereinigt.
    func deleteUserData(uid: String) async {
        // 1. RTDB: Profil, Freunde
        _ = try? await db.child("users").child(uid).removeValue()
        _ = try? await db.child("friends").child(uid).removeValue()

        // 2. RTDB: eigenen Discovery-Index-Eintrag direkt entfernen (kein Scan nötig —
        //    wir kennen Telefon aus UserDefaults und E-Mail aus Auth)
        let savedPhone = UserDefaults.standard.string(forKey: "ud_userPhone") ?? ""
        if !savedPhone.isEmpty {
            let normPhone = Self.normalizePhone(savedPhone)
            if !normPhone.isEmpty {
                _ = try? await db.child("phoneIndex").child(normPhone).removeValue()
            }
        }
        let authPhone = Auth.auth().currentUser?.phoneNumber ?? ""
        if !authPhone.isEmpty {
            let normAuth = Self.normalizePhone(authPhone)
            if !normAuth.isEmpty && normAuth != Self.normalizePhone(savedPhone) {
                _ = try? await db.child("phoneIndex").child(normAuth).removeValue()
            }
        }
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            let emailKey = email.lowercased()
                .replacingOccurrences(of: ".", with: ",")
                .replacingOccurrences(of: "@", with: "-at-")
            _ = try? await db.child("emailIndex").child(emailKey).removeValue()
        }

        // 3. Firestore: Profilergänzung (Reliability-Score, profileImageURL)
        _ = try? await Firestore.firestore().collection("users").document(uid).delete()

        // 4. Firebase Storage: Profilbild
        _ = try? await Storage.storage().reference().child("profileImages/\(uid).jpg").delete()
    }

    /// Setzt einen Tombstone-Marker nach Konto-Löschung. Wenn sich der User erneut
    /// mit derselben Apple-ID einloggt (gleiche uid), erkennt die App das anhand
    /// dieses Markers und behandelt den Login als Neuregistrierung.
    func markAccountDeleted(uid: String) async {
        _ = try? await db.child("deletedAccounts").child(uid).setValue([
            "deletedAt": ServerValue.timestamp()
        ])
    }

    /// Prüft ob ein Tombstone existiert und entfernt ihn (für den resurrect-Flow).
    /// Gibt `true` zurück wenn der Account als gelöscht markiert war — der Caller
    /// muss dann das Onboarding neu starten.
    func consumeDeletionTombstone(uid: String) async -> Bool {
        let ref = db.child("deletedAccounts").child(uid)
        guard let snap = try? await ref.getData(), snap.exists() else { return false }
        _ = try? await ref.removeValue()
        return true
    }

    // MARK: - Drop Views (Drops+ „wer hat geschaut")

    /// Snapshot eines Drop-Viewers — für die Host-UI.
    struct DropViewerSnapshot: Identifiable {
        let id: String               // viewerUID
        let name: String
        let age: Int?
        let emoji: String
        let profileImageURL: String?
        let viewedAt: Date
    }

    /// Schreibt einen "view"-Eintrag (idempotent — Timestamp wird bei erneutem Öffnen aktualisiert).
    /// Der Host selbst wird nicht als Viewer gezählt.
    func recordDropView(dropID: String, viewerName: String, viewerEmoji: String,
                        viewerAge: Int?, viewerProfileImageURL: String?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Host nicht als Viewer zählen — wird client-seitig im Caller gechekt
        var payload: [String: Any] = [
            "name":      viewerName,
            "emoji":     viewerEmoji,
            "viewedAt":  ServerValue.timestamp()
        ]
        if let age = viewerAge { payload["age"] = age }
        if let url = viewerProfileImageURL { payload["profileImageURL"] = url }
        db.child("dropViews").child(dropID).child(uid).setValue(payload)
    }

    /// Beobachtet alle Viewer eines Drops (für den Host).
    /// Feuert bei jedem neuen View und bei Updates. Liefert die komplette Liste neu.
    @discardableResult
    func observeDropViews(dropID: String, onUpdate: @escaping ([DropViewerSnapshot]) -> Void) -> DatabaseHandle {
        let ref = db.child("dropViews").child(dropID)
        return ref.observe(.value) { snapshot in
            var viewers: [DropViewerSnapshot] = []
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any],
                      let name = dict["name"] as? String
                else { continue }
                let tsMs = dict["viewedAt"] as? Double ?? 0
                let date = tsMs > 0 ? Date(timeIntervalSince1970: tsMs / 1000) : Date()
                viewers.append(DropViewerSnapshot(
                    id: snap.key,
                    name: name,
                    age: dict["age"] as? Int,
                    emoji: dict["emoji"] as? String ?? "👤",
                    profileImageURL: dict["profileImageURL"] as? String,
                    viewedAt: date
                ))
            }
            // Neueste zuerst
            viewers.sort { $0.viewedAt > $1.viewedAt }
            DispatchQueue.main.async { onUpdate(viewers) }
        }
    }

    func removeDropViewsObserver(_ handle: DatabaseHandle, dropID: String) {
        db.child("dropViews").child(dropID).removeObserver(withHandle: handle)
    }

    /// Schreibt den Drops+ Status des aktuell eingeloggten Users nach Firebase.
    /// Wird nach erfolgreichem IAP-Kauf oder Entitlement-Refresh aufgerufen.
    func setMyPlusStatus(_ isPlus: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.child("users").child(uid).updateChildValues(["isPlusUser": isPlus])
    }

    // MARK: - Aktive Drops (Fremde)

    /// Parst den `scheduledTime`-String + createdAt zu einer absoluten Startzeit.
    /// Wird beim Publish geschrieben, damit die Cloud-Function den 30-Min-Reminder
    /// triggern kann ohne den String parsen zu müssen.
    static func parseDropStartAt(scheduledTime: String, createdAt: Date) -> Date {
        let s = scheduledTime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cal = Calendar.current
        switch s {
        case "", "jetzt":
            return createdAt
        case "in 30 min", "in 30min":
            return createdAt.addingTimeInterval(30 * 60)
        case "in 1 std", "in 1std", "in 1 stunde":
            return createdAt.addingTimeInterval(60 * 60)
        case "heute abend":
            var c = cal.dateComponents([.year, .month, .day], from: createdAt)
            c.hour = 19; c.minute = 0
            return cal.date(from: c) ?? createdAt.addingTimeInterval(60 * 60)
        default:
            // Custom HH:mm — heute, sonst morgen
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.locale = Locale(identifier: "de_DE")
            if let t = f.date(from: scheduledTime) {
                var c = cal.dateComponents([.year, .month, .day], from: createdAt)
                let tc = cal.dateComponents([.hour, .minute], from: t)
                c.hour = tc.hour; c.minute = tc.minute
                if let date = cal.date(from: c) {
                    return date < createdAt
                        ? (cal.date(byAdding: .day, value: 1, to: date) ?? date)
                        : date
                }
            }
            return createdAt
        }
    }

    /// Schreibt den eigenen aktiven Drop in die DB, sichtbar für alle Nutzer
    func publishDrop(dropID: String, userID: String, displayName: String, emoji: String,
                     activityName: String, coordinate: CLLocationCoordinate2D, radius: Double,
                     expiresAt: Date, scheduledTime: String = "Jetzt", hostGender: String = "",
                     maxParticipants: Int = 10) {
        let dropRef = db.child("drops").child(dropID)
        let createdAt = Date()
        let startAt = Self.parseDropStartAt(scheduledTime: scheduledTime, createdAt: createdAt)
        var payload: [String: Any] = [
            "userID": userID,
            "displayName": displayName,
            "emoji": emoji,
            "activityName": activityName,
            "lat": coordinate.latitude,
            "lng": coordinate.longitude,
            "radius": radius,
            "timestamp": ServerValue.timestamp(),
            "expiresAt": expiresAt.timeIntervalSince1970,
            "scheduledTime": scheduledTime,
            // Absolute Startzeit (epoch sec) — für Cloud-Function 30-Min-Reminder.
            "startAt": startAt.timeIntervalSince1970,
            "maxParticipants": maxParticipants,
            "active": true
        ]
        if !hostGender.isEmpty { payload["hostGender"] = hostGender }
        dropRef.setValue(payload)
        // Auto-Cleanup bei App-Termination (Force-Quit, Deinstallation, Crash):
        // Firebase löscht den Drop, sobald die Client-Verbindung abreißt.
        // Hintergrund allein triggert das nicht — Connection bleibt bei
        // backgroundeter App bestehen, Drop bleibt also sichtbar.
        dropRef.onDisconnectRemoveValue()
    }

    /// Verlängert den Drop — aktualisiert nur das expiresAt-Feld in Firebase.
    func extendDropExpiry(dropID: String, newExpiry: Date) {
        db.child("drops").child(dropID).updateChildValues([
            "expiresAt": newExpiry.timeIntervalSince1970,
            "active": true
        ])
    }

    /// Löscht den eigenen Drop aus der DB
    func unpublishDrop(dropID: String) {
        db.child("drops").child(dropID).removeValue()
    }

    /// Setzt den Drops+-Boost eines Drops in Firebase (active = true → boosted, false → unboosted).
    func boostDrop(dropID: String, active: Bool = true) {
        db.child("drops").child(dropID).updateChildValues(["isBoosted": active])
    }

    /// Beobachtet alle aktiven Drops in Echtzeit (gefiltert auf Umgebung lokal)
    func observeNearbyDrops(around coordinate: CLLocationCoordinate2D, radiusKm: Double,
                             onUpdate: @escaping ([StrangerDropData]) -> Void) -> DatabaseHandle {
        let handle = db.child("drops").observe(.value) { snapshot in
            var result: [StrangerDropData] = []
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any],
                      let lat = dict["lat"] as? Double,
                      let lng = dict["lng"] as? Double,
                      let name = dict["displayName"] as? String,
                      let emoji = dict["emoji"] as? String,
                      let activity = dict["activityName"] as? String,
                      let active = dict["active"] as? Bool, active
                else { continue }

                // Abgelaufene Drops herausfiltern (Host hat die App evtl. ohne Abmelden geschlossen)
                let now = Date()
                if let expiresTs = dict["expiresAt"] as? Double {
                    // Neues Feld: exakt prüfen
                    if now > Date(timeIntervalSince1970: expiresTs) { continue }
                } else if let tsMs = dict["timestamp"] as? Double {
                    // Altes Feld (ServerValue.timestamp = Millisekunden): max. 12h Lebensdauer
                    let created = Date(timeIntervalSince1970: tsMs / 1000)
                    if now.timeIntervalSince(created) > 12 * 60 * 60 { continue }
                }

                let ownerID         = dict["userID"] as? String ?? ""
                let scheduled       = dict["scheduledTime"] as? String ?? "Jetzt"
                let hostGender      = dict["hostGender"] as? String
                let maxParticipants = dict["maxParticipants"] as? Int ?? 10
                let isBoosted       = dict["isBoosted"] as? Bool ?? false
                let dropCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lng))

                if distance <= radiusKm * 1000 {
                    result.append(StrangerDropData(
                        id: snap.key,
                        ownerID: ownerID,
                        displayName: name,
                        emoji: emoji,
                        activityName: activity,
                        coordinate: dropCoord,
                        distanceMeters: distance,
                        scheduledTime: scheduled,
                        hostGender: hostGender,
                        maxParticipants: maxParticipants,
                        isBoosted: isBoosted
                    ))
                }
            }
            onUpdate(result)
        }
        return handle
    }

    func removeObserver(_ handle: DatabaseHandle) {
        db.child("drops").removeObserver(withHandle: handle)
    }

    // MARK: - Eigene Drops beim App-Start rehydrieren

    /// Snapshot eines eigenen Drops in Firebase — für Rehydration nach App-Neustart.
    struct MyActiveDropSnapshot {
        let dropID: String
        let activityName: String
        let emoji: String
        let coordinate: CLLocationCoordinate2D
        let scheduledTime: String
        let maxParticipants: Int
        let isBoosted: Bool
        let createdAt: Date
        let expiresAt: Date
    }

    /// Lädt alle eigenen, noch nicht abgelaufenen Drops des Users aus Firebase.
    /// Wird beim App-Start aufgerufen, damit ein Drop im „Aktiv"-Tab sichtbar bleibt
    /// auch wenn die App komplett geschlossen und neu gestartet wurde.
    func loadMyActiveDrops(ownerUID: String) async -> [MyActiveDropSnapshot] {
        guard let snapshot = try? await db.child("drops").getData() else { return [] }
        let now = Date()
        var results: [MyActiveDropSnapshot] = []
        // `snapshot.children` ist ein NSEnumerator und in Swift 6 in async-Kontexten
        // nicht direkt iterierbar — über `allObjects` umweg über ein Array.
        for child in snapshot.children.allObjects {
            guard let snap = child as? DataSnapshot,
                  let dict = snap.value as? [String: Any],
                  (dict["userID"] as? String) == ownerUID,
                  (dict["active"] as? Bool) ?? false,
                  let lat = dict["lat"] as? Double,
                  let lng = dict["lng"] as? Double,
                  let activityName = dict["activityName"] as? String,
                  let emoji = dict["emoji"] as? String
            else { continue }

            // CreatedAt aus Unix-Timestamp (ms) rekonstruieren
            let createdAt: Date
            if let tsMs = dict["timestamp"] as? Double {
                createdAt = Date(timeIntervalSince1970: tsMs / 1000)
            } else {
                createdAt = now.addingTimeInterval(-60)  // Fallback: 1 Min. vor jetzt
            }

            // ExpiresAt: explizites Feld oder 12h-Fallback
            let expiresAt: Date
            if let exp = dict["expiresAt"] as? Double {
                expiresAt = Date(timeIntervalSince1970: exp)
            } else {
                expiresAt = createdAt.addingTimeInterval(12 * 3600)
            }

            // Abgelaufene Drops ignorieren — cleanupOrphanedDrops räumt sie nebenbei auf
            if now > expiresAt { continue }

            results.append(MyActiveDropSnapshot(
                dropID: snap.key,
                activityName: activityName,
                emoji: emoji,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                scheduledTime: dict["scheduledTime"] as? String ?? "Jetzt",
                maxParticipants: dict["maxParticipants"] as? Int ?? 10,
                isBoosted: dict["isBoosted"] as? Bool ?? false,
                createdAt: createdAt,
                expiresAt: expiresAt
            ))
        }
        return results
    }

    // MARK: - Verwaiste Drops aufräumen

    /// Löscht beim App-Start alle Drops in Firebase die dem aktuellen User gehören aber
    /// entweder abgelaufen sind oder nicht mehr im lokalen activeDrops stehen.
    /// Verhindert "Ghost-Drops" wenn die App ohne Abmelden beendet wurde.
    func cleanupOrphanedDrops(ownerUID: String, activeDropIDs: Set<String>) {
        db.child("drops").observeSingleEvent(of: .value) { [weak self] snapshot in
            guard let self = self else { return }
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any],
                      let uid  = dict["userID"] as? String,
                      uid == ownerUID                      // nur eigene Drops prüfen
                else { continue }

                let dropID = snap.key
                let now    = Date()

                // Abgelaufen?
                var isExpired = false
                if let expiresTs = dict["expiresAt"] as? Double {
                    isExpired = now > Date(timeIntervalSince1970: expiresTs)
                } else if let tsMs = dict["timestamp"] as? Double {
                    isExpired = now.timeIntervalSince(Date(timeIntervalSince1970: tsMs / 1000)) > 12 * 3600
                } else {
                    isExpired = true // kein Zeitstempel → löschen
                }

                // Nur wirklich abgelaufene Drops löschen.
                // "Nicht lokal bekannt" reicht nicht als Kriterium —
                // nach Logout / App-Neustart ist activeDropIDs leer und würde
                // sonst alle Drops des Users aus Firebase entfernen.
                if isExpired {
                    self.db.child("drops").child(dropID).removeValue()
                }
            }
        }
    }

    // MARK: - DropIn (Beitreten)

    /// Schreibt einen DropIn-Eintrag, damit der Drop-Ersteller benachrichtigt wird.
    /// joinerLat/joinerLng: aktuelle GPS-Koordinaten des Joiners — sonst bekommt der
    /// Host als Fallback den User-Default (München-Center) angezeigt.
    func joinDrop(dropID: String, joinerID: String, joinerName: String,
                  joinerEmoji: String = "", joinerAge: Int? = nil,
                  joinerLat: Double? = nil, joinerLng: Double? = nil) {
        let joinRef = db.child("dropins").child(dropID).child(joinerID)
        var payload: [String: Any] = [
            "name": joinerName,
            "emoji": joinerEmoji,
            "timestamp": ServerValue.timestamp()
        ]
        if let age = joinerAge { payload["age"] = age }
        // Initiale Position direkt mitschreiben → Host hat sofort echten Standort.
        if let lat = joinerLat { payload["lat"] = lat }
        if let lng = joinerLng { payload["lng"] = lng }
        if joinerLat != nil || joinerLng != nil {
            payload["locTime"] = ServerValue.timestamp()
        }
        joinRef.setValue(payload)
        // Auto-Cleanup bei App-Termination — sonst bleiben Geister-Joiner hängen
        joinRef.onDisconnectRemoveValue()
    }

    /// Aktualisiert die Live-Position eines Joiners — vom Joiner selbst geschrieben.
    /// Der Host observiert diesen Pfad und rendert den Joiner-Pin an der neuen Stelle.
    func updateJoinerLiveLocation(dropID: String, joinerID: String,
                                  lat: Double, lng: Double) {
        db.child("dropins").child(dropID).child(joinerID).updateChildValues([
            "lat":      lat,
            "lng":      lng,
            "locTime":  ServerValue.timestamp()
        ])
    }

    /// Host observiert Joiner-Positionen für seinen Drop — .childAdded + .childChanged.
    /// Callback bekommt die aktuelle Joiner-UID + coordinate bei jedem Update.
    /// .childAdded ist wichtig damit die initiale Position (von joinDrop) erfasst wird,
    /// nicht erst beim ersten Move-Update — sonst zeigt der Host den User-Default
    /// (München-Center) statt der echten Joiner-Position.
    @discardableResult
    func observeJoinerLocations(dropID: String,
                                onUpdate: @escaping (_ joinerID: String, _ lat: Double, _ lng: Double) -> Void) -> DatabaseHandle {
        let ref = db.child("dropins").child(dropID)
        // Initial-Snapshot holen für bereits existierende Einträge mit lat/lng
        ref.observeSingleEvent(of: .value) { snap in
            for case let child as DataSnapshot in snap.children {
                if let dict = child.value as? [String: Any],
                   let lat  = dict["lat"] as? Double,
                   let lng  = dict["lng"] as? Double {
                    DispatchQueue.main.async { onUpdate(child.key, lat, lng) }
                }
            }
        }
        // Live-Updates: childAdded für neue Joiner, childChanged für Bewegungen
        let handle = ref.observe(.childChanged) { snapshot in
            guard let dict = snapshot.value as? [String: Any],
                  let lat  = dict["lat"] as? Double,
                  let lng  = dict["lng"] as? Double else { return }
            DispatchQueue.main.async { onUpdate(snapshot.key, lat, lng) }
        }
        ref.observe(.childAdded) { snapshot in
            guard let dict = snapshot.value as? [String: Any],
                  let lat  = dict["lat"] as? Double,
                  let lng  = dict["lng"] as? Double else { return }
            DispatchQueue.main.async { onUpdate(snapshot.key, lat, lng) }
        }
        return handle
    }

    func removeJoinerLocationObserver(_ handle: DatabaseHandle, dropID: String) {
        db.child("dropins").child(dropID).removeObserver(withHandle: handle)
    }

    /// Beobachtet neue DropIns für einen Drop (für den Host).
    /// Gibt einen DatabaseHandle zurück — mit `removeDropInObserver(_:dropID:)` abmelden.
    @discardableResult
    func observeDropIns(dropID: String, onNew: @escaping (_ name: String, _ emoji: String, _ age: Int?) -> Void) -> DatabaseHandle {
        let ref = db.child("dropins").child(dropID)
        // childAdded feuert für jeden neuen Eintrag
        return ref.observe(.childAdded) { snapshot in
            guard let dict = snapshot.value as? [String: Any],
                  let name = dict["name"] as? String
            else { return }
            let emoji = dict["emoji"] as? String ?? ""
            let age = dict["age"] as? Int
            DispatchQueue.main.async { onNew(name, emoji, age) }
        }
    }

    func removeDropInObserver(_ handle: DatabaseHandle, dropID: String) {
        db.child("dropins").child(dropID).removeObserver(withHandle: handle)
    }

    /// Löscht alle DropIn-Einträge wenn der Drop beendet wird.
    func cleanupDropIns(dropID: String) {
        db.child("dropins").child(dropID).removeValue()
    }

    // MARK: - Join Requests (Host-Bestätigung)

    /// Joiner sendet Beitrittsanfrage — Status: "pending"
    func sendJoinRequest(dropID: String, joinerID: String, joinerName: String,
                         joinerEmoji: String, joinerAge: Int?, profileImageURL: String?,
                         reliabilityPoints: Int = 100, isPlus: Bool = false) {
        var payload: [String: Any] = [
            "name":              joinerName,
            "emoji":             joinerEmoji,
            "status":            "pending",
            "reliabilityPoints": reliabilityPoints,
            "isPlus":            isPlus,
            "requestedAt":       ServerValue.timestamp()
        ]
        if let age = joinerAge { payload["age"] = age }
        if let url = profileImageURL { payload["profileImageURL"] = url }
        db.child("joinRequests").child(dropID).child(joinerID).setValue(payload)
    }

    /// Host beobachtet eingehende Anfragen für seinen Drop.
    @discardableResult
    func observeIncomingJoinRequests(dropID: String,
                                     onNew: @escaping (_ joinerID: String, _ name: String,
                                                       _ emoji: String, _ age: Int?,
                                                       _ imageURL: String?,
                                                       _ reliabilityPoints: Int,
                                                       _ isPlus: Bool,
                                                       _ requestedAt: Date) -> Void) -> DatabaseHandle {
        db.child("joinRequests").child(dropID).observe(.childAdded) { snap in
            guard let dict   = snap.value as? [String: Any],
                  let name   = dict["name"]   as? String,
                  let status = dict["status"] as? String, status == "pending"
            else { return }
            let emoji    = dict["emoji"]          as? String ?? ""
            let age      = dict["age"]            as? Int
            let imageURL = dict["profileImageURL"] as? String
            let points   = dict["reliabilityPoints"] as? Int ?? 100
            let isPlus   = dict["isPlus"]            as? Bool ?? false
            let ts       = (dict["requestedAt"]   as? Double ?? 0) / 1000
            let date     = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
            DispatchQueue.main.async { onNew(snap.key, name, emoji, age, imageURL, points, isPlus, date) }
        }
    }

    /// Host akzeptiert oder lehnt eine Anfrage ab.
    func respondToJoinRequest(dropID: String, joinerID: String, accepted: Bool) {
        let status = accepted ? "accepted" : "declined"
        db.child("joinRequests").child(dropID).child(joinerID)
            .updateChildValues(["status": status, "respondedAt": ServerValue.timestamp()])
        // Bei Accept: auch in dropins schreiben (bisherige Struktur)
        if accepted {
            db.child("dropins").child(dropID).child(joinerID)
                .updateChildValues(["status": "accepted", "timestamp": ServerValue.timestamp()])
        }
    }

    /// Joiner beobachtet den Status seiner eigenen Anfrage.
    @discardableResult
    func observeMyJoinRequestStatus(dropID: String, joinerID: String,
                                    onChange: @escaping (_ status: String) -> Void) -> DatabaseHandle {
        db.child("joinRequests").child(dropID).child(joinerID).child("status")
            .observe(.value) { snap in
                guard let status = snap.value as? String else { return }
                DispatchQueue.main.async { onChange(status) }
            }
    }

    func removeJoinRequestObserver(_ handle: DatabaseHandle, dropID: String) {
        db.child("joinRequests").child(dropID).removeObserver(withHandle: handle)
    }

    func cleanupJoinRequests(dropID: String) {
        db.child("joinRequests").child(dropID).removeValue()
    }

    // MARK: - Drop canceln

    func cancelDrop(dropID: String) {
        db.child("drops").child(dropID).removeValue()
    }

    // MARK: - Begegnungen (Encounters)

    /// Schreibt eine gegenseitige Begegnung — beide User sehen sie in FreundeView
    func recordEncounter(userA: String, userB: String, activityEmoji: String, activityName: String) {
        let timestamp = ServerValue.timestamp()
        let payload: [String: Any] = [
            "partnerA": userA,
            "partnerB": userB,
            "activityEmoji": activityEmoji,
            "activityName": activityName,
            "timestamp": timestamp,
            "confirmedA": false,
            "confirmedB": false
        ]
        let encounterID = "\(userA)_\(userB)_\(Int(Date().timeIntervalSince1970))"
        db.child("encounters").child(encounterID).setValue(payload)
    }

    // MARK: - Admin Functions

    /// Alle User aus der DB laden + aktive Drops matchen (nur für Admins)
    func adminFetchAllUsers(completion: @escaping ([AdminUserEntry]) -> Void) {
        let group = DispatchGroup()
        var entries: [AdminUserEntry] = []

        // 1. Alle User laden
        group.enter()
        db.child("users").observeSingleEvent(of: .value) { snapshot in
            guard let dict = snapshot.value as? [String: Any] else { group.leave(); return }
            for (uid, value) in dict {
                guard let data = value as? [String: Any] else { continue }
                // Soft-gelöschte Accounts ausblenden
                if data["isDeleted"] as? Bool == true { continue }
                entries.append(AdminUserEntry(
                    id:           uid,
                    name:         data["name"]         as? String ?? "–",
                    email:        data["email"]        as? String ?? "–",
                    phoneNumber:  data["phoneNumber"]  as? String ?? "",
                    createdAt:    (data["createdAt"]   as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                    isAdmin:      data["isAdmin"]      as? Bool ?? false,
                    isBanned:     data["isBanned"]     as? Bool ?? false,
                    isPlusUser:   data["isPlusUser"]   as? Bool ?? false
                ))
            }
            group.leave()
        }

        // 2. Alle Drops laden — aktive herausfiltern + ersten Drop je User für Stadt-Derivation
        group.enter()
        var activeDrops: [String: (label: String, dropKey: String)] = [:]
        // Earliest drop's coord per userID — Basis für "Registrations-Stadt"
        var earliestDropCoord: [String: (ts: Double, lat: Double, lng: Double)] = [:]
        db.child("drops").observeSingleEvent(of: .value) { snapshot in
            let now = Date()
            for child in snapshot.children {
                guard let snap   = child as? DataSnapshot,
                      let dict   = snap.value as? [String: Any],
                      let uid    = dict["userID"] as? String
                else { continue }
                // Earliest-drop tracking: läuft auf ALLE drops (auch inaktive/expired)
                if let lat = dict["latitude"] as? Double,
                   let lng = dict["longitude"] as? Double {
                    let ts = (dict["createdAt"] as? Double) ?? Double.greatestFiniteMagnitude
                    if let cur = earliestDropCoord[uid] {
                        if ts < cur.ts {
                            earliestDropCoord[uid] = (ts, lat, lng)
                        }
                    } else {
                        earliestDropCoord[uid] = (ts, lat, lng)
                    }
                }
                // Aktive Drops nur fürs Active-Filter
                guard let active = dict["active"] as? Bool, active else { continue }
                if let expiresTs = dict["expiresAt"] as? Double,
                   now > Date(timeIntervalSince1970: expiresTs) { continue }
                let emoji    = dict["emoji"]        as? String ?? ""
                let activity = dict["activityName"] as? String ?? "Drop"
                let label    = "\(emoji) \(activity)".trimmingCharacters(in: .whitespaces)
                activeDrops[uid] = (label: label, dropKey: snap.key)
            }
            group.leave()
        }

        // 3. Zusammenführen
        group.notify(queue: .main) {
            for i in entries.indices {
                let uid = entries[i].id
                if let info = activeDrops[uid] {
                    entries[i].hasActiveDrop      = true
                    entries[i].activeDropActivity = info.label
                    entries[i].activeDropID       = info.dropKey
                }
                // Registrations-Stadt aus erstem Drop des Users
                if let first = earliestDropCoord[uid] {
                    let coord = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)
                    entries[i].cityName = ServiceCities.city(for: coord)?.name
                }
            }
            entries.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            completion(entries)
        }
    }

    /// User bannen / entbannen
    func adminSetBan(uid: String, banned: Bool, completion: (() -> Void)? = nil) {
        db.child("users").child(uid).updateChildValues(["isBanned": banned]) { _, _ in
            completion?()
        }
    }

    /// Admin-Status vergeben / entziehen
    /// Schreibt isAdmin:true in Firebase falls es noch fehlt — einmaliger Startup-Fix
    func ensureAdminFlagInFirebase(uid: String) {
        db.child("users").child(uid).child("isAdmin").observeSingleEvent(of: .value) { snap in
            if snap.value as? Bool != true {
                self.db.child("users").child(uid).updateChildValues(["isAdmin": true])
            }
        }
    }

    func adminSetAdmin(uid: String, isAdmin: Bool, completion: (() -> Void)? = nil) {
        db.child("users").child(uid).updateChildValues(["isAdmin": isAdmin]) { _, _ in
            completion?()
        }
    }

    /// Drops+ manuell freischalten oder entziehen (Admin-Override, unabhängig von StoreKit).
    func adminSetPlus(uid: String, isPlus: Bool, completion: (() -> Void)? = nil) {
        db.child("users").child(uid).updateChildValues(["isPlusUser": isPlus]) { _, _ in
            completion?()
        }
    }

    /// User komplett aus DB löschen (Admin)
    func adminDeleteUser(uid: String, completion: (() -> Void)? = nil) {
        // Hard delete versuchen; schlägt fehl wenn Rules es verbieten → Soft-Delete als Fallback
        let usersRef = db.child("users").child(uid)
        usersRef.removeValue { error, _ in
            if error == nil {
                // Hard delete erfolgreich
                DispatchQueue.main.async { completion?() }
            } else {
                // Fallback: Soft-Delete — wird im Fetch herausgefiltert.
                // `usersRef` lokal gefangen, damit kein Zugriff auf den
                // @MainActor-isolierten `self.db` aus dem Sendable-Closure.
                usersRef.updateChildValues([
                    "isBanned":  true,
                    "isDeleted": true,
                    "name":      "[Gelöscht]",
                    "email":     ""
                ]) { _, _ in
                    DispatchQueue.main.async { completion?() }
                }
            }
        }
    }

    /// Einzelnen Drop eines Nutzers sofort beenden (Admin)
    func adminEndDrop(dropID: String, completion: (() -> Void)? = nil) {
        db.child("drops").child(dropID).updateChildValues(["active": false]) { _, _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    /// App-Statistiken laden (User + aktive Drops)
    func adminFetchStats(completion: @escaping (AdminStats) -> Void) {
        let group = DispatchGroup()
        var total = 0; var banned = 0; var admins = 0; var activeDropCount = 0

        group.enter()
        db.child("users").observeSingleEvent(of: .value) { snapshot in
            total = Int(snapshot.childrenCount)
            if let dict = snapshot.value as? [String: Any] {
                for (_, value) in dict {
                    guard let data = value as? [String: Any] else { continue }
                    if data["isBanned"] as? Bool == true { banned += 1 }
                    if data["isAdmin"]  as? Bool == true { admins += 1 }
                }
            }
            group.leave()
        }

        group.enter()
        db.child("drops").observeSingleEvent(of: .value) { snapshot in
            let now = Date()
            for child in snapshot.children {
                guard let snap   = child as? DataSnapshot,
                      let dict   = snap.value as? [String: Any],
                      let active = dict["active"] as? Bool, active else { continue }
                if let expiresTs = dict["expiresAt"] as? Double,
                   now > Date(timeIntervalSince1970: expiresTs) { continue }
                activeDropCount += 1
            }
            group.leave()
        }

        var openReports = 0
        group.enter()
        db.child("reports").observeSingleEvent(of: .value) { snapshot in
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any] else { continue }
                let status = dict["status"] as? String ?? "open"
                if status == "open" { openReports += 1 }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(AdminStats(totalUsers: total, bannedUsers: banned,
                                  verifiedUsers: 0, adminUsers: admins,
                                  activeDrops: activeDropCount,
                                  openReports: openReports))
        }
    }

    /// Lädt alle Reports — neueste zuerst. Für's Admin-Panel.
    func adminFetchReports(completion: @escaping ([AdminReportEntry]) -> Void) {
        db.child("reports").observeSingleEvent(of: .value) { snapshot in
            var entries: [AdminReportEntry] = []
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any] else { continue }
                let createdMs = dict["createdAt"] as? Double ?? 0
                let entry = AdminReportEntry(
                    id:           snap.key,
                    reporterUID:  dict["reporterUID"]  as? String ?? "",
                    reportedUID:  dict["reportedUID"]  as? String ?? "",
                    reportedName: dict["reportedName"] as? String ?? "",
                    reason:       dict["reason"]       as? String ?? "",
                    details:      dict["details"]      as? String ?? "",
                    createdAt:    Date(timeIntervalSince1970: createdMs / 1000),
                    status:       dict["status"]       as? String ?? "open"
                )
                entries.append(entry)
            }
            entries.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { completion(entries) }
        }
    }

    /// Lädt alle **aktiven** Drops für's Admin-Panel. Neueste zuerst.
    func adminFetchActiveDrops(completion: @escaping ([AdminDropEntry]) -> Void) {
        db.child("drops").observeSingleEvent(of: .value) { snapshot in
            var entries: [AdminDropEntry] = []
            let now = Date().timeIntervalSince1970
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any] else { continue }
                let expiresAt = dict["expiresAt"] as? Double ?? 0
                // Nur wirklich aktive (expiresAt in der Zukunft)
                if expiresAt > 0 && expiresAt < now { continue }
                let entry = AdminDropEntry(
                    id:            snap.key,
                    hostUID:       dict["userID"]       as? String ?? "",
                    hostName:      dict["displayName"]  as? String ?? "—",
                    emoji:         dict["emoji"]        as? String ?? "🔵",
                    activityName:  dict["activityName"] as? String ?? "",
                    latitude:      dict["latitude"]     as? Double ?? 0,
                    longitude:     dict["longitude"]    as? Double ?? 0,
                    participants:  (dict["participants"] as? [String: Any])?.count ?? 1,
                    createdAt:     Date(timeIntervalSince1970: (dict["timestamp"] as? Double ?? 0) / 1000),
                    expiresAt:     Date(timeIntervalSince1970: expiresAt)
                )
                entries.append(entry)
            }
            entries.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { completion(entries) }
        }
    }

    /// Drop **aus der Admin-Perspektive** löschen: unpublished + dropins/joinRequests weg.
    /// Optionaler Push an den Host mit dem Grund.
    func adminDeleteDrop(dropID: String, hostUID: String?, reason: String?) {
        let updates: [String: Any] = [
            "drops/\(dropID)":        NSNull(),
            "dropins/\(dropID)":      NSNull(),
            "joinRequests/\(dropID)": NSNull()
        ]
        db.updateChildValues(updates)

        // Wenn Host-UID bekannt → Nachricht in users/{uid}/adminNotices ablegen.
        // Cloud Function kann daraus einen Push machen (Struktur für später).
        if let uid = hostUID, !uid.isEmpty {
            let noticeID = String(Int(Date().timeIntervalSince1970 * 1000))
            db.child("users").child(uid).child("adminNotices").child(noticeID).setValue([
                "type":    "drop_removed",
                "dropID":  dropID,
                "reason":  reason ?? "Verstoß gegen die Nutzungsbedingungen",
                "at":      ServerValue.timestamp()
            ])
        }
    }

    /// Setzt den Status eines Reports (open / resolved / dismissed).
    func adminSetReportStatus(reportID: String, status: String) {
        db.child("reports").child(reportID).updateChildValues([
            "status":     status,
            "resolvedAt": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }

    /// Prüft beim Login ob der User gebannt ist
    func checkIfBanned(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(false); return }
        db.child("users").child(uid).child("isBanned").observeSingleEvent(of: .value) { snapshot in
            completion(snapshot.value as? Bool ?? false)
        }
    }

    // MARK: - Kontakt-Matching

    struct ContactMatchResult: Identifiable {
        let id = UUID()
        let phone: String   // original aus dem Adressbuch
        let uid: String
        let name: String
    }

    /// Normalisiert eine Telefonnummer auf E.164-Format (DE-Fallback: 0xxx → +49xxx).
    static func normalizePhone(_ raw: String) -> String {
        var digits = raw.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if digits.hasPrefix("0")  { digits = "+49" + digits.dropFirst(1) }
        return digits
    }


    /// **Deprecated** — direkter bidirektionaler Add wird nur noch intern
    /// vom Accept-Flow genutzt. Neue Client-Aufrufe gehen über
    /// `sendFriendRequest` → der Empfänger muss annehmen.
    func addFriend(theirUID: String) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        db.child("friends").child(myUID).child(theirUID).setValue(true)
        db.child("friends").child(theirUID).child(myUID).setValue(true)
    }

    /// Entfernt gegenseitige Freundschaft in Firebase.
    func removeFriend(theirUID: String) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        db.child("friends").child(myUID).child(theirUID).removeValue()
        db.child("friends").child(theirUID).child(myUID).removeValue()
    }

    // MARK: - Friend Requests

    /// Schickt eine Freundschaftsanfrage von mir an `theirUID`.
    /// Schreibt nach `friendRequests/{theirUID}/{myUID}` mit meinem Profil
    /// als Payload — damit Empfänger sofort Name + Avatar sehen kann ohne
    /// extra Lookup. Cloud Function `onFriendRequestCreated` sendet Push.
    func sendFriendRequest(theirUID: String, myName: String, myProfileImageURL: String?) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        guard myUID != theirUID else { return }   // Kein Selbst-Add
        var payload: [String: Any] = [
            "fromName":  myName,
            "createdAt": ServerValue.timestamp()
        ]
        if let url = myProfileImageURL, !url.isEmpty {
            payload["fromImageURL"] = url
        }
        db.child("friendRequests").child(theirUID).child(myUID).setValue(payload)
    }

    /// Nimmt eine Freundschaftsanfrage von `fromUID` an:
    /// — setzt `friends/{myUID}/{fromUID}` + `friends/{fromUID}/{myUID}`
    /// — löscht `friendRequests/{myUID}/{fromUID}`
    /// Cloud Function `onFriendshipAdded` sendet Push an fromUID.
    func acceptFriendRequest(fromUID: String) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        let updates: [String: Any] = [
            "friends/\(myUID)/\(fromUID)": true,
            "friends/\(fromUID)/\(myUID)": true,
            "friendRequests/\(myUID)/\(fromUID)": NSNull()
        ]
        db.updateChildValues(updates)
    }

    /// Lehnt eine Freundschaftsanfrage ab — löscht sie kommentarlos.
    /// Kein Push an den Sender (sonst wäre es Druck, eine Erklärung zu geben).
    func rejectFriendRequest(fromUID: String) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        db.child("friendRequests").child(myUID).child(fromUID).removeValue()
    }

    /// Live-Observer auf eingehende Freundschaftsanfragen.
    /// Feuert bei jeder Änderung (neue Anfrage, angenommen, abgelehnt).
    @discardableResult
    func observeIncomingFriendRequests(onUpdate: @escaping ([FriendRequestSnapshot]) -> Void) -> DatabaseHandle? {
        guard let myUID = Auth.auth().currentUser?.uid else { return nil }
        let ref = db.child("friendRequests").child(myUID)
        return ref.observe(.value) { snapshot in
            var list: [FriendRequestSnapshot] = []
            for child in snapshot.children {
                guard let c = child as? DataSnapshot,
                      let dict = c.value as? [String: Any] else { continue }
                let fromUID = c.key
                let name    = dict["fromName"] as? String ?? "Unbekannt"
                let url     = dict["fromImageURL"] as? String
                let createdAtMs = dict["createdAt"] as? TimeInterval
                let createdAt: Date = createdAtMs.map {
                    Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0)
                } ?? Date()
                list.append(FriendRequestSnapshot(
                    fromUID:         fromUID,
                    fromName:        name,
                    fromImageURL:    url,
                    createdAt:       createdAt
                ))
            }
            // Neueste zuerst
            list.sort { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { onUpdate(list) }
        }
    }

    func removeFriendRequestsObserver(_ handle: DatabaseHandle) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        db.child("friendRequests").child(myUID).removeObserver(withHandle: handle)
    }

    /// Snapshot eines Freundes — minimal ausgefüllt aus `users/{uid}` für die Freunde-Liste.
    struct FriendSnapshot {
        let uid: String
        let name: String
        let profileImageURL: String?
        /// Unix-Timestamp (Sekunden) des letzten App-Heartbeats dieses Users.
        /// Wird für die Online-Status-Anzeige genutzt (online = letzte 5 Min).
        let lastActiveAt: TimeInterval?
        /// Aktuelle Reliability-Punkte des Users (Start = 100, mit Events veränderlich).
        /// Fallback auf `startingPoints` wenn der User noch nie Punkte persistiert hat.
        let reliabilityPoints: Int
    }

    /// Schreibt die eigene Profilbild-URL nach `users/{uid}/profileImageURL` in RTDB.
    /// So können Freunde sie in einer einzigen Query mitlesen (spart Firestore-Rundfahrten).
    func setMyProfileImageURL(_ urlString: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.child("users").child(uid).updateChildValues(["profileImageURL": urlString])
    }

    /// Spiegelt den aktuellen Reliability-Score nach `users/{uid}/reliabilityPoints`.
    /// Firestore ist die authoritative Quelle für alle Score-Felder, aber RTDB
    /// bekommt die **kompakte Gesamtpunktzahl** damit Freunde-Observer und
    /// Drop-Pin-Badges den Score ohne Firestore-Call lesen können.
    func setMyReliabilityPoints(_ points: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.child("users").child(uid).updateChildValues([
            "reliabilityPoints": points
        ])
    }

    /// Schreibt einen "online"-Heartbeat nach `users/{uid}/lastActiveAt` mit
    /// dem Server-Timestamp. Freunde-Observer lesen diesen Wert und zeigen
    /// den User als online wenn der Timestamp < 5 Minuten alt ist.
    /// Wird aus der App getriggert: beim Login + bei jedem Foreground-Enter.
    func markOnlineHeartbeat() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.child("users").child(uid).updateChildValues([
            "lastActiveAt": ServerValue.timestamp()
        ])
    }

    /// Liest die eigene Profilbild-URL aus der Realtime DB.
    /// Fallback falls Firestore nach Re-Login noch keinen Token durchgerouted hat.
    func loadMyProfileImageURL(completion: @escaping (String?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(nil); return }
        db.child("users").child(uid).child("profileImageURL").observeSingleEvent(of: .value) { snap in
            let url = snap.value as? String
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Persistiert den FCM-Token unter `users/{uid}/fcmToken`, damit Cloud-Functions
    /// (Friendship-Push u.ä.) den User adressieren können.
    func setMyFCMToken(_ token: String, uid: String? = nil) {
        let targetUID = uid ?? Auth.auth().currentUser?.uid
        guard let u = targetUID, !token.isEmpty else { return }
        db.child("users").child(u).updateChildValues(["fcmToken": token])
    }

    /// Schreibt +10 App-Invite-Bonus direkt auf das Konto des Einladenden (UID).
    /// Wird aufgerufen wenn ein Neuling via `/invite/{uid}` Onboarding abschließt.
    func creditAppInviteBonus(inviterUID: String) {
        guard !inviterUID.isEmpty else { return }
        let ref = db.child("users").child(inviterUID).child("reliabilityAppInviteBonus")
        ref.runTransactionBlock { currentData in
            let current = currentData.value as? Int ?? 0
            currentData.value = current + 10
            return .success(withValue: currentData)
        }
    }

    /// Schreibt +5 Drop-Invite-Bonus auf das Konto des Drop-Erstellers.
    /// Wird aufgerufen wenn ein via Invite-Link gejointer User vor Ort war.
    func creditDropInviteBonus(hostUID: String) {
        guard !hostUID.isEmpty else { return }
        let ref = db.child("users").child(hostUID).child("reliabilityInviteBonus")
        ref.runTransactionBlock { currentData in
            let current = currentData.value as? Int ?? 0
            currentData.value = current + 5
            return .success(withValue: currentData)
        }
    }

    /// Prüft einmalig ob der gegebene User Drops+ Status hat — für UI-Anzeige
    /// (z.B. Plus-Badge im MiniProfileSheet von Freunden/Teilnehmern).
    func fetchPlusStatus(uid: String, completion: @escaping (Bool) -> Void) {
        guard !uid.isEmpty else { completion(false); return }
        db.child("users").child(uid).child("isPlusUser").observeSingleEvent(of: .value) { snap in
            let isPlus = snap.value as? Bool ?? false
            DispatchQueue.main.async { completion(isPlus) }
        }
    }

    /// Throttled-Schreiber für die Last-Known-Location eines Users (für Drop-Nearby-Pushes).
    /// - 1× pro 10 Min Throttle in UserDefaults
    /// - Coords auf 3 Dezimalstellen gerundet (~110m Auflösung) für Privacy
    /// - Pfad: users/{uid}/lastLat, lastLng, lastSeen (Server-Timestamp)
    private static let lastLocWriteKey = "ud_lastKnownLocWrite"
    func maybeUpdateLastKnownLocation(coord: CLLocationCoordinate2D) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.lastLocWriteKey)
        guard now - last >= 600 else { return }   // 10 Min Throttle
        UserDefaults.standard.set(now, forKey: Self.lastLocWriteKey)

        // Coordinates auf 3 Nachkommastellen runden (~110m), spart Privacy-Sensibilität
        let lat = (coord.latitude * 1000).rounded() / 1000
        let lng = (coord.longitude * 1000).rounded() / 1000
        db.child("users").child(uid).updateChildValues([
            "lastLat":  lat,
            "lastLng":  lng,
            "lastSeen": ServerValue.timestamp()
        ])
    }

    /// Lädt einmalig `createdAt` (Unix ms) und `birthdate` (Unix s) eines Users.
    /// Wird im MiniProfileSheet genutzt um Beta-Badge & Alter anzuzeigen.
    /// Lädt die App-Version-Config aus `/config`:
    ///   - `minRequiredVersion`: Hard-Force, unter dieser Version → Block
    ///   - `recommendedVersion`: Soft-Recommend, unter dieser → Banner
    /// Wenn beide fehlen oder Netzwerk-Fehler → completion mit (nil, nil),
    /// die App läuft normal (kein Force ohne Server-Antwort).
    func fetchAppVersionConfig(completion: @escaping (_ minRequired: String?, _ recommended: String?) -> Void) {
        db.child("config").observeSingleEvent(of: .value) { snap in
            let dict = snap.value as? [String: Any] ?? [:]
            let minReq = dict["minRequiredVersion"] as? String
            let rec    = dict["recommendedVersion"] as? String
            DispatchQueue.main.async { completion(minReq, rec) }
        } withCancel: { _ in
            DispatchQueue.main.async { completion(nil, nil) }
        }
    }

    func fetchUserMeta(uid: String, completion: @escaping (_ createdAt: Date?, _ birthdate: Date?) -> Void) {
        guard !uid.isEmpty else { completion(nil, nil); return }
        db.child("users").child(uid).observeSingleEvent(of: .value) { snap in
            let dict = snap.value as? [String: Any] ?? [:]
            let createdAt: Date? = (dict["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let birthdate: Date? = (dict["birthdate"] as? Double).map { Date(timeIntervalSince1970: $0) }
            DispatchQueue.main.async { completion(createdAt, birthdate) }
        }
    }

    /// Schreibt eine Nutzer-Meldung nach `reports/{autoID}`.
    /// Admin-Panel kann diese Liste auswerten (offene/bearbeitete Reports).
    func submitReport(reportedUID: String?, reportedName: String, reason: String, details: String) {
        guard let reporterUID = Auth.auth().currentUser?.uid else { return }
        let ref = db.child("reports").childByAutoId()
        let payload: [String: Any] = [
            "reporterUID":   reporterUID,
            "reportedUID":   reportedUID ?? "",
            "reportedName":  reportedName,
            "reason":        reason,
            "details":       details,
            "createdAt":     Int(Date().timeIntervalSince1970 * 1000),
            "status":        "open"
        ]
        ref.setValue(payload)
    }

    /// Lädt eine Freundes-Liste EINMALIG — für Legacy-Aufrufer die nicht observe nutzen.
    func loadMyFriends(ownerUID: String) async -> [FriendSnapshot] {
        guard let friendsSnap = try? await db.child("friends").child(ownerUID).getData(),
              friendsSnap.exists() else { return [] }
        var uids: [String] = []
        for child in friendsSnap.children.allObjects {
            guard let c = child as? DataSnapshot else { continue }
            uids.append(c.key)
        }
        return await hydrateFriendSnapshots(from: uids)
    }

    /// Interne Helper: UIDs → FriendSnapshots (Name + Avatar) aus `users/{uid}`.
    private func hydrateFriendSnapshots(from uids: [String]) async -> [FriendSnapshot] {
        var results: [FriendSnapshot] = []
        for uid in uids.prefix(50) {
            guard let userSnap = try? await db.child("users").child(uid).getData(),
                  let dict = userSnap.value as? [String: Any] else { continue }
            if (dict["isDeleted"] as? Bool) == true { continue }
            let name = (dict["name"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            let url = dict["profileImageURL"] as? String
            // lastActiveAt kann als ServerValue.timestamp (Millisekunden) oder
            // als Sekunden abgelegt sein — beide Varianten hier normalisieren.
            var lastActive: TimeInterval? = nil
            if let rawMs = dict["lastActiveAt"] as? TimeInterval {
                lastActive = rawMs > 10_000_000_000 ? rawMs / 1000 : rawMs
            }
            // Reliability-Punkte: wenn noch nicht gesetzt → Start-Wert (100)
            let points = (dict["reliabilityPoints"] as? Int) ?? ReliabilityScore.startingPoints
            results.append(FriendSnapshot(uid: uid, name: name,
                                          profileImageURL: url,
                                          lastActiveAt: lastActive,
                                          reliabilityPoints: points))
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Live-Observer auf `friends/{ownerUID}` — feuert bei jeder Änderung
    /// (Freund hinzufügen, entfernen, anderes Gerät). Liefert die rehydratisierte Liste.
    @discardableResult
    func observeMyFriends(ownerUID: String, onUpdate: @escaping ([FriendSnapshot]) -> Void) -> DatabaseHandle {
        let ref = db.child("friends").child(ownerUID)
        return ref.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            var uids: [String] = []
            for child in snapshot.children {
                guard let c = child as? DataSnapshot else { continue }
                uids.append(c.key)
            }
            Task { @MainActor in
                let list = await self.hydrateFriendSnapshots(from: uids)
                onUpdate(list)
            }
        }
    }

    func removeFriendsObserver(_ handle: DatabaseHandle, ownerUID: String) {
        db.child("friends").child(ownerUID).removeObserver(withHandle: handle)
    }
}

struct AdminStats {
    var totalUsers:    Int
    var bannedUsers:   Int
    var verifiedUsers: Int
    var adminUsers:    Int
    var activeDrops:   Int = 0
    var openReports:   Int = 0
}

struct AdminReportEntry: Identifiable {
    let id:           String
    let reporterUID:  String
    let reportedUID:  String
    let reportedName: String
    let reason:       String
    let details:      String
    let createdAt:    Date
    let status:       String
}

// MARK: - User Profile Snapshot

struct UserProfileSnapshot {
    var name:            String?
    var email:           String?
    var birthdate:       Date?
    var gender:          String?
    var isAdmin:         Bool = false
    var isBanned:        Bool = false
    var isPlusUser:      Bool = false
    var profileImageURL: String?
    var settings:        UserSettingsSnapshot = UserSettingsSnapshot()
}

/// Snapshot einer eingehenden Freundschaftsanfrage.
struct FriendRequestSnapshot: Identifiable, Equatable {
    var id: String { fromUID }
    let fromUID:      String
    let fromName:     String
    let fromImageURL: String?
    let createdAt:    Date
}

/// Benutzerspezifische Einstellungen, die beim Re-Login restauriert werden sollen.
/// Alle Felder optional — nil bedeutet "nicht in Firebase gesetzt → lokalen Default behalten".
struct UserSettingsSnapshot {
    var radiusFilter:           Double?
    var ageFilterMin:           Int?
    var ageFilterMax:           Int?
    var selectedAgeGroups:      [String]?
    var userInterests:          [String]?
    var blockedUsers:           [String]?
    var unavailabilityReason:   String?
    var genderFilterEnabled:    Bool?
    var activityCategoryFilter: String?
}

// MARK: - Admin User Entry
struct AdminUserEntry: Identifiable {
    let id: String          // Firebase UID
    var name:         String
    var email:        String
    var phoneNumber:  String = ""          // für Admin-Suche
    var createdAt:    Date?
    var isAdmin:      Bool
    var isBanned:     Bool
    var isPlusUser:   Bool   = false
    var hasActiveDrop:      Bool    = false
    var activeDropActivity: String? = nil   // z.B. "☕️ Kaffee"
    /// Stadt-Name aus erstem Drop des Users abgeleitet (München/Berlin/etc.).
    /// nil = User hat noch keinen Drop erstellt → "—" in UI.
    var cityName: String?    = nil
    var activeDropID:       String? = nil   // Firebase-Key des laufenden Drops
}

// MARK: - Admin Drop Entry (Live-Monitoring)
struct AdminDropEntry: Identifiable {
    let id: String               // Firebase-Drop-Key
    let hostUID: String
    let hostName: String
    let emoji: String
    let activityName: String
    let latitude: Double
    let longitude: Double
    let participants: Int
    let createdAt: Date
    let expiresAt: Date

    /// Liefert die Service-Stadt in der der Drop liegt — für UI-Filter.
    var cityName: String {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return ServiceCities.city(for: coord)?.name ?? "—"
    }
}

// MARK: - Datenmodell für Fremde Drops aus DB

struct StrangerDropData: Identifiable {
    let id: String          // Firebase-Key (= drop.id.uuidString vom Host)
    let ownerID: String     // currentUser.id.uuidString des Erstellers
    let displayName: String
    let emoji: String
    let activityName: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let scheduledTime: String  // "Jetzt", "In 30 Min", "In 1 Std", "Heute Abend"
    let hostGender: String?    // "männlich" | "weiblich" | "divers" | nil (älter)
    let maxParticipants: Int   // vom Host gesetzt; Default 10 für ältere Einträge
    let isBoosted: Bool        // Drops+: goldener Boost-Rahmen auf der Karte
}
