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
        .onChange(of: store.selectedTab) { tab in
            if tab == .create && !store.isInActiveDrop {
                showCreateSheet = true
                store.selectedTab = .map
            }
        }
        .onChange(of: store.isInActiveDrop) { isActive in
            if !isActive && store.selectedTab == .create {
                store.selectedTab = .map
            }
        }
        .fullScreenCover(isPresented: $showCreateSheet) {
            CreateDropView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $store.showDropsPlusSuccess) {
            DropsPlusSuccessView()
                .environmentObject(store)
        }

            // Aurora-Pulse unten — zieht sich durch die Tab-Bar wenn ein Drop aktiv ist.
            // Wird BELOW TabView gerendert; die iOS-26-Glass-Tab-Bar lässt die Farben
            // dezent durchschimmern, als "breathing" Akzent unter den Tabs.
            if store.isInActiveDrop {
                ActiveDropAuroraPulse()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

        } // ZStack
        .animation(.easeInOut(duration: 0.4), value: store.isInActiveDrop)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                OfflineBanner()
                if store.showWelcomeBackToast,
                   let lastName = UserDefaults.standard.string(forKey: "ud_lastKnownName"),
                   !lastName.isEmpty {
                    welcomeBackToast(name: lastName)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        // ── Stadtsperre ─────────────────────────────
        .fullScreenCover(isPresented: .constant(BetaConfig.cityRestrictionEnabled && cityGate.isOutsideCity)) {
            CityGateView()
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
    }

    /// Dezenter „Willkommen zurück"-Toast, wird einmalig nach ≥ 24 h Abwesenheit gezeigt
    /// und blendet sich nach 3 Sek automatisch wieder aus.
    @ViewBuilder
    private func welcomeBackToast(name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brand)
            Text("Willkommen zurück, \(name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.brand.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 6)
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

// MARK: - Active Drop Aurora Pulse

/// Pulse der ausschließlich im Tab-Bar-Bereich läuft: sanfter Grundglow in der Mitte
/// plus zwei Ripple-Ringe, die von der Mitte nach außen expandieren und dabei
/// ausfaden — wie ein Sonar-Ping horizontal durch die Tab-Bar. Die iOS-26-Glass-
/// Tab-Bar lässt die Farben durchschimmern; oberhalb der Tab-Bar ist nichts sichtbar,
/// da der Container auf die Tab-Bar-Höhe beschränkt und geclippt ist.
struct ActiveDropAuroraPulse: View {
    /// Höhe des Streifens — passt ungefähr zur iOS-Tab-Bar inkl. Safe Area.
    private let barHeight: CGFloat = 82
    private let pulsePeriod: Double = 2.5

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let p1 = CGFloat(t.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod)
                    let p2 = CGFloat((t + pulsePeriod / 2).truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod)
                    ZStack {
                        // Stabile sanfte Mitten-Tönung
                        RadialGradient(
                            colors: [Color.brand.opacity(0.38), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: geo.size.width * 0.35
                        )

                        pulseRing(phase: p1, color: .brand, geo: geo)
                        pulseRing(phase: p2, color: Color(hex: "06b6d4"), geo: geo)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 4)
                }
            }
            .frame(height: barHeight)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    /// Einzelner Ring, der vom Zentrum (phase=0) auf volle Breite (phase=1) expandiert
    /// und dabei ausfadet. Nutzt Capsule — gibt den horizontalen Tab-Bar-Look.
    private func pulseRing(phase: CGFloat, color: Color, geo: GeometryProxy) -> some View {
        Capsule()
            .stroke(color.opacity(Double(1 - phase) * 0.55), lineWidth: 2.5)
            .frame(
                width: max(10, geo.size.width * phase),
                height: geo.size.height * 0.55
            )
    }
}
