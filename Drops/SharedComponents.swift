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
        .onChange(of: url) { _, _ in loadImage() }
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
                        // Aurora-Sunset Palette — Orange + Grün als Anker
                        // (aus dem App-Icon), plus drei weiche Akzent-
                        // Farben (Rose, Gold, Lavender) für mehr visuelle
                        // Tiefe und Aurora-Feel ohne den warmen Charakter
                        // zu verlieren. Bewusst weiche, gedämpfte Töne —
                        // nicht knall-bunt.
                        //
                        // Kreis 1 — Orange (top-left, dominant) wie Icon-Top
                        Circle()
                            .fill(Color.auroraOrange.opacity((light ? 0.74 : 0.58) * (1 + Self.pulseBoost * p0)))
                            .frame(width: 520 * (1 + 0.06 * p0))
                            .offset(x: a ? -130 : -80, y: a ? -370 : -320)
                            .blur(radius: 90)
                        // Kreis 2 — Soft Rose/Pink (top-right) — warmer
                        // Sunset-Hauch, bricht das reine Orange auf
                        Circle()
                            .fill(Color.auroraPink.opacity((light ? 0.58 : 0.46) * (1 + Self.pulseBoost * p1)))
                            .frame(width: 460 * (1 + 0.06 * p1))
                            .offset(x: a ? 160 : 110, y: a ? -350 : -300)
                            .blur(radius: 85)
                        // Kreis 3 — Grün (bottom-left, dominant) wie Icon-Bottom
                        Circle()
                            .fill(Color.auroraGreen.opacity((light ? 0.60 : 0.46) * (1 + Self.pulseBoost * p2)))
                            .frame(width: 420 * (1 + 0.06 * p2))
                            .offset(x: a ? -150 : -100, y: a ? 420 : 370)
                            .blur(radius: 80)
                        // Kreis 4 — Soft Lavender (bottom-right) — kühler
                        // Aurora-Akzent, balanciert das warme Top-Drittel
                        Circle()
                            .fill(Color.auroraViolet.opacity((light ? 0.50 : 0.40) * (1 + Self.pulseBoost * p3)))
                            .frame(width: 380 * (1 + 0.06 * p3))
                            .offset(x: a ? 140 : 90, y: a ? 400 : 350)
                            .blur(radius: 75)
                        // Kreis 5 — Warm Gold (center) — Sun-Glow als
                        // weiche Übergangsfarbe zwischen Orange-Top und
                        // Grün-Bottom. Setzt die Mitte „in Licht".
                        Circle()
                            .fill(Color.auroraAmber.opacity((light ? 0.44 : 0.32) * (1 + Self.pulseBoost * p4)))
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

// MARK: - Push Permission Banner
//
// Persistenter Inline-Banner für User die Push abgelehnt haben oder den
// Reask-Sheet weggedismissed haben. Wichtig weil ohne Push die ganze App-
// Reaktivität wegfällt: Drop-Anfragen, Drop-beendet, Pair-Auto-Accept
// sind alle silently broken. Banner ist klar dismissable damit User der
// bewusst kein Push will nicht genervt wird (ud_pushBannerDismissed).
struct PushPermissionBanner: View {
    @AppStorage("ud_pushBannerDismissed") private var dismissed = false
    @State private var isAuthorized: Bool? = nil
    @State private var checkedOnce = false

    var body: some View {
        Group {
            if !dismissed,
               let auth = isAuthorized,
               !auth {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                EmptyView()
            }
        }
        .task(id: checkedOnce) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let auth = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            await MainActor.run { self.isAuthorized = auth }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraPink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("shared.push_missing"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("shared.push_missing_body"))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.25)) { dismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.auroraOrange.opacity(0.3), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            // iOS-Einstellungen für die App öffnen — Apple erlaubt keinen
            // zweiten Permission-Dialog programmatisch nach „Denied".
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Radar Pulse Hero

/// Zentrales Visual: konzentrische pulsierende Aurora-Ringe um ein
/// SF-Symbol im Zentrum. Matched die Sprache des App-Icons (Radar-Wellen
/// aus dem Drop-Center). Wird in EmptyStates, Onboarding-Sheets und
/// Permission-Gates wiederverwendet — eine Quelle, ein Look.
struct RadarPulseHero: View {
    let icon: String
    /// Skaliert die gesamte Komposition. 1.0 = Original-Größe (180×180
    /// Frame, 72pt Core, 28pt Icon, Ringe 116/160/204).
    var scale: CGFloat = 1.0
    /// 3 Ringe = volle EmptyState-Version, 2 = kompakte (ohne äußersten
    /// grünen Ring) für engere Layouts wie FreundeEmptyState.
    var ringCount: Int = 3

    @State private var pulse0 = false
    @State private var pulse1 = false
    @State private var pulse2 = false

    var body: some View {
        ZStack {
            // Innerster Ring — Orange, kräftigste Sichtbarkeit
            Circle()
                .stroke(Color.auroraOrange.opacity(0.16), lineWidth: 1)
                .frame(width: 116 * scale, height: 116 * scale)
                .scaleEffect(pulse0 ? 1.06 : 0.96)
            // Mittlerer Ring
            Circle()
                .stroke(Color.auroraOrange.opacity(0.10), lineWidth: 1)
                .frame(width: 160 * scale, height: 160 * scale)
                .scaleEffect(pulse1 ? 1.05 : 0.97)
            // Äußerer Ring — Grün, weichste Sichtbarkeit
            if ringCount >= 3 {
                Circle()
                    .stroke(Color.auroraGreen.opacity(0.08), lineWidth: 1)
                    .frame(width: 204 * scale, height: 204 * scale)
                    .scaleEffect(pulse2 ? 1.04 : 0.97)
            }
            // Center: Gradient-Circle + SF-Symbol
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange.opacity(0.18),
                                     Color.auroraGreen.opacity(0.14)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72 * scale, height: 72 * scale)
                Image(systemName: icon)
                    .font(.system(size: 28 * scale, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(width: 180 * scale, height: 180 * scale)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse0 = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(0.3)) {
                pulse1 = true
            }
            if ringCount >= 3 {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.6)) {
                    pulse2 = true
                }
            }
        }
    }
}

// MARK: - Dynamic Island Mock (WelcomeSheet Hero)

/// Animierte Nachbildung der Dynamic Island — zeigt wie ein laufender Drop
/// oben auf dem Sperrbildschirm / in der Live Activity aussieht.
/// Loopt: kompakt → expandiert (Aktivität + Count + Live) → kompakt.
struct DynamicIslandMock: View {
    @State private var expanded = false
    @State private var showContent = false

    var body: some View {
        // Single morphing shape — no if/else view destruction.
        // cornerRadius 17 = capsule (half of height 34), 28 = expanded pill.
        RoundedRectangle(cornerRadius: expanded ? 28 : 17, style: .continuous)
            .fill(Color.black)
            .frame(
                width:  expanded ? 300 : 126,
                height: expanded ? 88  : 34
            )
            .shadow(
                color:  .black.opacity(expanded ? 0.35 : 0.20),
                radius: expanded ? 18 : 8,
                y:      expanded ? 8  : 4
            )
            .overlay {
                ZStack {
                    // Compact content — always in tree, fades out on expand
                    compactContent
                        .frame(width: 126)          // fixed → no layout thrash
                        .opacity(expanded ? 0 : 1)
                    // Expanded content — fades in after shape finishes morphing
                    expandedContent
                        .frame(width: 300)
                        .opacity(showContent ? 1 : 0)
                }
                .clipped()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.74), value: expanded)
            .frame(height: 140)
            .task {
                do {
                    // Wait for sheet presentation to finish before starting loop.
                    try await Task.sleep(for: .seconds(0.7))
                    while true {
                        try await Task.sleep(for: .seconds(1.0))
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { expanded = true }
                        try await Task.sleep(for: .seconds(0.3))
                        withAnimation(.easeIn(duration: 0.18)) { showContent = true }
                        try await Task.sleep(for: .seconds(2.8))
                        withAnimation(.easeOut(duration: 0.12)) { showContent = false }
                        try await Task.sleep(for: .seconds(0.2))
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { expanded = false }
                        try await Task.sleep(for: .seconds(1.5))
                    }
                } catch {}
            }
    }

    // Compact: links emoji + "2/4", rechts grüner Dot
    private var compactContent: some View {
        HStack {
            HStack(spacing: 3) {
                Text("☕️").font(.system(size: 14))
                Text("2/4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.leading, 10)
            Spacer()
            Circle()
                .fill(Color(hex: "22c55e"))
                .frame(width: 6, height: 6)
                .padding(.trailing, 10)
        }
    }

    // Expanded: Leading = emoji-Box + Name + Ort, Trailing = Personen-Capsule
    private var expandedContent: some View {
        HStack(alignment: .center, spacing: 0) {
            // Leading
            HStack(spacing: 8) {
                Text("☕️")
                    .font(.system(size: 28))
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kaffee")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Schwabing")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Trailing — Personen-Capsule
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                Text("2/4")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12), in: Capsule())
            .padding(.trailing, 14)
        }
    }
}

// MARK: - Empty State: Keine Drops in der Nähe

struct DropsEmptyState: View {
    var onCreateTap: (() -> Void)? = nil
    /// Wenn true → kleine Boost-Bonus-Zeile unter der Beschreibung
    /// ("+15 / +25 Punkte als Bonus für deinen Drop"). Triggert wenn weniger
    /// als `AppStore.boostThreshold` Drops in der Umgebung sind — die
    /// gleiche Bedingung, unter der dieser Empty-State sichtbar ist.
    /// Der frühere separate `BoostBanner` weiter unten im Feed entfällt
    /// damit, weil sonst zwei UI-Elemente die gleiche Info doppelt zeigen.
    var boostActive: Bool = false
    /// Während Power-Hour-Slots ist `boostBonus` 25 statt 15 — wird vom
    /// Aufrufer durchgereicht, damit der Empty-State den richtigen Wert
    /// + ein "Power-Hour"-Label statt "Bonus" zeigen kann.
    var boostBonus: Int = 15
    var isPowerHour: Bool = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            RadarPulseHero(icon: "binoculars.fill")

            VStack(spacing: 6) {
                Text(tr("shared.feed_empty_title"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("shared.feed_empty_body"))
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)

                // Boost-Bonus-Zeile — sichtbar wenn Boost-Phase aktiv ist.
                // Schmale Capsule mit Bolt-Icon + Hinweis auf die +15
                // Punkte. Belohnung statt eigener Werbe-Banner — die
                // Botschaft "sei der erste" oben bleibt der primäre CTA,
                // der Bonus untermauert ihn nur.
                if boostActive {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accentOrange)
                        Text(isPowerHour
                             ? tr("shared.power_hour_bonus_amount").replacingOccurrences(of: "{bonus}", with: "\(boostBonus)")
                             : tr("shared.boost_bonus_amount").replacingOccurrences(of: "{bonus}", with: "\(boostBonus)"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentOrange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.accentOrange.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(Color.accentOrange.opacity(0.30), lineWidth: 1)
                    )
                    .padding(.top, 8)
                }
            }

            if let action = onCreateTap {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(tr("shared.create_drop"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.auroraOrange, Color.auroraGreen],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color.auroraOrange.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Empty State: Noch keine Freunde

struct FreundeEmptyState: View {
    /// Optionaler Tap-Handler für „Aus Kontakten hinzufügen". Wenn gesetzt
    /// wird der Button gerendert. Falls die Parent-View den Flow nicht
    /// braucht (z.B. Settings-Section ohne diesen Aktion), kann sie nil
    /// übergeben und der Button erscheint nicht.
    var onAddFromContacts: (() -> Void)? = nil
    var onShareInvite: (() -> Void)? = nil

    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            // person.2.fill ist semantisch positiver als person.2.slash —
            // signalisiert "Freunde finden" statt "keine Freunde".
            // Kompakte 2-Ring-Variante des RadarPulseHero (ohne äußersten
            // grünen Ring) damit der Empty-State knapp bleibt.
            RadarPulseHero(icon: "person.2.fill", ringCount: 2)

            VStack(spacing: 6) {
                Text(tr("shared.no_friends_title"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("shared.no_friends_body"))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }

            // CTA-Buttons — primär „Kontakte" (häufigster Pfad), sekundär
            // „Einladungslink teilen". Vorher: gar nichts klickbar →
            // Sackgassen-Empty-State, Frust statt Action.
            if onAddFromContacts != nil || onShareInvite != nil {
                VStack(spacing: 8) {
                    if let action = onAddFromContacts {
                        Button(action: action) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(tr("shared.add_from_contacts"))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.auroraOrange, Color.auroraGreen],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: Color.auroraOrange.opacity(0.35), radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                    if let share = onShareInvite {
                        Button(action: share) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tr("shared.share_invite_link"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.brand)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.brand.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
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
        // www-Subdomain nutzen — Apex 307-redirected zu www, Apple Universal
        // Links akzeptieren keine Redirects (siehe LiveMapView).
        let deepLink = "https://www.drops-app.de/drop/\(item.id.uuidString)"
        let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
        let text = "\(item.emoji) \(item.activity)\(location) — komm vorbei. Spontan, vor Ort, kein Smalltalk. 👋"
        // Text + URL als EIN String — sonst kopiert iOS „In Zwischenablage"
        // nur den Text und verliert die URL. Apps wie iMessage/WhatsApp
        // parsen die URL eh automatisch raus und zeigen Link-Preview.
        let combined = "\(text)\n\(deepLink)"
        let items: [Any] = [combined]

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


// MARK: - Profile Hero Background Templates

/// Vordefinierte Hintergrund-Vorlagen für die Profil-Hero-Karte.
/// User kann via Picker zwischen den 6 Varianten wählen — wird in
/// UserDefaults persistiert (`ud_profileHeroTemplate`).
enum ProfileHeroTemplate: String, CaseIterable, Identifiable {
    case tester, aurora, sunset, ocean, forest, neon, midnight
    var id: String { rawValue }

    var label: String {
        switch self {
        case .tester:   return "Tester"
        case .aurora:   return "Aurora"
        case .sunset:   return "Sunset"
        case .ocean:    return "Ocean"
        case .forest:   return "Forest"
        case .neon:     return "Neon"
        case .midnight: return "Midnight"
        }
    }

    /// Exklusive Tester-Variante — holographisch / iridescent. Symbolisiert
    /// die Beta-Tester-Identität visuell. Default für Beta-User.
    var isExclusive: Bool { self == .tester }

    /// Hauptfarben — auch für Thumbnail-Vorschau im Picker genutzt.
    var colors: [Color] {
        switch self {
        case .tester:
            // Holographic/iridescent — pink → cyan → gold → violet
            return [Color.auroraPink, Color.auroraCyan,
                    Color.auroraAmber, Color.auroraPurple]
        case .aurora:
            // Neue Icon-Palette: warmes Orange → Coral → frisches Grün.
            // Direkt aus icon.json abgeleitet damit das Profil-Hero
            // dieselbe Brand-Identity hat wie Login + App-Icon.
            return [Color.auroraOrange, Color.auroraOrange, Color.auroraGreen]
        case .sunset:
            return [Color.auroraOrange, Color.auroraPink, Color.auroraViolet]
        case .ocean:
            return [Color.auroraCyan, Color.auroraCyan, Color.auroraTeal]
        case .forest:
            return [Color(hex: "166534"), Color(hex: "65a30d"), Color(hex: "facc15")]
        case .neon:
            return [Color.auroraPink, Color.auroraAmber, Color.auroraCyan]
        case .midnight:
            return [Color(hex: "0f172a"), Color(hex: "1e293b"), Color(hex: "334155")]
        }
    }

    var gradient: LinearGradient {
        // Tester nutzt steileren Winkel für mehr "Iridescent"-Effekt
        if self == .tester {
            return LinearGradient(colors: colors,
                                  startPoint: UnitPoint(x: 0, y: 0),
                                  endPoint: UnitPoint(x: 1, y: 1))
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Tap-Picker-Sheet zum Wechseln des Hero-Backgrounds.
struct ProfileHeroPickerSheet: View {
    @Binding var selection: ProfileHeroTemplate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(tr("shared.choose_background"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28).padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(ProfileHeroTemplate.allCases) { tpl in
                            Button {
                                Haptic.selection()
                                selection = tpl
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .fill(tpl.gradient)
                                        .frame(height: 110)
                                        .overlay(alignment: .topTrailing) {
                                            // Exklusiv-Marker für Tester-Variante
                                            if tpl.isExclusive {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "sparkle")
                                                        .font(.system(size: 7, weight: .bold))
                                                    Text(tr("shared.beta"))
                                                        .font(.system(size: 8, weight: .bold))
                                                        .kerning(0.3)
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.6))
                                                .padding(8)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                                .stroke(
                                                    selection == tpl ? Color.brand : Color.white.opacity(0.15),
                                                    lineWidth: selection == tpl ? 3 : 1
                                                )
                                        )
                                        .shadow(color: tpl.colors.first?.opacity(0.35) ?? .clear, radius: 8, y: 4)
                                    HStack(spacing: 5) {
                                        if selection == tpl {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.brand)
                                        }
                                        Text(tpl.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 24)
                }
            }
            .navigationTitle(tr("shared.background"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("shared.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Beta Badge

/// Kleiner Badge für Early-Adopter / Beta-User. Wird neben dem Namen
/// im Profil + auf User-Karten angezeigt.
struct BetaBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
            Text(tr("shared.beta"))
                .font(.system(size: 9, weight: .bold))
                .kerning(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            LinearGradient(
                colors: [Color.brand, Color.auroraCyan],
                startPoint: .leading, endPoint: .trailing
            ),
            in: Capsule()
        )
        .shadow(color: Color.brand.opacity(0.35), radius: 4, y: 1)
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
                Text(tr("shared.your_emoji"))
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
                            Haptic.selection()
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
                                    in: RoundedRectangle(cornerRadius: Radius.md)
                                )
                                .overlay(
                                    emoji == selected
                                        ? RoundedRectangle(cornerRadius: Radius.md)
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

// MARK: - Power-Hour Countdown Pill
//
// Wird sowohl im LiveMapView als auch im FeedView angezeigt — extrahiert
// damit beide Tabs konsistent dieselbe Pille rendern. Sichtbar ≤60 Min vor
// einem Window-Start oder ≤60 Min vor Ende eines aktiven Slots; sonst nil.
//
// Hostende Views wickeln den Aufruf in eine TimelineView, damit der
// Countdown jede Minute neu berechnet wird.
struct PowerHourCountdownPill: View {
    let countdown: AppStore.PowerHourCountdown

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
        .shadow(color: Color.accentOrange.opacity(0.30), radius: 6, y: 2)
    }

    private var label: String {
        let mins = formatMinutes(countdown.minutesRemaining)
        switch countdown.phase {
        case .startingSoon: return tr("shared.ph_starting_in").replacingOccurrences(of: "{time}", with: mins)
        case .running:      return tr("shared.power_hour_running").replacingOccurrences(of: "{time}", with: mins)
        case .endingSoon:   return tr("shared.ph_ending_in").replacingOccurrences(of: "{time}", with: mins)
        }
    }

    /// Visuelle Differenzierung: endingSoon kriegt umgekehrten Verlauf
    /// (brand → orange) für mehr Dringlichkeit, die anderen orange → brand.
    private var gradientColors: [Color] {
        switch countdown.phase {
        case .endingSoon:   return [Color.brand, Color.accentOrange]
        default:            return [Color.accentOrange, Color.brand]
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) Min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)min"
    }
}

// MARK: - App Version Gate (Force-Update + Recommend-Banner)
//
// Liest store.appVersionStatus und rendert je nach Phase:
//   - .updateRequired: blockierender Vollbild (kein Schließen möglich)
//   - .updateRecommended: dezenter dismissibler Banner oben
//   - .ok / .unknown: nichts
/// Force-Update-Vollbild-Overlay. NUR für Hard-Force. Der Soft-Recommend-
/// Banner wird in MainTabView via safeAreaInset(.top) eingehängt, damit er
/// wirklich an den oberen Screen-Rand andockt und nicht von anderen Overlays
/// verdrängt wird.
struct AppVersionGate: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if case .updateRequired(let v) = store.appVersionStatus {
                ForceUpdateSheet(requiredVersion: v)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.appVersionStatus)
    }
}

/// Recommend-Banner als eigene Top-Inset-View, damit er als wirklicher
/// Top-Banner direkt unter der Status Bar sitzt und nicht im View-Mittelteil
/// verschwindet.
struct AppVersionRecommendBanner: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if case .updateRecommended(let v) = store.appVersionStatus {
                RecommendUpdateBanner(recVersion: v) {
                    store.dismissRecommendBanner(forVersion: v)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.appVersionStatus)
    }
}

/// Vollbild-Blocker: kein "X", kein Drag-Dismiss. Einziger Ausweg ist
/// "App Store öffnen". Genutzt nur für Notfälle (kritische Bugs).
///
/// Design: vollflächiger `AppAuroraBackground` (matched zum Rest der App)
/// + Hero-Icon-Stack mit drei pulsierenden Radar-Wellen + Sunset-Gradient-
/// Glow drumherum. Visuell parallel zum `EndDropSheet`/`HomeZoneWarningSheet`,
/// nur „aufwärts" statt „beenden" konnotiert.
private struct ForceUpdateSheet: View {
    let requiredVersion: String
    @EnvironmentObject var store: AppStore

    @State private var ring0 = false
    @State private var ring1 = false
    @State private var ring2 = false
    @State private var iconBeat = false

    var body: some View {
        ZStack {
            // Aurora-Hintergrund — exakt wie ActiveDropTabView / Onboarding.
            // Eindeutig kein „X", weil .ignoresSafeArea + voll-deckend.
            AppAuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                // ── Hero-Icon mit drei pulsierenden Radar-Wellen ──────
                ZStack {
                    radarRing(scale: ring0 ? 1.7 : 0.95, opacity: ring0 ? 0.0 : 0.55)
                    radarRing(scale: ring1 ? 1.7 : 0.95, opacity: ring1 ? 0.0 : 0.55)
                    radarRing(scale: ring2 ? 1.7 : 0.95, opacity: ring2 ? 0.0 : 0.55)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.auroraOrange.opacity(0.30),
                                         Color.auroraGreen.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: Color.auroraOrange.opacity(0.40), radius: 18, y: 6)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraOrange, Color.auroraGreen],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.auroraOrange.opacity(0.50), radius: 10)
                        .scaleEffect(iconBeat ? 1.08 : 1.0)
                }
                // 96 × 1.7 = 163pt max ring size — Frame muss das aufnehmen
                .frame(height: 170)

                VStack(spacing: 10) {
                    Text(tr("shared.version_not_supported"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    Text(tr("shared.version_required").replacingOccurrences(of: "{ver}", with: requiredVersion))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                }

                // Version-Badge — kleine Glass-Pill mit „Du nutzt 1.0.x"
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    Text(tr("shared.using_version").replacingOccurrences(of: "{ver}", with: store.currentAppVersion))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))

                Spacer()

                // App-Store-Button — Sunset-Gradient-Pill
                Button(action: openAppStore) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(tr("shared.open_app_store"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.auroraOrange, Color.auroraGreen],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color.auroraOrange.opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
        .onAppear {
            // Drei zeitversetzte Ring-Wellen mit 0.6s-Stagger — wie das
            // Radar-Pulse-Muster im AppIcon und beim EndDropSheet.
            let dur: Double = 2.0
            withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                ring0 = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                    ring1 = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                    ring2 = true
                }
            }
            // Icon-Beat synchron zum ersten Ring.
            withAnimation(
                .spring(response: 0.7, dampingFraction: 0.55)
                    .repeatForever(autoreverses: true)
            ) {
                iconBeat = true
            }
        }
    }

    /// Einzelner Radar-Ring — frame-basierte Animation (kein scaleEffect),
    /// damit ScrollView den Ring nicht am Layout-Rand clippt.
    @ViewBuilder
    private func radarRing(scale: CGFloat, opacity: Double) -> some View {
        let size: CGFloat = 96 * scale
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.auroraOrange, Color.auroraGreen],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 2.5
            )
            .frame(width: size, height: size)
            .opacity(opacity)
    }

    private func openAppStore() {
        let id = AppStore.appStoreID
        // itms-apps:// öffnet die App-Store-App direkt; falls die ID
        // mal nicht gesetzt ist (Pre-Release-Branch o.ä.) → https-Fallback
        // auf den echten Drops-Listing-Pfad.
        let urlString = id.isEmpty
            ? "https://apps.apple.com/de/app/drops-triff-leute/id6762097493"
            : "itms-apps://itunes.apple.com/app/id\(id)"
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

/// Soft-Recommend: kleiner Banner oben, dismissibel mit X.
private struct RecommendUpdateBanner: View {
    let recVersion: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("shared.new_version"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(tr("shared.version_in_store").replacingOccurrences(of: "{ver}", with: recVersion))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button(action: openAppStore) {
                Text(tr("shared.now"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("shared.close_banner"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color.brand, Color.accentOrange],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
        .shadow(color: Color.accentOrange.opacity(0.25), radius: 8, y: 2)
    }

    private func openAppStore() {
        let id = AppStore.appStoreID
        let urlString = id.isEmpty
            ? "https://apps.apple.com/de/app/drops"
            : "itms-apps://itunes.apple.com/app/id\(id)"
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Home Zone Warning Sheet
//
// Eigene Warnung statt System-Alert: visuell wärmer, mit Icon und
// strukturierten Hinweisen. Gibt dem User mehr Kontext was passiert
// und ist visuell konsistent mit dem restlichen App-Design (Aurora-
// Hintergrund, Brand-Farben, Liquid-Glass-Card).
struct HomeZoneWarningSheet: View {
    /// User wählt "Trotzdem hier starten".
    let onProceed: () -> Void
    /// User wählt "Abbrechen" oder Drag-to-dismiss.
    let onCancel: () -> Void

    @State private var pulse = false

    var body: some View {
        // Inhalt in ScrollView — auf kleinen Geräten (SE / mini) war
        // sonst der Bottom-Button abgeschnitten, weil 110pt-Visual +
        // Titel + 2 Warning-Rows + 2 Buttons mehr Höhe brauchen als die
        // 0.65-Detent-Fraction hergibt. Buttons unten in einem festen
        // Footer, der Rest scrollt.
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Visual: pulsierendes Haus mit Schild-Overlay
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentOrange.opacity(0.22),
                                             Color.brand.opacity(0.14)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulse ? 1.05 : 0.96)

                        Image(systemName: "house.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.accentOrange)
                            .shadow(color: Color.accentOrange.opacity(0.4), radius: 10)
                        // Schild-Overlay rechts unten am Haus
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                            .padding(6)
                            .background(Circle().fill(Color.accentOrange))
                            .offset(x: 30, y: 30)
                    }
                    // 110 × 1.05 = 115.5pt max — 130pt Frame gibt Puffer, kein .clipped()
                    .frame(width: 130, height: 130)
                    .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text(tr("shared.drop_in_homezone"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 20)
                        // Padding von 36 → 20 reduziert: vorher brach
                        // "Zuhause" auf kompakten Geräten unsauber um und
                        // wurde teils abgeschnitten. minimumScaleFactor
                        // greift falls die Textgröße trotzdem mal nicht
                        // reicht (z.B. größere Dynamic-Type-Stufen).
                        Text(tr("shared.starting_near_home"))
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 20)
                    }

                    // Konkrete Hinweis-Liste
                    VStack(spacing: 12) {
                        warningRow(
                            icon: "eye.fill",
                            text: tr("shared.others_can_see_home")
                        )
                        warningRow(
                            icon: "person.fill",
                            text: tr("shared.meet_at_public_place")
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
            }

            // Aktionen — fester Footer, scrollt nicht weg
            VStack(spacing: 10) {
                // Primär: sicherer Weg
                Button(action: onCancel) {
                    Text(tr("shared.choose_different_location"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.brand, Color.accentOrange],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                        .shadow(color: Color.brand.opacity(0.30), radius: 10, y: 3)
                }
                .buttonStyle(.plain)

                // Sekundär (destruktiv): trotzdem hier
                Button(action: onProceed) {
                    Text(tr("shared.start_here_anyway"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentOrange)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentOrange.opacity(0.14)))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Admin Notice Sheet
//
// Pflicht-Sheet wenn ein Admin den Drop des Users via Live-Drops-Monitor
// entfernt hat. Wird auf MainTabView-Ebene gebunden (sheet(item:)
// auf store.pendingAdminNotice). Der User MUSS „Verstanden" tippen,
// das löscht den Notice aus Firebase. Drag-to-dismiss ist deaktiviert
// — die Botschaft soll wirklich gelesen werden.

struct AdminNoticeSheet: View {
    let notice: RealtimeDBManager.AdminNotice
    let onAcknowledge: () -> Void

    private var headline: String {
        switch notice.type {
        case "drop_removed": return "Dein Drop wurde entfernt"
        default:             return "Hinweis"
        }
    }

    private var body1: String {
        switch notice.type {
        case "drop_removed":
            return "Ein Admin hat ihn von der Karte genommen."
        default:
            return "Lies dir das durch."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Visual: Schild mit Ausrufezeichen
                    ZStack {
                        Circle()
                            .fill(Color.accentRed.opacity(0.15))
                            .frame(width: 96, height: 96)
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.accentRed)
                    }
                    .padding(.top, 18)

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        Text(body1)
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }

                    // Reason-Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            Text(tr("shared.reason"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                        }
                        Text(notice.reason)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(Color.accentRed.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.accentRed.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Sekundär-Hinweis
                    Text(tr("shared.questions_support"))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                .padding(.bottom, 12)
            }

            // Acknowledge-Button — fester Footer
            Button(action: onAcknowledge) {
                Text(tr("shared.understood"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.accentRed, Color.accentOrange],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color.accentRed.opacity(0.30), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Power-Hour Intro Sheet
//
// Einmaliger Hinweis nach App-Update, gezeigt beim ersten Map-Open.
// Erklärt Power-Hour kurz mit Bonus-Wert und den drei Slots — danach
// wird der Hinweis via @AppStorage("hasSeenPowerHourIntro") nicht mehr
// angezeigt. Auch ohne nochmal in die Settings zu gehen, weiß der User
// dann was Power-Hour ist und wann.
struct PowerHourIntroSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            // Visual: pulsing bolt
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentOrange.opacity(0.25), Color.brand.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.accentOrange)
                    .shadow(color: Color.accentOrange.opacity(0.5), radius: 12)
            }
            .padding(.top, 18)

            VStack(spacing: 10) {
                Text(tr("shared.new_power_hour"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("shared.power_hour_explainer").replacingOccurrences(of: "{bonus}", with: "\(AppStore.powerHourBonus)").replacingOccurrences(of: "{base}", with: "\(AppStore.boostBonus)"))
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(2)
            }

            // Window-Übersicht kompakt
            VStack(spacing: 0) {
                ForEach(Array(AppStore.powerHourWindows.enumerated()), id: \.offset) { idx, window in
                    HStack {
                        Text(window.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(formatWindow(window))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if idx < AppStore.powerHourWindows.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 22)

            Spacer()

            Button(action: onDismiss) {
                Text(tr("shared.understood"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.accentOrange, Color.brand],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color.accentOrange.opacity(0.35), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    /// Formatiert ein Window für die Intro-Liste z.B. "Mo–Do · 18–20".
    private func formatWindow(_ w: AppStore.PowerHourWindow) -> String {
        let names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let mondayFirst = w.weekdays.map { ($0 == 1 ? 6 : $0 - 2) }.sorted()
        guard let first = mondayFirst.first, let last = mondayFirst.last else { return "" }
        let isContiguous = mondayFirst.count == (last - first + 1)
        let dayLabel: String
        if isContiguous {
            dayLabel = mondayFirst.count == 1 ? names[first] : "\(names[first])–\(names[last])"
        } else {
            dayLabel = mondayFirst.map { names[$0] }.joined(separator: ", ")
        }
        return "\(dayLabel) · \(w.startHour)–\(w.endHour) Uhr"
    }
}

// MARK: - Points Toast
//
// Globaler Toast für jeden Punkte-Gewinn. Wird vom AppStore via
// `pointsToast` getriggert — die View hier ist rein visuell und
// auto-dismisst sich nach 2.5 Sekunden via `.task`. Gradient + Bolt
// imitieren die Optik von Boost/Power-Hour-Hinweisen, im Power-Hour-
// Modus mit hellerem Akzent für mehr "pop".
// MARK: - Pending Join Request Pill (Joiner-Seite)

/// Floating-Pill oben in der App während eine Beitrittsanfrage des Users
/// pending ist. Zeigt Drop-Emoji + Aktivität + Live-Countdown bis Auto-
/// Accept (5 Min). Schwebt über Sheets + Tab-Bar damit der Joiner immer
/// sieht dass seine Anfrage läuft, egal wo er gerade ist in der App.
struct PendingJoinRequestPill: View {
    @EnvironmentObject var store: AppStore

    /// Emoji + Activity-Name werden beim sendJoinRequest in `store.pendingJoinDropEmoji`
    /// / `pendingJoinDropActivity` gecached — robuster als allMapAnnotations-
    /// Lookup, der fehlschlägt wenn der Drop aus dem Radius rutscht oder
    /// gerade vom Host gecancelt wird.
    private var dropEmoji: String {
        if !store.pendingJoinDropEmoji.isEmpty { return store.pendingJoinDropEmoji }
        // Fallback für Edge-Cases (Cache leer aus früherer App-Version etc.)
        if let id = store.pendingJoinDropID,
           let match = store.allMapAnnotations.first(where: { $0.id == id }) {
            return match.emoji
        }
        return "📍"
    }
    private var dropActivity: String {
        if !store.pendingJoinDropActivity.isEmpty { return store.pendingJoinDropActivity }
        if let id = store.pendingJoinDropID,
           let match = store.allMapAnnotations.first(where: { $0.id == id }) {
            return match.activity
        }
        return ""
    }

    /// Sekunden bis Auto-Accept (5 Min nach Anfrage). Capped bei 0.
    private func secondsRemaining(now: Date) -> Int {
        guard let requestedAt = store.pendingJoinRequestedAt else { return 0 }
        let elapsed = now.timeIntervalSince(requestedAt)
        return max(0, Int(5 * 60 - elapsed))
    }

    private func timeLabel(now: Date) -> String {
        let s = secondsRemaining(now: now)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Progress 0..1 — wieviel der 5 Min sind verstrichen.
    private func progress(now: Date) -> Double {
        guard let requestedAt = store.pendingJoinRequestedAt else { return 0 }
        let elapsed = now.timeIntervalSince(requestedAt)
        return min(1.0, max(0, elapsed / (5 * 60)))
    }

    /// Räumt den Pending-State lokal auf wenn der Timer 5 Min überschritten
    /// hat OHNE dass eine Antwort kam (Drop weg, Firebase-Path gelöscht,
    /// Host-App offline). Sonst hängt die Pill ewig bei 0:00.
    /// 5s Puffer für die Auto-Accept-Propagation; größere Hänger fängt der
    /// direkte Drop-Observer in AppStore (`observePendingDropEnd`) ab.
    private func cleanupIfStale(now: Date) {
        guard let requestedAt = store.pendingJoinRequestedAt else { return }
        let elapsed = now.timeIntervalSince(requestedAt)
        guard elapsed > 5 * 60 + 5 else { return }
        store.pendingJoinDropID = nil
        store.pendingJoinRequestedAt = nil
        store.pendingJoinDropEmoji = ""
        store.pendingJoinDropActivity = ""
        store.myJoinRequestStatus = ""
    }

    var body: some View {
        if store.myJoinRequestStatus == "pending",
           store.pendingJoinDropID != nil {
            // TimelineView statt Timer.publish — akkurater Tick auch wenn
            // andere Sheets/Animationen den Main-Thread belasten.
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let now = timeline.date
                VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Drop-Emoji-Avatar mit pulsierendem Ring
                    ZStack {
                        Circle()
                            .stroke(Color.auroraOrange.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 38, height: 38)
                            .scaleEffect(1.0 + 0.1 * sin(now.timeIntervalSinceReferenceDate * 2))
                        Circle()
                            .fill(Color.auroraOrange.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text(dropEmoji)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tr("shared.request_pending"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                            if !dropActivity.isEmpty {
                                Text("· \(dropActivity)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        // Countdown + Progress-Bar
                        HStack(spacing: 6) {
                            Text(timeLabel(now: now))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.textSecondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.textTertiary.opacity(0.18))
                                        .frame(height: 3)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.auroraOrange, Color.auroraGreen],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * CGFloat(progress(now: now)), height: 3)
                                }
                            }
                            .frame(height: 3)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.auroraOrange.opacity(0.30), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                }
                .frame(maxWidth: 380)
                .onAppear { cleanupIfStale(now: now) }
                // Jeder Timeline-Tick (1× pro Sekunde) checkt ob die 5min+
                // bereits abgelaufen sind. Vorher: onChange(of: secondsRemaining)
                // feuerte einmal bei 0 — wenn dann die Guard (elapsed > 5*60+X)
                // noch nicht erfüllt war, blieb die Pill ewig bei „0:00" hängen,
                // weil secondsRemaining sich nicht mehr ändert.
                .onChange(of: Int(now.timeIntervalSinceReferenceDate)) { _, _ in
                    cleanupIfStale(now: now)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct PointsToastView: View {
    let toast: AppStore.PointsToast
    /// Wird beim Auto-Dismiss aufgerufen (setzt store.pointsToast = nil).
    let onDismiss: () -> Void

    @State private var visible = false

    var body: some View {
        // Wenn Reason vorhanden → 2-Zeilen-Layout mit Subline darunter,
        // sonst kompakte 1-Zeile wie vorher. So weiß der User immer wofür
        // die Punkte kommen, ohne dass die Pille überfüllt wirkt.
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: toast.isPowerHour ? "bolt.fill" : "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(tr("shared.points_plus").replacingOccurrences(of: "{delta}", with: "\(toast.delta)"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if toast.isPowerHour {
                    Text(tr("shared.power_hour"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            if let reason = toast.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, toast.reason == nil ? 10 : 8)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: toast.isPowerHour
                        ? [Color.accentOrange, Color.brand]
                        : [Color.brand, Color.brand.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: Color.accentOrange.opacity(0.32), radius: 12, y: 4)
        .scaleEffect(visible ? 1.0 : 0.85)
        .opacity(visible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                visible = true
            }
        }
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                visible = false
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onDismiss()
        }
    }
}

// MARK: - Info-Toast (Anti-Farm-Feedback)
//
// Negativ-Variante des PointsToast: zeigt KEINE Punkte-Zahl, sondern
// einen kurzen Hinweis warum gerade nichts vergeben wurde
// ("Drop zu kurz", "12 h Cooldown"). Eigenes Styling (neutral grau-blau
// statt Brand-Orange) damit der User es sofort als „kein Gewinn"
// einordnet. Auto-Dismiss erfolgt im Store über asyncAfter — die View
// rendert nur solange `store.infoToast != nil`.
struct InfoToastView: View {
    let toast: AppStore.InfoToast

    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.22, blue: 0.28),
                        Color(red: 0.28, green: 0.30, blue: 0.36)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: Color.black.opacity(0.20), radius: 10, y: 3)
        .scaleEffect(visible ? 1.0 : 0.9)
        .opacity(visible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                visible = true
            }
        }
    }
}

// MARK: - Leave-Drop Sheet (Joiner verlässt einen Drop)
//
// Visuell und vom Aufbau angelehnt an HomeZoneWarningSheet — wir wollen
// nicht dass der User aus Versehen einen Drop verlässt und seine
// Reliability-Punkte verliert. Klares Wording, primärer Bleiben-Button,
// destruktiver Verlassen-Button als Sekundär-Aktion.
struct LeaveDropSheet: View {
    let activityEmoji: String
    let activityName: String
    /// Sekunden seit Beitritt — entscheidet ob ein No-Show-Risiko besteht
    /// (nach 12 min wird Verlassen als Score-Abzug gewertet).
    let elapsedSeconds: TimeInterval
    let onLeave: () -> Void
    let onCancel: () -> Void

    @State private var pulse = false

    /// 12-Min-Schwelle = "kritischer Bereich" mit Score-Risiko.
    private var hasScoreRisk: Bool { elapsedSeconds >= 12 * 60 }

    var body: some View {
        VStack(spacing: 22) {
            // Mehr Top-Spacing damit der pulsierende Kreis nicht den Drag-
            // Indicator des Sheets überlappt — die Animation skaliert bis
            // 1.05× und schluckt sonst die obere Sheet-Kante.
            Spacer(minLength: 28)

            // Visual: pulsierender Ausgang. Tür-Symbol passt semantisch
            // besser als "figure.walk.departure" — "ich gehe durch die Tür".
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: hasScoreRisk
                                ? [Color.accentRed.opacity(0.22), Color.accentOrange.opacity(0.14)]
                                : [Color.accentOrange.opacity(0.22), Color.brand.opacity(0.14)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.05 : 0.96)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(hasScoreRisk ? .accentRed : .accentOrange)
                    .shadow(color: (hasScoreRisk ? Color.accentRed : Color.accentOrange).opacity(0.4), radius: 10)
            }
            // 110 × 1.05 = 115.5pt max — 130pt Frame gibt Puffer, kein .clipped()
            .frame(width: 130, height: 130)

            VStack(spacing: 8) {
                Text(tr("shared.leave_drop_q"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(activityEmoji) \(activityName)")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            // Konkrete Hinweis-Liste — Inhalt abhängig von der Dauer
            VStack(spacing: 12) {
                if hasScoreRisk {
                    infoRow(
                        icon: "exclamationmark.triangle.fill",
                        tint: .accentRed,
                        text: tr("shared.no_show_warning")
                    )
                } else {
                    infoRow(
                        icon: "checkmark.shield.fill",
                        tint: .onlineGreen,
                        text: tr("shared.under_12min_safe")
                    )
                }
                infoRow(
                    icon: "person.fill.questionmark",
                    tint: .accentOrange,
                    text: tr("shared.host_will_see_left")
                )
                infoRow(
                    icon: "clock.arrow.circlepath",
                    tint: .brand,
                    text: tr("shared.cooldown_10min")
                )
            }
            .padding(.horizontal, 22)

            Spacer()

            // Aktionen — Hierarchie matched Apple HIG: User hat das Sheet
            // geöffnet weil er verlassen WILL → destructive primary, cancel
            // als sekundärer Text-Link. Konsistent zum EndDropSheet.
            VStack(spacing: 10) {
                // Primary: Drop verlassen — solid rot mit weißem Text
                Button(action: onLeave) {
                    HStack(spacing: 8) {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 14, weight: .bold))
                        Text(tr("shared.leave_drop"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.accentRed)
                    )
                    .shadow(color: Color.accentRed.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)

                // Secondary: Dabei bleiben — Text-Link in Grau
                Button(action: onCancel) {
                    Text(tr("shared.stay_in"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - End-Drop Sheet (Host beendet seinen eigenen Drop)
//
// Gleiches Design-Pattern wie LeaveDropSheet, aber Host-Perspektive:
// klare Konsequenzen + primärer Weiter-Button damit der Host nicht aus
// Versehen einen laufenden Drop killt während Joiner unterwegs sind.
struct EndDropSheet: View {
    let activityEmoji: String
    let activityName: String
    let participantCount: Int
    /// Sekunden seit Drop-Erstellung — ≥ 15 min = Punkte werden vergeben.
    let elapsedSeconds: TimeInterval
    let onEnd: () -> Void
    let onCancel: () -> Void

    /// 3 versetzte Ring-Wellen für eine "Stopp"-Pulsation. Phase-shift
    /// erzeugt einen Wellen-Effekt — wirkt energetischer als ein einfacher
    /// Pulse und unterstreicht den destruktiven Charakter der Aktion.
    @State private var ring0 = false
    @State private var ring1 = false
    @State private var ring2 = false
    /// Subtle Icon-Beat im Takt der ersten Welle.
    @State private var iconBeat = false

    private var qualifiesForPoints: Bool { elapsedSeconds >= 15 * 60 }
    private var hasOthers: Bool { participantCount >= 2 }

    var body: some View {
        // ScrollView damit auf kleinen Devices (iPhone SE) der Content
        // nicht abgeschnitten wird. Buttons sind Pinned am Bottom außerhalb
        // der ScrollView, sonst muss der User scrollen um zu beenden.
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                contentBlock
            }
            actionButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Drei zeitversetzte Ring-Wellen erzeugen einen Sirenen-Effekt.
            // Jede Welle dauert 1.8s und repeatet forever; Stagger 0.6s.
            let dur: Double = 1.8
            withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                ring0 = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                    ring1 = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: dur).repeatForever(autoreverses: false)) {
                    ring2 = true
                }
            }
            // Icon-Beat synchron zum ersten Ring — Spring sorgt für lebendige
            // Pulsation statt mechanischem Skalieren.
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.55)
                    .repeatForever(autoreverses: true)
            ) {
                iconBeat = true
            }
        }
    }

    /// Scrollbarer Content-Block: Visual + Header + Info-Rows.
    /// Kompakt gehalten damit das Sheet bei `.fraction(0.62)` ohne
    /// Scrolling auskommt. Buttons sind außerhalb der ScrollView pinned
    /// (siehe body). Falls iPhone SE / Display-Zoom doch nicht reicht,
    /// kann der User scrollen.
    @ViewBuilder
    private var contentBlock: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)

            ZStack {
                radarRing(scale: ring0 ? 1.5 : 0.9, opacity: ring0 ? 0.0 : 0.45)
                radarRing(scale: ring1 ? 1.5 : 0.9, opacity: ring1 ? 0.0 : 0.45)
                radarRing(scale: ring2 ? 1.5 : 0.9, opacity: ring2 ? 0.0 : 0.45)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentRed.opacity(0.30),
                                     Color.accentOrange.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.accentRed.opacity(0.35), radius: 12, y: 4)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.accentRed)
                    .shadow(color: Color.accentRed.opacity(0.5), radius: 8)
                    .scaleEffect(iconBeat ? 1.08 : 1.0)
            }
            // Frame muss die Ringe bei Max-Scale (1.5 × 110 = 165pt) aufnehmen.
            // Kein .clipped() — die Ringe faden gegen opacity 0, bevor sie
            // den Rand des Frames erreichen; ein Clip würde sie sichtbar
            // abschneiden wie auf dem Screenshot zu sehen war.
            .frame(width: 170, height: 170)

            VStack(spacing: 2) {
                Text(tr("shared.end_drop_q"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(activityEmoji) \(activityName)")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            VStack(spacing: 6) {
                if hasOthers {
                    infoRow(
                        icon: "person.2.fill",
                        tint: .accentOrange,
                        text: (participantCount - 1 == 1
                               ? tr("shared.participants_notified_singular")
                               : tr("shared.participants_notified_plural")).replacingOccurrences(of: "{count}", with: "\(participantCount - 1)")
                    )
                } else {
                    infoRow(
                        icon: "person.crop.circle.badge.xmark",
                        tint: .textTertiary,
                        text: tr("shared.no_participants_yet")
                    )
                }
                if qualifiesForPoints && hasOthers {
                    infoRow(
                        icon: "sparkles",
                        tint: .onlineGreen,
                        text: tr("shared.host_points_awarded")
                    )
                } else if !qualifiesForPoints && hasOthers {
                    infoRow(
                        icon: "hourglass",
                        tint: .accentOrange,
                        text: tr("shared.only_x_min_no_points").replacingOccurrences(of: "{mins}", with: "\(Int(elapsedSeconds / 60))")
                    )
                }
                infoRow(
                    icon: "map",
                    tint: .brand,
                    text: tr("shared.drop_disappears")
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    /// Action-Buttons unten am Sheet — bleiben außerhalb der ScrollView
    /// damit der User immer beenden/cancel kann ohne erst scrollen zu müssen.
    /// Hierarchie matched HIG: destructive Aktion (Beenden) prominent rot,
    /// Cancel (Weiterlaufen) sekundär als Text-Link. Der User hat das Sheet
    /// ja eröffnet weil er beenden WILL — der Primary-CTA muss das matchen.
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Primary: Destructive Aktion — solid rot mit weißem Text.
            Button(action: onEnd) {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("shared.end_drop"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(Color.accentRed)
                )
                .shadow(color: Color.accentRed.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            // Secondary: Cancel — Text-Link, kein Background, leicht zurückhaltend.
            Button(action: onCancel) {
                Text(tr("shared.keep_running"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    /// Einzelner expandierender Warnring — frame-basierte Animation statt scaleEffect.
    /// scaleEffect ändert nur die visuelle Darstellung, nicht den Layout-Frame:
    /// ScrollView clippt am Layout-Rand und schneidet Ringe ab (Bug).
    /// Mit .frame(size) wächst der tatsächliche Layout-Frame mit → kein Clip.
    @ViewBuilder
    private func radarRing(scale: CGFloat, opacity: Double) -> some View {
        let size: CGFloat = 110 * scale
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.accentRed, Color.accentOrange],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 2.5
            )
            .frame(width: size, height: size)
            .opacity(opacity)
    }

    @ViewBuilder
    private func infoRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Drop-Feedback Sheet
//
// Erscheint nach Drop-Ende (für Host nach `cancelDrop`, für Joiner nach
// `leaveActiveJoin` mit Session ≥ 5 min). Zeigt pro Mit-Teilnehmer eine
// Zeile mit 👍/👎. User kann pro Person voten oder einfach "Überspringen"
// drücken — Datenschutz: nichts ist Pflicht.
struct DropFeedbackSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let prompt: AppStore.DropFeedbackPrompt

    /// votes[targetUID] = "up" | "down" | nil (= unentschieden / skip)
    @State private var votes: [String: String] = [:]
    @State private var submitted: Bool = false

    private var headline: String {
        prompt.wasHostMyself ? tr("shared.how_were_guests") : tr("shared.how_was_host")
    }

    private var subline: String {
        "\(prompt.dropEmoji) \(prompt.dropActivity)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(headline)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(subline)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            .padding(.top, 22).padding(.bottom, 22)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(prompt.targets) { target in
                        feedbackRow(for: target)
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(maxHeight: 320)

            Spacer(minLength: 12)

            // Buttons
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text(tr("shared.skip"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Button {
                    submitAll()
                } label: {
                    HStack(spacing: 6) {
                        if submitted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text(submitted ? "Danke!" : "Senden")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(votes.isEmpty ? Color.textTertiary : Color.brand)
                            .shadow(color: Color.brand.opacity(0.3), radius: 10, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(votes.isEmpty || submitted)
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func feedbackRow(for target: AppStore.FeedbackTarget) -> some View {
        let currentVote = votes[target.id]
        HStack(spacing: 12) {
            // Avatar
            if let url = target.profileImageURL, !url.isEmpty {
                RemoteProfileImage(url: url, fallbackEmoji: target.emoji,
                                   size: 44, strokeColor: .clear)
            } else {
                Circle()
                    .fill(Color.brand.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(Text(target.emoji).font(.system(size: 22)))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(target.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    if target.wasHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentOrange)
                    }
                }
                Text(target.wasHost ? "Host" : "Teilnehmer")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                voteButton(systemImage: "hand.thumbsdown.fill",
                           selected: currentVote == "down",
                           tint: .accentRed) {
                    votes[target.id] = currentVote == "down" ? nil : "down"
                }
                voteButton(systemImage: "hand.thumbsup.fill",
                           selected: currentVote == "up",
                           tint: .onlineGreen) {
                    votes[target.id] = currentVote == "up" ? nil : "up"
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: Radius.card))
    }

    @ViewBuilder
    private func voteButton(systemImage: String, selected: Bool,
                            tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(selected ? .white : tint.opacity(0.6))
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(selected ? tint : tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }

    private func submitAll() {
        guard !submitted else { return }
        for (uid, vote) in votes {
            store.submitFeedbackVote(ratedUID: uid, dropID: prompt.dropID, vote: vote)
        }
        withAnimation(.spring(response: 0.3)) { submitted = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
    }
}

// MARK: - Drop Success Share Sheet

struct DropSuccessShareSheet: View {
    let data: AppStore.DropSuccessShareData
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var rendered = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(Color(UIColor.tertiaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Vorschau der Share-Card
            DropShareCardView(data: data)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .padding(.horizontal, 32)
                .scaleEffect(rendered ? 1 : 0.92)
                .opacity(rendered ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: rendered)

            Spacer(minLength: 24)

            // Buttons
            VStack(spacing: 12) {
                Button {
                    renderAndShare()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text(tr("shared.share_story"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }

                Button(tr("shared.skip")) { dismiss() }
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            withAnimation { rendered = true }
            // Image vorab rendern
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shareImage = renderCard()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(items: [img])
            }
        }
    }

    private func renderAndShare() {
        if let img = shareImage {
            presentShareSheet(img)
        } else if let img = renderCard() {
            presentShareSheet(img)
        }
    }

    @MainActor
    private func renderCard() -> UIImage? {
        let card = DropShareCardView(data: data).frame(width: 390, height: 390)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func presentShareSheet(_ image: UIImage) {
        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
}

// MARK: - Drop Share Card View (wird via ImageRenderer als Bild gerendert)

struct DropShareCardView: View {
    let data: AppStore.DropSuccessShareData

    private var headline: String {
        data.wasHost ? "Ich hab's gedropt! 🎉" : "Ich war dabei! 🎉"
    }
    private var sub: String {
        data.wasHost ? "Heute spontan jemanden getroffen" : "Spontan zugesagt — und hingegangen"
    }

    var body: some View {
        ZStack {
            // Hintergrund-Gradient
            LinearGradient(
                colors: [Color(hex: "0D0D0D"), Color(hex: "1A1A1A")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Aurora-Glow
            Circle()
                .fill(Color.auroraOrange.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -60, y: -60)
            Circle()
                .fill(Color.auroraGreen.opacity(0.25))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 80, y: 80)

            VStack(spacing: 0) {
                Spacer()

                // Emoji
                Text(data.activityEmoji)
                    .font(.system(size: 80))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Spacer().frame(height: 16)

                // Aktivität
                Text(data.activityName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer().frame(height: 8)

                // Headline
                Text(headline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))

                Spacer().frame(height: 6)

                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))

                Spacer()

                // Branding
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 20, height: 20)
                    Text("Drops · drops-app.de")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// ShareSheet ist in LiveMapView.swift definiert (projektweite Nutzung)

// MARK: - Activity Category (shared: Map + Feed + CreateDrop)

struct ActivityCategory {
    let key: String
    let icon: String          // SF Symbol
    let emoji: String         // Repräsentatives Emoji für CreateDrop-Chips
    let dropEmojis: [String]  // Alle Emojis die zu dieser Kategorie matchen
    let keywords: [String]    // Keywords die gegen activityName matchen

    static let all: [ActivityCategory] = [
        ActivityCategory(
            key: "Kaffee", icon: "cup.and.saucer.fill", emoji: "☕️",
            dropEmojis: ["☕️", "☕", "🧋", "🍵", "🥐"],
            keywords: ["kaffee", "coffee", "café", "cafe", "espresso", "latte"]
        ),
        ActivityCategory(
            key: "Drink", icon: "wineglass", emoji: "🍺",
            dropEmojis: ["🍺", "🍻", "🍷", "🥂", "🍹", "🍸"],
            keywords: ["drink", "drinks", "bier", "beer", "wein", "wine",
                       "cocktail", "bar", "feierabend", "club", "party", "ausgehen"]
        ),
        ActivityCategory(
            key: "Sport", icon: "figure.run", emoji: "🏃",
            dropEmojis: ["🏃", "🏃‍♂️", "🏃‍♀️", "🏋️", "🧘", "⚽️", "🎾", "🏀", "🚴"],
            keywords: ["sport", "fitness", "gym", "laufen", "run", "joggen",
                       "jog", "fußball", "tennis", "basketball", "yoga", "fahrrad", "bike"]
        ),
        ActivityCategory(
            key: "Essen", icon: "fork.knife", emoji: "🍕",
            dropEmojis: ["🍕", "🍔", "🍣", "🍱", "🍜", "🌮", "🥗"],
            keywords: ["essen", "food", "lunch", "dinner", "pizza", "burger",
                       "restaurant", "brunch", "sushi", "dönner"]
        ),
        ActivityCategory(
            key: "Zocken", icon: "gamecontroller.fill", emoji: "🎮",
            dropEmojis: ["🎮", "🕹️"],
            keywords: ["zocken", "zock", "gaming", "game", "games", "spielen",
                       "xbox", "playstation"]
        )
    ]

    func matches(emoji dropEmoji: String, activity: String) -> Bool {
        if dropEmojis.contains(dropEmoji) { return true }
        let lower = activity.lowercased()
        return keywords.contains(where: { lower.contains($0) })
    }

    /// Prüft ob ein Drop zum aktiven Filter passt. Leerer Filter = alles sichtbar.
    static func matches(filter: String, emoji: String, activity: String) -> Bool {
        guard !filter.isEmpty else { return true }
        guard let cat = all.first(where: { $0.key == filter }) else { return true }
        return cat.matches(emoji: emoji, activity: activity)
    }
}

// MARK: - Shared Activity Filter Chips (Map + Feed)

struct ActivityFilterChipsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Alle", icon: "square.grid.2x2.fill",
                     selected: store.activityCategoryFilter.isEmpty) {
                    store.activityCategoryFilter = ""
                    store.saveAll()
                }
                ForEach(ActivityCategory.all, id: \.key) { cat in
                    chip(title: cat.key, icon: cat.icon,
                         selected: store.activityCategoryFilter == cat.key) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            store.activityCategoryFilter =
                                (store.activityCategoryFilter == cat.key) ? "" : cat.key
                        }
                        store.saveAll()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(title: String, icon: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .brand)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
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
}
