import SwiftUI

// MARK: - Profile Image Cache

final class ProfileImageCache {
    static let shared = ProfileImageCache()
    private var cache: [String: UIImage] = [:]
    private let lock = NSLock()

    func get(_ url: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }
    func set(_ url: String, image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        cache[url] = image
    }
    /// Komplett leeren — wird beim Logout/Account-Löschen aufgerufen,
    /// damit altes Profilbild nicht beim Re-Login wieder auftaucht.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - Remote Profile Image View

struct RemoteProfileImage: View {
    let url: String?
    let fallbackEmoji: String
    let size: CGFloat
    var strokeColor: Color = Color.white.opacity(0.25)

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(Text(fallbackEmoji).font(.system(size: size * 0.48)))
                    .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
            }
        }
        .onAppear { loadImage() }
        .onChange(of: url) { _ in loadImage() }
    }

    private func loadImage() {
        guard let urlString = url, let remoteURL = URL(string: urlString) else { return }
        if let cached = ProfileImageCache.shared.get(urlString) {
            image = cached; return
        }
        URLSession.shared.dataTask(with: remoteURL) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ProfileImageCache.shared.set(urlString, image: img)
            DispatchQueue.main.async { image = img }
        }.resume()
    }
}

// MARK: – Gemeinsamer Aurora-Hintergrund (Login, Welcome, Registrierung)

struct AppAuroraBackground: View {
    var isLight: Bool? = nil          // nil → folgt System-ColorScheme
    @Environment(\.colorScheme) var cs
    @State private var a = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    private var light: Bool { isLight ?? (cs == .light) }

    /// Drop-Pulse: jeder Aurora-Kreis leuchtet nacheinander stärker auf
    /// (wie ein "Drop", der durch die Farben rippt). Voller Loop in 10s,
    /// also 2s pro Kreis. Boost = +60% Opacity am Peak, glättet sich mit
    /// sin-Kurve aus.
    private static let pulseCycle: Double = 10.0
    private static let circleCount: Int = 5
    private static let pulseBoost: Double = 0.6   // 0=aus, 1=verdoppelt

    /// Berechnet 0..1 wie stark Kreis `i` gerade gepulst ist.
    /// Spitze bei `(i + 0.5) * stepDuration`, sin²-Glättung.
    private static func pulse(forCircle i: Int, at elapsed: Double) -> Double {
        let step = pulseCycle / Double(circleCount)
        let phase = elapsed.truncatingRemainder(dividingBy: pulseCycle)
        let center = (Double(i) + 0.5) * step
        // Distanz zum Peak (mit Wrap-around damit der letzte Kreis am
        // Ende+Anfang nicht abrupt cuttet)
        var dist = abs(phase - center)
        if dist > pulseCycle / 2 { dist = pulseCycle - dist }
        let halfWidth = step * 0.85
        if dist > halfWidth { return 0 }
        // sin² → smooth peak, klingt sauber an den Rändern aus
        let t = (1 - dist / halfWidth)  // 1 am Peak, 0 am Rand
        return sin(.pi * 0.5 * t) * sin(.pi * 0.5 * t)
    }

    var body: some View {
        ZStack {
            // Basisfarbe füllt den gesamten Bildschirm inkl. Safe Areas
            (light ? Color(hex: "f5f7fe") : Color(hex: "0d0f14"))
                .ignoresSafeArea()

            // Aurora-Kreise: GeometryReader mit ignoresSafeArea liest den
            // vollen Bildschirm. Die Kreise werden exakt am Bildschirm-
            // Mittelpunkt verankert. .clipped() verhindert Overflow.
            GeometryReader { _ in
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    // Per-Kreis Pulse-Intensität 0..1 berechnen
                    let p0 = Self.pulse(forCircle: 0, at: elapsed)
                    let p1 = Self.pulse(forCircle: 1, at: elapsed)
                    let p2 = Self.pulse(forCircle: 2, at: elapsed)
                    let p3 = Self.pulse(forCircle: 3, at: elapsed)
                    let p4 = Self.pulse(forCircle: 4, at: elapsed)

                    ZStack {
                        // Kreis 1 — grün (top-left)
                        Circle()
                            .fill(Color(hex: "34D36E").opacity((light ? 0.78 : 0.62) * (1 + Self.pulseBoost * p0)))
                            .frame(width: 520 * (1 + 0.06 * p0))
                            .offset(x: a ? -130 : -80, y: a ? -370 : -320)
                            .blur(radius: 90)
                        // Kreis 2 — violet (top-right)
                        Circle()
                            .fill(Color(hex: "A78BFA").opacity((light ? 0.68 : 0.54) * (1 + Self.pulseBoost * p1)))
                            .frame(width: 460 * (1 + 0.06 * p1))
                            .offset(x: a ? 160 : 110, y: a ? -350 : -300)
                            .blur(radius: 85)
                        // Kreis 3 — teal (bottom-left)
                        Circle()
                            .fill(Color(hex: "2DD4BF").opacity((light ? 0.58 : 0.46) * (1 + Self.pulseBoost * p2)))
                            .frame(width: 420 * (1 + 0.06 * p2))
                            .offset(x: a ? -150 : -100, y: a ? 420 : 370)
                            .blur(radius: 80)
                        // Kreis 4 — amber (bottom-right)
                        Circle()
                            .fill(Color(hex: "FBBF24").opacity((light ? 0.52 : 0.42) * (1 + Self.pulseBoost * p3)))
                            .frame(width: 380 * (1 + 0.06 * p3))
                            .offset(x: a ? 140 : 90, y: a ? 400 : 350)
                            .blur(radius: 75)
                        // Kreis 5 — grün (center)
                        Circle()
                            .fill(Color(hex: "34D36E").opacity((light ? 0.42 : 0.30) * (1 + Self.pulseBoost * p4)))
                            .frame(width: 260 * (1 + 0.06 * p4))
                            .offset(x: a ? 20 : -20, y: a ? 40 : 80)
                            .blur(radius: 60)
                    }
                    .frame(
                        width: UIScreen.main.bounds.width,
                        height: UIScreen.main.bounds.height
                    )
                    .position(
                        x: UIScreen.main.bounds.width / 2,
                        y: UIScreen.main.bounds.height / 2
                    )
                    .clipped()
                }
            }
            .ignoresSafeArea() // GeometryReader bekommt vollen Bildschirm, NICHT nur Safe-Area
        }
        // Kein .ignoresSafeArea() auf dem äußeren ZStack — Layout-Rahmen für
        // Inhalte in Parent-ZStacks bleibt korrekt
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { a = true }
        }
    }
}

// MARK: - Empty State: Keine Drops in der Nähe

struct DropsEmptyState: View {
    @State private var pulse0 = false
    @State private var pulse1 = false
    @State private var pulse2 = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.brand.opacity(0.12), lineWidth: 1)
                    .frame(width: 116, height: 116)
                    .scaleEffect(pulse0 ? 1.06 : 0.96)
                Circle()
                    .stroke(Color.brand.opacity(0.08), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse1 ? 1.05 : 0.97)
                Circle()
                    .stroke(Color.brand.opacity(0.05), lineWidth: 1)
                    .frame(width: 204, height: 204)
                    .scaleEffect(pulse2 ? 1.04 : 0.97)
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(Color.brand)
                }
            }
            .frame(width: 180, height: 180)

            VStack(spacing: 6) {
                Text("Keine Drops in der Nähe")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Sei der Erste und erstell einen Drop –\noder erweitere deinen Radius in den Einstellungen.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse0 = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(0.3)) {
                pulse1 = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.6)) {
                pulse2 = true
            }
        }
    }
}

// MARK: - Empty State: Noch keine Freunde

struct FreundeEmptyState: View {
    @State private var pulse0 = false
    @State private var pulse1 = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(UIColor.systemPurple).opacity(0.12), lineWidth: 1)
                    .frame(width: 116, height: 116)
                    .scaleEffect(pulse0 ? 1.06 : 0.96)
                Circle()
                    .stroke(Color(UIColor.systemPurple).opacity(0.07), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse1 ? 1.05 : 0.97)
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemPurple).opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(Color(UIColor.systemPurple))
                }
            }
            .frame(width: 180, height: 160)

            VStack(spacing: 6) {
                Text("Noch keine Freunde")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Triff jemanden bei einem Drop und bestätige die Begegnung – so entstehen Verbindungen.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse0 = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.4)) {
                pulse1 = true
            }
        }
    }
}

// MARK: - Drop teilen (ShareSheet)

struct DropShareButton: View {
    let item: MapAnnotationItem
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Button {
            shareDrops()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func shareDrops() {
        let deepLink = "https://drops-app.de/drop/\(item.id.uuidString)"
        let text = "\(item.emoji) \(item.activity) – \(item.name) teilt gerade einen Drop auf Drops."
        let items: [Any] = [text, URL(string: deepLink) ?? deepLink]

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.excludedActivityTypes = [.assignToContact, .saveToCameraRoll, .print]

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
}


// MARK: - Emoji Picker Sheet

struct EmojiPickerSheet: View {
    let selected: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    // Kategorien: Personen, Tiere, Gesichter/Natur, Essen, Aktivitäten, Objekte
    private let categories: [(name: String, icon: String, emojis: [String])] = [
        ("Personen", "person.fill", [
            "😊","😎","🤩","😇","🥳","🤓","🧐","😏","😌","🥰",
            "😂","🤣","😆","😄","😁","😋","🤤","🤗","🫡","🤭",
            "😤","😅","🤠","🥸","🫠","🤑","😈","👾","🤖","👻",
            "🧑","👦","👧","👨","👩","🧔","👱","🧕","👮","🕵️"
            
        ]),
        ("Tiere", "pawprint.fill", [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯",
            "🦁","🐮","🐷","🐸","🐵","🐔","🐧","🐦","🦅","🦉",
            "🦋","🐢","🦎","🐍","🐬","🐳","🦈","🦑","🐙","🦔",
            "🦄","🐲","🦖","🦕","🦩","🦚","🦜","🐺","🦝","🦛"
        ]),
        ("Natur", "leaf.fill", [
            "🌸","🌺","🌻","🌹","🌷","🌼","💐","🍀","🌿","🌱",
            "🌲","🌴","🌵","🎋","🍁","🍂","🍃","⭐️","🌟","✨",
            "🔥","💧","🌊","❄️","⚡️","🌈","☀️","🌙","🌍","🪐"
        ]),
        ("Essen", "fork.knife", [
            "🍕","🍔","🌮","🌯","🍜","🍣","🍩","🍪","🎂","🍰",
            "🍦","🧃","🥤","☕️","🍺","🍷","🧋","🍭","🍫","🍿",
            "🥑","🍓","🍇","🍉","🍋","🥦","🧀","🥚","🥐","🍞"
        ]),
        ("Sport", "figure.run", [
            "⚽️","🏀","🏈","⚾️","🎾","🏐","🎱","🏓","🏸","🥊",
            "🎿","🏂","🏄","🚴","🧗","🤸","⛹️","🏋️","🤼","🥋",
            "🎯","🎳","🎮","🕹️","🎲","♟️","🎭","🎨","🎵","🎸"
        ]),
        ("Objekte", "star.fill", [
            "🚀","🛸","🏆","🥇","🎖️","👑","💎","🔮","🎁","🎀",
            "📱","💻","🎧","📷","🎤","🎬","🔑","💡","🧲","⚙️",
            "🛡️","⚔️","🪄","🎩","🕶️","💼","🧳","🌂","🪬","🔭"
        ])
    ]

    @State private var selectedCategory = 0
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)

            // Titel
            HStack {
                Text("Dein Emoji")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                // Vorschau
                Text(selected)
                    .font(.system(size: 28))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Kategorien-Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { i, cat in
                        Button {
                            withAnimation(.spring(response: 0.25)) { selectedCategory = i }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(cat.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(selectedCategory == i ? .white : .textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                selectedCategory == i
                                    ? Color.brand
                                    : Color(UIColor.systemGray5),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)

            // Emoji-Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(categories[selectedCategory].emojis, id: \.self) { emoji in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(emoji)
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background(
                                    emoji == selected
                                        ? Color.brand.opacity(0.18)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(
                                    emoji == selected
                                        ? RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.brand.opacity(0.5), lineWidth: 1.5)
                                        : nil
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }
}
