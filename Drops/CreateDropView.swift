import SwiftUI
import MapKit
import CoreLocation

// Makes the sheet truly transparent by clearing every UIKit layer
// between UIHostingController.view and the window.
// On modern iOS the white comes from _UISheetDetentContainerView /
// UIDropShadowView which sit ABOVE the hosting VC's own view.
private struct _ClearSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Run once after layout so the sheet hierarchy is fully built
        DispatchQueue.main.async { Self.clearSheetLayers() }
        // Run again slightly later in case iOS re-applies a background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.clearSheetLayers() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.clearSheetLayers() }
    }

    private static func clearSheetLayers() {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }

        // Walk to the topmost presented VC (our sheet's UIHostingController)
        var vc = window.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        guard let sheetVC = vc else { return }

        // 1. Clear the presentation controller's container view —
        //    this is the UISheetPresentationController's root view and
        //    is typically where the white rounded-rect background lives.
        sheetVC.presentationController?.containerView?.backgroundColor = .clear
        sheetVC.presentationController?.containerView?.subviews.forEach {
            $0.backgroundColor = .clear
        }

        // 2. Clear the VC's own view
        sheetVC.view.backgroundColor = .clear

        // 3. Traverse UP the superview chain (handles _UISheetDetentContainerView,
        //    UIDropShadowView, and other wrapper views on iOS 16–26).
        var view: UIView? = sheetVC.view
        for _ in 0..<6 {
            view?.backgroundColor = .clear
            view = view?.superview
        }
    }
}

class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText = ""
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var selectedLocation: DropLocationResult? = nil
    private var completer = MKLocalSearchCompleter()

    /// Bekannte Ortsnamen der Drops-Servicezone für Text-Filterung
    private static let zoneKeywords: [String] = [
        "münchen", "munich",
        "schwabing", "maxvorstadt", "haidhausen", "bogenhausen", "sendling",
        "neuhausen", "nymphenburg", "pasing", "aubing", "moosach", "allach",
        "milbertshofen", "freimann", "trudering", "riem", "perlach", "neuperlach",
        "solln", "forstenried", "hadern", "lochhausen", "feldmoching", "hasenbergl",
        "unterschleißheim", "oberschleißheim", "ismaning", "unterföhring",
        "haar", "ottobrunn", "unterhaching", "grünwald", "gauting",
        "germering", "puchheim", "karlsfeld", "dachau", "gilching",
        "bayern", "bavaria"
    ]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Suche auf aktuelle Region begrenzen (~50 km Radius um Nutzerstandort)
        updateRegion()
    }

    func updateRegion(center: CLLocationCoordinate2D? = nil) {
        let coord = center ?? CLLocationManager().location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575) // München fallback
        completer.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }

    func search(_ query: String) { completer.queryFragment = query }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let keywords = Self.zoneKeywords
        var seen = Set<String>()
        let filtered = completer.results.filter { r in
            // 1. Nur Ergebnisse aus der Drops-Servicezone
            let combined = (r.title + " " + r.subtitle).lowercased()
            let inZone = keywords.contains { combined.contains($0) }
            guard inZone else { return false }
            // 2. Duplikate: nur der erste Treffer pro Titel zählt
            return seen.insert(r.title.lowercased()).inserted
        }
        results = Array(filtered.prefix(5))
    }

    func selectResult(_ result: MKLocalSearchCompletion, completion: @escaping (DropLocationResult?) -> Void) {
        let request = MKLocalSearch.Request(completion: result)
        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else { completion(nil); return }
            let loc = DropLocationResult(
                title: item.name ?? result.title,
                subtitle: result.subtitle,
                coordinate: item.placemark.coordinate
            )
            DispatchQueue.main.async { completion(loc) }
        }
    }
}

struct DropLocationResult {
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Emoji Suggestion Engine

private let emojiKeywords: [(keywords: [String], emoji: String)] = [
    (["fußball", "fussball", "soccer", "football"], "⚽"),
    (["basketball"], "🏀"),
    (["volleyball"], "🏐"),
    (["tennis"], "🎾"),
    (["golf"], "⛳"),
    (["kaffee", "coffee", "café", "cafe"], "☕"),
    (["tee", "tea"], "🍵"),
    (["bier", "beer", "brauen", "craft"], "🍺"),
    (["wein", "wine", "vino"], "🍷"),
    (["cocktail", "bar", "drink"], "🍹"),
    (["pizza"], "🍕"),
    (["burger", "mcdonald", "fastfood"], "🍔"),
    (["sushi", "japanisch"], "🍣"),
    (["eis", "eiscreme", "frozen"], "🍦"),
    (["kuchen", "cake", "torte", "dessert"], "🎂"),
    (["essen", "restaurant", "lunch", "dinner", "mittag", "abend"], "🍽️"),
    (["frühstück", "breakfast", "brunch"], "🥐"),
    (["laufen", "joggen", "running", "jogging", "rennen"], "🏃"),
    (["wandern", "hiking", "hike", "berg", "mountain"], "🥾"),
    (["schwimmen", "swimming", "pool", "freibad"], "🏊"),
    (["fahrrad", "cycling", "bike", "radfahren", "rad"], "🚴"),
    (["yoga", "meditation"], "🧘"),
    (["fitness", "gym", "training", "workout", "sport"], "💪"),
    (["gaming", "zocken", "spielen", "gamer", "game"], "🎮"),
    (["kino", "film", "movie", "cinema"], "🎬"),
    (["musik", "konzert", "concert", "festival", "musik"], "🎵"),
    (["party", "feiern", "club", "disco"], "🎉"),
    (["geburtstag", "birthday"], "🎂"),
    (["shoppen", "shopping", "einkaufen", "kaufen"], "🛍️"),
    (["museum", "ausstellung", "galerie"], "🏛️"),
    (["strand", "beach", "meer", "sea"], "🏖️"),
    (["park", "spazieren", "spaziergang", "garten", "walk"], "🌳"),
    (["hund", "dog", "welpe", "gassi"], "🐕"),
    (["lernen", "studieren", "study", "büfeln", "bibliothek"], "📚"),
    (["arbeiten", "work", "meeting", "büro", "homeoffice"], "💼"),
    (["klettern", "climbing", "bouldern", "boulder"], "🧗"),
    (["ski", "snowboard", "skifahren"], "⛷️"),
    (["tanzen", "dance", "dancing"], "💃"),
    (["picknick", "picnic", "wiese"], "🧺"),
    (["kochen", "cooking", "cook", "küche"], "👨‍🍳"),
    (["flohmarkt", "markt", "market", "antik"], "🏪"),
    (["karten", "brettspiel", "board", "tabletop", "monopoly"], "🎲"),
    (["basteln", "basteln", "craft", "diy", "malen", "paint"], "🎨"),
    (["spazieren", "spaziergang"], "🚶"),
]

func suggestEmojis(for text: String) -> [String] {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
    var matched: [String] = []
    for entry in emojiKeywords {
        for word in words {
            if entry.keywords.contains(where: { word.contains($0) || $0.contains(word) && word.count >= 3 }) {
                if !matched.contains(entry.emoji) { matched.append(entry.emoji) }
                break
            }
        }
        if matched.count >= 6 { break }
    }
    return matched
}

struct CreateDropView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    @State private var activityName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var emojiLockedByUser = false
    @State private var dropDescription: String = ""
    @State private var scheduledTime: String = "Jetzt"
    @State private var showCustomTimePicker = false
    @State private var customDate: Date = Date()
@State private var selectedLocationType: LocationType = CLLocationManager().authorizationStatus == .authorizedWhenInUse || CLLocationManager().authorizationStatus == .authorizedAlways ? .current : .searched
    @State private var maxParticipants: Int = 10   // 2–15
    @State private var durationMinutes: Int = 120  // 0 = kein Limit
    @State private var isCreating = false
    @State private var created = false
    @State private var showPinMap = false
    @StateObject private var searchVM = LocationSearchViewModel()
    @State private var selectedLocationResult: DropLocationResult? = nil
    @State private var pinnedCoordinate: CLLocationCoordinate2D? = nil

    @State private var sheetPulse = false
    @State private var pendingHomeZoneCoord: CLLocationCoordinate2D? = nil
    @State private var showEmojiPicker = false

    var suggestedEmojis: [String] { suggestEmojis(for: activityName) }

    /// Nur leer oder explizit vom Nutzer gewählt — kein Auto-Vorschlag im Kreis.
    var displayEmoji: String { selectedEmoji }

    var locationSubtitle: String {
        switch selectedLocationType {
        case .current:  return "Aktueller Standort"
        case .searched: return selectedLocationResult?.title ?? "Ort suchen…"
        case .pin:      return pinnedCoordinate != nil ? "Pin gesetzt ✓" : "Auf Karte tippen"
        }
    }

    var body: some View {
        ZStack {
            // Vollflächiger App-Hintergrund
            AppAuroraBackground().ignoresSafeArea()

            // Aurora-Akzent (Grün, Lila, Teal)
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.22))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: sheetPulse ? 40 : -30, y: sheetPulse ? -70 : 10)
                Circle()
                    .fill(Color(UIColor.systemPurple).opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: sheetPulse ? -60 : 35, y: sheetPulse ? 10 : -50)
                Circle()
                    .fill(Color(UIColor.systemTeal).opacity(0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: 65)
                    .offset(x: sheetPulse ? 50 : -45, y: sheetPulse ? 40 : -20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // ── Sticky Navigationszeile: Titel + Schließen-Button ────
                // Liegt OBERHALB des ScrollViews und scrollt nicht mit —
                // damit "Drop erstellen" beim Scrollen nicht hinter dem
                // Status-Bar / der Uhrzeit verschwindet.
                //
                // Bewusst KEIN eigener Material-Hintergrund: Inhalt scrollt
                // im ScrollView darunter, nicht hinter dem Header durch.
                // Eine Material-Schicht würde sich farblich vom darunter
                // liegenden AppAuroraBackground absetzen und unschön
                // aussehen.
                HStack {
                    Text("Drop erstellen")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(UIColor.systemGray5).opacity(0.8),
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                    // ── Quick-Templates: dynamisch aus Interests + Past Drops
                    if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                        DropQuickTemplatesBar { tpl in
                            activityName = tpl.name
                            selectedEmoji = tpl.emoji
                            emojiLockedByUser = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }

                    // ── Aktivität ──────────────────────────────────────────
                    createSection(label: "Was macht ihr?", aurora: true) {
                        // Emoji + Textfeld
                        HStack(spacing: 14) {
                            // Tappbarer Emoji-Kreis: öffnet manuellen Picker.
                            // Wenn leer: Plus-Icon als Hinweis. Sonst gewähltes Emoji.
                            Button(action: { showEmojiPicker = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.brand.opacity(displayEmoji.isEmpty ? 0.07 : 0.12))
                                        .frame(width: 52, height: 52)
                                    Circle()
                                        .stroke(Color.brand.opacity(displayEmoji.isEmpty ? 0.25 : 0.0),
                                                style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                        .frame(width: 52, height: 52)
                                    if displayEmoji.isEmpty {
                                        Image(systemName: "face.smiling")
                                            .font(.system(size: 22, weight: .light))
                                            .foregroundColor(.textTertiary)
                                    } else {
                                        Text(displayEmoji).font(.system(size: 26))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: displayEmoji)
                            }
                            .buttonStyle(.plain)

                            TextField("z.B. Fußball, Kaffee, Wandern…", text: $activityName)
                                .font(.system(size: 15))
                                .foregroundColor(.textPrimary)
                                .onChange(of: activityName) { _, _ in
                                    if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                                        selectedEmoji = ""
                                        emojiLockedByUser = false
                                    } else if !emojiLockedByUser {
                                        selectedEmoji = ""
                                    }
                                }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)

                        // Emoji-Vorschläge — verschwinden nach Auswahl.
                        // Wenn keine Vorschläge matchen, kommt der "Selbst wählen"-Link.
                        if selectedEmoji.isEmpty {
                            if !suggestedEmojis.isEmpty {
                                Divider().padding(.leading, 16)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(suggestedEmojis, id: \.self) { emoji in
                                            Button(action: {
                                                selectedEmoji = emoji; emojiLockedByUser = true
                                            }) {
                                                let isActive = selectedEmoji == emoji
                                                Text(emoji).font(.system(size: 22))
                                                    .frame(width: 42, height: 42)
                                                    .background(isActive ? Color.brand.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                                        .stroke(isActive ? Color.brand.opacity(0.5) : Color.clear, lineWidth: 1.5))
                                            }
                                            .buttonStyle(.plain)
                                            .animation(.spring(response: 0.2), value: selectedEmoji)
                                        }
                                        // Picker-Button am Ende der Vorschläge — falls nichts passt
                                        Button(action: { showEmojiPicker = true }) {
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.textSecondary)
                                                .frame(width: 42, height: 42)
                                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else if !activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                                // Kein Match in der Keyword-Liste → User-Picker anbieten
                                Divider().padding(.leading, 16)
                                Button(action: { showEmojiPicker = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "face.smiling")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Emoji wählen")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(.brand)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                            }
                        }
                    }

                    // ── Wann ──────────────────────────────────────────────
                    createSection(label: "Wann?") {
                        // Quick-Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "Jetzt"-Chip
                                let nowLabel = "Jetzt"
                                let isJetzt = scheduledTime == nowLabel && !showCustomTimePicker
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    scheduledTime = nowLabel
                                    showCustomTimePicker = false
                                }) {
                                    Text(nowLabel)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(isJetzt ? .white : .textPrimary)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .background {
                                            if isJetzt {
                                                Capsule().fill(Color.brand)
                                                    .shadow(color: Color.brand.opacity(0.35), radius: 8, y: 3)
                                            } else {
                                                ZStack {
                                                    Capsule().fill(.thinMaterial)
                                                    Capsule().fill(Color.brand.opacity(0.04))
                                                }
                                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                                                .overlay(Capsule().stroke(
                                                    LinearGradient(colors: [Color.brand.opacity(0.2), .white.opacity(0.06)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                                    lineWidth: 0.8))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isJetzt)

                                // Uhrzeit-Chip direkt neben Jetzt
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.3)) { showCustomTimePicker.toggle() }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock").font(.system(size: 12))
                                        Text(showCustomTimePicker
                                             ? customDate.formatted(date: .omitted, time: .shortened)
                                             : "Uhrzeit")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(showCustomTimePicker ? .white : .textPrimary)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background {
                                        if showCustomTimePicker {
                                            Capsule().fill(Color.brand)
                                                .shadow(color: Color.brand.opacity(0.35), radius: 8, y: 3)
                                        } else {
                                            ZStack {
                                                Capsule().fill(.thinMaterial)
                                                Capsule().fill(Color.brand.opacity(0.04))
                                            }
                                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                                            .overlay(Capsule().stroke(
                                                LinearGradient(colors: [Color.brand.opacity(0.2), .white.opacity(0.06)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 0.8))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showCustomTimePicker)

                                // Restliche Zeit-Chips
                                let timeOptions = ["In 30 Min", "In 1 Std"]
                                ForEach(timeOptions, id: \.self) { t in
                                    let isActive = scheduledTime == t && !showCustomTimePicker
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        scheduledTime = t
                                        showCustomTimePicker = false
                                    }) {
                                        Text(t)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(isActive ? .white : .textPrimary)
                                            .padding(.horizontal, 14).padding(.vertical, 9)
                                            .background {
                                                if isActive {
                                                    Capsule().fill(Color.brand)
                                                        .shadow(color: Color.brand.opacity(0.35), radius: 8, y: 3)
                                                } else {
                                                    ZStack {
                                                        Capsule().fill(.thinMaterial)
                                                        Capsule().fill(Color.brand.opacity(0.04))
                                                    }
                                                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                                                    .overlay(Capsule().stroke(
                                                        LinearGradient(colors: [Color.brand.opacity(0.2), .white.opacity(0.06)],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                                        lineWidth: 0.8))
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }

                        // Compact time picker row
                        if showCustomTimePicker {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("Uhrzeit")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: $customDate,
                                    in: Date()...,
                                    displayedComponents: [.hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.brand)
                                .onChange(of: customDate) { _, _ in
                                    let f = DateFormatter()
                                    f.dateFormat = "HH:mm 'Uhr'"
                                    scheduledTime = f.string(from: customDate)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // ── Dauer ──────────────────────────────────────────────
                    createSection(label: "Dauer") {
                        let durationOptions: [(String, Int)] = [
                            ("30 Min", 30), ("1 Std", 60), ("2 Std", 120),
                            ("4 Std", 240), ("Kein Limit", 0)
                        ]
                        HStack(spacing: 6) {
                            ForEach(durationOptions, id: \.1) { label, value in
                                let isActive = durationMinutes == value
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    durationMinutes = value
                                } label: {
                                    Text(label)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(isActive ? .white : .textPrimary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background {
                                            if isActive {
                                                Capsule().fill(Color.brand)
                                                    .shadow(color: Color.brand.opacity(0.35), radius: 8, y: 3)
                                            } else {
                                                ZStack {
                                                    Capsule().fill(.thinMaterial)
                                                    Capsule().fill(Color.brand.opacity(0.04))
                                                }
                                                .overlay(Capsule().stroke(
                                                    LinearGradient(colors: [Color.brand.opacity(0.2), .white.opacity(0.06)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                                    lineWidth: 0.8))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)

                        if durationMinutes > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle").font(.system(size: 11))
                                Text("Endet nach \(durationMinutes < 60 ? "\(durationMinutes) Min" : "\(durationMinutes / 60) Std") · jederzeit verlängerbar")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                            .transition(.opacity)
                        }
                    }

                    // ── Max. Teilnehmer ────────────────────────────────────
                    createSection(label: "Max. Teilnehmer") {
                        VStack(spacing: 2) {
                            HStack {
                                Text("\(maxParticipants)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text("Personen")
                                    .font(.system(size: 13)).foregroundColor(.textSecondary.opacity(0.85))
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.top, 12)

                            Slider(
                                value: Binding(
                                    get: { Double(maxParticipants) },
                                    set: { v in
                                        let new = Int(v.rounded())
                                        if new != maxParticipants {
                                            maxParticipants = new
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                    }
                                ),
                                in: 2...15, step: 1
                            )
                            .tint(Color.brand)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                        .animation(.spring(response: 0.25), value: maxParticipants)
                    }

                    // ── Ort ────────────────────────────────────────────────
                    createSection(label: "Ort") {
                        let locStatus = CLLocationManager().authorizationStatus
                        let locationAllowed = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways

                        if locationAllowed {
                            locationOptionRow(
                                icon: "location.fill",
                                title: "Aktueller Standort",
                                subtitle: "Dein jetziger Standort",
                                isSelected: selectedLocationType == .current
                            ) {
                                selectedLocationType = .current
                                searchVM.searchText = ""
                            }
                            Divider().padding(.leading, 60)
                        }

                        locationOptionRow(
                            icon: "magnifyingglass",
                            title: "Ort suchen",
                            subtitle: selectedLocationResult?.title ?? "Restaurant, Bar, Café…",
                            isSelected: selectedLocationType == .searched
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedLocationType = .searched
                            }
                        }

                        // Inline-Suche klappt auf wenn "Ort suchen" aktiv
                        if selectedLocationType == .searched {
                            VStack(spacing: 0) {
                                Divider().padding(.leading, 16)
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.brand)
                                    TextField("Café, Bar, Park, Adresse…", text: $searchVM.searchText)
                                        .font(.system(size: 14))
                                        .foregroundColor(.textPrimary)
                                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                                        .submitLabel(.search)
                                    if !searchVM.searchText.isEmpty {
                                        Button { searchVM.searchText = "" } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.textTertiary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)

                                if !searchVM.results.isEmpty {
                                    Divider()
                                    ForEach(Array(searchVM.results.prefix(5).enumerated()), id: \.element.title) { idx, result in
                                        Button(action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            searchVM.selectResult(result) { loc in
                                                if let loc = loc {
                                                    selectedLocationResult = loc
                                                    searchVM.searchText = loc.title
                                                    searchVM.results = []
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.brand)
                                                    .frame(width: 28)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.title)
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.textPrimary)
                                                    if !result.subtitle.isEmpty {
                                                        Text(result.subtitle)
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 11)
                                        }
                                        .buttonStyle(.plain)
                                        if idx < min(searchVM.results.count, 5) - 1 {
                                            Divider().padding(.leading, 56)
                                        }
                                    }
                                } else if searchVM.searchText.isEmpty && selectedLocationResult == nil {
                                    HStack(spacing: 8) {
                                        Image(systemName: "text.magnifyingglass")
                                            .foregroundColor(.textTertiary)
                                        Text("Tippe um einen Ort zu suchen")
                                            .font(.system(size: 13))
                                            .foregroundColor(.textTertiary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Divider().padding(.leading, 60)

                        locationOptionRow(
                            icon: "mappin",
                            title: "Pin setzen",
                            subtitle: pinnedCoordinate != nil ? "Pin gesetzt ✓" : "Manuell auf der Karte",
                            isSelected: selectedLocationType == .pin
                        ) { selectedLocationType = .pin; showPinMap = true }
                    }

                    // ── Drops+ Upsell (nur für Free-User, vor CTA) ──────────
                    // Aus für den Launch (FeatureFlags.dropsPlusEnabled).
                    if FeatureFlags.dropsPlusEnabled && !store.isDropsPlusActive && !created {
                        plusReachUpsell
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    // ── CTA ────────────────────────────────────────────────
                    if created {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.onlineGreen)
                            Text("Drop ist live! Freunde in der Nähe werden benachrichtigt.")
                                .font(.system(size: 14, weight: .medium)).foregroundColor(.onlineGreen)
                        }
                        .padding(14).frame(maxWidth: .infinity)
                        .liquidGlass(cornerRadius: 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.onlineGreen.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 16)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Validierung: Aktivitätsname + München-Grenze
                        let isValid = !activityName.trimmingCharacters(in: .whitespaces).isEmpty
                        let dropCoordPreview: CLLocationCoordinate2D = {
                            switch selectedLocationType {
                            case .current:  return store.currentUser.coordinate
                            case .searched: return selectedLocationResult?.coordinate ?? store.currentUser.coordinate
                            case .pin:      return pinnedCoordinate ?? store.currentUser.coordinate
                            }
                        }()
                        // Drop-Erstellen-Gate: Drop-Koordinate muss in einer
                        // der 5 Launch-Städte liegen (Berlin, Hamburg, München,
                        // Köln, Frankfurt). Bei deaktiviertem Gate ist alles
                        // erlaubt.
                        let isInServiceArea = !BetaConfig.cityRestrictionEnabled
                            || ServiceCities.isInside(dropCoordPreview)
                        AuroraDropButton(isLoading: isCreating, isEnabled: isValid && isInServiceArea) {
                            guard isValid && isInServiceArea else { return }
                            // Heimzone-Warnung: wenn der Drop in der Heimzone des
                            // Users liegt, zeigen wir vorher einen Privacy-Hinweis.
                            if store.isInHomeZone(dropCoordPreview) {
                                pendingHomeZoneCoord = dropCoordPreview
                            } else {
                                performCreate(coord: dropCoordPreview)
                            }
                        }
                        .padding(.horizontal, 16)
                        if !isValid {
                            Text("Gib zuerst an, was ihr macht.")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        } else if !isInServiceArea {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 11))
                                Text("Drops nur in Berlin, Hamburg, München, Köln oder Frankfurt.")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(Color(hex: "f59e0b"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 20)
                }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(selected: selectedEmoji) { emoji in
                selectedEmoji = emoji
                emojiLockedByUser = true
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.hidden)
            .sheetBackground()
        }
        // Custom Heimzone-Warn-Sheet (statt System-Alert) — bietet wärmere
        // Optik, klare Hinweise und einen "Anderen Ort wählen"-Primärbutton
        // damit die sichere Wahl die offensichtliche bleibt.
        .sheet(isPresented: Binding(
            get: { pendingHomeZoneCoord != nil },
            set: { if !$0 { pendingHomeZoneCoord = nil } }
        )) {
            HomeZoneWarningSheet(
                onProceed: {
                    if let coord = pendingHomeZoneCoord {
                        pendingHomeZoneCoord = nil
                        performCreate(coord: coord)
                    }
                },
                onCancel: {
                    pendingHomeZoneCoord = nil
                }
            )
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.visible)
            .sheetBackground()
        }
        .fullScreenCover(isPresented: $showPinMap) {
            ZStack(alignment: .bottom) {
                InteractivePinMapView(pinnedCoordinate: $pinnedCoordinate, initialCenter: pinnedCoordinate ?? store.currentUser.coordinate)
                VStack(spacing: 10) {
                    PrimaryButton(title: pinnedCoordinate != nil ? "Pin bestätigen ✓" : "Tippe auf die Karte") {
                        if pinnedCoordinate != nil { showPinMap = false }
                    }
                    .disabled(pinnedCoordinate == nil)
                    .opacity(pinnedCoordinate != nil ? 1 : 0.45)
                }
                .padding(20)
            }
            .overlay(alignment: .topLeading) {
                Button(action: { showPinMap = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textSecondary)
                        .padding(20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                sheetPulse = true
            }
        }
    }

    // MARK: - Section Container

    @ViewBuilder
    private func createSection<Content: View>(label: String, aurora: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: 16)
                .overlay {
                    if aurora {
                        AuroraCardBorder(cornerRadius: 16)
                    }
                }
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func locationOptionRow(icon: String, title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.brand.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(isSelected ? .brand : .textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.textSecondary)
                }
                Spacer()
                // Radio-Button Indikator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.brand : Color.primary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 11, height: 11)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(isSelected ? Color.brand.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
    }

    // MARK: - Drops+ Reichweite-Upsell (nur Free-User)

    /// Subtile Gold-Karte direkt vor dem „Drop erstellen"-Button.
    /// Öffnet die Paywall beim Tap. Zeigt konkreten Nutzen (Boost + Priority Listing)
    /// statt einer generischen „Pro"-Werbung.
    private var plusReachUpsell: some View {
        Button {
            store.showDropsPlusPaywall = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "f59e0b").opacity(0.35), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mehr Leute erreichen mit Drops+")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Boost auf der Karte · größerer Suchradius · sieh wer geschaut hat")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "f59e0b"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "f59e0b").opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "f59e0b").opacity(0.55), Color(hex: "f59e0b").opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Helper

    private func performCreate(coord: CLLocationCoordinate2D) {
        isCreating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let loc = DropLocation(
                title: locationSubtitle, subtitle: "München",
                coordinate: coord, type: selectedLocationType
            )
            let name = activityName.trimmingCharacters(in: .whitespaces).isEmpty ? "Drop" : activityName.trimmingCharacters(in: .whitespaces)
            // Reihenfolge: 1) explizite User-Auswahl, 2) erster Auto-Match,
            // 3) ✨-Fallback damit der Drop-Pin auf der Karte nie leer ist.
            let emoji: String
            if !displayEmoji.isEmpty {
                emoji = displayEmoji
            } else if let auto = suggestedEmojis.first {
                emoji = auto
            } else {
                emoji = "✨"
            }
            let finalActivity = Activity(id: UUID(), name: name, emoji: emoji)
            store.createDrop(activity: finalActivity, location: loc,
                             description: dropDescription, scheduledTime: scheduledTime,
                             maxParticipants: maxParticipants,
                             durationMinutes: durationMinutes)
            isCreating = false
            withAnimation(.spring()) { created = true }
            // Kurz die Erfolgsmeldung zeigen, dann zum Aktiv-Tab wechseln
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
                store.selectedTab = .create   // .create ist der Aktiv-Tab
            }
        }
    }
}

struct DropLocationRow: View {
    let icon: String; let title: String; let subtitle: String
    var isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            DropLocationRowContent(icon: icon, title: title, subtitle: subtitle, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

struct DropLocationRowContent: View {
    let icon: String; let title: String; let subtitle: String; var isSelected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundColor(isSelected ? .brand : .textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brand)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.brand.opacity(0.5) : Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DropLocationSearchSheet: View {
    @ObservedObject var searchVM: LocationSearchViewModel
    let onSelect: (DropLocationResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color(UIColor.systemGray4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12).padding(.bottom, 16)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                    TextField("Café, Bar, Park…", text: $searchVM.searchText)
                        .font(.system(size: 16)).foregroundColor(.textPrimary)
                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                    if !searchVM.searchText.isEmpty {
                        Button(action: { searchVM.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(searchVM.results, id: \.title) { result in
                            Button(action: {
                                searchVM.selectResult(result) { loc in
                                    if let loc = loc { onSelect(loc) }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 20)).foregroundColor(.brand)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        Text(result.subtitle)
                                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
        }
        .presentationDetents([.fraction(0.75)])
        .sheetBackground()
    }
}

struct InteractivePinMapView: View {
    @Binding var pinnedCoordinate: CLLocationCoordinate2D?
    var initialCenter: CLLocationCoordinate2D? = nil
    @State private var region: MKCoordinateRegion
    @AppStorage("appLanguage") private var appLanguage = "de"

    init(pinnedCoordinate: Binding<CLLocationCoordinate2D?>, initialCenter: CLLocationCoordinate2D? = nil) {
        self._pinnedCoordinate = pinnedCoordinate
        let center = initialCenter ?? CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575)
        self._region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))
    }

    var body: some View {
        ZStack {
            InteractivePinMap(region: $region, coordinate: $pinnedCoordinate)
                .ignoresSafeArea()
            if pinnedCoordinate == nil {
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 28))
                        .foregroundColor(.textPrimary)
                    Text("Tippe auf die Karte")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
    }
}

struct InteractivePinMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var coordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(region, animated: false)
        map.showsUserLocation = true
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        if let coord = coordinate {
            let ann = MKPointAnnotation()
            ann.coordinate = coord
            map.addAnnotation(ann)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractivePinMap
        init(_ parent: InteractivePinMap) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coord = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                parent.coordinate = coord
            }
            map.setCenter(coord, animated: true)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.markerTintColor = .black
            view.animatesWhenAdded = true
            return view
        }
    }
}

// MARK: - Quick Drop Templates

/// One-Tap-Vorlagen für häufige Aktivitäten — füllen Name + Emoji direkt aus.
/// Erspart Tippen für die Standard-Cases (Kaffee, Spaziergang, Sport).
struct DropTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let emoji: String
}

extension DropTemplate {
    /// Statische Default-Vorlagen falls weder Past-Drops noch Interests etwas
    /// Brauchbares ergeben (Erst-User ohne Interests).
    static let universalDefaults: [DropTemplate] = [
        DropTemplate(name: "Kaffee", emoji: "☕️"),
        DropTemplate(name: "Spaziergang", emoji: "🚶"),
        DropTemplate(name: "Bier", emoji: "🍻"),
    ]

    /// Mapping von Onboarding-Interest-Keys auf Drop-Vorlagen.
    static func fromInterest(_ key: String) -> DropTemplate? {
        switch key {
        case "interest.coffee":   return DropTemplate(name: "Kaffee", emoji: "☕️")
        case "interest.food":     return DropTemplate(name: "Essen gehen", emoji: "🍽")
        case "interest.sport":    return DropTemplate(name: "Sport", emoji: "🏃")
        case "interest.music":    return DropTemplate(name: "Konzert", emoji: "🎵")
        case "interest.cinema":   return DropTemplate(name: "Kino", emoji: "🎬")
        case "interest.gaming":   return DropTemplate(name: "Gaming", emoji: "🎮")
        case "interest.shopping": return DropTemplate(name: "Bummeln", emoji: "🛍")
        case "interest.outdoor":  return DropTemplate(name: "Park-Hangout", emoji: "🌳")
        case "interest.party":    return DropTemplate(name: "Bier", emoji: "🍻")
        case "interest.photo":    return DropTemplate(name: "Foto-Walk", emoji: "📸")
        case "interest.cooking":  return DropTemplate(name: "Brunch", emoji: "🥐")
        case "interest.travel":   return nil   // Reise passt nicht als Spontan-Drop
        default: return nil
        }
    }
}

struct DropQuickTemplatesBar: View {
    @EnvironmentObject var store: AppStore
    var onSelect: (DropTemplate) -> Void

    /// Vorlagen-Pipeline:
    /// 1. Letzte 4 unterschiedliche Aktivitäten aus pastDrops (frisch zuerst)
    /// 2. Auffüllen mit Interest-Mappings (max. 8 gesamt)
    /// 3. Universal-Defaults nur wenn Liste sonst leer
    private var templates: [DropTemplate] {
        var list: [DropTemplate] = []
        var seen: Set<String> = []
        let key = { (t: DropTemplate) in "\(t.emoji)|\(t.name.lowercased())" }

        // 1. Past Drops (neueste zuerst, deduped)
        for drop in store.pastDrops.reversed() {
            let tpl = DropTemplate(name: drop.activityName, emoji: drop.activityEmoji)
            let k = key(tpl)
            if seen.contains(k) { continue }
            seen.insert(k)
            list.append(tpl)
            if list.count >= 4 { break }
        }

        // 2. Interest-Mappings auffüllen
        for interest in store.userInterests {
            guard let tpl = DropTemplate.fromInterest(interest) else { continue }
            let k = key(tpl)
            if seen.contains(k) { continue }
            seen.insert(k)
            list.append(tpl)
            if list.count >= 8 { break }
        }

        // 3. Fallback wenn weder Past-Drops noch Interests
        if list.isEmpty { return DropTemplate.universalDefaults }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.pastDrops.isEmpty ? "Für dich" : "Vorlagen")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { tpl in
                        Button { onSelect(tpl) } label: {
                            HStack(spacing: 6) {
                                Text(tpl.emoji).font(.system(size: 16))
                                Text(tpl.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            // Brand-getöntes Glass — gleiche Optik wie die
                            // anderen Sektions-Container in CreateDropView,
                            // damit sich die Pillen nicht visuell vom Rest
                            // abheben.
                            .background(
                                ZStack {
                                    Capsule().fill(.ultraThinMaterial)
                                    Capsule().fill(Color.brand.opacity(0.10))
                                }
                            )
                            .overlay(
                                Capsule().stroke(
                                    LinearGradient(
                                        colors: [Color.brand.opacity(0.45), Color.brand.opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: Color.brand.opacity(0.18), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)   // Damit der Glass-Shadow nicht abgeschnitten wird
            }
        }
    }
}
