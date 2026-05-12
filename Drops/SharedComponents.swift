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
                            .fill(Color(hex: "E48C3A").opacity((light ? 0.74 : 0.58) * (1 + Self.pulseBoost * p0)))
                            .frame(width: 520 * (1 + 0.06 * p0))
                            .offset(x: a ? -130 : -80, y: a ? -370 : -320)
                            .blur(radius: 90)
                        // Kreis 2 — Soft Rose/Pink (top-right) — warmer
                        // Sunset-Hauch, bricht das reine Orange auf
                        Circle()
                            .fill(Color(hex: "F08FA3").opacity((light ? 0.58 : 0.46) * (1 + Self.pulseBoost * p1)))
                            .frame(width: 460 * (1 + 0.06 * p1))
                            .offset(x: a ? 160 : 110, y: a ? -350 : -300)
                            .blur(radius: 85)
                        // Kreis 3 — Grün (bottom-left, dominant) wie Icon-Bottom
                        Circle()
                            .fill(Color(hex: "5FA937").opacity((light ? 0.60 : 0.46) * (1 + Self.pulseBoost * p2)))
                            .frame(width: 420 * (1 + 0.06 * p2))
                            .offset(x: a ? -150 : -100, y: a ? 420 : 370)
                            .blur(radius: 80)
                        // Kreis 4 — Soft Lavender (bottom-right) — kühler
                        // Aurora-Akzent, balanciert das warme Top-Drittel
                        Circle()
                            .fill(Color(hex: "B49BE0").opacity((light ? 0.50 : 0.40) * (1 + Self.pulseBoost * p3)))
                            .frame(width: 380 * (1 + 0.06 * p3))
                            .offset(x: a ? 140 : 90, y: a ? 400 : 350)
                            .blur(radius: 75)
                        // Kreis 5 — Warm Gold (center) — Sun-Glow als
                        // weiche Übergangsfarbe zwischen Orange-Top und
                        // Grün-Bottom. Setzt die Mitte „in Licht".
                        Circle()
                            .fill(Color(hex: "F6BD4D").opacity((light ? 0.44 : 0.32) * (1 + Self.pulseBoost * p4)))
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
                            colors: [Color(hex: "E48C3A"), Color(hex: "F08FA3")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Push aktivieren")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Ohne Push verpasst du Anfragen und Drop-Updates. Tippe um zu aktivieren.")
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "E48C3A").opacity(0.3), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            // iOS-Einstellungen für die App öffnen — Apple erlaubt keinen
            // zweiten Permission-Dialog programmatisch nach „Denied".
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
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
    @State private var pulse0 = false
    @State private var pulse1 = false
    @State private var pulse2 = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Drei Sunset-getönte Radar-Ringe (matched zum App-Icon
                // und dem Hero im Onboarding). Vorher: 3× Color.brand =
                // legacy Apple-Grün, inkonsistent mit dem Rest der App.
                Circle()
                    .stroke(Color(hex: "E48C3A").opacity(0.16), lineWidth: 1)
                    .frame(width: 116, height: 116)
                    .scaleEffect(pulse0 ? 1.06 : 0.96)
                Circle()
                    .stroke(Color(hex: "E48C3A").opacity(0.10), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse1 ? 1.05 : 0.97)
                Circle()
                    .stroke(Color(hex: "5FA937").opacity(0.08), lineWidth: 1)
                    .frame(width: 204, height: 204)
                    .scaleEffect(pulse2 ? 1.04 : 0.97)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "E48C3A").opacity(0.18),
                                         Color(hex: "5FA937").opacity(0.14)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .frame(width: 180, height: 180)

            VStack(spacing: 6) {
                Text("Noch ist hier nichts los")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Sei der erste der was startet —\nSpaziergang, Kaffee, Sport. Wer in der Nähe ist, sieht's sofort.")
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
                             ? "+\(boostBonus) Punkte Power-Hour Bonus"
                             : "+\(boostBonus) Punkte Bonus für deinen Drop")
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
                        Text("Drop erstellen")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color(hex: "E48C3A").opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
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
    /// Optionaler Tap-Handler für „Aus Kontakten hinzufügen". Wenn gesetzt
    /// wird der Button gerendert. Falls die Parent-View den Flow nicht
    /// braucht (z.B. Settings-Section ohne diesen Aktion), kann sie nil
    /// übergeben und der Button erscheint nicht.
    var onAddFromContacts: (() -> Void)? = nil
    var onShareInvite: (() -> Void)? = nil

    @State private var pulse0 = false
    @State private var pulse1 = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 20) {
            // Icon-Stack — neue Sunset-Palette (Orange dominant) statt
            // purple, damit's mit dem App-Icon und den Tab-Headern matched.
            // person.2.fill ist semantisch positiver als person.2.slash —
            // signalisiert "Freunde finden" statt "keine Freunde".
            ZStack {
                Circle()
                    .stroke(Color(hex: "E48C3A").opacity(0.18), lineWidth: 1)
                    .frame(width: 116, height: 116)
                    .scaleEffect(pulse0 ? 1.06 : 0.96)
                Circle()
                    .stroke(Color(hex: "E48C3A").opacity(0.10), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse1 ? 1.05 : 0.97)
                ZStack {
                    Circle()
                        .fill(Color(hex: "E48C3A").opacity(0.16))
                        .frame(width: 72, height: 72)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(Color(hex: "E48C3A"))
                }
            }
            .frame(width: 180, height: 160)

            VStack(spacing: 6) {
                Text("Noch keine Freunde")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Triff jemanden bei einem Drop oder lade Freunde direkt ein — so entstehen die ersten Verbindungen.")
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
                                Text("Aus Kontakten hinzufügen")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: Color(hex: "E48C3A").opacity(0.35), radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                    if let share = onShareInvite {
                        Button(action: share) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Einladungslink teilen")
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
        // www-Subdomain nutzen — Apex 307-redirected zu www, Apple Universal
        // Links akzeptieren keine Redirects (siehe LiveMapView).
        let deepLink = "https://www.drops-app.de/drop/\(item.id.uuidString)"
        let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
        let text = "\(item.emoji) \(item.activity)\(location) — komm vorbei. Spontan, vor Ort, kein Smalltalk. 👋"
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
            return [Color(hex: "ec4899"), Color(hex: "06b6d4"),
                    Color(hex: "fbbf24"), Color(hex: "a855f7")]
        case .aurora:
            // Neue Icon-Palette: warmes Orange → Coral → frisches Grün.
            // Direkt aus icon.json abgeleitet damit das Profil-Hero
            // dieselbe Brand-Identity hat wie Login + App-Icon.
            return [Color(hex: "E48C3A"), Color(hex: "F4956A"), Color(hex: "5FA937")]
        case .sunset:
            return [Color(hex: "fb923c"), Color(hex: "ec4899"), Color(hex: "8b5cf6")]
        case .ocean:
            return [Color(hex: "0ea5e9"), Color(hex: "06b6d4"), Color(hex: "14b8a6")]
        case .forest:
            return [Color(hex: "166534"), Color(hex: "65a30d"), Color(hex: "facc15")]
        case .neon:
            return [Color(hex: "ec4899"), Color(hex: "f59e0b"), Color(hex: "06b6d4")]
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
                    Text("Wähle einen Hintergrund für deine Profil-Karte. Wechselbar jederzeit.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28).padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(ProfileHeroTemplate.allCases) { tpl in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selection = tpl
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(tpl.gradient)
                                        .frame(height: 110)
                                        .overlay(alignment: .topTrailing) {
                                            // Exklusiv-Marker für Tester-Variante
                                            if tpl.isExclusive {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "sparkle")
                                                        .font(.system(size: 7, weight: .bold))
                                                    Text("BETA")
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
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .navigationTitle("Hintergrund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
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
            Text("BETA")
                .font(.system(size: 9, weight: .bold))
                .kerning(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            LinearGradient(
                colors: [Color.brand, Color(hex: "06b6d4")],
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
        case .startingSoon: return "Power-Hour in \(mins)"
        case .running:      return "Power-Hour läuft · noch \(mins)"
        case .endingSoon:   return "Power-Hour endet in \(mins)"
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
                                colors: [Color(hex: "E48C3A").opacity(0.30),
                                         Color(hex: "5FA937").opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: Color(hex: "E48C3A").opacity(0.40), radius: 18, y: 6)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "E48C3A").opacity(0.50), radius: 10)
                        .scaleEffect(iconBeat ? 1.08 : 1.0)
                }
                .frame(height: 140)

                VStack(spacing: 10) {
                    Text("Update erforderlich")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    Text("Drops braucht jetzt Version \(requiredVersion) oder neuer.")
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
                    Text("Du nutzt \(store.currentAppVersion)")
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
                        Text("Im App Store öffnen")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color(hex: "E48C3A").opacity(0.35), radius: 12, y: 4)
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

    /// Einzelner Radar-Ring — fadet von 0.55 → 0.0 während er von 0.95×
    /// auf 1.7× skaliert. Gestaffelt mit 0.65s-Versatz.
    @ViewBuilder
    private func radarRing(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 2.5
            )
            .frame(width: 96, height: 96)
            .scaleEffect(scale)
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
                Text("Update verfügbar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Version \(recVersion) im App Store")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button(action: openAppStore) {
                Text("Jetzt")
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
            .accessibilityLabel("Banner schließen")
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
                    .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("Drop in deiner Heimzone")
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
                        Text("Du startest gerade einen Drop nahe deinem Zuhause.")
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
                            text: "Andere können auf der Karte ungefähr sehen wo du wohnst — solange der Drop läuft."
                        )
                        warningRow(
                            icon: "person.fill",
                            text: "Treffe lieber an einem öffentlichen Ort: Café, Park, Platz."
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
                    Text("Anderen Ort wählen")
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
                    Text("Trotzdem hier starten")
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
            RoundedRectangle(cornerRadius: 14)
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
        default:             return "Hinweis vom Drops-Team"
        }
    }

    private var body1: String {
        switch notice.type {
        case "drop_removed":
            return "Ein Admin hat deinen Drop von der Karte genommen."
        default:
            return "Bitte beachte den folgenden Hinweis."
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
                            Text("Begründung")
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
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentRed.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentRed.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Sekundär-Hinweis
                    Text("Wenn du Fragen hast, kontaktiere uns über Profil → Support.")
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
                Text("Verstanden")
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
                Text("Neu: Power-Hour")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Zu festen Zeiten gibt's +\(AppStore.powerHourBonus) statt +\(AppStore.boostBonus) Punkte für jeden Drop, den du erstellst oder triffst.")
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 22)

            Spacer()

            Button(action: onDismiss) {
                Text("Verstanden")
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
                Text("+\(toast.delta) Punkte")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if toast.isPowerHour {
                    Text("Power-Hour")
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

            VStack(spacing: 8) {
                Text("Drop wirklich verlassen?")
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
                        text: "Du bist seit ≥ 12 min dabei — der Host wartet wahrscheinlich schon. Verlassen zählt jetzt als No-Show (Score-Abzug)."
                    )
                } else {
                    infoRow(
                        icon: "checkmark.shield.fill",
                        tint: .onlineGreen,
                        text: "Noch unter 12 min — Verlassen wirkt sich nicht negativ auf deinen Score aus."
                    )
                }
                infoRow(
                    icon: "person.fill.questionmark",
                    tint: .accentOrange,
                    text: "Der Host sieht dass du nicht mehr dabei bist."
                )
                infoRow(
                    icon: "clock.arrow.circlepath",
                    tint: .brand,
                    text: "10-Min-Cooldown: du kannst diesem Drop nicht sofort wieder beitreten."
                )
            }
            .padding(.horizontal, 22)

            Spacer()

            // Aktionen
            VStack(spacing: 10) {
                // Primär: dabei bleiben (sicherer Pfad)
                Button(action: onCancel) {
                    Text("Dabei bleiben")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.brand, Color.onlineGreen],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                        .shadow(color: Color.brand.opacity(0.30), radius: 10, y: 3)
                }
                .buttonStyle(.plain)

                // Sekundär (destruktiv): wirklich verlassen
                Button(action: onLeave) {
                    Text("Drop verlassen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
            RoundedRectangle(cornerRadius: 14)
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
            .frame(height: 92)

            VStack(spacing: 2) {
                Text("Drop beenden?")
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
                        text: "\(participantCount - 1) Teilnehmer \(participantCount - 1 == 1 ? "wird" : "werden") informiert."
                    )
                } else {
                    infoRow(
                        icon: "person.crop.circle.badge.xmark",
                        tint: .textTertiary,
                        text: "Noch keine Teilnehmer — Drop wird einfach geschlossen."
                    )
                }
                if qualifiesForPoints && hasOthers {
                    infoRow(
                        icon: "sparkles",
                        tint: .onlineGreen,
                        text: "Host-Punkte werden vergeben (≥ 15 min erfüllt)."
                    )
                } else if !qualifiesForPoints && hasOthers {
                    infoRow(
                        icon: "hourglass",
                        tint: .accentOrange,
                        text: "Erst seit \(Int(elapsedSeconds / 60)) min — unter 15 min keine Punkte."
                    )
                }
                infoRow(
                    icon: "map",
                    tint: .brand,
                    text: "Drop verschwindet sofort von der Karte."
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    /// Action-Buttons unten am Sheet — bleiben außerhalb der ScrollView
    /// damit der User immer beenden/cancel kann ohne erst scrollen zu müssen.
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Weiterlaufen lassen")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.brand, Color.accentOrange],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color.brand.opacity(0.30), radius: 8, y: 2)
            }
            .buttonStyle(.plain)

            Button(action: onEnd) {
                Text("Drop beenden")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    /// Einzelner expandierender Warnring — fadet von 0.45 → 0.0 während er
    /// von 0.9× auf 1.6× skaliert. Stack mehrerer Rings mit Stagger-Delay
    /// erzeugt den Sirenen-Effekt.
    @ViewBuilder
    private func radarRing(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.accentRed, Color.accentOrange],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 2.5
            )
            .frame(width: 110, height: 110)
            .scaleEffect(scale)
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
            RoundedRectangle(cornerRadius: 12)
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
        prompt.wasHostMyself ? "Wie waren deine Gäste?" : "Wie war der Host?"
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
                    Text("Überspringen")
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
                    in: RoundedRectangle(cornerRadius: 14))
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
