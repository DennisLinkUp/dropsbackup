import SwiftUI

// MARK: - Color Palette

extension Color {
    static let bgPrimary     = Color(UIColor.systemBackground)
    static let bgSecondary   = Color(UIColor.secondarySystemBackground)
    static let bgTertiary    = Color(UIColor.tertiarySystemBackground)
    static let brand         = Color(hex: "3FB852")
    static let brandInverse  = Color.white
    static let accentGreen   = Color(hex: "3FB852")
    static let accentRed     = Color(hex: "FF3B30")
    static let accentOrange  = Color(hex: "FF9500")
    static let textPrimary   = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary  = Color(UIColor.tertiaryLabel)
    static let textMuted     = Color(UIColor.quaternaryLabel)
    static let onlineGreen   = Color(hex: "34C759")
    /// Clero-Brand-Grün (hell, vibrant) — wird für Community-Drops & Community-
    /// Pins auf der Map verwendet, damit sie sich von normalen Drops abheben.
    static let cleroGreen    = Color(hex: "6FE85A")
    static let glassBorder   = Color(UIColor.separator)

    // Aurora-Palette — App-Icon-Anker (Orange/Grün) + häufige Akzente
    // (Amber für Boost, Gold für Drops+). Direkt-RGB statt Color(hex:),
    // damit die Tokens bei Hex→Token-Migrationen nicht durch replace_all
    // selbst zerschossen werden. Werte = exakte Umrechnung der Hexes.
    static let auroraOrange    = Color(red: 0.894, green: 0.549, blue: 0.227) // #E48C3A
    static let auroraGreen     = Color(red: 0.373, green: 0.663, blue: 0.216) // #5FA937
    static let auroraAmber     = Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
    static let auroraGoldLight = Color(red: 0.831, green: 0.627, blue: 0.090) // #d4a017
    static let auroraGoldDark  = Color(red: 0.659, green: 0.455, blue: 0.031) // #a87408
    // Erweiterte Aurora-Akzente — für Hintergründe, Badges, Hero-Gradients.
    // Alle als direkt-RGB damit Hex→Token-Replace sicher ist.
    static let auroraPink      = Color(red: 0.941, green: 0.608, blue: 0.639) // #F08FA3 (rose-glow)
    static let auroraViolet    = Color(red: 0.706, green: 0.608, blue: 0.878) // #B49BE0 (lavender)
    static let auroraCyan      = Color(red: 0.055, green: 0.714, blue: 0.831) // #0eb6d4 (cyan)
    static let auroraTeal      = Color(red: 0.082, green: 0.722, blue: 0.647) // #14b8a6 (teal)
    static let auroraBlue      = Color(red: 0.231, green: 0.510, blue: 0.965) // #3b82f6 (blue)
    static let auroraPurple    = Color(red: 0.659, green: 0.333, blue: 0.969) // #a855f7 (purple)
    static let auroraCoral     = Color(red: 0.957, green: 0.584, blue: 0.416) // #F4956A (peach-coral)

    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Radius Tokens
/// 3-stufige Eckenradius-Skala. Einheitlich in der gesamten App.
/// SM: Badges, Chips, Icons. MD: Cards, Rows, Sections. LG: Hero-Cards, Sheets.
enum Radius {
    static let sm: CGFloat   = 8   // kleine Chips, Tags
    static let md: CGFloat   = 12  // Input-Felder, Capsules
    static let card: CGFloat = 14  // Standard-Card-Radius
    static let lg: CGFloat   = 16  // Container, Sheets
    static let xl: CGFloat   = 20  // Hero-Elemente, große Sheets
}

// MARK: - Typography Scale
/// Semantische Font-Größen. Statt 25+ Magic Numbers überall dieselben 6 Stufen.
extension Font {
    static let dsCaption2 = Font.system(size: 10, weight: .regular)
    static let dsCaption  = Font.system(size: 12, weight: .regular)
    static let dsBody     = Font.system(size: 14, weight: .regular)
    static let dsBodySemi = Font.system(size: 15, weight: .semibold)
    static let dsHeadline = Font.system(size: 17, weight: .semibold)
    static let dsTitle    = Font.system(size: 20, weight: .bold, design: .rounded)
}

// MARK: - Shadow Presets
/// Dreistufiges Elevations-System. Ergibt konsistente Tiefe ohne Magic Numbers.
extension View {
    /// Elevation 1 — subtile Chips, Badges.
    func shadowSm(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.12), radius: 4, x: 0, y: 2)
    }
    /// Elevation 2 — Standard-Karten, Buttons.
    func shadowMd(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.14), radius: 8, x: 0, y: 3)
    }
    /// Elevation 3 — Hero-Elemente, Popovers.
    func shadowLg(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.18), radius: 16, x: 0, y: 6)
    }
    /// Aurora-Glow — Brand-Gradient-Buttons (grün/orange).
    func auroraGlow(active: Bool, color: Color = .brand) -> some View {
        self.shadow(color: active ? color.opacity(0.35) : .clear, radius: 10, x: 0, y: 4)
    }
}

// MARK: - Aurora Gradient Helper
extension LinearGradient {
    /// Standard-Aurora-Gradient (Orange → Grün) — für Primary-CTAs.
    static let aurora = LinearGradient(
        colors: [Color.auroraOrange, Color.auroraGreen],
        startPoint: .leading, endPoint: .trailing
    )
    /// Sunset-Variante (Orange → Pink) — für sekundäre Hero-Elemente.
    static let sunset = LinearGradient(
        colors: [Color.auroraOrange, Color.auroraPink],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - iOS 26 Glass Helpers

/// ViewModifier für `liquidGlass`. Wrapped als Modifier mit
/// @Environment(\.colorScheme), damit der iOS-26-`.glassEffect()`
/// zwingend neu gerendert wird, wenn der User die App-Darstellung
/// umschaltet. Vorher behielt der Glass-Block sein Hell-Material-
/// Rendering nach Wechsel auf Dunkel — `.id(colorScheme)` erzwingt
/// ein clean re-mount der Material-View.
private struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .id(scheme)
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.thinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.brand.opacity(0.04))
                    }
                    .shadow(color: Color.brand.opacity(0.08), radius: shadowRadius, x: 0, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.brand.opacity(0.25), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .id(scheme)
        }
    }
}

extension View {
    /// Applies Liquid Glass background — uses native .glassEffect() on iOS 26,
    /// falls back to ultraThinMaterial on earlier OS versions.
    func liquidGlass(cornerRadius: CGFloat = 18, shadowRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius))
    }

    /// Capsule Liquid Glass — for pill-shaped buttons/chips.
    @ViewBuilder
    func liquidGlassCapsule(shadowRadius: CGFloat = 10) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(in: Capsule())
        } else {
            self
                .background(
                    ZStack {
                        Capsule().fill(.thinMaterial)
                        Capsule().fill(Color.brand.opacity(0.04))
                    }
                    .shadow(color: Color.brand.opacity(0.06), radius: shadowRadius, x: 0, y: 4)
                )
                .overlay(
                    Capsule().stroke(
                        LinearGradient(
                            colors: [Color.brand.opacity(0.25), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    /// Circle Liquid Glass.
    @ViewBuilder
    func liquidGlassCircle(shadowRadius: CGFloat = 10) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(in: Circle())
        } else {
            self
                .background(
                    Circle().fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: shadowRadius, x: 0, y: 4)
                )
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    /// Sheet background — ultraThinMaterial für Frosted-Glass-Effekt,
    /// so die Karte dahinter leicht sichtbar bleibt.
    @ViewBuilder
    func sheetBackground() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(.ultraThinMaterial)
        } else {
            self
        }
    }
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    let content: Content
    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    var body: some View {
        content
            .liquidGlass(cornerRadius: cornerRadius)
    }
}

// MARK: - Primary Button (Brand Green, no glass)

// MARK: - Aurora Card Border

/// Animierter Aurora-Rand für Karten/Sections.
/// Gleiche Farbpalette und Geschwindigkeit wie der Aurora-Button.
struct AuroraCardBorder: View {
    var cornerRadius: CGFloat = 18
    var lineWidth: CGFloat = 1.5

    @State private var hue: Double = 0

    // Animierter Border — Palette aufs App-Icon abgestimmt: warmes Orange,
    // Coral-Übergang, frisches Grün, zusätzlicher Amber-Akzent. Loop endet
    // mit Orange (Start-Farbe), damit der Hue-Rotation-Cycle nahtlos läuft.
    private let gradient: AngularGradient = .init(
        colors: [
            Color.auroraOrange, Color.auroraCoral,
            Color.auroraGreen, Color(hex: "8FCC4F"),
            Color(hex: "F6BD4D"), Color.auroraOrange,
        ],
        center: .center
    )

    var body: some View {
        ZStack {
            // Weicher Glow (verschwommene breite Linie)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(gradient, lineWidth: lineWidth + 4)
                .hueRotation(.degrees(hue))
                .blur(radius: 5)
                .opacity(0.38)
            // Scharfe Mittellinie
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(gradient, lineWidth: lineWidth)
                .hueRotation(.degrees(hue))
                .opacity(0.65)
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                hue = 360
            }
        }
    }
}

// MARK: - Aurora Drop Button (animiert, kein Emoji)

struct AuroraDropButton: View {
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"

    @State private var hue: Double = 0

    var body: some View {
        Button(action: { guard isEnabled && !isLoading else { return }; action() }) {
            ZStack {
                // Subtiler Aurora-Gradient aufs App-Icon abgestimmt:
                // Orange → Coral → Grün → Orange (loop nahtlos). Vorher
                // grün/cyan/violet — neu warmer Sunset-Verlauf.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.auroraOrange.opacity(0.85),
                                Color.auroraCoral.opacity(0.85),
                                Color.auroraGreen.opacity(0.85),
                                Color.auroraOrange.opacity(0.85),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .hueRotation(.degrees(hue))
                    // Glas-Schimmer für Tiefe ohne zu viel Knall
                    .overlay(Capsule().fill(Color.white.opacity(0.08)))
                    // Glow auf Orange angepasst — passt zur Hauptfarbe
                    .shadow(color: Color.auroraOrange.opacity(0.30), radius: 12, x: 0, y: 4)

                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Drop starten")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(AuroraButtonStyle())
        .onAppear {
            // 8s Loop statt 5s — ruhiger, weniger aufdringlich
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                hue = 360
            }
        }
    }
}

private struct AuroraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if isLoading { ProgressView().tint(Color.brandInverse) }
                else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(Color.brandInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule()
                    .fill(Color.brand)
                    .shadow(color: Color.brand.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Button (Glass)

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .liquidGlass(cornerRadius: 50)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pulse Dot

struct PulseDot: View {
    var color: Color = .onlineGreen
    @State private var scale: CGFloat = 1.0
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 18, height: 18)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scale)
            Circle().fill(color).frame(width: 10, height: 10)
        }
        .onAppear { scale = 1.5 }
    }
}

// MARK: - Avatar Badge

struct AvatarBadge: View {
    let emoji: String
    var size: CGFloat = 44
    var isAvailable: Bool = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(Text(emoji).font(.system(size: size * 0.5)))
                .overlay(
                    Circle()
                        .stroke(isAvailable ? Color.onlineGreen : Color.clear, lineWidth: 2.5)
                        .padding(-2)
                )
            if isAvailable {
                Circle().fill(Color.onlineGreen)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .overlay(Circle().stroke(Color.bgPrimary, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.textTertiary)
            .kerning(0.8)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Activity Chip (Glass)

struct ActivityChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(isSelected ? Color.brandInverse : .textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(Color.brand)
                                .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 3)
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                )
                .overlay(
                    {
                        let borderStyle: AnyShapeStyle = isSelected
                            ? AnyShapeStyle(Color.clear)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.4), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                        return AnyView(
                            Capsule()
                                .stroke(borderStyle, lineWidth: 0.8)
                        )
                    }()
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}

// MARK: - Custom Switch (iOS 26 native Toggle)

struct CustomSwitch: View {
    let isOn: Bool
    let onToggle: () -> Void
    var body: some View {
        Toggle("", isOn: Binding(
            get: { isOn },
            set: { _ in onToggle() }
        ))
        .labelsHidden()
        .tint(Color.brand)
    }
}

// MARK: - Reliability Score

struct ReliabilityScore {
    var totalCommits: Int
    var showUps: Int
    var noShows: Int
    /// Zähler für Host-Erfolge (Drop gehostet und kam zustande — min. 1 Teilnehmer zusätzlich).
    var hostSuccesses: Int = 0
    /// Akkumulierte Bonus-Punkte.
    var streakBonusPoints: Int = 0       // +20 nach 5 Drops in Folge ohne No-Show
    var firstArrivalPoints: Int = 0      // +5 pro Mal als Erster vor Ort
    var dropInvitesPoints: Int = 0       // +5 pro Einladung die gejoint ist (Drop-Einladung)
    var newcomerHostPoints: Int = 0      // +3 pro neuem User (Drop-Entdecker) bei deinem Drop
    var appInvitesPoints: Int = 0        // +10 pro Freund der Drops neu installiert & onboarded hat
    var creationBonusPoints: Int = 0     // +5 für jeden erstellten Drop (Launch-Motivation)
    var boostBonusPoints: Int = 0        // +5 wenn Drop erstellt/bestätigt während Boost-Phase
                                          // (Umgebung leer: <5 Drops in der Nähe → extra Anreiz)
    /// Aktueller Show-Up-Streak (Anzahl Drops in Folge ohne No-Show).
    /// Jeder 5er-Block löst +20 Streak-Bonus aus; Counter läuft danach weiter (alle 5 erneut).
    var currentStreak: Int = 0
    var appLanguage: String = "de"

    // MARK: - Punktesystem (1.0.2 — höhere Werte für Launch-Phase)
    // Start 100 · Joinen+vor Ort +20 · Hosten+klappt +12 · No-Show -25
    // Boni: Streak +30, Erster +10, Drop-Einladung +10, Neuling-Host +5, App-Einladung +25
    static let startingPoints       = 100
    static let pointsPerShowUp      = 20
    static let pointsPerHostSuccess = 12
    static let pointsPerNoShow      = -25

    /// Gesamtpunktzahl — aus Ereignissen und Boni.
    /// showUps enthält historisch ALLE Anwesenheiten (Joiner + Host). hostSuccesses trennt
    /// die Host-Ankünfte raus damit sie korrekt mit 8 statt 15 Punkten verrechnet werden.
    var points: Int {
        let joinArrivals = max(0, showUps - hostSuccesses)
        return Self.startingPoints
            + joinArrivals * Self.pointsPerShowUp
            + hostSuccesses * Self.pointsPerHostSuccess
            + noShows * Self.pointsPerNoShow
            + bonusPoints
    }

    var bonusPoints: Int {
        streakBonusPoints + firstArrivalPoints + dropInvitesPoints + newcomerHostPoints + appInvitesPoints + creationBonusPoints + boostBonusPoints
    }

    /// Deckungsgleich mit badge — damit überall die gleiche Stufe erscheint.
    var label: String { badge }

    var color: Color {
        switch points {
        case ..<0:      return .accentRed
        case 0..<50:    return .accentOrange
        case 50..<200:  return Color.auroraAmber
        case 200..<500: return .onlineGreen
        default:        return .brand
        }
    }

    var badge: String {
        switch points {
        case ..<0:      return "Dropout"
        case 0..<50:    return "Neustart"
        case 50..<200:  return "Drop-Entdecker"
        case 200..<500: return "Stammgast"
        default:        return "Drop-Legende"
        }
    }

    /// SF-Symbol passend zum Tier.
    var badgeIcon: String {
        switch points {
        case ..<0:      return "exclamationmark.triangle.fill"
        case 0..<50:    return "leaf.fill"
        case 50..<200:  return "binoculars.fill"
        case 200..<500: return "star.fill"
        default:        return "crown.fill"
        }
    }

    /// Punktzahl als String fürs Hero-Label.
    var displayText: String { "\(points)" }

    /// Sekundär-Label.
    var displayLabel: String {
        totalCommits == 0 ? "Willkommen bei Drops" : badge
    }

    /// Wie viele Punkte bis zum nächsten Tier. nil = höchstes erreicht.
    var pointsToNextTier: Int? {
        switch points {
        case ..<0:      return -points
        case 0..<50:    return 50 - points
        case 50..<200:  return 200 - points
        case 200..<500: return 500 - points
        default:        return nil
        }
    }

    var nextTierName: String? {
        switch points {
        case ..<0:      return "Neustart"
        case 0..<50:    return "Drop-Entdecker"
        case 50..<200:  return "Stammgast"
        case 200..<500: return "Drop-Legende"
        default:        return nil
        }
    }

    /// Fortschritt (0–1) innerhalb des aktuellen Tiers bis zur nächsten Schwelle.
    var tierProgress: Double {
        switch points {
        case ..<0:      return 0
        case 0..<50:    return Double(points) / 50.0
        case 50..<200:  return Double(points - 50) / 150.0
        case 200..<500: return Double(points - 200) / 300.0
        default:        return 1.0
        }
    }

    // MARK: - Static helpers (ohne Event-Daten, nur aus Punktzahl)

    static func badge(forPoints points: Int) -> String {
        switch points {
        case ..<0:      return "Dropout"
        case 0..<50:    return "Neustart"
        case 50..<200:  return "Drop-Entdecker"
        case 200..<500: return "Stammgast"
        default:        return "Drop-Legende"
        }
    }

    static func color(forPoints points: Int) -> Color {
        switch points {
        case ..<0:      return .accentRed
        case 0..<50:    return .accentOrange
        case 50..<200:  return Color.auroraAmber
        case 200..<500: return .onlineGreen
        default:        return .brand
        }
    }

    static func badgeIcon(forPoints points: Int) -> String {
        switch points {
        case ..<0:      return "exclamationmark.triangle.fill"
        case 0..<50:    return "leaf.fill"
        case 50..<200:  return "binoculars.fill"
        case 200..<500: return "star.fill"
        default:        return "crown.fill"
        }
    }

    static func tierProgress(forPoints points: Int) -> Double {
        switch points {
        case ..<0:      return 0
        case 0..<50:    return Double(points) / 50.0
        case 50..<200:  return Double(points - 50) / 150.0
        case 200..<500: return Double(points - 200) / 300.0
        default:        return 1.0
        }
    }
}

struct ReliabilityBadgeView: View {
    let score: ReliabilityScore
    @AppStorage("appLanguage") private var appLanguage = "de"
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(score.color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: score.badgeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(score.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(score.badge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(score.points) Pkt · \(score.showUps) Drops")
                    .font(.system(size: 11)).foregroundColor(.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14, shadowRadius: 8)
    }
}

// MARK: - Safety Sheet

struct SafetySheetView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        NavigationView {
            ZStack {
                // Glass backdrop
                Color.clear.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Icon-Header
                        ZStack {
                            Circle()
                                .fill(Color.accentRed.opacity(0.12))
                                .frame(width: 60, height: 60)
                            Image(systemName: "shield.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.accentRed)
                        }
                        .padding(.top, 8)

                        VStack(spacing: 0) {
                            SafetyRow(icon: "star.circle.fill", color: .accentOrange,
                                      title: tr("design.reliability_score"),
                                      subtitle: tr("design.no_show_30"))
                            SafetyRow(icon: "hand.raised.circle.fill", color: .accentRed,
                                      title: tr("design.one_tap_block"),
                                      subtitle: tr("design.instant_no_explanation"))
                        }
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle(tr("settings.security"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.brand)
                }
            }
        }
        .presentationDetents([.fraction(0.65)])
        .sheetBackground()
    }
}

struct SafetyRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon).font(.system(size: 18))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().padding(.leading, 66)
        }
    }
}

// MARK: - Placeholder modifier

extension View {
    func placeholder<C: View>(when show: Bool, @ViewBuilder placeholder: () -> C) -> some View {
        ZStack(alignment: .center) {
            placeholder().opacity(show ? 1 : 0)
            self
        }
    }
}



// MARK: - Reliability Info Sheet (Premium Redesign)
// Modernes Layout: Hero-Punktekarte mit Gradient + Progress zur nächsten Stufe,
// Punkte-Events-Tabelle mit Werten, Bonus-Liste, Stufen-Übersicht, Stats.

struct ReliabilityInfoSheet: View {
    let score: ReliabilityScore
    @Environment(\.dismiss) private var dismiss
    @State private var animateProgress = false

    private let tiers: [(label: String, threshold: Int, color: Color, icon: String)] = [
        ("Dropout",         -999, .accentRed,              "exclamationmark.triangle.fill"),
        ("Neustart",         0,   .accentOrange,           "leaf.fill"),
        ("Drop-Entdecker",   50,  Color.auroraAmber,    "binoculars.fill"),
        ("Stammgast",        200, .onlineGreen,            "star.fill"),
        ("Drop-Legende",     500, .brand,                  "crown.fill"),
    ]

    private var currentTierIndex: Int {
        tiers.indices.last(where: { score.points >= tiers[$0].threshold }) ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    progressCard
                    pointsEventsCard
                    bonusCard
                    tiersCard
                    statsRow
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(tr("design.reliability"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("design.done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { animateProgress = true } }
        .presentationDragIndicator(.visible)
    }

    // MARK: Hero — Punkte, Tier-Icon, Gradient-Karte

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(score.color.opacity(0.14)).frame(width: 62, height: 62)
                Image(systemName: score.badgeIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(score.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(score.badge)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(score.points)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(score.color)
                    Text(tr("design.points_short"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Fortschritt zur nächsten Stufe

    @ViewBuilder private var progressCard: some View {
        if let remaining = score.pointsToNextTier, let next = score.nextTierName {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("design.pts_until_next").replacingOccurrences(of: "{pts}", with: "\(remaining)").replacingOccurrences(of: "{next}", with: next))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.textTertiary.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(score.color)
                            .frame(width: geo.size.width * (animateProgress ? CGFloat(score.tierProgress) : 0),
                                   height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.lg))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill").foregroundColor(.brand)
                Text(tr("design.top_tier_reached"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    // MARK: Punkte-Events

    private var pointsEventsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("So sammelst du Punkte")
            VStack(spacing: 0) {
                eventRow(icon: "figure.walk.circle.fill", color: .onlineGreen,
                         title: "Drop beitreten + vor Ort", value: "+20")
                Divider().padding(.leading, 56)
                eventRow(icon: "plus.circle.fill", color: Color(hex: "06b6d4"),
                         title: "Drop hosten + kommt zustande", value: "+12")
                Divider().padding(.leading, 56)
                eventRow(icon: "xmark.circle.fill", color: .accentRed,
                         title: "No-Show (nicht erschienen)", value: "-25",
                         negative: true)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Boni

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Extras & Boni")
            VStack(spacing: 0) {
                eventRow(icon: "flame.fill", color: .accentOrange,
                         title: "5× in Folge ohne No-Show", value: "+30")
                Divider().padding(.leading, 56)
                eventRow(icon: "bolt.fill", color: Color.auroraAmber,
                         title: "Als Erster vor Ort", value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "paperplane.fill", color: .brand,
                         title: "Eingeladener joint deinen Drop", value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "sparkles", color: Color(hex: "8b5cf6"),
                         title: "Neuling bei deinem Drop", value: "+5")
                Divider().padding(.leading, 56)
                eventRow(icon: "person.badge.plus.fill", color: Color(hex: "ec4899"),
                         title: "Freund installiert Drops neu", value: "+25")
                Divider().padding(.leading, 56)
                eventRow(icon: "plus.app.fill", color: Color(hex: "10b981"),
                         title: "Drop erstellen (egal ob's klappt)", value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "bolt.circle.fill", color: .accentOrange,
                         title: "Aktion in Boost-Phase (Umgebung leer)", value: "+15")
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Stufen

    private var tiersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Stufen")
            VStack(spacing: 0) {
                ForEach(tiers.indices, id: \.self) { i in
                    let tier = tiers[i]
                    let isNow = i == currentTierIndex
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tier.color.opacity(isNow ? 0.22 : 0.10))
                                .frame(width: 34, height: 34)
                            Image(systemName: tier.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(tier.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.label)
                                .font(.system(size: 14, weight: isNow ? .bold : .medium))
                                .foregroundColor(isNow ? tier.color : .textPrimary)
                            Text(tierRangeText(i))
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        if isNow {
                            Text("Du")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier.color)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(tier.color.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if i < tiers.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func tierRangeText(_ i: Int) -> String {
        switch i {
        case 0: return "unter 0 Pkt"
        case 1: return "0 – 49 Pkt"
        case 2: return "50 – 199 Pkt"
        case 3: return "200 – 499 Pkt"
        case 4: return "ab 500 Pkt"
        default: return ""
        }
    }

    // MARK: Stats-Zeile

    private var statsRow: some View {
        HStack(spacing: 10) {
            rsStatPill(value: "\(score.showUps)", label: "Erschienen",
                       icon: "checkmark.circle.fill", color: .onlineGreen)
            rsStatPill(value: "\(score.noShows)", label: "No-Shows",
                       icon: "xmark.circle.fill", color: .accentRed)
            rsStatPill(value: "+\(score.bonusPoints)", label: "Boni",
                       icon: "star.fill", color: Color.auroraAmber)
        }
    }

    // MARK: Helper

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .tracking(0.5)
            .textCase(.uppercase)
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    private func eventRow(icon: String, color: Color, title: String,
                          value: String, negative: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(negative ? .accentRed : color)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private func rsStatPill(value: String, label: String, icon: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Image(systemName: icon)
            .font(.system(size: 15))
            .foregroundColor(color)
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.textPrimary)
        Text(label)
            .font(.system(size: 10))
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Radius.md))
}

// MARK: - String Helpers

extension String {
    /// Ersten Buchstaben großschreiben, Rest unverändert lassen.
    /// "max" → "Max" · "MAX" → "MAX" · "" → ""
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Haptic Manager

/// Zentrale Haptic-Sprache für Drops.
/// Alle Funktionen dispatchen intern auf den Main Thread — sicher aus
/// Firebase-Callbacks, Combine-Streams und Background-Queues aufrufbar.
enum Haptic {

    // MARK: - Main-Thread-sicherer Dispatch

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async { work() } }
    }

    private static func onMainAfter(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
    }

    // MARK: - Primitive

    /// Leichte Selektion (Chips, Toggles, Picker)
    static func selection() {
        onMain { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Einfacher Impact
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        onMain { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }

    /// System-Notification-Haptic
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(type) }
    }

    // MARK: - Semantisch

    /// Drop geht live — zwei Schläge wie Raketenstart
    static func dropCreated() {
        onMain {
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare()
            g.impactOccurred()
        }
        onMainAfter(0.09) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage angenommen — Freude, Dopamine-Hit
    static func joinAccepted() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        onMainAfter(0.13) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage abgelehnt — klar, eindeutig
    static func joinRejected() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    /// Drop beendet — finaler Abschluss
    static func dropEnded() {
        onMain { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    }

    /// BLE-Treffen bestätigt — Doppelpuls "wir sind beide da!"
    static func meetupConfirmed() {
        onMain {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
        onMainAfter(0.18) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// GPS-Bestätigung — Show-Up erkannt
    static func gpsArrival() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Punkte-Toast erscheint — Belohnungs-Tap
    static func pointsEarned() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        onMainAfter(0.10) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    /// Freundschaft bestätigt — Social Win
    static func friendAdded() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Freundschaftsanfrage gesendet
    static func friendRequestSent() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage abgeschickt
    static func joinRequestSent() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Incoming Join Request Sheet erscheint (Host-Seite)
    static func incomingRequest() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    /// Timer auf null — scharfe finale Warnung
    static func timerExpired() {
        onMain { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    }

    /// Namensänderung genehmigt
    static func nameChangeApproved() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Namensänderung abgelehnt
    static func nameChangeDenied() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    /// Allgemeiner Erfolg
    static func success() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Allgemeine Warnung
    static func warning() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }
}

