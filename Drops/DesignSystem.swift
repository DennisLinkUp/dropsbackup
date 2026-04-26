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
    /// Zähler für Host-Erfolge (Drop gehostet und kam zustande — min. 1 Teilnehmer zusätzlich).
    var hostSuccesses: Int = 0
    /// Akkumulierte Bonus-Punkte.
    var streakBonusPoints: Int = 0       // +20 nach 5 Drops in Folge ohne No-Show
    var firstArrivalPoints: Int = 0      // +5 pro Mal als Erster vor Ort
    var dropInvitesPoints: Int = 0       // +5 pro Einladung die gejoint ist (Drop-Einladung)
    var newcomerHostPoints: Int = 0      // +3 pro neuem User (Drop-Entdecker) bei deinem Drop
    var appInvitesPoints: Int = 0        // +10 pro Freund der Drops neu installiert & onboarded hat
    /// Aktueller Show-Up-Streak (Anzahl Drops in Folge ohne No-Show).
    /// Jeder 5er-Block löst +20 Streak-Bonus aus; Counter läuft danach weiter (alle 5 erneut).
    var currentStreak: Int = 0
    var appLanguage: String = "de"

    // MARK: - Punktesystem
    // Start 100 · Joinen+vor Ort +15 · Hosten+klappt +8 · No-Show -25
    // Boni: Streak +20, Erster +5, Drop-Einladung +5, Neuling-Host +3, App-Einladung +10
    static let startingPoints       = 100
    static let pointsPerShowUp      = 15
    static let pointsPerHostSuccess = 8
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
        streakBonusPoints + firstArrivalPoints + dropInvitesPoints + newcomerHostPoints + appInvitesPoints
    }

    /// Deckungsgleich mit badge — damit überall die gleiche Stufe erscheint.
    var label: String { badge }

    var color: Color {
        switch points {
        case ..<0:      return .accentRed
        case 0..<50:    return .accentOrange
        case 50..<200:  return Color(hex: "f59e0b")
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
        case 50..<200:  return Color(hex: "f59e0b")
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
        ("Drop-Entdecker",   50,  Color(hex: "f59e0b"),    "binoculars.fill"),
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
            .navigationTitle("Zuverlässigkeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
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
                    Text("Pkt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Fortschritt zur nächsten Stufe

    @ViewBuilder private var progressCard: some View {
        if let remaining = score.pointsToNextTier, let next = score.nextTierName {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Noch \(remaining) Pkt bis \(next)")
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
                        in: RoundedRectangle(cornerRadius: 16))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill").foregroundColor(.brand)
                Text("Höchste Stufe erreicht")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Punkte-Events

    private var pointsEventsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("So sammelst du Punkte")
            VStack(spacing: 0) {
                eventRow(icon: "figure.walk.circle.fill", color: .onlineGreen,
                         title: "Drop beitreten + vor Ort", value: "+15")
                Divider().padding(.leading, 56)
                eventRow(icon: "plus.circle.fill", color: Color(hex: "06b6d4"),
                         title: "Drop hosten + kommt zustande", value: "+8")
                Divider().padding(.leading, 56)
                eventRow(icon: "xmark.circle.fill", color: .accentRed,
                         title: "No-Show (nicht erschienen)", value: "-25",
                         negative: true)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Boni

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Extras & Boni")
            VStack(spacing: 0) {
                eventRow(icon: "flame.fill", color: .accentOrange,
                         title: "5× in Folge ohne No-Show", value: "+20")
                Divider().padding(.leading, 56)
                eventRow(icon: "bolt.fill", color: Color(hex: "f59e0b"),
                         title: "Als Erster vor Ort", value: "+5")
                Divider().padding(.leading, 56)
                eventRow(icon: "paperplane.fill", color: .brand,
                         title: "Eingeladener joint deinen Drop", value: "+5")
                Divider().padding(.leading, 56)
                eventRow(icon: "sparkles", color: Color(hex: "8b5cf6"),
                         title: "Neuling bei deinem Drop", value: "+3")
                Divider().padding(.leading, 56)
                eventRow(icon: "person.badge.plus.fill", color: Color(hex: "ec4899"),
                         title: "Freund installiert Drops neu", value: "+10")
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
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
                    in: RoundedRectangle(cornerRadius: 16))
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
                       icon: "star.fill", color: Color(hex: "f59e0b"))
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
                in: RoundedRectangle(cornerRadius: 12))
}

