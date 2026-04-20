import SwiftUI

// MARK: - Color Palette

extension Color {
    static let bgPrimary     = Color(UIColor.systemBackground)
    static let bgSecondary   = Color(UIColor.secondarySystemBackground)
    static let bgTertiary    = Color(UIColor.tertiarySystemBackground)
    static let brand         = Color(hex: "34C759")
    static let brandInverse  = Color.white
    static let accentGreen   = Color(hex: "34C759")
    static let accentRed     = Color(hex: "FF3B30")
    static let accentOrange  = Color(hex: "FF9500")
    static let textPrimary   = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary  = Color(UIColor.tertiaryLabel)
    static let textMuted     = Color(UIColor.quaternaryLabel)
    static let onlineGreen   = Color(hex: "34C759")
    static let glassBorder   = Color(UIColor.separator)

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

// MARK: - iOS 26 Glass Helpers

extension View {
    /// Applies Liquid Glass background — uses native .glassEffect() on iOS 26,
    /// falls back to ultraThinMaterial on earlier OS versions.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 18, shadowRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
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
        }
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

    private let gradient: AngularGradient = .init(
        colors: [
            Color(hex: "22c55e"), Color(hex: "06b6d4"),
            Color(hex: "8b5cf6"), Color(hex: "ec4899"),
            Color(hex: "f59e0b"), Color(hex: "22c55e"),
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
                // Subtiler Aurora-Gradient — gedämpfte Sättigung, langsamerer Loop
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "22c55e").opacity(0.85),
                                Color(hex: "06b6d4").opacity(0.85),
                                Color(hex: "8b5cf6").opacity(0.85),
                                Color(hex: "22c55e").opacity(0.85),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .hueRotation(.degrees(hue))
                    // Glas-Schimmer für Tiefe ohne zu viel Knall
                    .overlay(Capsule().fill(Color.white.opacity(0.08)))
                    // Glow: fester, kein Pulsieren
                    .shadow(color: Color(hex: "06b6d4").opacity(0.22), radius: 12, x: 0, y: 4)

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
    var appLanguage: String = "de"

    var score: Double {
        guard totalCommits > 0 else { return 100 }
        return Double(showUps) / Double(totalCommits) * 100
    }
    /// Langtext-Label — deckungsgleich mit den Tier-Bezeichnungen aus `badge`,
    /// damit überall in der App dieselben 4 Stufen auftauchen
    /// (Drop-Legende / Stammgast / Drop-Entdecker / Dropout).
    var label: String { badge }
    var color: Color {
        guard totalCommits > 0 else { return .accentOrange }
        switch score {
        case 95...100: return .brand
        case 80..<95:  return .onlineGreen
        case 60..<80:  return .accentOrange
        default:       return .accentRed
        }
    }
    var badge: String {
        // Neue User starten als „Drop-Entdecker" — erst mit einer realen Commit-Historie
        // werden die höheren Tiers vergeben.
        guard totalCommits > 0 else { return "Drop-Entdecker" }
        switch score {
        case 95...100: return "Drop-Legende"
        case 80..<95:  return "Stammgast"
        case 60..<80:  return "Drop-Entdecker"
        default:       return "Dropout"
        }
    }

    /// SF-Symbol passend zum Tier — wird neben dem Badge gerendert.
    var badgeIcon: String {
        guard totalCommits > 0 else { return "binoculars.fill" }  // Entdecker-Look für neue User
        switch score {
        case 95...100: return "crown.fill"           // Legende
        case 80..<95:  return "star.fill"            // Stammgast
        case 60..<80:  return "binoculars.fill"      // Drop-Entdecker
        default:       return "exclamationmark.triangle.fill"  // Dropout
        }
    }
    /// Human-readable score — shows "Neu" for users with no commit history yet.
    var displayText: String {
        totalCommits == 0 ? "Neu" : "\(Int(score))%"
    }
    /// Show "–" label for new users without any drops yet.
    var displayLabel: String {
        totalCommits == 0 ? "Noch keine Drops" : label
    }
}

struct ReliabilityBadgeView: View {
    let score: ReliabilityScore
    @AppStorage("appLanguage") private var appLanguage = "de"
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(score.color.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(score.score / 100))
                    .stroke(score.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90))
                Text("\(Int(score.score))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(score.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(score.badge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(score.showUps) von \(score.totalCommits) Drops erschienen")
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
                                      title: "Zuverlässigkeits-Score",
                                      subtitle: "No-Shows werden nach 30 Min gemeldet")
                            SafetyRow(icon: "hand.raised.circle.fill", color: .accentRed,
                                      title: "1-Tap blockieren",
                                      subtitle: "Sofort und ohne Erklärung")
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



// MARK: - Reliability Info Sheet

struct ReliabilityInfoSheet: View {
    let score: ReliabilityScore
    @Environment(\.dismiss) private var dismiss
    @State private var animateRing = false

    // Tier-System: 4 Stufen mit Schwellenwerten + passenden SF-Symbolen
    private let tiers: [(label: String, threshold: Double, color: Color, icon: String)] = [
        ("Dropout",         0,   .accentRed,     "exclamationmark.triangle.fill"),
        ("Drop-Entdecker",  60,  .accentOrange,  "binoculars.fill"),
        ("Stammgast",       80,  .onlineGreen,   "star.fill"),
        ("Drop-Legende",    95,  .brand,         "crown.fill"),
    ]
    private var currentTierIndex: Int {
        tiers.indices.last(where: { score.score >= tiers[$0].threshold }) ?? 0
    }

    var body: some View {
        ZStack {
            AppAuroraBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── Hero ────────────────────────────────────────────
                    VStack(spacing: 16) {
                        // Großer Score-Ring
                        ZStack {
                            // Hintergrund-Ring
                            Circle()
                                .stroke(score.color.opacity(0.12), lineWidth: 14)
                                .frame(width: 130, height: 130)

                            // Fortschritts-Ring
                            Circle()
                                .trim(from: 0, to: animateRing ? CGFloat(min(score.score, 100) / 100) : 0)
                                .stroke(
                                    LinearGradient(colors: [score.color.opacity(0.7), score.color],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                                )
                                .frame(width: 130, height: 130)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15),
                                           value: animateRing)

                            // Innerer Glow
                            Circle()
                                .fill(score.color.opacity(0.07))
                                .frame(width: 104, height: 104)

                            VStack(spacing: 4) {
                                Image(systemName: score.badgeIcon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(score.color)
                                Text(score.displayText)
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundColor(score.color)
                                Text(score.badge)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .tracking(0.3)
                            }
                        }

                        // Status-Label
                        Text(score.displayLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .liquidGlass(cornerRadius: 24)

                    // ── Tier-Leiste ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stufen")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(tiers.indices, id: \.self) { i in
                                let tier   = tiers[i]
                                let isNow  = i == currentTierIndex
                                let isPast = i < currentTierIndex

                                HStack(spacing: 14) {
                                    // Farb-Kreis mit Tier-Icon
                                    ZStack {
                                        Circle()
                                            .fill((isPast || isNow) ? tier.color.opacity(0.18) : Color.textTertiary.opacity(0.08))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: tier.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(
                                                (isPast || isNow)
                                                    ? tier.color
                                                    : Color.textTertiary.opacity(0.6)
                                            )
                                    }
                                    .overlay(
                                        // Aktuelles Tier: dezenter Pulse-Ring
                                        Circle()
                                            .stroke(tier.color.opacity(isNow ? 0.45 : 0), lineWidth: 2)
                                            .frame(width: 40, height: 40)
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tier.label)
                                            .font(.system(size: 14, weight: isNow ? .bold : .medium))
                                            .foregroundColor(isNow ? tier.color : (isPast ? .textPrimary : .textTertiary))
                                        Text("ab \(Int(tier.threshold))%")
                                            .font(.system(size: 11))
                                            .foregroundColor(.textTertiary)
                                    }

                                    Spacer()

                                    if isNow {
                                        Text("Du")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(tier.color)
                                            .padding(.horizontal, 9).padding(.vertical, 4)
                                            .background(tier.color.opacity(0.15), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)

                                if i < tiers.count - 1 {
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 18)
                    }

                    // ── Stat-Karten ─────────────────────────────────────
                    HStack(spacing: 12) {
                        rsStatPill(value: "\(score.showUps)",      label: "Erschienen",  icon: "checkmark.circle.fill", color: .onlineGreen)
                        rsStatPill(value: "\(score.noShows)",      label: "No-Shows",    icon: "xmark.circle.fill",     color: .accentRed)
                        rsStatPill(value: "\(score.totalCommits)", label: "Gesamt",      icon: "person.2.fill",          color: .brand)
                    }

                    // ── So funktioniert's ────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text("So funktioniert der Score")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

                        VStack(spacing: 0) {
                            rsRuleRow(icon: "checkmark.circle.fill", color: .onlineGreen,
                                      title: "Erscheinen lohnt sich",
                                      sub: "Jeder Drop bei dem du auftauchst verbessert deinen Score")
                            Divider().padding(.leading, 66)
                            rsRuleRow(icon: "xmark.circle.fill", color: .accentRed,
                                      title: "No-Shows kosten Punkte",
                                      sub: "Nicht auftauchen ohne Absage senkt deinen Score")
                            Divider().padding(.leading, 66)
                            rsRuleRow(icon: "eye.fill", color: .accentOrange,
                                      title: "Andere sehen deinen Score",
                                      sub: "Vor dem Beitreten sehen Leute wie zuverlässig du bist")
                            Divider().padding(.leading, 66)
                            rsRuleRow(icon: "arrow.triangle.2.circlepath", color: .brand,
                                      title: "Score erholt sich",
                                      sub: "Regelmäßiges Erscheinen bringt den Score schnell wieder hoch")
                        }
                    }
                    .liquidGlass(cornerRadius: 18)

                    // Fertig-Button
                    Button {
                        dismiss()
                    } label: {
                        Text("Fertig")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.top, 4).padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
        .onAppear { animateRing = true }
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }
}

private func rsStatPill(value: String, label: String, icon: String, color: Color) -> some View {
    VStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundColor(color)
        Text(value)
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundColor(.textPrimary)
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .liquidGlass(cornerRadius: 16)
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.2), lineWidth: 1))
}

private func rsRuleRow(icon: String, color: Color, title: String, sub: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(sub)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
    }
    .padding(.horizontal, 16).padding(.vertical, 13)
}
