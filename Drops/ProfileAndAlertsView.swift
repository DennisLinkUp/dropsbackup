import SwiftUI
import MapKit
import AVFoundation
@preconcurrency import Contacts

// MARK: - Freunde View

// Encounter-Modell ist in Models.swift definiert

struct FreundeView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    @StateObject private var contactsVM = ContactsViewModel()
    @State private var showAddSheet = false
    @State private var addedContactUIDs: Set<String> = []
    @State private var profileParticipant: DropParticipant? = nil
    @State private var justConfirmedEncounterId: UUID? = nil
    @State private var auroraAnimate = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImageSourceSheet = false
    @State private var showEmojiPicker = false
    @State private var showScoreInfo = false

    private var onlineFriends: [User]  { store.friends.filter { $0.isAvailable } }
    private var offlineFriends: [User] { store.friends.filter { !$0.isAvailable } }

    /// Kontaktvorschläge: nur Leute die noch keine Freunde sind
    private var contactSuggestions: [RealtimeDBManager.ContactMatchResult] {
        let friendUIDs = Set(store.friends.map { $0.id.uuidString })
        return contactsVM.matches.filter { !friendUIDs.contains($0.uid) && !addedContactUIDs.contains($0.uid) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                // Aurora-Hintergrund oben
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.32))
                        .frame(width: 280, height: 280)
                        .blur(radius: 65)
                        .offset(x: auroraAnimate ? 25 : -35, y: auroraAnimate ? -40 : -10)
                    Circle()
                        .fill(Color(UIColor.systemPurple).opacity(0.22))
                        .frame(width: 220, height: 220)
                        .blur(radius: 55)
                        .offset(x: auroraAnimate ? -50 : 30, y: auroraAnimate ? -20 : -50)
                    Circle()
                        .fill(Color(UIColor.systemTeal).opacity(0.16))
                        .frame(width: 180, height: 180)
                        .blur(radius: 48)
                        .offset(x: auroraAnimate ? 55 : -15, y: auroraAnimate ? 10 : -30)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                        auroraAnimate = true
                    }
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {

                        // Eigener Status
                        myStatusCard

                        // ── Zu bestätigende Begegnungen ganz oben wenn ausstehend ──
                        if !store.pendingEncounters.isEmpty {
                            encountersSection
                        }

                        // Online-Freunde
                        if !onlineFriends.isEmpty {
                            friendSection(
                                title: tr("profile.online_nearby"),
                                badge: "\(onlineFriends.count)",
                                friends: onlineFriends,
                                isOnline: true
                            )
                        }

                        // Offline-Freunde
                        if !offlineFriends.isEmpty {
                            friendSection(
                                title: tr("profile.unavailable"),
                                badge: nil,
                                friends: offlineFriends,
                                isOnline: false
                            )
                        }

                        // Kontakt-Vorschläge: Leute aus Adressbuch die auf Drops sind
                        if !contactSuggestions.isEmpty {
                            contactSuggestionsSection
                        }

                        // Freundesvorschläge (nach bestätigten Begegnungen)
                        if !store.friendSuggestions.isEmpty {
                            friendSuggestionsSection
                        }

                        // Alle Begegnungen (auch bestätigte) — nur wenn keine ausstehenden oben
                        if store.pendingEncounters.isEmpty {
                            encountersSection
                        }

                        // Drop-Statistiken
                        dropStatsSection

                        // Drop-Verlauf
                        pastDropsSection

                        // Empty State wenn noch keine Freunde
                        if store.friends.isEmpty && store.pendingEncounters.isEmpty && store.friendSuggestions.isEmpty {
                            FreundeEmptyState()
                                .padding(.top, 32)
                        }

                        // Freund hinzufügen
                        addFriendCard

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("profile.title"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(image: $store.selfieImage,
                                isPresented: $showImagePicker,
                                sourceType: imagePickerSource)
            }
            .confirmationDialog("Profilbild ändern", isPresented: $showImageSourceSheet, titleVisibility: .visible) {
                Button("Foto aufnehmen") {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                imagePickerSource = .camera
                                showImagePicker = true
                            }
                        }
                    }
                }
                Button("Aus Bibliothek wählen") {
                    imagePickerSource = .photoLibrary
                    showImagePicker = true
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerSheet(selected: store.currentUser.emoji) { emoji in
                    store.currentUser.emoji = emoji
                    store.saveAll()
                }
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
            }
            .onChange(of: store.selfieImage) { img in
                guard img != nil else { return }
                store.saveAll()
                store.saveSelfie()   // Upload zu Firebase Storage → für andere Nutzer sichtbar
            }
            .sheet(isPresented: $showScoreInfo) {
                ReliabilityInfoSheet(score: store.reliabilityScore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Kontakte nur laden wenn Berechtigung bereits erteilt — kein Dialog beim Tab-Wechsel
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .authorized || status == .limited {
                    contactsVM.load()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddFromContactsSheet().environmentObject(store)
            }
            // Gegenseitige Bestätigung: zeigt Freunde-Vorschläge der bestätigten Person
            .sheet(isPresented: Binding(
                get: { justConfirmedEncounterId != nil },
                set: { if !$0 { justConfirmedEncounterId = nil } }
            )) {
                if let eid = justConfirmedEncounterId,
                   let encounter = store.encounters.first(where: { $0.id == eid }) {
                    MutualConfirmationSheet(encounter: encounter)
                        .environmentObject(store)
                        .presentationDetents([.fraction(0.5)])
                        .presentationDragIndicator(.hidden)
                        .sheetBackground()
                }
            }
            .sheet(isPresented: Binding(
                get: { profileParticipant != nil },
                set: { if !$0 { profileParticipant = nil } }
            )) {
                if let p = profileParticipant {
                    if #available(iOS 16.4, *) {
                        MiniProfileSheet(
                            name: p.name,
                            emoji: p.emoji,
                            selfie: p.selfie,
                            profileImageURL: p.profileImageURL,
                            reliabilityScore: p.reliabilityScore,
                            subtitle: tr("profile.your_friend"),
                            accentColor: .brand,
                            isVerified: p.isVerified,
                            canBlock: false
                        ) { profileParticipant = nil }
                        .environmentObject(store)
                        .presentationDetents([.height(360)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(.clear)
                    } else {
                        MiniProfileSheet(
                            name: p.name,
                            emoji: p.emoji,
                            selfie: p.selfie,
                            profileImageURL: p.profileImageURL,
                            reliabilityScore: p.reliabilityScore,
                            subtitle: tr("profile.your_friend"),
                            accentColor: .brand,
                            isVerified: p.isVerified,
                            canBlock: false
                        ) { profileParticipant = nil }
                        .environmentObject(store)
                        .presentationDetents([.height(360)])
                        .presentationDragIndicator(.hidden)
                    }
                }
            }
        }
    }

    // MARK: Eigener Status (Profil-Karte)

    private var myStatusCard: some View {
        VStack(spacing: 0) {
            // ── Avatar + Name + Score ────────────────────────────────────
            HStack(spacing: 16) {
                // Avatar mit Kamera-Button + Emoji-Badge
                ZStack(alignment: .bottomLeading) {
                    Button(action: { showImageSourceSheet = true }) {
                        ZStack(alignment: .bottomTrailing) {
                            // Gold-Rand für Drops+ User, sonst dezenter Standard-Stroke
                            let plusRing = LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            let ringWidth: CGFloat = store.isDropsPlusActive ? 2.5 : 1.5
                            Group {
                                if let img = store.selfieImage {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 70, height: 70).clipShape(Circle())
                                } else {
                                    RemoteProfileImage(url: store.profileImageURL,
                                                       fallbackEmoji: store.currentUser.emoji,
                                                       size: 70, strokeColor: .clear)
                                }
                            }
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        store.isDropsPlusActive
                                            ? AnyShapeStyle(plusRing)
                                            : AnyShapeStyle(Color.white.opacity(0.25)),
                                        lineWidth: ringWidth
                                    )
                            )
                            .shadow(color: store.isDropsPlusActive ? Color(hex: "f59e0b").opacity(0.35) : .clear,
                                    radius: 8, y: 2)

                            // Kamera-Badge
                            ZStack {
                                Circle().fill(Color.brand).frame(width: 22, height: 22)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                            }
                            .shadow(color: Color.brand.opacity(0.45), radius: 4, y: 2)
                        }
                    }
                    .buttonStyle(.plain)

                    // Emoji-Badge (unten links) — immer sichtbar
                    Button(action: { showEmojiPicker = true }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            Text(store.currentUser.emoji)
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: -2, y: 2)
                }

                // Name + Alter + Drops+ Badge + Score
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(store.currentUser.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        if let age = store.userAge {
                            Text(", \(age)")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.textSecondary)
                        }
                        if store.isDropsPlusActive {
                            // Drops+ Badge — goldene Blitz-Pille
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("PLUS")
                                    .font(.system(size: 9, weight: .bold))
                                    .kerning(0.4)
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: Color(hex: "f59e0b").opacity(0.35), radius: 4, y: 1)
                        }
                    }
                    // Score-Pill — tappbar für Erklärung
                    Button(action: { showScoreInfo = true }) {
                        HStack(spacing: 5) {
                            Text(store.reliabilityScore.displayText)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(store.reliabilityScore.color)
                            Text("·")
                                .font(.system(size: 11)).foregroundColor(.textTertiary)
                            Text(store.reliabilityScore.badge)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(store.reliabilityScore.color.opacity(0.07),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    // Drops-Zahl
                    Text("\(store.reliabilityScore.showUps) Drops · \(store.friends.count) Freunde")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

        }
        .liquidGlass(cornerRadius: 18)
        .padding(.horizontal, 16)
        .animation(.spring(), value: store.currentUser.isAvailable)
    }

    // MARK: Freundesvorschläge

    // MARK: Kontakt-Vorschläge aus Adressbuch

    private var contactSuggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.brand)
                Text("AUS DEINEN KONTAKTEN")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 2)
                Spacer()
            }
            .padding(.leading, 20).padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(contactSuggestions.enumerated()), id: \.element.id) { idx, match in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.brand.opacity(0.12))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(match.name.prefix(1)))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.brand)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("Auf Drops")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Button(action: {
                            RealtimeDBManager.shared.addFriend(theirUID: match.uid)
                            addedContactUIDs.insert(match.uid)
                            // Direkt in die lokale Freunde-Liste aufnehmen, damit
                            // der neue Kontakt sofort im Freunde-Tab erscheint.
                            if !store.friends.contains(where: { $0.name == match.name }) {
                                store.friends.append(User(
                                    name: match.name,
                                    emoji: "👋",
                                    isAvailable: false,
                                    statusMessage: tr("profile.newly_added")
                                ))
                            }
                        }) {
                            Text("Hinzufügen")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.brand)
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    if idx < contactSuggestions.count - 1 {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .liquidGlass(cornerRadius: 20)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Freundesvorschläge (nach bestätigten Begegnungen)

    private var friendSuggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("profile.maybe_know"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.brand)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.friendSuggestions) { suggestion in
                        VStack(spacing: 10) {
                            ZStack(alignment: .topTrailing) {
                                Circle()
                                    .fill(Color.bgSecondary)
                                    .frame(width: 64, height: 64)
                                    .overlay(Text(suggestion.emoji).font(.system(size: 32)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1.5))
                                // Dismiss-X
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        store.dismissSuggestion(id: suggestion.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.textTertiary)
                                        .background(Color.bgPrimary.clipShape(Circle()))
                                }
                                .accessibilityLabel(tr("profile.remove_suggestion"))
                                .offset(x: 4, y: -4)
                            }

                            VStack(spacing: 2) {
                                Text(suggestion.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(suggestion.mutualFriend)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                // Demo: Vorschlag zu Freunden hinzufügen
                                store.friends.append(User(
                                    name: suggestion.name,
                                    emoji: suggestion.emoji,
                                    isAvailable: false,
                                    statusMessage: tr("profile.newly_added")
                                ))
                                withAnimation(.spring(response: 0.3)) {
                                    store.dismissSuggestion(id: suggestion.id)
                                }
                            } label: {
                                Text(tr("profile.add"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.brandInverse)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.brand)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 100)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .liquidGlass(cornerRadius: 18)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 0)
    }

    // MARK: Freunde Sektion

    @ViewBuilder
    private func friendSection(title: String, badge: String?, friends: [User], isOnline: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.brandInverse)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.brand).cornerRadius(20)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(friends) { friend in
                    FreundRow(friend: friend, isOnline: isOnline) {
                        profileParticipant = DropParticipant(
                            name: friend.name,
                            emoji: friend.emoji,
                            selfie: nil,
                            reliabilityScore: 88
                        )
                    }
                    if friend.id != friends.last?.id {
                        Divider().padding(.leading, 70).padding(.trailing, 16)
                    }
                }
            }
            .liquidGlass(cornerRadius: 20)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Wer kommt zu meinem Drop

    @ViewBuilder private var joinNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk.arrival")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.brand)
                Text(tr("profile.coming_to_drop"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(store.activeJoinNotifications.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.brand)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(store.activeJoinNotifications.enumerated()), id: \.element.id) { i, note in
                    JoinNotificationRow(note: note)
                        .environmentObject(store)
                    if i < store.activeJoinNotifications.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Letzte Begegnungen

    @ViewBuilder private var encountersSection: some View {
        // Pending immer oben, dann bestätigte/abgelehnte nach Datum sortiert
        let sorted = store.encounters.sorted { a, b in
            let aPending = !a.confirmed && !a.denied && !a.isExpired
            let bPending = !b.confirmed && !b.denied && !b.isExpired
            if aPending != bPending { return aPending }
            return a.createdAt > b.createdAt
        }

        VStack(spacing: 0) {
            HStack {
                Text(tr("profile.recent_encounters"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, encounter in
                    EncounterRow(encounter: encounter)
                    if i < sorted.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)
        }
        .animation(.spring(), value: store.encounters.map { $0.confirmed || $0.denied })
    }

    // MARK: Drop-Statistiken

    @ViewBuilder private var dropStatsSection: some View {
        let total   = store.pastDrops.count
        let hosted  = store.pastDrops.filter { $0.wasHost }.count
        let joined  = total - hosted
        let rs      = store.reliabilityScore
        let favEmoji = store.pastDrops
            .map { $0.activityEmoji }
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key ?? "✨"

        if total > 0 || rs.totalCommits > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Statistiken")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 4)

                // ── Kacheln (2×2) ───────────────────────────────────
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(value: "\(total)",
                             label: "Drops gesamt",
                             icon: "bolt.fill",
                             color: Color.brand)
                    StatTile(value: "\(joined)",
                             label: "Beigetreten",
                             icon: "person.fill.badge.plus",
                             color: Color(UIColor.systemIndigo))
                    StatTile(value: "\(hosted)",
                             label: "Erstellt",
                             icon: "star.fill",
                             color: Color.accentOrange)
                    StatTile(value: rs.displayText,
                             label: "Zuverlässigkeit",
                             icon: "checkmark.seal.fill",
                             color: rs.totalCommits == 0 ? .textSecondary : rs.color)
                }

                // ── Lieblings-Aktivität ──────────────────────────────
                if total > 0 {
                    HStack(spacing: 12) {
                        Text(favEmoji).font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lieblings-Aktivität")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                            Text(store.pastDrops
                                .filter { $0.activityEmoji == favEmoji }
                                .first?.activityName ?? "")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Text("\(store.pastDrops.filter { $0.activityEmoji == favEmoji }.count)×")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                // ── Aktivitäts-Heatmap ───────────────────────────────
                ActivityHeatmap(drops: store.pastDrops)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: Drop-Verlauf

    @State private var selectedPastDrop: PastDrop? = nil

    @ViewBuilder private var pastDropsSection: some View {
        if !store.pastDrops.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tr("profile.recent_drops"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text("\(store.pastDrops.count) gesamt")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 20).padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(store.pastDrops.enumerated()), id: \.element.id) { i, drop in
                        Button { selectedPastDrop = drop } label: {
                            HStack(spacing: 14) {
                                // Emoji + Host-Indikator
                                ZStack(alignment: .bottomTrailing) {
                                    Text(drop.activityEmoji)
                                        .font(.system(size: 24))
                                        .frame(width: 40, height: 40)
                                        .background(Color.brand.opacity(0.08), in: Circle())
                                    if drop.wasHost {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.accentOrange)
                                            .padding(2)
                                            .background(Color(.systemBackground), in: Circle())
                                            .offset(x: 2, y: 2)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(drop.activityName)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        if drop.wasHost {
                                            Text(tr("profile.host"))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.accentOrange)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.accentOrange.opacity(0.1), in: Capsule())
                                        }
                                    }
                                    HStack(spacing: 4) {
                                        Text(drop.locationName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                        Text("·")
                                            .foregroundColor(.textTertiary)
                                        Text(drop.dateLabel)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                        Text(drop.timeLabel)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                    }
                                }

                                Spacer()

                                // Teilnehmer-Avatare (max 3) + Reliability-Dot
                                HStack(spacing: -8) {
                                    ForEach(drop.participants.prefix(3)) { p in
                                        Text(p.emoji)
                                            .font(.system(size: 14))
                                            .frame(width: 26, height: 26)
                                            .background(Color(.systemBackground), in: Circle())
                                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                                    }
                                }
                                .padding(.trailing, 4)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if i < store.pastDrops.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .liquidGlass(cornerRadius: 18)
                .padding(.horizontal, 16)
            }
            .sheet(item: $selectedPastDrop) { drop in
                DropSummarySheet(drop: drop)
            }
        }
    }

    // MARK: Freund hinzufügen

    private var addFriendCard: some View {
        VStack(spacing: 0) {
            // Via Kontakte
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.brand.opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 17)).foregroundColor(.brand)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("profile.add_from_contacts"))
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                        Text(tr("profile.find_friends_using"))
                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 60)

            // Via Link
            ShareLink(item: URL(string: "https://drops-app.de/invite/\(store.currentUser.name.lowercased())")!) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBlue).opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 17)).foregroundColor(Color(UIColor.systemBlue))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("profile.share_invite_link"))
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                        Text(tr("profile.link_via_messaging"))
                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
        .liquidGlass(cornerRadius: 18)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showAddSheet) {
            AddFromContactsSheet().environmentObject(store)
        }
    }
}

// MARK: - Drop Summary Sheet

struct DropSummarySheet: View {
    let drop: PastDrop
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    private var showUps: [PastDropParticipant]   { drop.participants.filter { $0.didShowUp } }
    private var noShows: [PastDropParticipant]    { drop.participants.filter { !$0.didShowUp } }
    private var reliabilityColor: Color {
        switch drop.avgReliability {
        case 85...: return .onlineGreen
        case 65..<85: return .accentOrange
        default: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 10) {
                        Text(drop.activityEmoji)
                            .font(.system(size: 52))
                            .frame(width: 84, height: 84)
                            .background(Color.brand.opacity(0.08), in: Circle())

                        Text(drop.activityName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                            Text(drop.locationName)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                            Text("·")
                                .foregroundColor(.textTertiary)
                            Text(drop.dateLabel + " " + drop.timeLabel)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }

                        if drop.wasHost {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                Text(tr("profile.was_host"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.accentOrange)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.accentOrange.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.top, 8)

                    // ── Stat-Kacheln ──────────────────────────────────────
                    HStack(spacing: 12) {
                        statTile(value: "\(drop.participantCount)",
                                 label: tr("drop_summary.there"),
                                 icon: "person.2.fill",
                                 color: .brand)
                        statTile(value: "\(drop.avgReliability)%",
                                 label: tr("drop_summary.reliability"),
                                 icon: "checkmark.seal.fill",
                                 color: reliabilityColor)
                        statTile(value: "\(showUps.count)/\(drop.participantCount)",
                                 label: tr("drop_summary.appeared"),
                                 icon: "figure.walk.arrival",
                                 color: .onlineGreen)
                    }
                    .padding(.horizontal, 16)

                    // ── Teilnehmer ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("profile.participants"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, 20).padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(drop.participants.enumerated()), id: \.element.id) { i, p in
                                HStack(spacing: 14) {
                                    Text(p.emoji)
                                        .font(.system(size: 22))
                                        .frame(width: 38, height: 38)
                                        .background(p.didShowUp ? Color.brand.opacity(0.07) : Color.red.opacity(0.06),
                                                    in: Circle())
                                        .overlay(
                                            Circle().stroke(p.didShowUp ? Color.clear : Color.red.opacity(0.2), lineWidth: 1)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(p.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.textPrimary)
                                            if p.wasHost {
                                                Image(systemName: "crown.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.accentOrange)
                                            }
                                        }
                                        if !p.didShowUp {
                                            Text(tr("profile.not_shown"))
                                                .font(.system(size: 11))
                                                .foregroundColor(.red.opacity(0.7))
                                        }
                                    }

                                    Spacer()

                                    // Reliability-Score
                                    let scoreColor: Color = {
                                        switch p.reliabilityScore {
                                        case 85...: return .onlineGreen
                                        case 65..<85: return .accentOrange
                                        default: return .red
                                        }
                                    }()
                                    VStack(spacing: 3) {
                                        Text("\(p.reliabilityScore)%")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(scoreColor)
                                        // Mini-Balken
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color.primary.opacity(0.07))
                                                    .frame(height: 3)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(scoreColor)
                                                    .frame(width: geo.size.width * CGFloat(p.reliabilityScore) / 100, height: 3)
                                            }
                                        }
                                        .frame(width: 44, height: 3)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)

                                if i < drop.participants.count - 1 {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle(tr("drop_summary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("common.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Encounter Row

struct EncounterRow: View {
    let encounter: Encounter
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle().fill(Color.brand.opacity(0.1)).frame(width: 48, height: 48)
                    Text(encounter.friendEmoji).font(.system(size: 24))
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(encounter.activityEmoji + " " + encounter.activityName + " mit " + encounter.friendName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(encounter.timeAgoLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Status-Badge
                if encounter.confirmed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.onlineGreen)
                        Text(tr("profile.confirmed"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.onlineGreen)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.onlineGreen.opacity(0.1), in: Capsule())
                } else if encounter.denied || encounter.isExpired {
                    Text(encounter.isExpired && !encounter.denied ? "Abgelaufen" : "Nicht getroffen")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(UIColor.systemGray5), in: Capsule())
                } else {
                    // BLE-Bestätigung läuft automatisch im Hintergrund
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundColor(.brand)
                        Text(tr("profile.detecting"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.brand.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .opacity(encounter.denied || encounter.isExpired ? 0.45 : 1)
    }
}

// MARK: - Join Notification Row (kein Accept/Decline — direkt dabei)

struct JoinNotificationRow: View {
    let note: JoinRequest
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Entfernung des Joiners vom Drop (simuliert)
    private var distanceLabel: String? {
        guard let joinerCoord = note.simulatedCoordinate,
              let dropCoord = note.dropCoordinate else { return nil }
        let joiner = CLLocation(latitude: joinerCoord.latitude, longitude: joinerCoord.longitude)
        let drop   = CLLocation(latitude: dropCoord.latitude, longitude: dropCoord.longitude)
        let m = joiner.distance(from: drop)
        let walkMins = max(1, Int(m / 80))
        let distStr = m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000)
        return "~\(walkMins) Min · \(distStr) vom Drop"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Emoji-Avatar mit Lauf-Animation
            ZStack {
                Circle()
                    .fill(Color.onlineGreen.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(note.requesterEmoji)
                    .font(.system(size: 20))
                // Kleiner grüner Punkt: online / unterwegs
                Circle()
                    .fill(Color.onlineGreen)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.bgPrimary, lineWidth: 1.5))
                    .offset(x: 14, y: 14)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(note.requesterName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(tr("profile.coming"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                if let dist = distanceLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10))
                            .foregroundColor(.onlineGreen)
                        Text(dist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.onlineGreen)
                    }
                } else {
                    Text("\(note.dropEmoji) \(note.dropActivity) · \(note.timeAgoLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "figure.walk.arrival")
                .font(.system(size: 14))
                .foregroundColor(.onlineGreen)
                .padding(9)
                .background(Color.onlineGreen.opacity(0.10), in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Mutual Confirmation Sheet

struct MutualConfirmationSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let encounter: Encounter
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Vorschläge die durch diese Begegnung generiert wurden
    private var suggestions: [FriendSuggestion] {
        store.friendSuggestions.filter {
            $0.mutualFriend == "Über \(encounter.friendName) kennenlernen"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12).padding(.bottom, 20)

            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.onlineGreen.opacity(0.12)).frame(width: 52, height: 52)
                    Text(encounter.friendEmoji).font(.system(size: 26))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13)).foregroundColor(.onlineGreen)
                        Text("\(encounter.friendName) hat auch bestätigt!")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Text("Vielleicht kennst du noch jemanden aus \(encounter.friendName)s Umfeld:")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            if suggestions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 32)).foregroundColor(.textTertiary)
                    Text(tr("profile.no_suggestions"))
                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(suggestions) { s in
                            VStack(spacing: 10) {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 60, height: 60)
                                    .overlay(Text(s.emoji).font(.system(size: 28)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1.5))
                                VStack(spacing: 2) {
                                    Text(s.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("Über \(encounter.friendName)")
                                        .font(.system(size: 10)).foregroundColor(.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                                Button {
                                    store.friends.append(User(
                                        name: s.name, emoji: s.emoji,
                                        isAvailable: false, statusMessage: tr("profile.newly_added")
                                    ))
                                    store.dismissSuggestion(id: s.id)
                                } label: {
                                    Text(tr("profile.add"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.brandInverse)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(Color.brand, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: 100)
                            .padding(.vertical, 14).padding(.horizontal, 8)
                            .liquidGlass(cornerRadius: 18)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }

            Spacer()

            Button(tr("common.done")) { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }
}

// MARK: - Contacts View Model

/// Klassen-basiertes ViewModel für den Kontakt-Import.
/// Durch @StateObject bleibt die CNContactStore-Instanz sicher am Leben —
/// kein ARC-Problem und keine SwiftUI-Struct-Kopier-Falle.
@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var matches: [RealtimeDBManager.ContactMatchResult] = []
    @Published var isLoading = false
    @Published var permissionDenied = false

    /// Einzige Instanz — wird nie neu erstellt solange die Sheet-View lebt.
    private let contactStore = CNContactStore()

    func load() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            fetchContacts()
        case .notDetermined:
            isLoading = true
            contactStore.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.fetchContacts()
                    } else {
                        self.isLoading = false
                        self.permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func retry() {
        permissionDenied = false
        load()
    }

    private func fetchContacts() {
        isLoading = true
        let cs = contactStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let keys = [CNContactPhoneNumbersKey,
                        CNContactEmailAddressesKey] as [CNKeyDescriptor]
            var phones: [String] = []
            var emails: [String] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? cs.enumerateContacts(with: request) { contact, _ in
                for ph in contact.phoneNumbers {
                    phones.append(ph.value.stringValue)
                }
                for em in contact.emailAddresses {
                    emails.append(em.value as String)
                }
            }
            RealtimeDBManager.shared.lookupContactsOnDrops(phones: phones, emails: emails) { [weak self] results in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.matches = results
                }
            }
        }
    }
}

// MARK: - Add From Contacts Sheet

struct AddFromContactsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage") private var appLanguage = "de"
    @StateObject private var vm = ContactsViewModel()
    @State private var searchText = ""
    @State private var addedUIDs: Set<String> = []

    private var filtered: [RealtimeDBManager.ContactMatchResult] {
        guard !searchText.isEmpty else { return vm.matches }
        return vm.matches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Suchleiste
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                    TextField("Name suchen…", text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.textPrimary)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 16).padding(.vertical, 12)

                if vm.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.brand)
                    Text("Kontakte werden durchsucht…")
                        .font(.system(size: 13)).foregroundColor(.textSecondary)
                        .padding(.top, 10)
                    Spacer()
                } else if vm.permissionDenied {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 40)).foregroundColor(.textTertiary)
                        Text("Kein Kontaktzugriff")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                        Text("Erlaube Drops den Zugriff auf deine Kontakte in den Einstellungen.")
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.brand)
                    }
                    Spacer()
                } else if vm.matches.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40)).foregroundColor(.textTertiary)
                        Text("Noch niemand aus deinen Kontakten auf Drops")
                            .font(.system(size: 14)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    // Treffer
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.brand)
                        Text("\(vm.matches.count) KONTAKT\(vm.matches.count == 1 ? "" : "E") AUF DROPS")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.textTertiary)
                            .kerning(0.4)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, match in
                                ContactMatchRow(match: match, isAdded: addedUIDs.contains(match.uid)) {
                                    RealtimeDBManager.shared.addFriend(theirUID: match.uid)
                                    addedUIDs.insert(match.uid)
                                    // Direkt in die lokale Freunde-Liste aufnehmen
                                    if !store.friends.contains(where: { $0.name == match.name }) {
                                        store.friends.append(User(
                                            name: match.name,
                                            emoji: "👋",
                                            isAvailable: false,
                                            statusMessage: tr("profile.newly_added")
                                        ))
                                    }
                                }
                                if idx < filtered.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 20)
                        .padding(.horizontal, 16)
                    }
                }

                // Einladen Button
                ShareLink(item: URL(string: "https://drops.app/invite")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Alle anderen einladen")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brand)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 16)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Freunde hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }.foregroundColor(.brand)
                }
            }
            .onAppear {
                // Kleiner Delay damit die Sheet-Animation fertig ist bevor der System-Dialog erscheint
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { vm.load() }
            }
            .onChange(of: scenePhase) { phase in
                // Wenn User aus iOS-Einstellungen zurückkommt → Zugriff erneut prüfen
                if phase == .active && vm.permissionDenied {
                    vm.retry()
                }
            }
        }
    }
}

private struct ContactMatchRow: View {
    let match: RealtimeDBManager.ContactMatchResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.brand.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(match.name.prefix(1)))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.brand)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                Text("Nutzt Drops")
                    .font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: onAdd) {
                Text(isAdded ? "✓ Hinzugefügt" : "Hinzufügen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAdded ? .onlineGreen : .brandInverse)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isAdded ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .animation(.spring(), value: isAdded)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct SuggestionRow: View {
    let name: String
    let emoji: String
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var added = false
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Color.brand.opacity(0.1)).frame(width: 44, height: 44)
                .overlay(Text(emoji).font(.system(size: 22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                Text(tr("profile.uses_drops")).font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: { withAnimation(.spring()) { added = true } }) {
                Text(added ? "✓" : tr("profile.add"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(added ? .onlineGreen : .brandInverse)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(added ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Freund Row

struct FreundRow: View {
    @EnvironmentObject var store: AppStore
    let friend: User
    let isOnline: Bool
    var onProfileTap: (() -> Void)? = nil
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var invited = false

    var body: some View {
        Button { onProfileTap?() } label: {
            HStack(spacing: 14) {
                AvatarBadge(emoji: friend.emoji, size: 44, isAvailable: isOnline)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(friend.statusMessage)
                        .font(.system(size: 13)).foregroundColor(.textSecondary).lineLimit(1)
                    if isOnline {
                        Text(store.etaString(to: friend.coordinate) + " entfernt")
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.brand)
                    }
                }

                Spacer()

                if isOnline {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) { invited = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { invited = false }
                        }
                    }) {
                        Text(invited ? "✓" : "Einladen")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(invited ? .onlineGreen : .brandInverse)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(invited ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(), value: invited)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile View

private struct HomePin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("mapStyleMode") private var mapStyleModeRaw: String = MapStyleMode.auto.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = "de"
    @AppStorage("settingLocationSharing") private var locationSharing = true
    @AppStorage("settingNotificationsOn") private var notificationsOn = true
    @State private var showDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteError = false
    @State private var showPrivacy = false
    @State private var showTerms = false

    @State private var auroraAnimate = false
    @State private var showTeensLockedInfo = false
    @State private var showAdminPanel = false
    @State private var showDropsPlus = false

    // Lokale Buffer für Altersslider — Store-Update nur beim Loslassen
    @State private var localAgeMin: Int = 18
    @State private var localAgeMax: Int = 99
    // Lokaler Buffer für Heimzone-Slider — Store/Karte nur beim Loslassen updaten
    @State private var localHomeZoneIndex: Double = 0

    // Mein Profil — editierbare Felder
    @State private var editedName: String = ""   // unused after onboarding, kept for compiler
    @State private var editedPhone: String = ""
    @FocusState private var phoneFocused: Bool
    @State private var editedBirthdate: Date = Date()

    /// Direkt-Check per gespeicherter Telefonnummer / Apple-Relay-E-Mail —
    /// Fallback falls store.isAdmin nach Neustart noch nicht asynchron gesetzt wurde.
    private var isAdminByCredentials: Bool {
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        let savedPhone  = (UserDefaults.standard.string(forKey: "savedPhoneDialCode") ?? "")
                        + (UserDefaults.standard.string(forKey: "savedPhoneNumber") ?? "")
        return AdminConfig.isBootstrapAdmin(storedAppleEmail: storedApple, savedPhone: savedPhone)
    }

    let radiusOptions: [(label: String, subtitle: String, value: Double)] = [
        ("500m", "~6 Min zu Fuß", 500),
        ("800m", "~10 Min zu Fuß", 800),
        ("1.5km", "~18 Min zu Fuß", 1500),
        ("3km", "~37 Min zu Fuß", 3000),
        ("Unbegrenzt", "Alle Drops sichtbar", 99999)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                // Aurora-Hintergrund oben (wie FreundeView)
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.32))
                        .frame(width: 280, height: 280)
                        .blur(radius: 65)
                        .offset(x: auroraAnimate ? 25 : -35, y: auroraAnimate ? -40 : -10)
                    Circle()
                        .fill(Color(UIColor.systemPurple).opacity(0.22))
                        .frame(width: 220, height: 220)
                        .blur(radius: 55)
                        .offset(x: auroraAnimate ? -50 : 30, y: auroraAnimate ? -20 : -50)
                    Circle()
                        .fill(Color(UIColor.systemTeal).opacity(0.16))
                        .frame(width: 180, height: 180)
                        .blur(radius: 48)
                        .offset(x: auroraAnimate ? 55 : -15, y: auroraAnimate ? 10 : -30)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                        auroraAnimate = true
                    }
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {

                        // ── Drops+ Banner ────────────────────────────────
                        Button { showDropsPlus = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(hex: "f59e0b"))
                                    .frame(width: 44, height: 44)
                                    .background(Color(hex: "f59e0b").opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("Drops+")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                                    startPoint: .leading, endPoint: .trailing
                                                )
                                            )
                                        if store.isPlusUser {
                                            Text("AKTIV")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.black)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color(hex: "f59e0b"), in: Capsule())
                                        }
                                    }
                                    Text(store.isPlusUser
                                         ? "Boost · Großer Radius · Wer hat geschaut"
                                         : "Boost · Radius bis ∞ · Wer hat geschaut")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color(hex: "f59e0b").opacity(0.5), Color(hex: "f59e0b").opacity(0.15)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .sheet(isPresented: $showDropsPlus) {
                            DropsPlusView()
                        }

                        // Drop-Statistiken: als Drops+ Feature angekündigt, kommt mit einem
                        // späteren Update. UI-Komponente (DropsPlusStatsCard) ist vorhanden
                        // und kann durch Entkommentieren reaktiviert werden.
                        // DropsPlusStatsCard(showPaywall: $showDropsPlus)
                        //     .environmentObject(store)
                        //     .padding(.horizontal, 16)

                        // Sichtbarkeit + Mitteilungen
                        settingsSection(icon: "location.fill", color: Color(UIColor.systemGreen), title: tr("settings.visibility")) {
                            locationSection
                            Divider().padding(.leading, 60)
                            notificationSection
                        }

                        // Datenschutz-Hinweis
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                                .padding(.top, 1)
                            Text("Dein Standort wird nur während eines aktiven Drops geteilt und ist ausschließlich für Teilnehmer sichtbar. Drops speichert keine Bewegungsverläufe.")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 2)

                        // Entdecken
                        settingsSection(icon: "scope", color: Color(UIColor.systemBlue), title: tr("settings.drops_radius")) {
                            radiusSection
                        }
                        settingsSection(icon: "house.fill", color: Color.accentOrange, title: "Heimzone") {
                            homeZoneSection
                        }
                        settingsSection(icon: "person.2.fill", color: Color(hex: "FF6B35"), title: tr("settings.age_groups")) {
                            ageGroupSection
                        }

                        // Darstellung
                        settingsSection(icon: "circle.lefthalf.filled", color: Color(UIColor.systemIndigo), title: tr("settings.appearance")) {
                            appearanceSection
                        }
                        // Datenschutz + Konto
                        settingsSection(icon: "hand.raised.fill", color: Color(UIColor.systemPurple), title: tr("settings.privacy_account")) {
                            privacySection
                            Divider().padding(.leading, 60)
                            accountSection
                        }

                        // Admin — nur sichtbar für Admins
                        if store.isAdmin || isAdminByCredentials {
                            settingsSection(icon: "star.fill", color: .orange, title: "Administration") {
                                Button(action: { showAdminPanel = true }) {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 9)
                                                .fill(Color.orange.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "shield.lefthalf.filled")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.orange)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Admin Panel")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text("Nutzer, Drops, Statistiken")
                                                .font(.system(size: 12))
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("settings.title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                editedPhone = store.userPhone
            }
            .sheet(isPresented: $showAdminPanel) {
                AdminPanelView().environmentObject(store)
            }
            .sheet(isPresented: $showPrivacy) {
                LegalView(type: .privacy)
            }
            .sheet(isPresented: $showTerms) {
                LegalView(type: .terms)
            }
            .alert(tr("account.confirm_delete"), isPresented: $showDeleteAlert) {
                Button(tr("common.cancel"), role: .cancel) {}
                Button(tr("common.delete"), role: .destructive) {
                    isDeletingAccount = true
                    store.deleteAccount { errorMsg in
                        isDeletingAccount = false
                        if let msg = errorMsg {
                            deleteErrorMessage = msg
                            showDeleteError = true
                        }
                    }
                }
            } message: {
                Text(tr("account.delete_warning"))
            }
            .alert(tr("account.delete_failed"), isPresented: $showDeleteError) {
                Button(tr("common.ok"), role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "Unbekannter Fehler.")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().scaleEffect(1.4).tint(.white)
                            Text("Konto wird gelöscht…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDeletingAccount)
            .alert(tr("account.age_restricted_title"), isPresented: $showTeensLockedInfo) {
                Button(tr("form.understood"), role: .cancel) {}
            } message: {
                Text(tr("account.age_restricted_msg"))
            }
        }
    }



    private func statsItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Settings Section Container

    @ViewBuilder
    private func settingsSection<Content: View>(icon: String, color: Color, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 18)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.4)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: 20)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Radius Section

    // Free:  500m / 1km / 2km            (max 2km)
    // Plus:  500m / 1km / 2km / 5km / 10km / 25km / ∞
    private var radiusSteps: [Double] {
        store.isPlusUser
            ? [500, 1000, 2000, 5000, 10000, 25000, 50000]
            : [500, 1000, 2000]
    }
    private var radiusIndex: Double {
        let idx = radiusSteps.firstIndex(where: { $0 >= store.radiusFilter }) ?? radiusSteps.count - 1
        return Double(idx)
    }
    private func radiusTickLabel(_ v: Double) -> String {
        if v >= 50000 { return "∞" }
        return v >= 1000 ? "\(Int(v / 1000))km" : "\(Int(v))m"
    }
    private func radiusWalkLabel(_ v: Double) -> String {
        switch v {
        case 500:   return "~6 Min zu Fuß"
        case 1000:  return "~12 Min zu Fuß"
        case 2000:  return "~25 Min zu Fuß"
        case 5000:  return "~60 Min zu Fuß"
        case 10000: return "~2 Std zu Fuß"
        case 25000: return "Stadtweit"
        case 50000: return "Unbegrenzt"
        default:    return ""
        }
    }

    @ViewBuilder private var radiusSection: some View {
        // Free-User: Radius auf max 2km clampen
        let clampedFilter: Double = {
            if !store.isPlusUser && store.radiusFilter > 2000 {
                DispatchQueue.main.async { store.radiusFilter = 2000; store.saveAll() }
                return 2000
            }
            return store.radiusFilter
        }()
        let steps = radiusSteps

        VStack(spacing: 0) {
            // Aktueller Wert + Walk-Label
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clampedFilter >= 50000 ? "∞"
                     : clampedFilter >= 1000 ? String(format: "%.0f km", clampedFilter / 1000)
                     : "\(Int(clampedFilter)) m")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Color(UIColor.systemBlue))
                    .contentTransition(.numericText())
                Text(radiusWalkLabel(clampedFilter))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            // Slider
            Slider(
                value: Binding(
                    get: { radiusIndex },
                    set: { idx in
                        let newValue = steps[Int(idx.rounded())]
                        if newValue != store.radiusFilter {
                            store.radiusFilter = newValue
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                ),
                in: 0...Double(steps.count - 1),
                step: 1
            ) { editing in
                if !editing { store.saveAll() }
            }
            .tint(Color(UIColor.systemBlue))
            .padding(.horizontal, 16)

            // Tick-Labels
            HStack {
                ForEach(steps, id: \.self) { step in
                    Text(radiusTickLabel(step))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(clampedFilter == step ? Color(UIColor.systemBlue) : .textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 4)

            Divider().padding(.horizontal, 16)

            // Info-Zeile
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clampedFilter >= 50000
                         ? "Du siehst alle Drops in der Stadt. Freunde sind immer sichtbar."
                         : "Du siehst Drops innerhalb von \(clampedFilter >= 1000 ? String(format: "%.0f km", clampedFilter / 1000) : "\(Int(clampedFilter)) m"). Freunde siehst du immer.")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !store.isPlusUser {
                        Text("Plus: bis zu 25km oder unbegrenzt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(UIColor.systemBlue).opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // MARK: - Home Zone Section

    private let homeZoneSteps: [Double] = [50, 75, 100, 150, 200, 300, 400, 500]

    private var homeZoneIndex: Double {
        let idx = homeZoneSteps.firstIndex(where: { $0 >= store.homeZoneRadius }) ?? homeZoneSteps.count - 1
        return Double(idx)
    }

    private func homeZoneLabel(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fkm", v / 1000) : "\(Int(v))m"
    }

    @ViewBuilder private var homeZoneSection: some View {
        VStack(spacing: 0) {
            // Status-Zeile
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(store.homeZoneCoordinate != nil
                              ? Color.accentOrange.opacity(0.15)
                              : Color.white.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: store.homeZoneCoordinate != nil ? "house.fill" : "house")
                        .font(.system(size: 16))
                        .foregroundColor(store.homeZoneCoordinate != nil ? Color.accentOrange : .textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.homeZoneCoordinate != nil ? "Heimzone aktiv" : "Keine Heimzone gesetzt")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(store.homeZoneCoordinate != nil ? Color.accentOrange : .textSecondary)
                    Text(store.homeZoneCoordinate != nil
                         ? "Radius: \(homeZoneLabel(store.homeZoneRadius)) um deinen Heimstandort"
                         : "Tippe auf \"Setzen\" um deinen aktuellen Standort zu speichern")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            // Mini-Karte (nur wenn Heimzone gesetzt)
            if let homeCoord = store.homeZoneCoordinate {
                // Region aus lokalem Slider-Wert — aktualisiert sich smooth beim Ziehen
                let liveRadius = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                let region = MKCoordinateRegion(
                    center: homeCoord,
                    latitudinalMeters: liveRadius * 4,
                    longitudinalMeters: liveRadius * 4
                )
                Map(coordinateRegion: .constant(region), annotationItems: [HomePin(coordinate: homeCoord)]) { pin in
                    MapAnnotation(coordinate: pin.coordinate) {
                        ZStack {
                            Circle()
                                .fill(Color.accentOrange.opacity(0.9))
                                .frame(width: 28, height: 28)
                            Image(systemName: "house.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.accentOrange.opacity(0.5), radius: 4)
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    // Radius-Ring
                    Circle()
                        .stroke(Color.accentOrange.opacity(0.5), lineWidth: 1.5)
                        .padding(8)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .disabled(true)
            }

            // Radius-Slider (nur wenn aktiv)
            if store.homeZoneCoordinate != nil {
                VStack(spacing: 4) {
                    HStack {
                        Text("Radius")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(homeZoneLabel(homeZoneSteps[Int(localHomeZoneIndex.rounded())]))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color.accentOrange)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16)

                    Slider(
                        value: $localHomeZoneIndex,
                        in: 0...Double(homeZoneSteps.count - 1),
                        step: 1
                    ) { editing in
                        if !editing {
                            // Store + Save nur beim Loslassen
                            let v = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                            store.homeZoneRadius = v
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.saveAll()
                        }
                    }
                    .tint(Color.accentOrange)
                    .padding(.horizontal, 16)
                    .onAppear { localHomeZoneIndex = homeZoneIndex }
                    .onChange(of: localHomeZoneIndex) { _ in
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }

                    HStack {
                        ForEach(homeZoneSteps, id: \.self) { s in
                            Text(homeZoneLabel(s))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(
                                    homeZoneSteps[Int(localHomeZoneIndex.rounded())] == s
                                    ? Color.accentOrange : .textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 8)
                }
            }

            Divider().padding(.horizontal, 16)

            // Aktionen
            HStack(spacing: 0) {
                Button(action: {
                    store.setHomeZone(coordinate: store.currentUser.coordinate)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }) {
                    Label(store.homeZoneCoordinate != nil ? "Aktualisieren" : "Setzen",
                          systemImage: "location.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.accentOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if store.homeZoneCoordinate != nil {
                    Divider().frame(height: 36)
                    Button(action: {
                        store.removeHomeZone()
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }) {
                        Label("Entfernen", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Age Group Section

    @ViewBuilder private var ageGroupSection: some View {
        if store.isAgeRestricted {
            // ── Unter 18: Nur eigene Gruppe anzeigen, Rest komplett versteckt ──
            VStack(alignment: .leading, spacing: 14) {
                // Schutz-Banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.orange.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("settings.youth_protection"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(tr("settings.locked_until"))
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        if let age = store.userAge {
                            Text("\(age) J.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ageProtectRow(icon: "eye.slash.fill", text: tr("settings.cannot_see_other_groups"))
                        ageProtectRow(icon: "person.2.fill", text: tr("settings.see_only_teens"))
                        ageProtectRow(icon: "checkmark.shield.fill", text: tr("settings.full_access_at_18"))
                        ageProtectRow(icon: "lock.rotation", text: tr("settings.protected_by_id"))
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.20), lineWidth: 1))

                // Nur eigene Gruppe als aktive Kachel
                if let own = store.userAgeGroup {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Color.brand.opacity(0.10)).frame(width: 44, height: 44)
                            Image(systemName: own.systemIcon).font(.system(size: 20)).foregroundColor(.brand)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(own.label)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.brand)
                            Text(tr("settings.your_age_group"))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.brand)
                    }
                    .padding(12)
                    .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brand.opacity(0.25), lineWidth: 1.5))
                }
            }
            .padding(14)
        } else {
            // ── Normal: Min/Max-Alter-Slider ───────────────────────────────
            VStack(spacing: 0) {
                // Anzeige: aktueller Bereich
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(localAgeMin)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.brand)
                        .contentTransition(.numericText())
                    Text("–")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Text(localAgeMax >= 60 ? "60+" : "\(localAgeMax)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.brand)
                        .contentTransition(.numericText())
                    Text("Jahre")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if let own = store.userAgeGroup {
                        HStack(spacing: 4) {
                            Image(systemName: own.systemIcon).font(.system(size: 11))
                            Text("Du: \(own.label)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.brand)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.brand.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

                // Slider: Mindestalter
                VStack(spacing: 2) {
                    HStack {
                        Text("Mindestalter")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text("\(localAgeMin)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 16)
                    Slider(
                        value: Binding(
                            get: { Double(localAgeMin) },
                            set: { val in
                                let v = Int(val.rounded())
                                if v <= localAgeMax - 1 { localAgeMin = v }
                            }
                        ),
                        in: 18...59, step: 1
                    ) { editing in
                        if !editing {
                            store.ageFilterMin = localAgeMin
                            store.saveAll()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    .tint(.brand)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
                .onAppear { localAgeMin = store.ageFilterMin }

                // Slider: Höchstalter
                VStack(spacing: 2) {
                    HStack {
                        Text("Höchstalter")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(localAgeMax >= 60 ? "60+" : "\(localAgeMax)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 16)
                    Slider(
                        value: Binding(
                            get: { Double(min(localAgeMax, 60)) },
                            set: { val in
                                let v = Int(val.rounded())
                                if v >= localAgeMin + 1 { localAgeMax = v >= 60 ? 99 : v }
                            }
                        ),
                        in: 19...60, step: 1
                    ) { editing in
                        if !editing {
                            store.ageFilterMax = localAgeMax
                            store.saveAll()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    .tint(.brand)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
                .onAppear { localAgeMax = min(store.ageFilterMax, 60) }

                // Tick-Labels
                HStack {
                    Text("18").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("30").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("45").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("60+").font(.system(size: 9)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private func ageProtectRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.8))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Interests Section

    // MARK: - Appearance Section

    private func appearanceIcon(for mode: MapStyleMode) -> String {
        switch mode {
        case .auto:  return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }
    private func appearanceSubtitle(for mode: MapStyleMode) -> String {
        switch mode {
        case .auto:  return "Wechselt automatisch Tag/Nacht"
        case .light: return "Karte immer hell"
        case .dark:  return "Karte immer dunkel"
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        ForEach(MapStyleMode.allCases, id: \.rawValue) { mode in
            let isSelected = mapStyleModeRaw == mode.rawValue
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.brand.opacity(isSelected ? 0.18 : 0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: appearanceIcon(for: mode))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .brand : .textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                    Text(appearanceSubtitle(for: mode))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                CustomSwitch(isOn: isSelected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mapStyleModeRaw = mode.rawValue
                    }
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16).padding(.vertical, 10)
            if mode != MapStyleMode.allCases.last {
                Divider().padding(.leading, 66)
            }
        }
    }

    // MARK: - Shared Row Helper

    @ViewBuilder
    private func inlineToggle(_ title: String, subtitle: String,
                               icon: String, color: Color,
                               isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Location Section

    @ViewBuilder private var locationSection: some View {
        inlineToggle(tr("settings.location_sharing"),
                     subtitle: tr("settings.visibility_info"),
                     icon: "location.fill",
                     color: .onlineGreen,
                     isOn: $locationSharing)
    }

    // MARK: - Notification Section

    @ViewBuilder private var notificationSection: some View {
        inlineToggle(tr("settings.notifications"),
                     subtitle: tr("settings.notifications_sub"),
                     icon: "bell.fill",
                     color: Color(UIColor.systemOrange),
                     isOn: $notificationsOn)
        .onChange(of: notificationsOn) { newValue in
            if newValue { PushNotificationManager.shared.requestPermission() }
        }
    }

    // MARK: - Phone Section (einziges änderbares Profil-Feld nach Onboarding)

    @ViewBuilder private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(UIColor.systemPurple).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.systemPurple))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Handynummer")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    TextField("+49 151 …", text: $editedPhone)
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                        .keyboardType(.phonePad)
                        .focused($phoneFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Fertig") {
                                    phoneFocused = false
                                    store.saveUserPhone(editedPhone.trimmingCharacters(in: .whitespaces))
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.system(size: 10))
                Text("Optional · Damit können dich Kontakte aus deinem Telefonbuch finden")
                    .font(.system(size: 11))
            }
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    @ViewBuilder private var privacySection: some View {
        Button { showPrivacy = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(UIColor.systemPurple).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(UIColor.systemPurple))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.privacy"))
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                    Text(tr("settings.legal"))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account Section

    @ViewBuilder private var accountSection: some View {
        // Abmelden
        Button {
            store.logout()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(UIColor.systemPurple).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(UIColor.systemPurple))
                }
                Text(tr("account.logout"))
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)

        Divider().padding(.leading, 60)

        // Konto löschen
        Button { showDeleteAlert = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                }
                Text(tr("settings.delete_account"))
                    .font(.system(size: 15))
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Stat Tile

private struct StatTile: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Activity Heatmap (GitHub-Style, letzte 16 Wochen)

private struct ActivityHeatmap: View {
    let drops: [PastDrop]

    private let weeks    = 16
    private let cellSize: CGFloat = 11
    private let gap:      CGFloat = 3

    /// Anzahl Drops pro Kalendertag (normiert auf Beginn des Tages)
    private var countsByDay: [Date: Int] {
        let cal = Calendar.current
        return drops.reduce(into: [:]) { dict, drop in
            let day = cal.startOfDay(for: drop.date)
            dict[day, default: 0] += 1
        }
    }

    /// Alle Tage der letzten `weeks` Wochen, aufgeteilt in Spalten (Wochen)
    private var grid: [[Date]] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anfang: Montag der ältesten Woche
        let weekday = cal.component(.weekday, from: today)  // 1=Sun…7=Sat
        let daysSinceMonday = (weekday + 5) % 7             // 0=Mon…6=Sun
        guard let gridStart = cal.date(byAdding: .day,
                                        value: -(daysSinceMonday + (weeks - 1) * 7),
                                        to: today) else { return [] }
        var columns: [[Date]] = []
        for w in 0..<weeks {
            var col: [Date] = []
            for d in 0..<7 {
                if let day = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart) {
                    col.append(day)
                }
            }
            columns.append(col)
        }
        return columns
    }

    private func color(for date: Date) -> Color {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard date <= today else { return Color.white.opacity(0.04) }
        let count = countsByDay[date] ?? 0
        switch count {
        case 0:       return Color.white.opacity(0.07)
        case 1:       return Color.brand.opacity(0.35)
        case 2:       return Color.brand.opacity(0.6)
        default:      return Color.brand
        }
    }

    /// Monatslabels über dem Grid
    private var monthLabels: [(col: Int, text: String)] {
        let cal = Calendar.current
        var labels: [(Int, String)] = []
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.dateFormat = "MMM"
        var lastMonth = -1
        for (w, col) in grid.enumerated() {
            if let first = col.first {
                let m = cal.component(.month, from: first)
                if m != lastMonth { labels.append((w, df.string(from: first))); lastMonth = m }
            }
        }
        return labels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aktivität")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 3) {
                    Text("Weniger")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                    ForEach([0, 1, 2, 3], id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(lvl == 0
                                  ? Color.white.opacity(0.07)
                                  : Color.brand.opacity(0.2 + 0.27 * Double(lvl)))
                            .frame(width: cellSize, height: cellSize)
                    }
                    Text("Mehr")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                }
            }

            // Monatslabels
            GeometryReader { geo in
                let colWidth = cellSize + gap
                ZStack(alignment: .topLeading) {
                    ForEach(monthLabels, id: \.col) { item in
                        Text(item.text)
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                            .offset(x: CGFloat(item.col) * colWidth)
                    }
                }
            }
            .frame(height: 10)

            // Grid
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(week, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }

            // Legende Wochentage links — nur Mo / Mi / Fr
            HStack(spacing: gap) {
                ForEach(Array(grid.enumerated()), id: \.offset) { idx, _ in
                    Text(idx == 0 ? "" : "")
                        .frame(width: cellSize)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Drops+ Stats Card

/// Kompakte Statistik-Karte in den Einstellungen: Joins, Zuverlässigkeit, erstellte Drops.
/// Für Free-User als gelockter Teaser, der beim Tap die Paywall öffnet.
struct DropsPlusStatsCard: View {
    @EnvironmentObject var store: AppStore
    @Binding var showPaywall: Bool

    private var totalJoins: Int { store.reliabilityScore.totalCommits }
    private var scorePct: Int   { Int(store.reliabilityScore.score.rounded()) }
    private var dropsCreated: Int { store.pastDrops.count + store.activeDrops.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "f59e0b"))
                Text("Deine Statistiken")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if !store.isDropsPlusActive {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Text(store.isDropsPlusActive ? "PLUS" : "DROPS+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(store.isDropsPlusActive ? .black : Color(hex: "f59e0b"))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        store.isDropsPlusActive ? Color(hex: "f59e0b") : Color(hex: "f59e0b").opacity(0.15),
                        in: Capsule()
                    )
            }

            HStack(spacing: 10) {
                StatBox(
                    icon: "person.2.fill",
                    value: "\(totalJoins)",
                    label: "Joins",
                    locked: !store.isDropsPlusActive
                )
                StatBox(
                    icon: "rosette",
                    value: totalJoins > 0 ? "\(scorePct)%" : "–",
                    label: "Zuverlässig",
                    locked: !store.isDropsPlusActive
                )
                StatBox(
                    icon: "mappin.and.ellipse",
                    value: "\(dropsCreated)",
                    label: "Erstellt",
                    locked: !store.isDropsPlusActive
                )
            }

            if store.isDropsPlusActive {
                Text(store.reliabilityScore.label)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            } else {
                Button { showPaywall = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Mit Drops+ freischalten")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

private struct StatBox: View {
    let icon: String
    let value: String
    let label: String
    let locked: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(locked ? .textTertiary : Color(hex: "f59e0b"))
            Text(locked ? "–" : value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(locked ? .textTertiary : .textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(locked ? Color.textTertiary.opacity(0.15) : Color(hex: "f59e0b").opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Age Range Slider


