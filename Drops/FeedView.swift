import SwiftUI

// MARK: - Feed Status

enum FeedStatus {
    case justArrived, active, starting

    var label: String {
        switch self {
        case .justArrived: return "Gerade da"
        case .active:      return "Aktiv"
        case .starting:    return "Startet gleich"
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
    @State private var profileAccent: Color = Color(UIColor.systemPurple)
    @State private var auroraAnimate = false

    private func showStrangerProfile(_ item: MapAnnotationItem) {
        let creator = item.participants.first ?? DropParticipant(name: item.name, emoji: item.emoji)
        profileParticipant = creator
        profileCanBlock = true
        profileSubtitle = tr("feed.user")
        profileAccent = Color(UIColor.systemPurple)
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

    /// Aktivitäts-Kategorien für den Chip-Filter. SF Symbol + Drop-Emojis +
    /// Keywords matchen gegen den activityName/emoji eines Drops.
    private let activityCategories: [(key: String, icon: String, dropEmojis: [String], keywords: [String])] = [
        ("Kaffee", "cup.and.saucer.fill",
            ["☕️", "☕", "🧋"],
            ["kaffee", "coffee", "café", "cafe", "espresso", "latte"]),
        ("Drink",  "wineglass",
            ["🍺", "🍻", "🍷", "🥂", "🍹", "🍸"],
            ["drink", "drinks", "bier", "beer", "wein", "wine", "cocktail", "bar", "feierabend", "club", "party", "ausgehen"]),
        ("Sport",  "figure.run",
            ["🏃", "🏃‍♂️", "🏃‍♀️", "🏋️", "🧘", "⚽️", "🎾", "🏀", "🚴"],
            ["sport", "fitness", "gym", "laufen", "run", "joggen", "jog", "fußball", "tennis", "basketball", "yoga", "fahrrad", "bike"]),
        ("Essen",  "fork.knife",
            ["🍕", "🍔", "🍣", "🍱", "🍜", "🌮", "🥗"],
            ["essen", "food", "lunch", "dinner", "pizza", "burger", "restaurant", "brunch", "sushi", "dönner"]),
        ("Zocken", "gamecontroller.fill",
            ["🎮", "🕹️"],
            ["zocken", "zock", "gaming", "game", "games", "spielen", "xbox", "playstation"])
    ]

    /// Prüft ob ein Drop in die aktuell gewählte Kategorie passt.
    private func matchesActivityFilter(_ item: MapAnnotationItem) -> Bool {
        guard !store.activityCategoryFilter.isEmpty else { return true }
        guard let cat = activityCategories.first(where: { $0.key == store.activityCategoryFilter }) else { return true }
        if cat.dropEmojis.contains(item.emoji) { return true }
        let activity = item.activity.lowercased()
        return cat.keywords.contains(where: { activity.contains($0) })
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
        switch store.feedDistanceFilter {
        case .nearby, .quarter:
            let radius = store.feedDistanceFilter.meters
            base = base.filter { $0.distance(from: userCoord) <= radius }
        case .city:
            if let myCity = ServiceCities.city(for: userCoord) {
                base = base.filter { myCity.contains($0.coordinate) }
            } else if let myCityNear = ServiceCities.cityNear(userCoord) {
                // User im Vorort (40km-Buffer) → zeig Drops aus der nächstgelegenen Stadt
                base = base.filter { myCityNear.contains($0.coordinate) }
            }
        }
        if store.genderFilterEnabled && store.userGender == "weiblich" {
            base = base.filter { ($0.hostGender?.lowercased() ?? "") == "weiblich" }
        }
        base = base.filter { matchesActivityFilter($0) }
        return base.sorted { a, b in
            // Priority Listing: geboostete Drops immer zuerst
            if a.isBoosted != b.isBoosted { return a.isBoosted }
            // Danach nach Interessen-Match (falls Interessen gesetzt sind)
            if !store.userInterests.isEmpty {
                let scoreA = interestScore(for: a)
                let scoreB = interestScore(for: b)
                if scoreA != scoreB { return scoreA > scoreB }
            }
            return false
        }
    }

    /// Horizontale Chip-Leiste für den Aktivitäts-Filter — im App-Stil (Liquid Glass).
    private var activityFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                activityChip(
                    title: "Alle",
                    icon: "square.grid.2x2.fill",
                    selected: store.activityCategoryFilter.isEmpty
                ) {
                    store.activityCategoryFilter = ""
                    store.saveAll()
                }
                ForEach(activityCategories, id: \.key) { cat in
                    activityChip(
                        title: cat.key,
                        icon: cat.icon,
                        selected: store.activityCategoryFilter == cat.key
                    ) {
                        store.activityCategoryFilter = (store.activityCategoryFilter == cat.key) ? "" : cat.key
                        store.saveAll()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func activityChip(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { action() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .brand)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selected ? .white : .textPrimary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    selected
                        ? Color.brand
                        : Color(UIColor.secondarySystemGroupedBackground)
                )
            )
            .shadow(color: selected ? Color.brand.opacity(0.30) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Segmented Control: Drop-Radius (1km / 3km / Stadt) + „Heute Abend"-Toggle.
    /// Sichtbarer Label-Header macht klar, dass es um den Suchradius geht.
    private var distanceTimeFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.brand)
                Text("Drop-Radius")
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
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    selected
                        ? Color.brand
                        : Color(UIColor.secondarySystemGroupedBackground)
                )
            )
            .shadow(color: selected ? Color.brand.opacity(0.25) : .clear, radius: 6, y: 2)
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
                Text("Nur weiblich")
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
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        store.genderFilterEnabled
                            ? Color.brand
                            : Color(UIColor.secondarySystemGroupedBackground)
                    )
            )
            .shadow(color: store.genderFilterEnabled ? Color.brand.opacity(0.30) : .clear, radius: 10, y: 4)
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
            "Bin gerade im \(item.place)",
            "Auf dem Weg – komm dazu!",
            "Schon da, wartet auf euch",
            "Gerade dort angekommen",
            "Startet in wenigen Minuten",
            "Drop offen – join jetzt!"
        ]
        // TODO: These statuses need to be localized per language preference
        return texts[index % texts.count]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                // Aurora-Hintergrund oben (wie Freunde-Tab)
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.30))
                        .frame(width: 280, height: 280)
                        .blur(radius: 65)
                        .offset(x: auroraAnimate ? 30 : -40, y: auroraAnimate ? -50 : -15)
                    Circle()
                        .fill(Color(UIColor.systemPurple).opacity(0.20))
                        .frame(width: 220, height: 220)
                        .blur(radius: 55)
                        .offset(x: auroraAnimate ? -55 : 35, y: auroraAnimate ? -15 : -55)
                    Circle()
                        .fill(Color(UIColor.systemTeal).opacity(0.15))
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
                            }
                        }

                        // ── Leer-State ──
                        if sortedFriendDrops.isEmpty && strangerAnnotations.isEmpty {
                            DropsEmptyState(onCreateTap: {
                                store.selectedTab = .create
                            })
                                .padding(.top, 48)
                        }

                        // ── Boost-Banner: unten, wenn <5 Drops in Reichweite ──
                        // Reine Info — kein eigener Drop-Button, der ist schon im
                        // DropsEmptyState bzw. der Tab-Bar.
                        if (sortedFriendDrops.count + strangerAnnotations.count) < AppStore.boostThreshold {
                            BoostBanner()
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
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
                        isVerified: p.isVerified,
                        userUID: p.firebaseUID,
                        canBlock: profileCanBlock
                    ) { profileParticipant = nil }
                        .environmentObject(store)
                        .presentationDetents([.height(360), .medium])
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
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay(
                            joined ? RoundedRectangle(cornerRadius: 11)
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
        // Note: These strings need localization context to use tr()
        // For now, kept in German as this is data-driven in code
        return count == 1 ? "1 wartet" : "\(count) warten"
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
            Color(hex: "06b6d4"), // cyan
            Color(hex: "22c55e"), // grün
            Color(hex: "f59e0b"), // amber
            Color(hex: "ec4899"), // pink
            Color(hex: "8b5cf6"), // violet
            Color(hex: "14b8a6"), // teal
        ]
        let index = abs(item.id.hashValue) % auroraColors.count
        return auroraColors[index]
    }
    private var alreadyJoined: Bool { store.hasJoinedDrop(dropID: item.id) }
    /// Im Feed (Umgebung) ist alles lesbar — Name, Emoji, Aktivität. Nur auf der
    /// Karte bleibt der genaue Standort bei Fremden-Drops verschwommen (isFuzzy).
    private var isVerified: Bool { true }

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
                        if isVerified {
                            Text(item.emoji.isEmpty ? "✨" : item.emoji)
                                .font(.system(size: 24))
                        } else {
                            Image(systemName: "questionmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(accentColor)
                                .blur(radius: 4)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(isVerified ? item.activity : "████████")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .blur(radius: isVerified ? 0 : 5)
                        // Zeitfenster-Badge statt "Offen für alle" — das ist die relevante Info
                        let timeLabel = item.scheduledTime ?? "Jetzt"
                        HStack(spacing: 3) {
                            Image(systemName: timeLabel == "Jetzt" ? "circle.fill" : "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(timeLabel)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accentColor.opacity(0.12))
                        .cornerRadius(5)
                    }
                    // Creator-Chip — nur tappbar wenn verifiziert
                    Button {
                        guard isVerified else { return }
                        onCreatorTap?()
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(accentColor.opacity(0.15))
                                .frame(width: 16, height: 16)
                                .overlay(Text(isVerified ? item.emoji : "?").font(.system(size: 8)))
                            Text(isVerified ? item.name : tr("feed.unknown"))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .blur(radius: isVerified ? 0 : 4)
                            if isVerified, let age = item.creatorAge {
                                Text("\(age)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                            Image(systemName: isVerified ? "chevron.right" : "lock.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 11)).foregroundColor(.textTertiary)
                        Text(isVerified
                             ? "\(store.etaString(to: item.coordinate)) · \(store.distanceString(to: item.coordinate))"
                             : "~? min · ~? km")
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                            .blur(radius: isVerified ? 0 : 4)
                        if isVerified && !item.participants.isEmpty {
                            Text("·").foregroundColor(.textTertiary).font(.system(size: 12))
                            Text("\(item.participants.count) \(tr("feed.joining"))")
                                .font(.system(size: 12)).foregroundColor(.textTertiary)
                        }
                    }
                }

                Spacer()

                let isJoined = alreadyJoined || joined
                let cooldown = store.joinCooldownRemaining(dropID: item.id)
                let inCooldown = cooldown > 0 && !isJoined

                Button(action: {
                        if isJoined {
                            // Bereits dabei → Verlassen bestätigen
                            showLeaveConfirm = true
                        } else if !inCooldown {
                            store.joinDrop(item)
                            withAnimation(.spring()) { joined = true }
                            showJoinConfirm = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            if inCooldown {
                                Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                                Text("\(Int(cooldown / 60) + 1) Min")
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
                        .foregroundColor(inCooldown ? .textTertiary : isJoined ? .onlineGreen : accentColor)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(inCooldown ? Color.primary.opacity(0.05) : isJoined ? Color.onlineGreen.opacity(0.1) : accentColor.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(inCooldown ? Color.primary.opacity(0.1) : isJoined ? Color.onlineGreen.opacity(0.3) : accentColor.opacity(0.2), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(inCooldown)
                    .confirmationDialog(tr("feed.leave_drop"), isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                        Button(tr("feed.leave"), role: .destructive) {
                            store.leaveDropJoin(dropID: item.id)
                            withAnimation(.spring()) { joined = false }
                        }
                        Button(tr("common.cancel"), role: .cancel) {}
                    } message: {
                        Text(tr("feed.leave_warning"))
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .liquidGlass(cornerRadius: 16)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { onCardTap?() }
        // Beitritts-Bestätigung
        .sheet(isPresented: $showJoinConfirm) {
            JoinConfirmSheet(item: item)
                .environmentObject(store)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
        }
    }
}

// MARK: - Join Confirm Sheet

struct JoinConfirmSheet: View {
    let item: MapAnnotationItem
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var sent = false

    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            // Icon
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemPurple).opacity(0.12))
                    .frame(width: 64, height: 64)
                Text(item.emoji)
                    .font(.system(size: 30))
            }

            VStack(spacing: 6) {
                Text(tr("feed.request_sent"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                Text("\(item.name) wird benachrichtigt und kann dich zum \(item.activity)-Drop einlassen.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Quick-Nachrichten (Demo)
            VStack(spacing: 8) {
                Text(tr("feed.add_message"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Bin gleich da! 🏃", "5 Min Wartezeit", "Bin schon in der Nähe ✓", "Komme alleine"], id: \.self) { msg in
                            Button(action: { sent = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() } }) {
                                Text(msg)
                                    .font(.system(size: 12))
                                    .foregroundColor(sent ? .onlineGreen : Color(UIColor.systemPurple))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color(UIColor.systemPurple).opacity(0.1))
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color(UIColor.systemPurple).opacity(0.2), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Button(action: { dismiss() }) {
                Text(tr("feed.close"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("Boost-Phase aktiv")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("+15 Extra-Punkte für jeden Drop, den du jetzt erstellst oder triffst.")
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
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

