import SwiftUI
import StoreKit

// MARK: - Drops+ Paywall

struct DropsPlusView: View {
    @ObservedObject private var store = DropsStoreManager.shared
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    /// Wird nur dann auf true gesetzt, wenn der User im aktuellen Sheet auf "Kaufen" getippt hat —
    /// verhindert, dass das Success-Popup beim bloßen Öffnen einer bereits aktiven Paywall auftaucht.
    @State private var justActivated = false

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // ── Hintergrund ─────────────────────────────────────────────
            LinearGradient(
                colors: [Color(hex: "0a0a0a"), Color(hex: "1c1200"), Color(hex: "0a0a0a")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Inhalt ───────────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    featuresSection.padding(.top, 36)
                    purchaseSection.padding(.top, 32)
                    footerSection.padding(.top, 20).padding(.bottom, 48)
                }
                .padding(.horizontal, 24)
            }

            // ── Schließen-Button ─────────────────────────────────────────
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.top, 16).padding(.trailing, 20)
        }
        .onChange(of: store.isPlusUser) { newValue in
            // Kauf erfolgreich → Paywall schließen, Global Success-Popup triggern
            if newValue && justActivated {
                justActivated = false
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appStore.showDropsPlusSuccess = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 52)

            // Leucht-Halo + Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "f59e0b").opacity(0.28), .clear],
                            center: .center,
                            startRadius: 0, endRadius: 64
                        )
                    )
                    .frame(width: 110, height: 110)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            // Titel
            Text("Drops+")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Text("Einmalig zahlen — für immer dabei.")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 12) {
            PlusFeatureRow(
                icon: "bolt.circle.fill",
                title: "Drop boosten",
                description: "Hebe deinen Drop mit goldenem Rahmen auf der Karte hervor — mehr Sichtbarkeit, mehr Teilnehmer."
            )
            PlusFeatureRow(
                icon: "scope",
                title: "Größerer Suchradius",
                description: "Finde Drops bis zu 25 km oder unbegrenzt stadtweit — Free-User sind auf 2 km begrenzt."
            )
            PlusFeatureRow(
                icon: "shield.fill",
                title: "Kein Zuverlässigkeits-Abzug",
                description: "Mal kurzfristig doch nicht erschienen? Als Drops+ Mitglied bleibt dein Score makellos."
            )
            PlusFeatureRow(
                icon: "arrow.up.forward.circle.fill",
                title: "Priority Listing",
                description: "Deine Drops werden in der Nähe-Ansicht zuerst angezeigt — auch ohne aktiven Boost."
            )
            PlusFeatureRow(
                icon: "clock.arrow.circlepath",
                title: "Verlängerung ohne Cooldown",
                description: "Verlängere deinen Drop so oft du willst — keine Wartezeit zwischen den Verlängerungen."
            )
            PlusFeatureRow(
                icon: "chart.bar.fill",
                title: "Drop-Statistiken",
                description: "Siehe deine Gesamt-Joins, Zuverlässigkeits-Verlauf und erstellte Drops auf einen Blick."
            )
            PlusFeatureRow(
                icon: "heart.fill",
                title: "Drops unterstützen",
                description: "Du hilfst uns, die App dauerhaft kostenlos und werbefrei für alle zu halten."
            )
        }
    }

    // MARK: - Kauf

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if store.isPlusUser {
                // Bereits gekauft
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "f59e0b"))
                    Text("Du bist Drops+ Mitglied")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Alle Features sind aktiv.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                // Preis
                if let price = store.product?.displayPrice {
                    Text("Einmalig \(price)")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.45))
                }

                // Kaufen-Button
                Button {
                    justActivated = true
                    Task { await store.purchase() }
                } label: {
                    ZStack {
                        if store.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Drops+ freischalten")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color(hex: "f59e0b").opacity(0.4), radius: 12, y: 4)
                }
                .disabled(store.isLoading || store.product == nil)

                if let err = store.purchaseError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text("Kauf wiederherstellen")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.38))
                    .underline()
            }
            .disabled(store.isLoading)

            Text("Einmalige Zahlung · Kein Abo · Keine Werbung")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.22))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Drops+ Success Popup (global, from purchase or admin grant)

struct DropsPlusSuccessView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Dunkler, goldener Glow-Hintergrund
            RadialGradient(
                colors: [Color(hex: "f59e0b").opacity(0.22), Color.black.opacity(0.94)],
                center: .center,
                startRadius: 20, endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "f59e0b").opacity(0.4), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 90
                            )
                        )
                        .frame(width: 160, height: 160)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 88, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(hex: "f59e0b").opacity(0.6), radius: 20)
                }

                VStack(spacing: 10) {
                    Text("Willkommen bei Drops+")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )

                    Text("Alle Premium-Features sind ab jetzt aktiv.\nDanke, dass du Drops unterstützt.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                // Feature-Kurzliste
                VStack(alignment: .leading, spacing: 10) {
                    SuccessFeatureLine(icon: "bolt.circle.fill", text: "Drop-Boost freigeschaltet")
                    SuccessFeatureLine(icon: "scope", text: "Suchradius bis unbegrenzt")
                    SuccessFeatureLine(icon: "shield.fill", text: "Score-Schutz aktiv")
                    SuccessFeatureLine(icon: "arrow.up.forward.circle.fill", text: "Priority Listing aktiv")
                    SuccessFeatureLine(icon: "clock.arrow.circlepath", text: "Keine Verlängerungs-Cooldowns")
                    SuccessFeatureLine(icon: "chart.bar.fill", text: "Drop-Statistiken verfügbar")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "f59e0b").opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)

                // Los-geht's-Button
                Button {
                    appStore.showDropsPlusSuccess = false
                    dismiss()
                } label: {
                    Text("Los geht's")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(hex: "f59e0b").opacity(0.5), radius: 14, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
}

// MARK: - Feature Row

private struct PlusFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 48, height: 48)
                .background(Color(hex: "f59e0b").opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Success Feature Line

private struct SuccessFeatureLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "f59e0b"))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Preview

#Preview("Paywall") {
    DropsPlusView()
        .environmentObject(AppStore())
}

#Preview("Success") {
    DropsPlusSuccessView()
        .environmentObject(AppStore())
}
