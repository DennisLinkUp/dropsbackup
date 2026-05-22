import SwiftUI

// MARK: - Feed Status

enum FeedStatus {
    case justArrived, active, starting

    var label: String {
        switch self {
        case .justArrived: return tr("feed.just_arrived")
        case .active:      return tr("feed.active")
        case .starting:    return tr("feed.starting_soon")
        }
    }

    var icon: String {
        switch self {
        case .justArrived: return "circle.fill"
        case .active:      return "flame.fill"
        case .starting:    return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .justArrived: return .onlineGreen
        case .active:      return Color(UIColor.systemOrange)
        case .starting:    return Color(UIColor.systemYellow)
        }
    }
}

// MARK: - Feed View

struct FeedView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"

    // Mini-Profil State
    @State private var profileParticipant: DropParticipant? = nil
    @State private var profileCanBlock = false
    @State private var profileSubtitle = "Drops-Nutzer"
    @State private var profileAccent: Color = Color.auroraViolet
    @State private var auroraAnimate = false
    @State private var selectedCommunityFromFeed: Community? = nil
    /// Persistiert: hat User die First-Time-Hint-Card schon dismisst?
    /// Nach erstem Tap wird das auf true gesetzt → erscheint nicht wieder.
    @AppStorage("ud_feedFirstTimeHintDismissed") private var feedHintDismissed = false

    /// Sichtbar nur für echte Erstnutzer: noch keinen Drop erstellt UND
    /// keinen aktiven Drop laufen. Solange Filter-Treffer vorhanden sind
    /// (also was im Feed steht zum Antippen), zeigen wir den Hint —
    /// sonst greift schon der DropsEmptyState weiter unten.
    private var showFirstTimeHint: Bool {
        guard !feedHintDismissed else { return false }
        guard store.pastDrops.isEmpty else { return false }
        guard store.activeDrops.isEmpty else { return false }
        guard !strangerAnnotations.isEmpty || !sortedFriendDrops.isEmpty else { return false }
        return true
    }

    /// Onboarding-Hint für Erstnutzer — erklärt in einem Satz den Haupt-
    /// flow ("Tap → vorbeikommen") und ist persistent dismissable.
    @ViewBuilder
    private var firstTimeHintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tr("feed.new_here"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("feed.new_here_body"))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    feedHintDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.auroraOrange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func showStrangerProfile(_ item: MapAnnotationItem) {
        let creator = item.participants.first ?? DropParticipant(name: item.name, emoji: item.emoji)
        profileParticipant = creator
        profileCanBlock = true
        profileSubtitle = tr("feed.user")
        profileAccent = Color.auroraViolet
    }

    private func showFriendProfile(_ friend: User) {
        profileParticipant = DropParticipant(name: friend.name, emoji: friend.emoji,
                                             reliabilityScore: friend.reliabilityPoints,
                                             profileImageURL: friend.profileImageURL,
                                             firebaseUID: friend.firebaseUID)
        profileCanBlock = false
        profileSubtitle = friend.isAvailable ? tr("feed.available_now") : (friend.statusMessage.isEmpty ? tr("feed.unavailable") : friend.statusMessage)
        profileAccent = Color.brand
    }

    /// Prüft ob ein Drop in die aktuell gewählte Kategorie passt.
    private func matchesActivityFilter(_ item: MapAnnotationItem) -> Bool {
        ActivityCategory.matches(filter: store.activityCategoryFilter,
                                 emoji: item.emoji, activity: item.activity)
    }

    /// Match für den „Heute Abend"-Filter. Greift wenn entweder das
    /// scheduledTime explizit „Abend" enthält oder der Drop heute erstellt
    /// wurde und nach 17 Uhr aktiv wird.
    private func matchesTonight(_ item: MapAnnotationItem) -> Bool {
        if let st = item.scheduledTime, st.localizedCaseInsensitiveContains("abend") {
            return true
        }
        let cal = Calendar.current
        guard cal.isDateInToday(item.createdAt) else { return false }
        let hour = cal.component(.hour, from: Date())
        return hour >= 17
    }

    // Öffentliche Drops — Drops+ Boost zuerst, dann nach Interessen-Match priorisiert.
    // Distanz-Filter: `.nearby`/`.quarter` schränken auf Radius vom User-Standort
    // ein, `.city` zeigt die ganze aktuelle Stadt (Verhalten wie vorher).
    // „Nur weiblich"-Filter blendet alle Nicht-weiblich-Hosts aus (nur für weibliche Userinnen).
    // Aktivitäts-Filter blendet Drops raus deren Kategorie nicht gewählt ist.
    private var strangerAnnotations: [MapAnnotationItem] {
        var base = store.allMapAnnotations.filter { $0.isStranger }
        let userCoord = store.currentUser.coordinate
        // Drop dem der User aktuell beigetreten ist NIEMALS rausfiltern —
        // egal welche Distance/Gender/Activity-Filter aktiv sind. Sonst
        // verschwindet ein gejointer Drop aus dem Umgebungstab obwohl man
        // ihn auf der Karte sieht (Bug-Report).
        let joinedDropID = store.activeJoinedDropID?.uuidString
        let isJoinedDrop: (MapAnnotationItem) -> Bool = { drop in
            joinedDropID != nil && drop.id.uuidString == joinedDropID
        }
        switch store.feedDistanceFilter {
        case .nearby, .quarter:
            let radius = store.feedDistanceFilter.meters
            base = base.filter { isJoinedDrop($0) || $0.distance(from: userCoord) <= radius }
        case .city:
            if let myCity = ServiceCities.city(for: userCoord) {
                base = base.filter { isJoinedDrop($0) || myCity.contains($0.coordinate) }
            } else if let myCityNear = ServiceCities.cityNear(userCoord) {
                // User im Vorort (40km-Buffer) → zeig Drops aus der nächstgelegenen Stadt
                base = base.filter { isJoinedDrop($0) || myCityNear.contains($0.coordinate) }
            }
        }
        if store.genderFilterEnabled && store.userGender == "weiblich" {
            base = base.filter { isJoinedDrop($0) || ($0.hostGender?.lowercased() ?? "") == "weiblich" }
        }
        base = base.filter { isJoinedDrop($0) || matchesActivityFilter($0) }
        return base.sorted { a, b in
            // Sortierung nach Interessen-Match (falls Interessen gesetzt sind)
            if !store.userInterests.isEmpty {
                let scoreA = interestScore(for: a)
                let scoreB = interestScore(for: b)
                if scoreA != scoreB { return scoreA > scoreB }
            }
            return false
        }
    }

    /// Chip-Leiste → shared ActivityFilterChipsView (auch auf der Map).
    private var activityFilterChips: some View {
        ActivityFilterChipsView()
    }

    /// Horizontaler Strip mit allen Communities in der Nähe — fixiert auf
    /// dem Bezirks-Zentrum. Tap öffnet das Join-Sheet.
    private var communitiesNearbyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cleroGreen)
                Text(tr("feed.communities_nearby"))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.nearbyCommunities) { community in
                        Button { selectedCommunityFromFeed = community } label: {
                            communityCard(community)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(item: $selectedCommunityFromFeed) { community in
            CommunityJoinSheet(community: community)
                .environmentObject(store)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
    }

    private func communityCard(_ c: Community) -> some View {
        let isMember = c.creatorUID == store.currentUser.firebaseUID
                    || store.myCommunityMemberships.contains(c.id)
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.cleroGreen, Color.brand],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                Image(systemName: c.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(c.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if isMember {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.cleroGreen)
                    }
                }
                Text("\(c.district) · \(c.memberCount)")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cleroGreen.opacity(0.25), lineWidth: 1)
        )
    }

    /// Segmented Control: Drop-Radius (1km / 3km / Stadt) + „Heute Abend"-Toggle.
    /// Sichtbarer Label-Header macht klar, dass es um den Suchradius geht.
    private var distanceTimeFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.brand)
                Text(tr("feed.drop_radius"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("· \(store.feedDistanceFilter.detailLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(FeedDistanceFilter.allCases, id: \.self) { dist in
                    segmentChip(
                        title: dist.label,
                        selected: store.feedDistanceFilter == dist
                    ) {
                        store.feedDistanceFilter = dist
                        store.saveAll()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func segmentChip(title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? .white : .brand)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    selected
                        ? Color.brand
                        : Color(UIColor.secondarySystemGroupedBackground)
                )
            )
            .shadow(color: selected ? Color.brand.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// „Nur weiblich"-Toggle im App-Stil.
    private var femaleOnlyFilterBar: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                store.genderFilterEnabled.toggle()
                store.saveAll()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(store.genderFilterEnabled ? .white : .brand)
                Text(tr("feed.female_only"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(store.genderFilterEnabled ? .white : .textPrimary)
                Spacer(minLength: 0)
                if store.genderFilterEnabled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(
                        store.genderFilterEnabled
                            ? Color.brand
                            : Color(UIColor.secondarySystemGroupedBackground)
                    )
            )
            .shadow(color: store.genderFilterEnabled ? Color.brand.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // Freunde-Drops — nach Interessen-Match priorisiert
    private var sortedFriendDrops: [(name: String, emoji: String, status: String,
                                     activity: String, place: String, eta: String, dist: String)] {
        let base = store.nearbyDropsForFeed
        guard !store.userInterests.isEmpty else { return base }
        return base.sorted { a, b in
            friendInterestScore(for: a) > friendInterestScore(for: b)
        }
    }

    /// Keywords pro Interesse-Key — für Matching gegen Activity-Strings
    private let interestKeywords: [String: [String]] = [
        "interest.coffee":  ["kaffee", "coffee", "café", "cafe"],
        "interest.food":    ["essen", "food", "lunch", "dinner", "pizza", "burger", "restaurant", "brunch"],
        "interest.sport":   ["sport", "fitness", "gym", "laufen", "run", "fußball", "soccer", "tennis", "basketball"],
        "interest.music":   ["musik", "music", "konzert", "concert", "festival"],
        "interest.cinema":  ["kino", "film", "cinema", "movie", "serie"],
        "interest.gaming":  ["gaming", "game", "games", "zocken", "spielen"],
        "interest.shopping":["shopping", "einkaufen", "outlet", "markt"],
        "interest.outdoor": ["outdoor", "natur", "nature", "park", "wandern", "hike", "fahrrad", "bike"],
        "interest.travel":  ["reisen", "travel", "trip", "ausflug", "urlaub"],
        "interest.party":   ["ausgehen", "party", "bar", "drink", "drinks", "cocktail", "nachtleben", "club", "feiern"],
        "interest.photo":   ["foto", "fotos", "photo", "photos", "kamera", "camera", "shooting"],
        "interest.cooking": ["kochen", "cooking", "cook", "küche", "backen", "bake", "rezept"],
    ]

    /// 1 wenn Activity-String ein Interesse-Keyword enthält, sonst 0
    private func interestScore(for item: MapAnnotationItem) -> Int {
        let activity = item.activity.lowercased()
        return store.userInterests.contains { key in
            interestKeywords[key]?.contains(where: { activity.contains($0) }) ?? false
        } ? 1 : 0
    }

    private func friendInterestScore(for item: (name: String, emoji: String, status: String,
                                                 activity: String, place: String,
                                                 eta: String, dist: String)) -> Int {
        let activity = item.activity.lowercased()
        return store.userInterests.contains { key in
            interestKeywords[key]?.contains(where: { activity.contains($0) }) ?? false
        } ? 1 : 0
    }

    private func feedStatus(for index: Int) -> FeedStatus {
        [FeedStatus.justArrived, .active, .starting, .justArrived, .active, .starting][index % 6]
    }

    private func participantCount(for index: Int) -> Int {
        [2, 0, 3, 1, 2, 0][index % 6]
    }

    private func extraParticipantEmojis(for index: Int) -> [String] {
        let sets: [[String]] = [["🧔", "👩"], [], ["😎", "🧑", "👱"], ["👩"], ["🧔", "👩"], []]
        return sets[index % sets.count]
    }

    private func concreteStatus(for item: (name: String, emoji: String, status: String,
                                           activity: String, place: String,
                                           eta: String, dist: String), index: Int) -> String {
        let texts = [
            tr("feed.status_in_place").replacingOccurrences(of: "{place}", with: item.place),
            tr("feed.status_on_way"),
            tr("feed.status_already_there"),
            tr("feed.status_just_arrived"),
            tr("feed.status_starting_soon"),
            tr("feed.status_open_join")
        ]
        return texts[index % texts.count]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                // Aurora-Hintergrund oben — neue Icon-Sunset-Palette:
                // Orange (warm-dominant), Rose (Sunset-Wärme), Lavender
                // (kühler Counterpoint). Konsistent mit dem globalen
                // AppAuroraBackground und dem App-Icon.
                ZStack {
                    Circle()
                        .fill(Color.auroraOrange.opacity(0.32))
                        .frame(width: 280, height: 280)
                        .blur(radius: 65)
                        .offset(x: auroraAnimate ? 30 : -40, y: auroraAnimate ? -50 : -15)
                    Circle()
                        .fill(Color.auroraPink.opacity(0.22))
                        .frame(width: 220, height: 220)
                        .blur(radius: 55)
                        .offset(x: auroraAnimate ? -55 : 35, y: auroraAnimate ? -15 : -55)
                    Circle()
                        .fill(Color.auroraViolet.opacity(0.18))
                        .frame(width: 180, height: 180)
                        .blur(radius: 48)
                        .offset(x: auroraAnimate ? 60 : -10, y: auroraAnimate ? 5 : -35)
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
                    LazyVStack(spacing: 0) {

                        // ── Filter — scrollen mit (wie im Profil-Tab) ──
                        if store.userGender == "weiblich" {
                            femaleOnlyFilterBar
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        distanceTimeFilterBar
                            .padding(.top, store.userGender == "weiblich" ? 4 : 8)
                            .padding(.bottom, 4)
                        activityFilterChips
                            .padding(.top, 2)
                            .padding(.bottom, 8)

                        // ── Communities in der Nähe ──────────────────────
                        // Horizontale Liste aller genehmigten Communities.
                        // Tap auf Card öffnet das Join-Sheet. Nur sichtbar
                        // wenn mind. 1 Community existiert.
                        if FeatureFlags.communitiesEnabled && !store.nearbyCommunities.isEmpty {
                            communitiesNearbyStrip
                                .padding(.bottom, 8)
                        }

                        // ── Power-Hour Countdown-Pille (≤60 Min vor Start
                        //    oder vor Ende eines aktiven Slots) ──
                        // Bewusst UNTER den Filtern: visuelle Hierarchie ist
                        // erst Filter (User-Aktion), dann Power-Hour-Hint
                        // (passiver Hinweis). Auto-update jede Minute via
                        // TimelineView; gleiche Komponente wie in der Map-
                        // View, damit beide Tabs konsistent bleiben.
                        TimelineView(.periodic(from: .now, by: 60)) { ctx in
                            if let cd = AppStore.powerHourCountdown(at: ctx.date) {
                                PowerHourCountdownPill(countdown: cd)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        // ── Push-Permission-Banner ──
                        // Zeigt sich nur wenn Push deaktiviert + nicht
                        // dismissed. Tap → iOS-Settings öffnen. Wichtig weil
                        // ohne Push die ganze Reaktivität (Anfragen, Drop-
                        // Ende, Auto-Accept) silently broken ist.
                        PushPermissionBanner()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        // ── First-Time-Hint für neue User ──
                        // Zeigt sich für User die noch keinen Drop erstellt
                        // ODER beigetreten sind, solange im Feed mindestens
                        // 1 Drop sichtbar ist. Verschwindet automatisch nach
                        // erster Aktion. Erklärt den Hauptpfad in 1 Satz +
                        // schließbar via X.
                        if showFirstTimeHint {
                            firstTimeHintCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Freunde in der Nähe (prominent) ──
                        if !sortedFriendDrops.isEmpty {
                            friendsSectionHeader(count: sortedFriendDrops.count)
                            ForEach(Array(sortedFriendDrops.enumerated()), id: \.offset) { i, item in
                                FriendDropCard(
                                    item: item,
                                    status: feedStatus(for: i),
                                    participantCount: participantCount(for: i),
                                    extraEmojis: extraParticipantEmojis(for: i),
                                    concreteStatus: concreteStatus(for: item, index: i),
                                    isFeatured: i == 0,
                                    onAvatarTap: {
                                        if let friend = store.friends.first(where: { $0.name == item.name }) {
                                            showFriendProfile(friend)
                                        }
                                    },
                                    onCardTap: {
                                        if let friend = store.friends.first(where: { $0.name == item.name }) {
                                            store.focusedDropCoordinate = friend.coordinate
                                        }
                                        withAnimation { store.selectedTab = .map }
                                    }
                                )
                            }
                        }

                        // ── Öffentliche Drops (schwächer) ──
                        if !strangerAnnotations.isEmpty {
                            strangerSectionHeader(count: strangerAnnotations.count)
                            ForEach(strangerAnnotations) { item in
                                StrangerDropFeedCard(item: item,
                                    onCreatorTap: { showStrangerProfile(item) },
                                    onCardTap: {
                                        store.focusedDropCoordinate = item.coordinate
                                        withAnimation { store.selectedTab = .map }
                                    })
                                    .opacity(0.95)
                                    // .id verhindert dass SwiftUI den View für
                                    // einen anderen Drop recycled → @State joined
                                    // bleibt nicht fälschlicherweise auf true.
                                    .id(item.id)
                            }
                        }

                        // ── Leer-State ──
                        // Boost-Bonus wird direkt im EmptyState als kleine
                        // Capsule angezeigt (statt früher separater
                        // BoostBanner-Sektion). So gibt es eine einzige,
                        // konsistente Botschaft: "Sei der erste — und du
                        // bekommst +15 Bonus dafür".
                        if sortedFriendDrops.isEmpty && strangerAnnotations.isEmpty {
                            DropsEmptyState(
                                onCreateTap: { store.selectedTab = .create },
                                boostActive: store.isBoostPhaseActive,
                                boostBonus: store.currentBoostBonus,
                                isPowerHour: store.isPowerHourActive
                            )
                                .padding(.top, 48)
                        }

                        // "Nicht verfügbar"-Sektion ist aus dem Umgebungs-Feed raus —
                        // offline Freunde sieht man im Freunde-Tab (dort dediziert).
                        // Im Feed geht's darum was JETZT passiert, daher irrelevant.

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("feed.title"))
            .sheet(item: $profileParticipant) { p in
                if #available(iOS 16.4, *) {
                    MiniProfileSheet(
                        name: p.name,
                        emoji: p.emoji,
                        selfie: p.selfie,
                        profileImageURL: p.profileImageURL,
                        reliabilityScore: p.reliabilityScore,
                        totalCommits: p.reliabilityCommits,
                        subtitle: profileSubtitle,
                        accentColor: profileAccent,
                        userUID: p.firebaseUID,
                        canBlock: profileCanBlock
                    ) {
                        // Alle abhängigen State-Vars zusammen zurücksetzen —
                        // sonst blieben subtitle/accent/canBlock vom vorherigen
                        // Sheet-User stehen wenn der nächste geöffnet wird.
                        profileParticipant = nil
                        profileSubtitle    = tr("feed.user_label")
                        profileAccent      = Color.auroraViolet
                        profileCanBlock    = false
                    }
                        .environmentObject(store)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.hidden)
                        .modifier(AvailabilityPresentationBackground())
                }
            }
        }
    }

    // MARK: - Section Headers

    @ViewBuilder
    private func friendsSectionHeader(count: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brand)
                Text(tr("feed.friends_nearby"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.brandInverse)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.brand)
                .cornerRadius(8)
            Spacer()
            Text("≤ \(Int(store.radiusFilter))m")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)
    }

    @ViewBuilder
    private func strangerSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
            Text(tr("feed.public_drops"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(5)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 6)
    }

    private var offlineFriendsHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.fill")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Text(tr("feed.unavailable"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
    }
}

private struct AvailabilityPresentationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}

// MARK: - Friend Drop Card

struct FriendDropCard: View {
    let item: (name: String, emoji: String, status: String,
               activity: String, place: String, eta: String, dist: String)
    let status: FeedStatus
    let participantCount: Int
    let extraEmojis: [String]
    let concreteStatus: String
    let isFeatured: Bool
    var onAvatarTap: (() -> Void)? = nil
    var onCardTap: (() -> Void)? = nil

    @State private var joined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Featured-Badge (nur erste Card)
            if isFeatured {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentOrange)
                    Text(tr("feed.popular_nearby"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentOrange)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            }

            HStack(alignment: .top, spacing: 12) {
                // Avatar — tappbar für Mini-Profil
                Button { onAvatarTap?() } label: {
                    AvatarBadge(emoji: item.emoji, size: 44, isAvailable: true)
                }
                .buttonStyle(.plain)
                .padding(.top, isFeatured ? 0 : 10)

                VStack(alignment: .leading, spacing: 0) {
                    // Name + Status-Badge
                    HStack(spacing: 7) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                        statusBadge
                    }
                    .padding(.top, isFeatured ? 0 : 10)

                    // Ort – prominent
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.brand)
                        Text(item.place)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("·")
                            .foregroundColor(.textTertiary)
                        Text(item.activity)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brand)
                    }
                    .padding(.top, 4)

                    // Social Proof + Distanz
                    HStack(spacing: 10) {
                        if participantCount > 0 || !extraEmojis.isEmpty {
                            participantRow
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 10)).foregroundColor(.textTertiary)
                            Text("\(item.eta) · \(item.dist)")
                                .font(.system(size: 11)).foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.top, 6)

                    // CTA Button
                    Button(action: { withAnimation(.spring(response: 0.3)) { joined = true } }) {
                        HStack(spacing: 6) {
                            if joined {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(tr("feed.im_in"))
                                    .font(.system(size: 13, weight: .bold))
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(tr("feed.join_now"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .foregroundColor(joined ? .onlineGreen : .brandInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            joined ? Color.onlineGreen.opacity(0.12) : Color.brand,
                            in: RoundedRectangle(cornerRadius: Radius.card)
                        )
                        .overlay(
                            joined ? RoundedRectangle(cornerRadius: Radius.card)
                                .stroke(Color.onlineGreen.opacity(0.5), lineWidth: 1) : nil
                        )
                        .shadow(color: joined ? .clear : Color.brand.opacity(0.25), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(joined)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 12)
        }
        .liquidGlass(cornerRadius: 18)
        .padding(.horizontal, 14).padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture { onCardTap?() }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(status.color)
            Text(status.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(status.color.opacity(0.12))
        .cornerRadius(8)
    }

    // MARK: - Participant Row

    private var participantRow: some View {
        HStack(spacing: -6) {
            // Host-Kreis
            Circle()
                .fill(Color.brand.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay(Text(item.emoji).font(.system(size: 11)))
                .zIndex(Double(extraEmojis.count + 1))

            // Extra-Teilnehmer
            ForEach(Array(extraEmojis.prefix(2).enumerated()), id: \.offset) { j, emoji in
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 22, height: 22)
                    .overlay(Text(emoji).font(.system(size: 11)))
                    .zIndex(Double(extraEmojis.count - j))
            }

            Text(participantCountLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.leading, 10)
        }
    }

    private var participantCountLabel: String {
        let total = participantCount
        if total == 0 && extraEmojis.isEmpty { return "" }
        let count = max(total, extraEmojis.count)
        return count == 1
            ? tr("feed.waiting_one")
            : tr("feed.waiting_many").replacingOccurrences(of: "{count}", with: "\(count)")
    }
}

// MARK: - Stranger Drop Feed Card (Öffentliche Drops — schwächer)

struct StrangerDropFeedCard: View {
    let item: MapAnnotationItem
    @EnvironmentObject var store: AppStore
    @State private var joined = false
    @State private var showJoinConfirm = false
    @State private var showLeaveConfirm = false
    var onCreatorTap: (() -> Void)? = nil
    var onCardTap: (() -> Void)? = nil

    // Aurora-Farbe: deterministisch aus Drop-ID → immer gleiche Farbe pro Drop
    private var accentColor: Color {
        let auroraColors: [Color] = [
            Color.auroraCyan, // cyan
            Color.onlineGreen, // grün
            Color.auroraAmber, // amber
            Color.auroraPink, // pink
            Color.auroraViolet, // violet
            Color.auroraTeal, // teal
        ]
        let index = abs(item.id.hashValue) % auroraColors.count
        return auroraColors[index]
    }
    private var alreadyJoined: Bool { store.hasJoinedDrop(dropID: item.id) }

    var body: some View {
        ZStack {
            // ── Karten-Inhalt ───────────────────────────────────────
            HStack(alignment: .center, spacing: 14) {
                // Emoji Badge
                Button {
                    onCreatorTap?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Text(item.emoji.isEmpty ? "✨" : item.emoji)
                            .font(.system(size: 24))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.activity)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        // Zeitfenster-Badge
                        let timeLabel = item.scheduledTime ?? "Jetzt"
                        let timeLabelDisplay = trScheduledTime(timeLabel)
                        HStack(spacing: 3) {
                            Image(systemName: timeLabel == "Jetzt" ? "circle.fill" : "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(timeLabelDisplay)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accentColor.opacity(0.12))
                        .cornerRadius(5)
                    }
                    Button {
                        onCreatorTap?()
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                            if let age = item.creatorAge {
                                Text("\(age)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                            // Community-Creator Badge — wenn der Host eine Community hat
                            if FeatureFlags.communitiesEnabled,
                               let uid = item.hostUID,
                               store.communityForCreator(uid: uid) != nil {
                                CommunityCreatorBadge(community: nil, compact: true)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 11)).foregroundColor(.textSecondary)
                        Text("\(store.etaString(to: item.coordinate)) · \(store.distanceString(to: item.coordinate))")
                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                        Text("·").foregroundColor(.textTertiary).font(.system(size: 12))
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10)).foregroundColor(.textSecondary)
                        Text("\(item.participants.count) / \(item.maxParticipants)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(item.isFull ? .accentRed : .textSecondary)
                    }
                }

                Spacer()

                // Pending: Anfrage rausgegangen, Host hat noch nicht reagiert.
                // Wichtig: vor `isJoined` prüfen, weil hasJoinedDrop auch
                // pending als "joined" zählt — ohne diese Trennung würde der
                // Joiner sofort "Bin dabei!" sehen, bevor der Host bestätigt.
                let isPending = store.pendingJoinDropID == item.id
                let isJoined = (alreadyJoined || joined) && !isPending
                let cooldown = store.joinCooldownRemaining(dropID: item.id)
                let inCooldown = cooldown > 0 && !isJoined && !isPending
                // Blocked: User ist in EINEM ANDEREN Drop drin und kann
                // diesem nicht beitreten. Vorher: Button war aktiv, Tap
                // führte zu silent-fail im Store (sendJoinRequest blockt).
                // User dachte „der Button geht nicht".
                let blockedByOther = store.isInActiveDrop && !isJoined && !isPending
                // Voll: Drop hat sein Teilnehmer-Limit erreicht. Auf der
                // Karte wird der Pin in dem Fall ausgeblendet, hier im
                // Umgebungstab bleibt er sichtbar — aber der Button
                // wird zu „Voll" und ist deaktiviert.
                let isFull = item.isFull && !isJoined && !isPending

                Button(action: {
                        // Statt silent-fail bei deaktiviertem Button:
                        // erklärenden Toast zeigen. User hatte vorher kein
                        // Feedback warum der Tap nichts macht.
                        if isFull {
                            store.showInfoToast(
                                tr("feed.drop_full_toast").replacingOccurrences(of: "{max}", with: "\(item.maxParticipants)"),
                                icon: "person.fill.xmark"
                            )
                            return
                        }
                        if blockedByOther {
                            store.showInfoToast(
                                tr("feed.in_other_drop_toast"),
                                icon: "lock.fill"
                            )
                            return
                        }
                        if inCooldown {
                            let mins = Int(cooldown / 60) + 1
                            store.showInfoToast(
                                tr("feed.cooldown_toast").replacingOccurrences(of: "{mins}", with: "\(mins)"),
                                icon: "clock.arrow.circlepath"
                            )
                            return
                        }
                        if isPending {
                            // Pending-Tap: Anfrage zurückziehen
                            store.leaveDropJoin(dropID: item.id)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = false }
                        } else if isJoined {
                            // Bereits dabei → Verlassen bestätigen
                            showLeaveConfirm = true
                        } else {
                            // ÖFFNET das Compose-Sheet — schickt NICHT direkt.
                            showJoinConfirm = true
                        }
                    }) {
                        let colors = feedJoinButtonColors(
                            blockedByOther: blockedByOther,
                            inCooldown: inCooldown,
                            isPending: isPending,
                            isJoined: isJoined,
                            isFull: isFull
                        )
                        feedJoinButtonLabel(
                            blockedByOther: blockedByOther,
                            inCooldown: inCooldown,
                            cooldownMin: Int(cooldown / 60) + 1,
                            isPending: isPending,
                            isJoined: isJoined,
                            isFull: isFull
                        )
                        .foregroundColor(colors.fg)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(colors.bg)
                        .cornerRadius(Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(colors.stroke, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    // Kein `.disabled(...)` mehr — wir wollen den Tap
                    // bewusst durchlassen, um im Action-Closure einen
                    // erklärenden Toast zu zeigen (Cooldown / Voll /
                    // Bereits-in-Drop). Visuell wirkt der Button durch
                    // die grauen Farben aus feedJoinButtonColors weiter
                    // wie „nicht aktiv".
                    .sheet(isPresented: $showLeaveConfirm) {
                        // Lokales Sekunden-Delta anhand der hostessen joinRequest
                        // (createdAt). Bei pending Requests sind 0 sekunden okay,
                        // bei akzeptierten kann das 12+ min sein → Sheet zeigt
                        // dann die Score-Risiko-Warnung.
                        let elapsed: TimeInterval = {
                            if let req = store.joinRequests.first(where: { $0.dropID == item.id }) {
                                return Date().timeIntervalSince(req.createdAt)
                            }
                            return 0
                        }()
                        LeaveDropSheet(
                            activityEmoji: item.emoji,
                            activityName: item.activity,
                            elapsedSeconds: elapsed
                        ) {
                            store.leaveDropJoin(dropID: item.id)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = false }
                            showLeaveConfirm = false
                        } onCancel: {
                            showLeaveConfirm = false
                        }
                        .presentationDetents([.fraction(0.65)])
                        // Verlassen-Warnung darf nicht versehentlich
                        // weggewischt werden — User muss bewusst Verlassen
                        // oder Abbrechen tippen.
                        .presentationDragIndicator(.hidden)
                        .interactiveDismissDisabled()
                        .sheetBackground()
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .liquidGlass(cornerRadius: Radius.lg)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { onCardTap?() }
        // Beitritts-Compose + Bestätigung
        .sheet(isPresented: $showJoinConfirm) {
            JoinConfirmSheet(item: item) {
                // Wird vom Sheet aufgerufen wenn die Anfrage tatsächlich
                // rausgegangen ist — erst dann den Card-State auf "Bin dabei"
                // setzen, sonst flackert der Status falls der User abbricht.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = true }
            }
                .environmentObject(store)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
        }
    }

    /// Farbpalette für den Join-Button — als Tuple ausgelagert weil
    /// inline-Ternäres-Cascading den Compiler überfordert.
    private func feedJoinButtonColors(
        blockedByOther: Bool, inCooldown: Bool,
        isPending: Bool, isJoined: Bool, isFull: Bool
    ) -> (fg: Color, bg: Color, stroke: Color) {
        if isFull {
            // Rot — signalisiert „nicht beitretbar weil voll" (klar
            // unterscheidbar von neutral-grau wie blocked/cooldown).
            return (.accentRed, Color.accentRed.opacity(0.10), Color.accentRed.opacity(0.25))
        }
        if blockedByOther {
            return (.textTertiary, Color.primary.opacity(0.05), Color.primary.opacity(0.10))
        }
        if inCooldown {
            return (.textTertiary, Color.primary.opacity(0.05), Color.primary.opacity(0.10))
        }
        if isPending {
            return (.accentOrange, Color.accentOrange.opacity(0.10), Color.accentOrange.opacity(0.30))
        }
        if isJoined {
            return (.onlineGreen, Color.onlineGreen.opacity(0.10), Color.onlineGreen.opacity(0.30))
        }
        return (accentColor, accentColor.opacity(0.10), accentColor.opacity(0.20))
    }

    /// Label für den Join-Button — extrahiert damit der SwiftUI-Compiler
    /// den verschachtelten if/else-Branch nicht type-check-timeoutet.
    @ViewBuilder
    private func feedJoinButtonLabel(blockedByOther: Bool,
                                     inCooldown: Bool,
                                     cooldownMin: Int,
                                     isPending: Bool,
                                     isJoined: Bool,
                                     isFull: Bool) -> some View {
        HStack(spacing: 4) {
            if isFull {
                Image(systemName: "person.fill.xmark").font(.system(size: 10, weight: .medium))
                Text(tr("feed.full"))
                    .font(.system(size: 12, weight: .semibold))
            } else if blockedByOther {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text(tr("feed.in_drop"))
                    .font(.system(size: 12, weight: .semibold))
            } else if inCooldown {
                Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                Text("\(cooldownMin) \(tr("map.min_short"))")
                    .font(.system(size: 12, weight: .semibold))
            } else if isPending {
                Image(systemName: "hourglass").font(.system(size: 10, weight: .medium))
                Text(tr("feed.pending"))
                    .font(.system(size: 12, weight: .semibold))
            } else if isJoined {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Text(tr("feed.im_in"))
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text(tr("feed.im_coming"))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

// MARK: - Join Confirm Sheet

struct JoinConfirmSheet: View {
    let item: MapAnnotationItem
    /// Wird gerufen wenn die Anfrage tatsächlich gesendet wurde — die
    /// FeedView setzt darauf hin den `joined`-State. Vorher fehlte das,
    /// dadurch flackerte die Card wenn der User das Sheet zumachte ohne
    /// "Senden" zu drücken.
    let onSent: () -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Tatsächlich rausgehende Nachricht — befüllt durch Quick-Chip-Tap
    /// oder freie Eingabe im TextField. nil = keine Nachricht senden.
    @State private var composedMessage: String = ""
    @State private var sending = false
    @State private var sent = false

    /// Activity-bezogene Quick-Messages — passende Vorschläge je nach
    /// Drop-Typ. WICHTIG: nur Statements, keine Fragen — der Host sieht
    /// die Nachricht nur einmal in der Beitrittsanfrage und kann nicht
    /// darauf antworten. Fragen wie "Welche Bar?" laufen also ins Leere.
    /// Substring-Match damit Varianten wie "Bier", "Bierchen", "Drink"
    /// dasselbe Set treffen.
    private var quickMessages: [String] {
        let activity = item.activity.lowercased()
        // Drinks / Bar
        if activity.contains("bier") || activity.contains("drink")
            || activity.contains("bar") || activity.contains("cocktail")
            || activity.contains("party") {
            return ["Bin in 10 Min da 🍻",
                    "Erste Runde geht auf mich!",
                    "Hab Bock auf den Abend",
                    "Freu mich!"]
        }
        // Kaffee / Café / Brunch
        if activity.contains("kaffee") || activity.contains("brunch")
            || activity.contains("café") || activity.contains("cafe") {
            return [tr("feed.preset.coffee.1"),
                    tr("feed.preset.coffee.2"),
                    tr("feed.preset.coffee.3"),
                    tr("feed.preset.coffee.4")]
        }
        // Essen / Restaurant
        if activity.contains("essen") || activity.contains("food")
            || activity.contains("dinner") || activity.contains("lunch")
            || activity.contains("pizza") || activity.contains("burger") {
            return [tr("feed.preset.food.1"),
                    tr("feed.preset.food.2"),
                    tr("feed.preset.food.3"),
                    tr("feed.preset.food.4")]
        }
        // Sport / Workout / Laufen
        if activity.contains("sport") || activity.contains("workout")
            || activity.contains("lauf") || activity.contains("yoga")
            || activity.contains("gym") || activity.contains("fitness")
            || activity.contains("foto-walk") || activity.contains("walk")
            || activity.contains("spazier") {
            return [tr("feed.preset.sport.1"),
                    tr("feed.preset.sport.2"),
                    tr("feed.preset.sport.3"),
                    tr("feed.preset.sport.4")]
        }
        // Konzert / Musik / Festival
        if activity.contains("konzert") || activity.contains("musik")
            || activity.contains("festival") || activity.contains("club")
            || activity.contains("dj") {
            return [tr("feed.preset.music.1"),
                    tr("feed.preset.music.2"),
                    tr("feed.preset.music.3"),
                    tr("feed.preset.music.4")]
        }
        // Kino / Film
        if activity.contains("kino") || activity.contains("film")
            || activity.contains("movie") {
            return [tr("feed.preset.movie.1"),
                    tr("feed.preset.movie.2"),
                    tr("feed.preset.movie.3"),
                    tr("feed.preset.movie.4")]
        }
        // Gaming / Zocken
        if activity.contains("zock") || activity.contains("gaming")
            || activity.contains("game") {
            return [tr("feed.preset.gaming.1"),
                    tr("feed.preset.gaming.2"),
                    tr("feed.preset.gaming.3"),
                    tr("feed.preset.gaming.4")]
        }
        // Park / Outdoor / Hangout
        if activity.contains("park") || activity.contains("outdoor")
            || activity.contains("strand") || activity.contains("see") {
            return [tr("feed.preset.outdoor.1"),
                    tr("feed.preset.outdoor.2"),
                    tr("feed.preset.outdoor.3"),
                    tr("feed.preset.outdoor.4")]
        }
        // Shopping / Bummeln
        if activity.contains("shop") || activity.contains("bummel")
            || activity.contains("einkauf") {
            return [tr("feed.preset.shopping.1"),
                    tr("feed.preset.shopping.2"),
                    tr("feed.preset.shopping.3"),
                    tr("feed.preset.shopping.4")]
        }
        // Generischer Fallback
        return [tr("feed.preset.fallback.1"),
                tr("feed.preset.fallback.2"),
                tr("feed.preset.fallback.3"),
                tr("feed.preset.fallback.4")]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            // Icon
            ZStack {
                Circle()
                    .fill(Color.auroraViolet.opacity(0.12))
                    .frame(width: 64, height: 64)
                Text(item.emoji)
                    .font(.system(size: 30))
            }

            VStack(spacing: 4) {
                Text(sent ? tr("feed.waiting_for_confirm") : tr("feed.send_request_to").replacingOccurrences(of: "{name}", with: item.name))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                if !sent {
                    Text(tr("feed.optional_message"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            if !sent {
                // Quick-Nachrichten — Chip befüllt das TextField, User kann's
                // dann noch editieren oder einfach so absenden.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickMessages, id: \.self) { msg in
                            Button {
                                composedMessage = msg
                            } label: {
                                Text(msg)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(composedMessage == msg
                                                     ? .white
                                                     : Color.auroraViolet)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(
                                        composedMessage == msg
                                        ? Color.auroraViolet
                                        : Color.auroraViolet.opacity(0.12)
                                    )
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Freie Texteingabe entfernt — nur Quick-Chips (oben).
                // Custom-Nachrichten führten zu Spam-Risiko + erforderten
                // mehr Modering. Quick-Chips reichen für „kurzer Kontext"-Use-Case.
            } else {
                // Wartezustand nach Senden — zeigt klar dass der Host
                // erst noch bestätigen muss. Pulsierender Indicator gibt
                // visuelles Feedback dass die App aktiv "wartet" und kein
                // dead-end ist.
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView().tint(.brand).scaleEffect(0.9)
                            .tint(Color.auroraViolet)
                            .scaleEffect(0.9)
                        Text(tr("feed.notified").replacingOccurrences(of: "{name}", with: item.name))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    Text(tr("feed.close_window_msg").replacingOccurrences(of: "{name}", with: item.name))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            // Senden / Schließen
            HStack(spacing: 10) {
                if !sent {
                    Button { dismiss() } label: {
                        Text(tr("feed.cancel"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Button { sendRequest() } label: {
                        HStack(spacing: 6) {
                            if sending {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text(sending ? tr("feed.sending") : tr("feed.send"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(Color.auroraViolet)
                                .shadow(color: Color.auroraViolet.opacity(0.35),
                                        radius: 10, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                } else {
                    // Sheet bleibt offen bis User selber schließt — sonst
                    // sieht's so aus als wäre die Anfrage angenommen, was
                    // sie noch nicht ist. User entscheidet wann fertig.
                    Button { dismiss() } label: {
                        Text(tr("feed.wait_in_background"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendRequest() {
        guard !sending && !sent else { return }
        sending = true
        let trimmed = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        store.sendJoinRequest(to: item, message: payload)
        onSent()
        // Sheet sofort schließen — der Wartestatus ist global sichtbar
        // über die Pending-Pill oben in der App (PendingJoinRequestPill).
        // User muss nicht mehr im Sheet sitzen während er auf Antwort wartet.
        dismiss()
    }
}

// MARK: - Boost Banner
//
// Erscheint im Umgebungs-Tab unten wenn weniger als `AppStore.boostThreshold`
// Drops in Reichweite sind. Reine Info-Karte — der „Drop erstellen"-Button
// ist im DropsEmptyState bzw. in der Tab-Bar; doppelt wäre verwirrend.
// Der eigentliche Bonus wird in AppStore.applyBoostBonusIfActive vergeben
// (createDrop / confirmEncounter / recordHostSuccess).
struct BoostBanner: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentOrange, Color.brand],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.accentOrange.opacity(pulse ? 0.55 : 0.25), radius: pulse ? 14 : 6)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("feed.boost_phase_active"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(tr("feed.boost_phase_explainer"))
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentOrange.opacity(0.10),
                            Color.brand.opacity(0.10),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.accentOrange.opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

