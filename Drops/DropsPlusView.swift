import SwiftUI
import StoreKit

// MARK: - Drops+ Paywall

struct DropsPlusView: View {
    @ObservedObject private var store = DropsStoreManager.shared
    @Environment(\.dismiss) private var dismiss

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
                icon: "arrow.up.circle.fill",
                title: "Drop boosten",
                description: "Heb deinen Drop auf der Karte mit goldenem Rahmen hervor — mehr Sichtbarkeit, mehr Teilnehmer."
            )
            PlusFeatureRow(
                icon: "shield.fill",
                title: "Kein Zuverlässigkeits-Abzug",
                description: "Du trittst einem Drop bei und erscheinst doch nicht? Als Drops+ User bleibt dein Score makellos."
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

// MARK: - Preview

#Preview {
    DropsPlusView()
}
