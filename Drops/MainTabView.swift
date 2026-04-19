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

        } // ZStack
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
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
