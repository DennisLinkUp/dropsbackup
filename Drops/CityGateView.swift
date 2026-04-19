import SwiftUI
import CoreLocation

// ─────────────────────────────────────────────────
// MARK: – Beta-Stadt Konfiguration
// ─────────────────────────────────────────────────

enum BetaConfig {
    /// Auf `false` setzen um die Stadtsperre zu deaktivieren
    static let cityRestrictionEnabled = true

    static let cityName    = "München"
    static let cityLat     = 48.1371
    static let cityLon     = 11.5754
    /// Großraum München: ~60 km Radius (deckt Augsburg, Ingolstadt, Rosenheim ab)
    static let radiusKm    = 60.0
    /// Wie lange (Sek.) auf einen Standort gewartet wird, bevor der Gate übersprungen wird
    static let timeoutSecs: Double = 6

    /// Auf `false` setzen für App Store Release — überspringt Ausweis-Scan in Beta-Builds
    static let skipIDVerification = false
}

// ─────────────────────────────────────────────────
// MARK: – City Gate Checker
// ─────────────────────────────────────────────────

@MainActor
final class CityGateChecker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isOutsideCity = false
    @Published var isChecking    = true

    private let manager = CLLocationManager()
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func startChecking() {
        guard BetaConfig.cityRestrictionEnabled else {
            isChecking = false
            return
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            startTimeout()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            startTimeout()
        default:
            // Keine Berechtigung — App trotzdem starten (Benefit of doubt)
            isChecking = false
        }
    }

    private func startTimeout() {
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(BetaConfig.timeoutSecs * 1_000_000_000))
            if isChecking {
                isChecking = false  // Timeout → App öffnen
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.check(location: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isChecking = false  // Fehler → App öffnen
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                self.isChecking = false
            }
        }
    }

    private func check(location: CLLocation) {
        timeoutTask?.cancel()
        let cityCenter = CLLocation(latitude: BetaConfig.cityLat, longitude: BetaConfig.cityLon)
        let distKm = location.distance(from: cityCenter) / 1000
        isOutsideCity = distKm > BetaConfig.radiusKm
        isChecking = false
    }
}

// ─────────────────────────────────────────────────
// MARK: – City Gate View
// ─────────────────────────────────────────────────

struct CityGateView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var animateAurora = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ─────────────────────────
            Color(hex: "f5f7fe").ignoresSafeArea()

            Circle()
                .fill(Color(hex: "34D36E").opacity(0.32))
                .frame(width: 500)
                .offset(x: animateAurora ? -140 : -100, y: animateAurora ? -280 : -240)
                .blur(radius: 90)

            Circle()
                .fill(Color(hex: "A78BFA").opacity(0.26))
                .frame(width: 420)
                .offset(x: animateAurora ? 180 : 140, y: animateAurora ? -260 : -220)
                .blur(radius: 80)

            Circle()
                .fill(Color(hex: "2DD4BF").opacity(0.20))
                .frame(width: 360)
                .offset(x: animateAurora ? -160 : -120, y: animateAurora ? 340 : 300)
                .blur(radius: 75)

            Circle()
                .fill(Color(hex: "FBBF24").opacity(0.16))
                .frame(width: 300)
                .offset(x: animateAurora ? 150 : 110, y: animateAurora ? 320 : 280)
                .blur(radius: 70)

            // ── Inhalt ────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "34D36E").opacity(0.12))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

                    Circle()
                        .fill(Color(hex: "34D36E").opacity(0.18))
                        .frame(width: 88, height: 88)

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(Color(hex: "34D36E"))
                }
                .padding(.bottom, 36)

                // Titel
                Text(tr("city.not_in_city"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "111827"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)

                // Beschreibung
                Text("Drops startet zunächst nur in **\(BetaConfig.cityName)**.\nWir expandieren bald in weitere Städte – bleib dran!")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "111827").opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)

                // Stadt-Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "34D36E"))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().fill(Color(hex: "34D36E").opacity(0.3))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulse ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                        )
                    Text("Beta aktiv in \(BetaConfig.cityName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "34D36E"))
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color(hex: "34D36E").opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "34D36E").opacity(0.25), lineWidth: 1))
                .padding(.bottom, 56)

                Spacer()

                // Info-Text unten
                Text(tr("city.notification_request"))
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "111827").opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateAurora = true
            }
            pulse = true
        }
    }
}
