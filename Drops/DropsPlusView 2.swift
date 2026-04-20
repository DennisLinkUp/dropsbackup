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
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                PlusFeatureRow(
                    icon: "bolt.circle.fill",
                    title: "Drop boosten",
                    description: "Hebe deinen Drop mit goldenem Rahmen auf der Karte hervor — mehr Sichtbarkeit, mehr Teilnehmer.",
                    comingSoon: false
                )
                PlusFeatureRow(
                    icon: "scope",
                    title: "Größerer Suchradius",
                    description: "Finde Drops bis zu 25 km oder unbegrenzt stadtweit — Free-User sind auf 2 km begrenzt.",
                    comingSoon: false
                )
                PlusFeatureRow(
                    icon: "eye.fill",
                    title: "Wer hat geschaut",
                    description: "Sieh welche Personen dein Drop geöffnet haben — mit Name, Alter und Zeitpunkt.",
                    comingSoon: false
                )
            }

            // ── Bald verfügbar ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Bald verfügbar")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.8)
                }
                .foregroundColor(.white.opacity(0.45))
                .padding(.leading, 4)

                VStack(spacing: 12) {
                    PlusFeatureRow(
                        icon: "shield.fill",
                        title: "Kein Zuverlässigkeits-Abzug",
                        description: "Score-Schutz bei kurzfristigen Absagen.",
                        comingSoon: true
                    )
                    PlusFeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: "Verlängerung ohne Cooldown",
                        description: "Drops beliebig oft verlängern, ohne Wartezeit.",
                        comingSoon: true
                    )
                    PlusFeatureRow(
                        icon: "chart.bar.fill",
                        title: "Drop-Statistiken",
                        description: "Joins, Score-Verlauf und erstellte Drops auf einen Blick.",
                        comingSoon: true
                    )
                }
            }
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
            // Dezent abgedunkelter Hintergrund — Glow nur um das Icon, nicht ganzflächig
            LinearGradient(
                colors: [Color(hex: "0a0a0a"), Color(hex: "1c1200"), Color(hex: "0a0a0a")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icon mit engem Glow (reicht nicht bis zum Titel)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "f59e0b").opacity(0.35), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 80, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: 10) {
                    // Titel in Weiß für maximalen Kontrast — „Drops+" als goldener Akzent
                    (Text("Willkommen bei ")
                        .foregroundColor(.white)
                     + Text("Drops+")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text("Alle Premium-Features sind ab jetzt aktiv.\nDanke, dass du Drops unterstützt.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                // Feature-Kurzliste
                VStack(alignment: .leading, spacing: 10) {
                    SuccessFeatureLine(icon: "bolt.circle.fill", text: "Drop-Boost freigeschaltet")
                    SuccessFeatureLine(icon: "scope", text: "Suchradius bis unbegrenzt")
                    SuccessFeatureLine(icon: "eye.fill", text: "Du siehst, wer deinen Drop geöffnet hat")
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
    var comingSoon: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        comingSoon
                            ? AnyShapeStyle(Color.white.opacity(0.35))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              ))
                    )
            }
            .frame(width: 48, height: 48)
            .background(
                comingSoon ? Color.white.opacity(0.04) : Color(hex: "f59e0b").opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(comingSoon ? .white.opacity(0.6) : .white)
                    if comingSoon {
                        Text("BALD")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.4)
                            .foregroundColor(.black.opacity(0.7))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.55), in: Capsule())
                    }
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(comingSoon ? 0.4 : 0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(comingSoon ? 0.02 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(comingSoon ? 0.04 : 0.07), lineWidth: 1)
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
