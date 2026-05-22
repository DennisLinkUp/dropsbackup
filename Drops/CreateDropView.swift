import SwiftUI
import MapKit
import CoreLocation
import TipKit

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

    /// Falls aus dem Community-Dashboard geöffnet — markiert den entstehenden
    /// Drop als Community-Drop und triggert automatischen Push an Mitglieder.
    var communityID: String? = nil
    /// Pre-Fill für die Aktivität (Name + Emoji). Wird vom Community-Dashboard
    /// gesetzt, damit der Tennis-Creator nicht jedes Mal Tennis selber tippen muss.
    var prefilledActivityName: String? = nil
    var prefilledActivityEmoji: String? = nil
    /// Max-Teilnehmer-Cap. Default 15 für normale Drops; Community-Drops
    /// können auf 100 hochgesetzt werden (z.B. Laufgruppen).
    var maxParticipantsLimit: Int = 15
    /// Wenn true: First-Drop-Coach-Overlay wird angezeigt (kommt vom WelcomeSheet-CTA).
    var isWalkthrough: Bool = false

    // ── First-Drop Coach-Mark Overlay ──────────────────────────────────────
    @State private var coachStep: CoachStep? = nil
    @State private var coachHighlightFrame: CGRect = .zero
    @AppStorage("hasCompletedFirstDropWalkthrough") private var walkthroughDone = false

    // Coach-Mark Tips — TipKit zeigt jeden genau einmal (MaxDisplayCount 1),
    // danach werden sie automatisch als gesehen markiert.
    @State private var activityTip = ActivityTip()
    @State private var timeTip    = TimeTip()
    @State private var startTip   = StartDropTip()

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
        case .current:  return tr("create.current_location")
        case .searched: return selectedLocationResult?.title ?? tr("create.search_place")
        case .pin:      return pinnedCoordinate != nil ? tr("create.pin_set") : tr("create.tap_on_map_caps")
        }
    }

    var body: some View {
        let isCommunityDrop = communityID != nil
        return ZStack {
            // Vollflächiger App-Hintergrund — bei Community-Drop in Clero-Grün-Tint,
            // sonst der normale Aurora-Background.
            if isCommunityDrop {
                LinearGradient(
                    colors: [
                        Color.cleroGreen.opacity(0.35),
                        Color.cleroGreen.opacity(0.18),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                AppAuroraBackground().ignoresSafeArea()
            }

            // Aurora-Akzent — bei Community-Drop in Clero-Grün, sonst Sunset-Orange.
            ZStack {
                Circle()
                    .fill((isCommunityDrop ? Color.cleroGreen : Color.auroraOrange).opacity(0.24))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: sheetPulse ? 40 : -30, y: sheetPulse ? -70 : 10)
                Circle()
                    .fill((isCommunityDrop ? Color.brand : Color.auroraPink).opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: sheetPulse ? -60 : 35, y: sheetPulse ? 10 : -50)
                Circle()
                    .fill((isCommunityDrop ? Color.cleroGreen : Color.auroraViolet).opacity(0.14))
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
                    Text(isCommunityDrop ? tr("create.community_drop") : tr("create.drop"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer()
                    Button {
                        Haptic.selection()
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

                ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                    // ── Quick-Templates: dynamisch aus Interests + Past Drops
                    if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                        DropQuickTemplatesBar { tpl in
                            activityName = tpl.name
                            selectedEmoji = tpl.emoji
                            emojiLockedByUser = true
                            Haptic.selection()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }

                    // ── Aktivität ──────────────────────────────────────────
                    createSection(label: tr("create.what_section"), aurora: true) {
                        // TipKit nur zeigen wenn kein Walkthrough aktiv
                        if !isWalkthrough {
                            TipView(activityTip, arrowEdge: .top)
                                .tipBackground(.ultraThinMaterial)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                        }
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

                            TextField(tr("create.activity_field_placeholder"), text: $activityName)
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
                                                    .background(isActive ? Color.brand.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.md))
                                                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
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
                                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.md))
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
                                        Text(tr("create.pick_emoji"))
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
                    .id(CoachStep.activity.scrollID)
                    .coachHighlight(active: coachStep == .activity)

                    // ── Wann ──────────────────────────────────────────────
                    createSection(label: tr("create.when_section")) {
                        if !isWalkthrough {
                            TipView(timeTip, arrowEdge: .top)
                                .tipBackground(.ultraThinMaterial)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                        }
                        // Quick-Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "Jetzt"-Chip
                                let nowLabel = "Jetzt"
                                let isJetzt = scheduledTime == nowLabel && !showCustomTimePicker
                                Button(action: {
                                    Haptic.selection()
                                    scheduledTime = nowLabel
                                    showCustomTimePicker = false
                                }) {
                                    Text(tr("shared.now"))
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
                                    Haptic.selection()
                                    withAnimation(.spring(response: 0.3)) { showCustomTimePicker.toggle() }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock").font(.system(size: 12))
                                        Text(showCustomTimePicker
                                             ? customDate.formatted(date: .omitted, time: .shortened)
                                             : tr("create.time"))
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

                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }

                        // Compact time picker row
                        if showCustomTimePicker {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text(tr("create.time"))
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
                                    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
                                    f.dateFormat = lang == "de" ? "HH:mm 'Uhr'" : "h:mm a"
                                    scheduledTime = f.string(from: customDate)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // ── Dauer ──────────────────────────────────────────────
                    createSection(label: tr("create.duration_section")) {
                        let durationOptions: [(String, Int)] = [
                            (tr("create.dur_30min"), 30), (tr("create.dur_1h"), 60), (tr("create.dur_2h"), 120),
                            (tr("create.duration_4h"), 240), (tr("create.no_limit"), 0)
                        ]
                        HStack(spacing: 6) {
                            ForEach(durationOptions, id: \.1) { label, value in
                                let isActive = durationMinutes == value
                                Button {
                                    Haptic.selection()
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
                                Text(tr("create.ends_after").replacingOccurrences(of: "{duration}", with: durationMinutes < 60 ? tr("create.duration_min").replacingOccurrences(of: "{n}", with: "\(durationMinutes)") : tr("create.duration_hours").replacingOccurrences(of: "{n}", with: "\(durationMinutes / 60)")))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                            .transition(.opacity)
                        }
                    }

                    // ── Max. Teilnehmer ────────────────────────────────────
                    createSection(label: tr("create.max_section")) {
                        VStack(spacing: 2) {
                            HStack {
                                Text("\(maxParticipants)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text(tr("create.people"))
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
                                            Haptic.selection()
                                        }
                                    }
                                ),
                                in: 2...Double(maxParticipantsLimit), step: 1
                            )
                            .tint(Color.brand)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                        .animation(.spring(response: 0.25), value: maxParticipants)
                    }

                    // ── Ort ────────────────────────────────────────────────
                    createSection(label: tr("create.location_section")) {
                        let locStatus = CLLocationManager().authorizationStatus
                        let locationAllowed = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways

                        if locationAllowed {
                            locationOptionRow(
                                icon: "location.fill",
                                title: tr("create.current_location"),
                                subtitle: tr("create.current_location_subtitle"),
                                isSelected: selectedLocationType == .current
                            ) {
                                selectedLocationType = .current
                                searchVM.searchText = ""
                            }
                            Divider().padding(.leading, 60)
                        }

                        locationOptionRow(
                            icon: "magnifyingglass",
                            title: tr("create.search_place_title"),
                            subtitle: selectedLocationResult?.title ?? tr("create.search_place_subtitle"),
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
                                    TextField(tr("create.location_search_full"), text: $searchVM.searchText)
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
                                            Haptic.selection()
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
                                        Text(tr("create.tap_to_search"))
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
                            title: tr("create.set_pin"),
                            subtitle: pinnedCoordinate != nil ? tr("create.pin_set") : tr("create.set_pin_subtitle"),
                            isSelected: selectedLocationType == .pin
                        ) { selectedLocationType = .pin; showPinMap = true }
                    }
                    .id(CoachStep.location.scrollID)
                    .coachHighlight(active: coachStep == .location)

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
                            Text(tr("create.drop_live_msg"))
                                .font(.system(size: 14, weight: .medium)).foregroundColor(.onlineGreen)
                        }
                        .padding(14).frame(maxWidth: .infinity)
                        .liquidGlass(cornerRadius: 14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.onlineGreen.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 16)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Validierung: Aktivitätsname + München-Grenze
                        let locationSelected = selectedLocationType == .current
                            || (selectedLocationType == .searched && selectedLocationResult != nil)
                            || (selectedLocationType == .pin && pinnedCoordinate != nil)
                        let isValid = !activityName.trimmingCharacters(in: .whitespaces).isEmpty && locationSelected
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
                        // Coach-Mark Schritt 3: Drop starten
                        .popoverTip(startTip, arrowEdge: .bottom)
                        .id(CoachStep.start.scrollID)
                        .coachHighlight(active: coachStep == .start)
                        if !isValid {
                            Text(activityName.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? tr("create.enter_activity_first")
                                 : tr("create.select_location"))
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        } else if !isInServiceArea {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 11))
                                Text(tr("create.cities_only"))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(Color.auroraAmber)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 20)
                    // Walkthrough-Puffer: damit auch der CTA-Button (letztes Element)
                    // per scrollTo(anchor:.top) über die Coach-Karte gescrollt werden
                    // kann. Ohne diesen Spacer reicht der Scroll nicht weit genug.
                    if coachStep != nil {
                        Spacer().frame(height: 360)
                    }
                }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
                .scrollDisabled(coachStep != nil)
                // ── Coach-Scroll: beim Step-Wechsel zum Anker scrollen ──
                .onChange(of: coachStep) { _, newStep in
                    guard let newStep else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                            proxy.scrollTo(newStep.scrollID, anchor: .top)
                        }
                    }
                }
            } // ScrollViewReader
            } // VStack(spacing: 0)

            // ── First-Drop Coach-Mark Overlay ──────────────────────────────
            // Liegt im ZStack über dem gesamten Inhalt (inkl. Sticky-Header).
            if coachStep != nil {
                FirstDropCoachOverlay(
                    step: $coachStep,
                    highlightFrame: coachHighlightFrame,
                    scrollTo: { _ in }, // Scroll via onChange in ScrollViewReader
                    onDone: {
                        coachStep = nil
                        walkthroughDone = true
                    },
                    onSkip: {
                        coachStep = nil
                        walkthroughDone = true
                    }
                )
                .zIndex(100)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: coachStep == nil)
            }
        } // ZStack
        // Frame der aktiven Coach-Section einsammeln (kommt per Preference
        // aus CoachHighlightModifier via GeometryReader in global coordinates).
        .onPreferenceChange(CoachSpotlightFrameKey.self) { frame in
            coachHighlightFrame = frame
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
            // 0.78 statt 0.65 — auf SE/mini wurden sonst die Buttons
            // unten abgeschnitten. Der Inhalt ist jetzt zusätzlich
            // scrollbar (Footer fix), das ist die Belt-and-Suspenders-
            // Lösung für sehr kompakte Display Zoom-Modi.
            .presentationDetents([.fraction(0.78)])
            // Heimzone-Warnung darf nicht versehentlich weggewischt werden —
            // User soll bewusst „Anderen Ort" oder „Trotzdem erstellen"
            // wählen, sonst geht der Sicherheits-Check ins Leere.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        .fullScreenCover(isPresented: $showPinMap) {
            ZStack(alignment: .bottom) {
                InteractivePinMapView(pinnedCoordinate: $pinnedCoordinate, initialCenter: pinnedCoordinate ?? store.currentUser.coordinate)
                VStack(spacing: 10) {
                    PrimaryButton(title: pinnedCoordinate != nil ? tr("create.confirm_pin") : tr("create.tap_on_map")) {
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
            // First-Drop Walkthrough — kurze Verzögerung damit Sheet erst
            // vollständig eingefahren ist bevor die Coach-Karte erscheint.
            if isWalkthrough && !walkthroughDone {
                // TipKit-Tips unterdrücken: würden sich sonst mit dem
                // Coach-Overlay überlagern und verwirren.
                activityTip.invalidate(reason: .actionPerformed)
                timeTip.invalidate(reason: .actionPerformed)
                startTip.invalidate(reason: .actionPerformed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    coachStep = .activity
                }
            }
            // Pre-Fill aus Community-Kontext — Aktivität + Emoji + sinnvoller
            // Default für Teilnehmerzahl (Community-Drops sind oft Gruppen-Events).
            if let name = prefilledActivityName, activityName.isEmpty {
                activityName = name
            }
            if let emoji = prefilledActivityEmoji, selectedEmoji.isEmpty {
                selectedEmoji = emoji
                emojiLockedByUser = true   // verhindert dass das Auto-Pick es überschreibt
            }
            // Community-Drops bekommen 25 als Default (mehr als 10, weniger als max).
            if communityID != nil && maxParticipants == 10 {
                maxParticipants = min(25, maxParticipantsLimit)
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
                        AuroraCardBorder(cornerRadius: Radius.lg)
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
                    RoundedRectangle(cornerRadius: Radius.sm)
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
                                colors: [Color.auroraAmber.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraAmber, Color.auroraAmber],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("create.reach_more_plus"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(tr("create.plus_features"))
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.auroraAmber)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.auroraAmber.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.auroraAmber.opacity(0.55), Color.auroraAmber.opacity(0.15)],
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
        // Content-Filter: Beleidigungen, Slurs, Sexual-Solicitation und
        // Drohwörter blockieren den Drop bevor er überhaupt erstellt wird.
        // Whole-Word-Match auf normalisiertem Text (Leetspeak rückwärts) —
        // siehe ContentFilter.swift. Aktiviert für Drop-Name + Beschreibung.
        if let match = ContentFilter.firstMatch(
            activityName: activityName,
            description: dropDescription
        ) {
            store.showInfoToast(
                tr("create.blocked_words").replacingOccurrences(of: "{word}", with: match.word),
                icon: "exclamationmark.shield.fill"
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

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
                             durationMinutes: durationMinutes,
                             communityID: communityID)
            isCreating = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { created = true }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
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
                    TextField(tr("create.location_search_short"), text: $searchVM.searchText)
                        .font(.system(size: 16)).foregroundColor(.textPrimary)
                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                    if !searchVM.searchText.isEmpty {
                        Button(action: { searchVM.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.white.opacity(0.2), lineWidth: 1))
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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
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
                    Text(tr("create.tap_on_map"))
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

        // 2. Fallback wenn keine Past-Drops
        if list.isEmpty { return DropTemplate.universalDefaults }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section-Header — kräftiger uppercase-Cut mit Tracking,
            // stärkere Farbe. Vorher wirkten Header + Chips gemeinsam
            // „ausgegraut" auf dem Aurora-Background — beides sah aus
            // wie blasse Sektionslabels.
            Text(store.pastDrops.isEmpty ? tr("create.popular") : tr("create.templates"))
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { tpl in
                        Button { onSelect(tpl) } label: {
                            HStack(spacing: 6) {
                                Text(tpl.emoji).font(.system(size: 16))
                                Text(tpl.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            // Solides Brand-Gradient statt ultraThin/10%-Tönung —
                            // die alte Glass-Variante wirkte ausgegraut auf der
                            // Aurora. Jetzt klarer Tap-Affordance: vollfarbige
                            // Capsule mit Sunset-Gradient (passt zur App-Icon-
                            // Identity).
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.auroraOrange, Color.auroraGreen],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: Color.auroraOrange.opacity(0.30), radius: 8, y: 3)
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
