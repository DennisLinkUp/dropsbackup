import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCreateSheet = false
    @StateObject private var cityGate = CityGateChecker()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var showWelcomeSheet = false

    var body: some View {
        ZStack(alignment: .top) {
        TabView(selection: $store.selectedTab) {
            LiveMapView()
                .tabItem { Label(tr("tab.map"), systemImage: "map.fill") }
                .tag(AppStore.Tab.map)

            FeedView()
                .tabItem { Label(tr("tab.nearby"), systemImage: "person.2.wave.2.fill") }
                .tag(AppStore.Tab.feed)

            Group {
                if store.isInActiveDrop, let item = store.currentActiveAnnotation {
                    ActiveDropTabView(item: item)
                        .environmentObject(store)
                } else {
                    Color.clear
                }
            }
            .tabItem {
                if store.isInActiveDrop {
                    Label(tr("tab.active"), systemImage: "dot.radiowaves.left.and.right")
                } else {
                    Label("", systemImage: "plus.circle.fill")
                }
            }
            .tag(AppStore.Tab.create)

            FreundeView()
                .tabItem { Label(tr("tab.friends"), systemImage: "person.fill") }
                .tag(AppStore.Tab.alerts)

            ProfileView()
                .tabItem { Label(tr("tab.settings"), systemImage: "gearshape.fill") }
                .tag(AppStore.Tab.profile)
        }
        // iOS 26: tint statt accentColor für das neue Glass Tab Bar
        .tint(.brand)
        .onChange(of: store.selectedTab) { _, tab in
            if tab == .create && !store.isInActiveDrop {
                showCreateSheet = true
                store.selectedTab = .map
            }
        }
        .onChange(of: store.isInActiveDrop) { _, isActive in
            if !isActive && store.selectedTab == .create {
                store.selectedTab = .map
            }
        }
        .fullScreenCover(isPresented: $showCreateSheet) {
            CreateDropView()
                .environmentObject(store)
        }
        // Quick Actions — konsumiert pending-Shortcut vom Store.
        // Wird ausgelöst beim ersten onAppear (Cold-Start, nach Auth) +
        // sobald sich pendingQuickAction ändert (Background→Foreground).
        .onAppear {
            consumePendingQuickAction()
        }
        .onChange(of: store.pendingQuickAction) { _, _ in
            consumePendingQuickAction()
        }
        .fullScreenCover(isPresented: $store.showDropsPlusSuccess) {
            DropsPlusSuccessView()
                .environmentObject(store)
        }

        } // ZStack
        // ── Globaler Punkte-Toast ─────────────────────────────────────────
        // Liegt über der ganzen Tab-View, damit egal in welchem Tab Punkte
        // vergeben werden, der User die "+X Punkte"-Pille zentral oben
        // sieht. Die Pille selbst dismisst sich nach 2.5s; wir nullen den
        // Store-State im onDismiss-Callback.
        .overlay(alignment: .top) {
            if let toast = store.pointsToast {
                PointsToastView(toast: toast) {
                    store.pointsToast = nil
                }
                .id(toast.id)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8),
                   value: store.pointsToast?.id)
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        // Stadtsperre als Vollbild-Gate ist entfernt: User außerhalb der 5
        // Service-Städte können sich registrieren und die App nutzen, dürfen
        // aber keine Drops erstellen oder joinen (Guards in CreateDropView/AppStore).
        .fullScreenCover(isPresented: $store.needsCorePermissions) {
            PermissionGateView()
        }
        .onAppear {
            cityGate.startChecking()
            if !hasSeenWelcome {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showWelcomeSheet = true
                }
            }
        }
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeSheet {
                hasSeenWelcome = true
                showWelcomeSheet = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $store.showPushReaskSheet) {
            PushReaskSheet()
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $store.firstDropCelebrationKind) { kind in
            FirstDropCelebrationSheet(kind: kind)
        }
    }

    /// Routet ein pending Quick-Action vom Store — wird beim onAppear (Cold-
    /// Start nach Auth) und bei Änderung (Warm-Start) aufgerufen.
    private func consumePendingQuickAction() {
        guard let type = store.pendingQuickAction else { return }
        store.pendingQuickAction = nil
        print("🚦 [QA] MainTabView consumes: \(type)")
        switch type {
        case "com.dennis.drops.shortcut.create":
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCreateSheet = true
            }
        case "com.dennis.drops.shortcut.map":
            store.selectedTab = .map
        case "com.dennis.drops.shortcut.feed":
            store.selectedTab = .feed
        case "com.dennis.drops.shortcut.profile":
            store.selectedTab = .profile
        default:
            break
        }
    }
}

// MARK: - First Drop Celebration

/// Vollbild-Celebration mit Konfetti-Explosion vom Emoji-Punkt aus.
/// Läuft im fullScreenCover damit das Konfetti den ganzen Screen einnimmt.
struct FirstDropCelebrationSheet: View {
    let kind: FirstDropCelebration
    @Environment(\.dismiss) private var dismiss
    @State private var emojiAppeared = false

    private var hero: String { kind == .created ? "🎉" : "🙌" }

    /// Marketing-Copy — kürzer, punchier, hook-driven.
    private var headline: String {
        switch kind {
        case .created: return "Drop ist live."
        case .joined:  return "Du bist dabei."
        }
    }

    private var subline: String {
        switch kind {
        case .created:
            return "Deine Stadt sieht dich jetzt auf der Karte. Wer Bock hat, kommt einfach vorbei — kein Smalltalk, kein \"lass mal\"."
        case .joined:
            return "Hingehen, Bluetooth bestätigt automatisch. Kein Check-In, kein Chat. Drops einfach gemacht."
        }
    }

    private var cta: String {
        kind == .created ? "Jetzt geht's los" : "Auf zum Drop"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Hintergrund mit weichem Aurora-Gradient
                LinearGradient(
                    colors: [
                        Color.brand.opacity(0.18),
                        Color(UIColor.systemBackground),
                        Color.accentOrange.opacity(0.10)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Konfetti-Explosion ausgehend vom Emoji-Zentrum
                ConfettiBurstView(
                    origin: CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.32),
                    screenSize: geo.size
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.20)

                    // Hero-Emoji mit Spring-Pop-In
                    Text(hero)
                        .font(.system(size: 96))
                        .scaleEffect(emojiAppeared ? 1.0 : 0.4)
                        .opacity(emojiAppeared ? 1.0 : 0.0)
                        .shadow(color: Color.brand.opacity(0.35), radius: 30, y: 8)

                    Spacer().frame(height: 28)

                    VStack(spacing: 12) {
                        Text(headline)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(subline)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .opacity(emojiAppeared ? 1.0 : 0.0)
                    .offset(y: emojiAppeared ? 0 : 20)

                    Spacer()

                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Text(cta)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.brand, Color.brand.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        )
                        .shadow(color: Color.brand.opacity(0.45), radius: 16, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                    .opacity(emojiAppeared ? 1.0 : 0.0)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                    emojiAppeared = true
                }
            }
        }
    }
}

/// Konfetti-Explosion mit echter Physik: Partikel starten am Origin mit
/// initialer Geschwindigkeit in zufällige Richtung, dann zieht Gravitation
/// sie kontinuierlich nach unten. Luftwiderstand bremst horizontal.
/// Läuft EINMAL ~7s, danach komplett stille Canvas (kein Loop).
struct ConfettiBurstView: View {
    let origin: CGPoint
    let screenSize: CGSize
    /// `@State` damit pieces & startDate über View-Updates hinweg stabil bleiben.
    /// Sonst würde die Animation bei jedem Re-Render der Parent-View neu starten
    /// (z.B. wenn GeometryReader die Größe meldet).
    @State private var pieces: [ConfettiPiece] = (0..<55).map { _ in ConfettiPiece.random() }
    @State private var startDate: Date = Date()

    private let totalLifetime: Double = 7.0

    var body: some View {
        TimelineView(.animation(paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            // Komplett stoppen sobald alle Partikel ausgeblendet sind — sonst
            // würde TimelineView ewig weiter ticken (auch wenn nichts gezeichnet).
            if elapsed > totalLifetime + 1.0 {
                Color.clear
            } else {
                Canvas { ctx, size in
                    for piece in pieces {
                        drawPiece(piece, elapsed: elapsed, in: &ctx, size: size)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Berechnet Position + Rotation + Opacity zu Zeit `t` und zeichnet
    /// den Partikel als Text-Symbol auf den Canvas.
    private func drawPiece(_ piece: ConfettiPiece, elapsed: Double, in ctx: inout GraphicsContext, size: CGSize) {
        let t = max(0, elapsed - piece.delay)
        guard t > 0 else { return }
        let lifetime = 7.0   // Gesamtanimationsdauer

        // Initial-Geschwindigkeit aus Winkel + Speed (relative zur Diagonale)
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let v0: CGFloat = piece.speed * diagonal * 0.7
        let vx0: CGFloat = CGFloat(cos(piece.angle)) * v0
        let vy0: CGFloat = CGFloat(sin(piece.angle)) * v0
        // Bias nach oben für Explosion-Feel: -10% y für mehr Aufwärtsbewegung
        let vyBias: CGFloat = -diagonal * 0.08

        // Luftwiderstand: x-Bewegung dämpft mit e^(-k·t)
        let drag: CGFloat = 0.55       // pro Sekunde
        let dragFactor = (1.0 - exp(-drag * CGFloat(t))) / drag
        let x = origin.x + vx0 * dragFactor

        // Gravitation: y-Bewegung = v0_y + 0.5 g t² (mit leichter y-Dämpfung)
        let g: CGFloat = diagonal * 0.55   // Schwerkraft
        let yDrag: CGFloat = 0.4
        let yDragFactor = (1.0 - exp(-yDrag * CGFloat(t))) / yDrag
        let y = origin.y + (vy0 + vyBias) * yDragFactor + 0.5 * g * CGFloat(t * t) * 0.6

        // Rotation skaliert linear mit t
        let rotation = piece.rotationStart + (piece.rotationEnd - piece.rotationStart) * (t / lifetime)

        // Fade-Out: erste 5s voll sichtbar, dann linear ausblenden
        let fadeStart = 5.0
        let opacity: Double = t < fadeStart
            ? 1.0
            : max(0.0, 1.0 - (t - fadeStart) / (lifetime - fadeStart))

        // Sobald Partikel weit aus dem Bild → nicht mehr zeichnen (Performance)
        if y > size.height + 80 || opacity <= 0.0 { return }

        // Text-Resolve mit Rotation
        let resolved = ctx.resolve(Text(piece.emoji).font(.system(size: piece.size)))
        var transformed = ctx
        transformed.opacity = opacity
        transformed.translateBy(x: x, y: y)
        transformed.rotate(by: .degrees(rotation))
        transformed.draw(resolved, at: .zero, anchor: .center)
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let emoji: String
    /// Winkel in Radiant — bestimmt Richtung der Explosion. 0 = rechts, π/2 = unten.
    let angle: Double
    /// Initiale Geschwindigkeit (relativ zur Bildschirm-Diagonale).
    let speed: CGFloat
    let delay: Double
    let rotationStart: Double
    let rotationEnd: Double
    let size: CGFloat

    static func random() -> ConfettiPiece {
        let emojis = ["🎉", "✨", "💫", "🎊", "⭐️", "🟠", "🟣", "🔵"]
        return ConfettiPiece(
            emoji: emojis.randomElement() ?? "🎉",
            // Vollkreis 360° gleichmäßig verteilt
            angle: Double.random(in: -Double.pi ... Double.pi),
            // Speed: variabel, einige fliegen weiter, andere nah am Origin
            speed: CGFloat.random(in: 0.45...1.25),
            delay: Double.random(in: 0...0.15),
            rotationStart: Double.random(in: -45...45),
            // Volle Drehungen je nach „Gewicht" — kleinere Partikel drehen mehr
            rotationEnd: Double.random(in: 540...1440),
            size: CGFloat.random(in: 18...30)
        )
    }
}

// MARK: - Push Re-Ask Sheet

/// Wird einmalig nach dem ersten ShowUp eines Users angezeigt wenn er
/// im Onboarding Push-Berechtigung abgelehnt hatte. iOS erlaubt keinen
/// zweiten System-Dialog — der Sheet leitet daher zu den App-Einstellungen.
struct PushReaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.brand)
            }

            Spacer().frame(height: 22)

            VStack(spacing: 10) {
                Text("Verpass keinen Drop mehr")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Du warst gerade bei deinem ersten Drop dabei — top! 🎉\n\nMit Push-Nachrichten erfährst du sofort wenn jemand zu deinem Drop kommt oder Freunde in der Nähe einen starten.")
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                } label: {
                    Text("Push aktivieren")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Capsule().fill(Color.brand))
                }
                .padding(.horizontal, 24)

                Button("Vielleicht später") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 28)
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Welcome Sheet

struct WelcomeSheet: View {
    let onDismiss: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"

    private var features: [(icon: String, color: Color, titleKey: String, subtitleKey: String)] {[
        ("dot.radiowaves.left.and.right", Color(hex: "22c55e"),  "welcome.feature1_title", "welcome.feature1_sub"),
        ("map.fill",                      Color(hex: "06b6d4"),  "welcome.feature2_title", "welcome.feature2_sub"),
        ("person.2.fill",                 Color(hex: "f59e0b"),  "welcome.feature3_title", "welcome.feature3_sub"),
        ("lock.shield.fill",              Color(hex: "8b5cf6"),  "welcome.feature4_title", "welcome.feature4_sub"),
    ]}

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            // App-Icon + Titel
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.brand)
                }

                VStack(spacing: 6) {
                    Text(tr("welcome.title"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(tr("welcome.subtitle"))
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 36)

            // Feature-Liste
            VStack(spacing: 0) {
                ForEach(features.indices, id: \.self) { i in
                    let f = features[i]
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(f.color.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: f.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(f.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr(f.titleKey))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tr(f.subtitleKey))
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    if i < features.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }

            Spacer()

            // CTA Button
            Button(action: onDismiss) {
                Text(tr("welcome.cta"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Capsule().fill(Color.brand))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
}


// MARK: - Permission Gate

/// Blockierender Sheet, wenn WEDER Standort NOCH Bluetooth verfügbar sind.
/// Ohne mindestens eines davon kann Drops keine echten Begegnungen erkennen,
/// daher werden die Haupt-Features gesperrt bis der User mindestens eine
/// Berechtigung freigibt.
struct PermissionGateView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.brand)
                }

                VStack(spacing: 10) {
                    Text("Drops braucht Zugriff")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)

                    Text("Damit Drops echte Begegnungen erkennen kann, brauchen wir mindestens eine dieser Berechtigungen:\n\n• Standort — um dich vor Ort zu erkennen\n• Bluetooth — um dich mit Drop-Teilnehmern zu verbinden")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Einstellungen öffnen")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Capsule().fill(Color.brand))
                }
                .padding(.horizontal, 24)

                Button {
                    // Manuell nochmal prüfen (falls der User die Berechtigung im
                    // anderen Tab bereits gegeben hat und zurückkommt).
                    store.evaluateCorePermissions()
                } label: {
                    Text("Erneut prüfen")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding(.bottom, 36)
            }
        }
    }
}
