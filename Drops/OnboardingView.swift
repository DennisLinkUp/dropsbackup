import SwiftUI
import MapKit
import AuthenticationServices
import LocalAuthentication
import FirebaseAuth
import UserNotifications
import CoreLocation

// MARK: - Fake Map Background (fiktive Stadtkarte, Apple-Maps-Stil)

struct FakeMapBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── 1. Grundfläche (Apple Maps Hellgrau) ──────────────────────
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.918, green: 0.918, blue: 0.933)))

            // ── 2. Wohngebiete (leicht wärmeres Grau, unregelmäßige Blöcke) ─
            let residentialColor = Color(red: 0.882, green: 0.882, blue: 0.900)
            let blocks: [CGRect] = [
                CGRect(x: w*0.00, y: h*0.00, width: w*0.28, height: h*0.18),
                CGRect(x: w*0.32, y: h*0.00, width: w*0.20, height: h*0.13),
                CGRect(x: w*0.58, y: h*0.00, width: w*0.42, height: h*0.22),
                CGRect(x: w*0.00, y: h*0.22, width: w*0.18, height: h*0.25),
                CGRect(x: w*0.22, y: h*0.17, width: w*0.32, height: h*0.20),
                CGRect(x: w*0.60, y: h*0.26, width: w*0.40, height: h*0.18),
                CGRect(x: w*0.00, y: h*0.72, width: w*0.22, height: h*0.28),
                CGRect(x: w*0.26, y: h*0.78, width: w*0.28, height: h*0.22),
                CGRect(x: w*0.62, y: h*0.75, width: w*0.38, height: h*0.25),
            ]
            for b in blocks {
                ctx.fill(Path(b), with: .color(residentialColor))
            }

            // ── 3. Parks (Apple Maps Grün) ────────────────────────────────
            let parkColor = Color(red: 0.780, green: 0.896, blue: 0.737)
            let parks: [(CGRect, CGFloat)] = [
                (CGRect(x: w*0.04, y: h*0.04, width: w*0.20, height: h*0.14), 10),
                (CGRect(x: w*0.54, y: h*0.03, width: w*0.24, height: h*0.18), 14),
                (CGRect(x: w*0.14, y: h*0.52, width: w*0.26, height: h*0.16), 10),
                (CGRect(x: w*0.64, y: h*0.48, width: w*0.20, height: h*0.22), 12),
                (CGRect(x: w*0.34, y: h*0.80, width: w*0.18, height: h*0.14), 8),
            ]
            for (rect, r) in parks {
                ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(parkColor))
            }

            // ── 4. Fluss (geschwungen, Apple-Blau) ────────────────────────
            var river = Path()
            river.move(to: CGPoint(x: -10, y: h*0.44))
            river.addCurve(
                to: CGPoint(x: w+10, y: h*0.60),
                control1: CGPoint(x: w*0.20, y: h*0.38),
                control2: CGPoint(x: w*0.80, y: h*0.66)
            )
            river.addLine(to: CGPoint(x: w+10, y: h*0.69))
            river.addCurve(
                to: CGPoint(x: -10, y: h*0.53),
                control1: CGPoint(x: w*0.80, y: h*0.75),
                control2: CGPoint(x: w*0.20, y: h*0.47)
            )
            river.closeSubpath()
            ctx.fill(river, with: .color(Color(red: 0.616, green: 0.808, blue: 0.933, opacity: 0.85)))

            // ── 5. Nebenstraßen (dünne weiße Linien, unregelmäßig) ────────
            let minorW: CGFloat = 3
            let minor: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.18), CGPoint(x: w,     y: h*0.18)),
                (CGPoint(x: 0,     y: h*0.30), CGPoint(x: w*0.6, y: h*0.30)),
                (CGPoint(x: 0,     y: h*0.42), CGPoint(x: w,     y: h*0.42)),
                (CGPoint(x: 0,     y: h*0.70), CGPoint(x: w,     y: h*0.70)),
                (CGPoint(x: 0,     y: h*0.83), CGPoint(x: w*0.5, y: h*0.83)),
                (CGPoint(x: 0,     y: h*0.93), CGPoint(x: w,     y: h*0.93)),
                (CGPoint(x: w*0.14, y: 0),     CGPoint(x: w*0.14, y: h*0.42)),
                (CGPoint(x: w*0.28, y: 0),     CGPoint(x: w*0.28, y: h)),
                (CGPoint(x: w*0.44, y: 0),     CGPoint(x: w*0.44, y: h*0.40)),
                (CGPoint(x: w*0.60, y: 0),     CGPoint(x: w*0.60, y: h)),
                (CGPoint(x: w*0.76, y: 0),     CGPoint(x: w*0.76, y: h*0.44)),
                (CGPoint(x: w*0.88, y: h*0.22),CGPoint(x: w*0.88, y: h)),
            ]
            for (a, b) in minor {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.white.opacity(0.95)), lineWidth: minorW)
            }

            // ── 6. Hauptstraßen (breiter, leicht gelblich wie Apple Maps) ─
            let majorColor = Color(red: 1.0, green: 0.97, blue: 0.88)
            let majorW: CGFloat = 7
            let major: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.25), CGPoint(x: w,     y: h*0.25)),
                (CGPoint(x: 0,     y: h*0.57), CGPoint(x: w,     y: h*0.57)),
                (CGPoint(x: w*0.38, y: 0),     CGPoint(x: w*0.38, y: h)),
                (CGPoint(x: w*0.72, y: 0),     CGPoint(x: w*0.72, y: h)),
            ]
            for (a, b) in major {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(majorColor), lineWidth: majorW)
            }

            // ── 7. Diagonalstraßen / Boulevards ──────────────────────────
            let diags: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.16), CGPoint(x: w*0.44, y: 0)),
                (CGPoint(x: w*0.56, y: h),     CGPoint(x: w,      y: h*0.48)),
                (CGPoint(x: 0,     y: h*0.60), CGPoint(x: w*0.30, y: h)),
            ]
            for (a, b) in diags {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.white.opacity(0.9)), lineWidth: 5)
            }

            // ── 8. Gebäude-Footprints (kleine dunkle Rechtecke in Blöcken) ─
            let buildingColor = Color(red: 0.845, green: 0.845, blue: 0.865)
            let footprints: [CGRect] = [
                CGRect(x: w*0.06, y: h*0.20, width: w*0.06, height: h*0.04),
                CGRect(x: w*0.14, y: h*0.20, width: w*0.04, height: h*0.06),
                CGRect(x: w*0.32, y: h*0.04, width: w*0.08, height: h*0.07),
                CGRect(x: w*0.32, y: h*0.14, width: w*0.05, height: h*0.04),
                CGRect(x: w*0.64, y: h*0.04, width: w*0.06, height: h*0.09),
                CGRect(x: w*0.78, y: h*0.06, width: w*0.09, height: h*0.06),
                CGRect(x: w*0.64, y: h*0.28, width: w*0.07, height: h*0.10),
                CGRect(x: w*0.78, y: h*0.28, width: w*0.10, height: h*0.08),
                CGRect(x: w*0.04, y: h*0.73, width: w*0.08, height: h*0.08),
                CGRect(x: w*0.14, y: h*0.76, width: w*0.06, height: h*0.06),
                CGRect(x: w*0.30, y: h*0.74, width: w*0.06, height: h*0.05),
                CGRect(x: w*0.66, y: h*0.76, width: w*0.08, height: h*0.08),
                CGRect(x: w*0.80, y: h*0.77, width: w*0.07, height: h*0.06),
                CGRect(x: w*0.36, y: h*0.61, width: w*0.05, height: h*0.05),
            ]
            for f in footprints {
                ctx.fill(Path(roundedRect: f, cornerRadius: 2), with: .color(buildingColor))
            }
        }
        .ignoresSafeArea()
    }
}

struct AnimatedDrop: Identifiable {
    let id = UUID()
    let name: String
    let activity: String
    let coordinate: CLLocationCoordinate2D
}

class DropMKAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let activity: String
    let name: String
    let dropID: String
    init(drop: AnimatedDrop) {
        self.coordinate = drop.coordinate
        self.activity = drop.activity
        self.name = drop.name
        self.dropID = drop.id.uuidString
    }
}

class DropMapViewController: UIViewController, MKMapViewDelegate {
    var mapView: MKMapView!

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.mapType = .standard
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation = false
        mapView.delegate = self
        view.addSubview(mapView)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
        )
        mapView.setRegion(region, animated: false)
    }

    func showDrop(_ drop: AnimatedDrop) {
        let ann = DropMKAnnotation(drop: drop)
        mapView.addAnnotation(ann)
    }

    func hideDrop(id: String) {
        guard let ann = mapView.annotations
            .first(where: { ($0 as? DropMKAnnotation)?.dropID == id }) else { return }
        if let view = mapView.view(for: ann) {
            UIView.animate(withDuration: 0.35, animations: {
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            }) { _ in self.mapView.removeAnnotation(ann) }
        } else {
            mapView.removeAnnotation(ann)
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let drop = annotation as? DropMKAnnotation else { return nil }
        let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
        let chip = makeChip(activity: drop.activity, name: drop.name)
        view.addSubview(chip)
        let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        chip.frame = CGRect(origin: .zero, size: size)
        view.frame.size = size
        view.centerOffset = CGPoint(x: 0, y: -size.height / 2)
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.8) {
            view.alpha = 1
            view.transform = .identity
        }
        return view
    }

    private func makeChip(activity: String, name: String) -> UIView {
        let chip = UIView()
        chip.backgroundColor = .white
        chip.layer.cornerRadius = 14
        chip.layer.shadowColor = UIColor.black.cgColor
        chip.layer.shadowOpacity = 0.10
        chip.layer.shadowRadius = 8
        chip.layer.shadowOffset = CGSize(width: 0, height: 3)
        chip.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "\(activity)  \(name)"
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
        ])
        return chip
    }
}

struct StableDropMapView: UIViewControllerRepresentable {
    let controller: DropMapViewController
    func makeUIViewController(context: Context) -> DropMapViewController { controller }
    func updateUIViewController(_ vc: DropMapViewController, context: Context) {}
}

class DropMapControllerHolder: ObservableObject {
    let controller = DropMapViewController()

    private let drops: [AnimatedDrop] = [
        AnimatedDrop(name: "Mia",   activity: "☕️ Kaffee",  coordinate: .init(latitude: 48.155, longitude: 11.548)),
        AnimatedDrop(name: "Ben",   activity: "🍺 Drink",   coordinate: .init(latitude: 48.125, longitude: 11.592)),
        AnimatedDrop(name: "Zoe",   activity: "🏃 Sport",   coordinate: .init(latitude: 48.148, longitude: 11.601)),
        AnimatedDrop(name: "Leo",   activity: "🍕 Essen",   coordinate: .init(latitude: 48.120, longitude: 11.558)),
        AnimatedDrop(name: "Max",   activity: "🎮 Zocken",  coordinate: .init(latitude: 48.158, longitude: 11.582)),
        AnimatedDrop(name: "Lena",  activity: "🎸 Jam",     coordinate: .init(latitude: 48.130, longitude: 11.545)),
        AnimatedDrop(name: "Jonas", activity: "🏋️ Gym",     coordinate: .init(latitude: 48.143, longitude: 11.610)),
        AnimatedDrop(name: "Sara",  activity: "🎨 Kunst",   coordinate: .init(latitude: 48.118, longitude: 11.575)),
        AnimatedDrop(name: "Finn",  activity: "🚴 Radeln",  coordinate: .init(latitude: 48.162, longitude: 11.565)),
        AnimatedDrop(name: "Lia",   activity: "📚 Lernen",  coordinate: .init(latitude: 48.128, longitude: 11.600)),
    ]

    func startAnimating() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.runCycle() }
    }

    private func runCycle() {
        var delay: Double = 0
        let order = drops.shuffled()
        for drop in order {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.controller.showDrop(drop)
            }
            let visible = Double.random(in: 7.0...12.0)
            let dropID = drop.id.uuidString
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + visible) {
                self.controller.hideDrop(id: dropID)
            }
            delay += Double.random(in: 1.8...2.8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 5.0) {
            self.runCycle()
        }
    }
}

class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var tokens: [NSObjectProtocol] = []

    init() {
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
            ) { [weak self] n in
                let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                self?.height = frame.height
            }
        )
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.height = 0 }
        )
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

enum OnboardingStep {
    case welcome, profile, birthday, interests, intro, done, underage
}


// MARK: - Shared Onboarding UI Helpers

/// Hintergrund mit radialem Farbglow von oben
struct OnboardingStepBackground: View {
    let color: Color
    @Environment(\.colorScheme) var cs
    var body: some View {
        ZStack {
            (cs == .dark ? Color(hex: "0d0f14") : Color(hex: "f5f7fe"))
                .ignoresSafeArea()
            // Oben: Haupt-Akzent
            RadialGradient(
                colors: [color.opacity(0.22), Color.clear],
                center: .top, startRadius: 0, endRadius: 480
            )
            .ignoresSafeArea()
            // Unten: schwacher Akzent damit kein kahler Rand entsteht
            RadialGradient(
                colors: [color.opacity(0.10), Color.clear],
                center: .bottom, startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()
        }
    }
}

/// Pulsierendes Icon mit drei Ringen
struct OnboardingPulseIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 80
    var iconSize: CGFloat = 34

    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.13 - Double(i) * 0.03), lineWidth: 1.5)
                    .frame(width: size + CGFloat(i) * 36,
                           height: size + CGFloat(i) * 36)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.3),
                        value: pulse
                    )
            }
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(color)
        }
        .onAppear { pulse = true }
    }
}

/// Kapsel-Punkt-Fortschrittsanzeige für Onboarding-Schritte
struct OnboardingDotProgress: View {
    let current: Int   // 1-basiert
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                let active = i == current - 1
                Capsule()
                    .fill(active ? color : Color.primary.opacity(0.15))
                    .frame(width: active ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: active)
            }
        }
    }
}

// MARK: - Animated Backgrounds

// MARK: – Tageszeit-Helper

private func isNightTime() -> Bool {
    let h = Calendar.current.component(.hour, from: Date())
    return h < 6 || h >= 20
}

// MARK: – Adaptive Glow-Hintergrund (Step 1 – Telefon)

struct WarmGlowBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color(hex: "FFF8F0")).ignoresSafeArea()
            Circle()
                .fill(Color(hex: "FF9500").opacity(dark ? 0.45 : 0.22))
                .frame(width: 360)
                .offset(x: 110, y: animate ? 220 : 280)
                .blur(radius: dark ? 90 : 70)
            Circle()
                .fill(Color(hex: "34C759").opacity(dark ? 0.30 : 0.15))
                .frame(width: 260)
                .offset(x: -110, y: animate ? -200 : -160)
                .blur(radius: 75)
            Circle()
                .fill(Color(hex: "FF3B30").opacity(dark ? 0.15 : 0.08))
                .frame(width: 200)
                .offset(x: animate ? -60 : 60, y: 80)
                .blur(radius: 60)
        }
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: – Adaptive Glow-Hintergrund (Step 2 – SMS)

struct CoolPulseBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color(hex: "F0F4FF")).ignoresSafeArea()
            Circle()
                .fill(Color.blue.opacity(dark ? 0.35 : 0.18))
                .frame(width: 320)
                .offset(x: animate ? -90 : -60, y: animate ? 160 : 220)
                .blur(radius: 80)
            Circle()
                .fill(Color.purple.opacity(dark ? 0.30 : 0.15))
                .frame(width: 280)
                .offset(x: animate ? 100 : 70, y: animate ? -130 : -90)
                .blur(radius: 70)
            Circle()
                .fill(Color.cyan.opacity(dark ? 0.20 : 0.12))
                .frame(width: 200)
                .offset(x: animate ? 40 : -40, y: 20)
                .blur(radius: 55)
        }
        .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: – Adaptive Glow-Hintergrund (Name/Bestätigung Step)

struct GreenGlowBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color(hex: "F0FFF5")).ignoresSafeArea()
            Circle()
                .fill(Color(hex: "34C759").opacity(dark ? 0.40 : 0.20))
                .frame(width: 400)
                .offset(x: animate ? -20 : 20, y: animate ? -200 : -160)
                .blur(radius: 100)
            Circle()
                .fill(Color(hex: "FF9500").opacity(dark ? 0.20 : 0.10))
                .frame(width: 280)
                .offset(x: 130, y: animate ? 280 : 240)
                .blur(radius: 90)
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: "34C759").opacity(dark ? 0.08 - Double(i)*0.015
                                                               : 0.05 - Double(i)*0.01),
                            lineWidth: 1.5)
                    .frame(width: CGFloat(120 + i * 70))
                    .scaleEffect(animate ? 1.06 : 0.96)
                    .animation(.easeInOut(duration: 2.5 + Double(i)*0.4).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: - DSGVO Consent Step (vor Ausweis-Scan)

// MARK: - Minderjährigen-Sperrscreen

/// Wird angezeigt wenn das eingegebene Geburtsdatum ein Alter unter 18 ergibt.
/// Kein Weiterkommen — der Nutzer muss die App verlassen.
struct UnderAgeBlockView: View {
    /// Callback: Zurück zum ID-Scan (z.B. "anderer Ausweis") oder App-Reset
    let onBack: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Neutraler dunkler Hintergrund — kein bunter Glow
            Color(hex: "1C1C1E").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentRed.opacity(0.14))
                        .frame(width: 96, height: 96)
                    Image(systemName: "nosign")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(Color.accentRed)
                }
                .padding(.bottom, 28)

                Text(tr("onboard.access_denied"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)

                Text("Drops ist ausschließlich für Personen ab 18 Jahren.\n\nDein angegebenes Alter liegt unter dieser Grenze. Eine Nutzung ist leider nicht möglich.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)

                Spacer()

                // Rechtlicher Hinweis
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.35))
                    Text(tr("onboard.legal_notice"))
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

                // Zurück-Button (kein Weiterkommen)
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                        Text(tr("common.back"))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Age check helper

private func isUserUnderage(birthdate: Date) -> Bool {
    let age = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    return age < 18
}


// MARK: - Aurora Overlay (Phone → Name Steps)

struct OnboardingAuroraOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brand.opacity(0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: pulse ? 40 : -50, y: pulse ? -180 : -130)
            Circle()
                .fill(Color(UIColor.systemPurple).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: pulse ? -70 : 50, y: pulse ? 80 : 140)
            Circle()
                .fill(Color(UIColor.systemTeal).opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 65)
                .offset(x: pulse ? 80 : -30, y: pulse ? -60 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.colorScheme) var systemColorScheme

    @State private var step: OnboardingStep = .welcome
    @State private var isLoginMode: Bool = false
    @State private var userName = ""
    @State private var userPhone = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDuplicateAccountAlert = false
    @State private var showNotFoundAlert = false
    @StateObject private var auth = FirebaseAuthManager()
    @State private var capturedAppleEmail: String? = nil
    // Muss als Property gehalten werden damit ARC es nicht sofort freigibt
    @State private var onboardingLocManager: CLLocationManager? = nil

    /// System-Setting hat Vorrang; bei „Auto" entscheidet die Uhrzeit
    private var prefersDark: Bool {
        switch systemColorScheme {
        case .dark:  return true
        case .light: return false
        default:     return isNightTime()
        }
    }
    private var adaptiveScheme: ColorScheme { prefersDark ? .dark : .light }

    var body: some View {
        ZStack {
            // Basisschicht: verhindert weiße Balken in safe areas —
            // Opake Basis-Farbe IMMER sichtbar → kein Durchschimmern beim Step-Wechsel
            (systemColorScheme == .dark ? Color(hex: "0d0f14") : Color(hex: "f5f7fe"))
                .ignoresSafeArea()

            // Einheitlicher Aurora-Hintergrund für alle Steps
            if step == .underage {
                Color(hex: "1C1C1E").ignoresSafeArea()
            } else if step != .welcome {
                AppAuroraBackground()
            }

            // Inhalt je nach Step — ausgelagert in @ViewBuilder um Type-Check-Timeout zu vermeiden
            stepContent
                .id(step)
                .animation(.none, value: step)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { drag in
                    guard drag.translation.width > 80,
                          abs(drag.translation.height) < abs(drag.translation.width) else { return }
                    withAnimation(.spring(response: 0.4)) {
                        switch step {
                        case .interests: step = .profile
                        case .intro:     step = .interests
                        default: break
                        }
                    }
                }
        )
        .alert("Konto bereits vorhanden", isPresented: $showDuplicateAccountAlert) {
            Button("Einloggen") {
                withAnimation(.spring(response: 0.4)) {
                    isLoginMode = true
                    step = .welcome
                }
            }
            Button("Abbrechen", role: .cancel) {
                withAnimation(.spring(response: 0.4)) { step = .welcome }
            }
        } message: {
            Text(tr("onboard.account_exists"))
        }
        .alert("Kein Konto gefunden", isPresented: $showNotFoundAlert) {
            Button("Registrieren") {
                withAnimation(.spring(response: 0.4)) {
                    isLoginMode = false
                    step = .welcome
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Diese Nummer ist noch nicht registriert. Möchtest du ein neues Konto erstellen?")
        }
        .onAppear { }
    }

    // MARK: - Step Content (ausgelagert für schnelleren Compiler)

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:   welcomeStepView
        case .profile:   profileStepView
        case .birthday:  profileStepView   // Zurück zum Profil-Schritt (Geburtsdatum korrigieren)
        case .interests: interestsStepView
        case .intro:     introStepView
        case .done:      doneStepView
        case .underage:  underageStepView
        }
    }

    @ViewBuilder private var welcomeStepView: some View {
        WelcomeStep(
            onPhone: { },  // unused — nur Apple Sign In
            onApple: { isNewUser, email in
                capturedAppleEmail = email
                // Apple sendet die Relay-E-Mail nur beim ersten Login → persistent speichern
                if let email = email {
                    UserDefaults.standard.set(email.lowercased(), forKey: "ud_appleEmail")
                }

                // Tombstone-Check: Wurde dieser Apple-Account in der App schon mal
                // gelöscht? Dann als Neuregistrierung behandeln — auch wenn Firebase
                // den User weiterhin als „bekannt" meldet (isNewUser = false).
                Task { @MainActor in
                    var wasDeleted = false
                    if let uid = Auth.auth().currentUser?.uid {
                        wasDeleted = await RealtimeDBManager.shared.consumeDeletionTombstone(uid: uid)
                    }
                    if wasDeleted {
                        // Frische Registrierung erzwingen
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }

                    // Firebase weiß sicher ob der Account neu ist.
                    // isNewUser = false → Account existiert definitiv → sofort einloggen.
                    if !isNewUser {
                        handleAppleSignInResult(exists: true)
                        return
                    }
                    // Nur bei echten Neuzugängen: DB prüfen (mit Timeout als Netz-Absicherung)
                    var appleCheckDone = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        guard !appleCheckDone else { return }
                        appleCheckDone = true
                        try? Auth.auth().signOut()
                        showNotFoundAlert = true
                    }
                    RealtimeDBManager.shared.hasExistingProfile { exists in
                        DispatchQueue.main.async {
                            guard !appleCheckDone else { return }
                            appleCheckDone = true
                            handleAppleSignInResult(exists: exists)
                        }
                    }
                }
            },
            isLoginMode: $isLoginMode,
            savedPhone: nil,
            onQuickLogin: nil,
            onBetaLogin: nil
        )
        .onAppear { isLoginMode = hasOnboarded }
    }

    @ViewBuilder private var profileStepView: some View {
        ProfileSetupStep(
            name:   $userName,
            phone:  $userPhone,
            selfie: $store.selfieImage,
            onNext: { name, birthdate, gender, phone in
                if isUserUnderage(birthdate: birthdate) {
                    store.userBirthdate = birthdate
                    withAnimation(.spring(response: 0.4)) { step = .underage }
                    return
                }
                store.currentUser.name = name.isEmpty ? "Du" : name
                store.userBirthdate    = birthdate
                store.userGender       = gender.lowercased()   // immer lowercase speichern
                if !phone.isEmpty {
                    // saveUserPhone schreibt in Firestore + phoneIndex (damit Kontakte uns finden)
                    store.saveUserPhone(phone)
                }
                store.saveAll()
                withAnimation(.spring(response: 0.4)) { step = .interests }
            },
            onBack: { withAnimation(.spring(response: 0.4)) { step = .welcome } }
        )
        .environment(\.colorScheme, adaptiveScheme)
    }

    @ViewBuilder private var interestsStepView: some View {
        InterestsStep(
            selected: $store.userInterests,
            onNext: {
                store.saveAll()
                withAnimation(.spring(response: 0.4)) { step = .intro }
            },
            onBack: { withAnimation(.spring(response: 0.4)) { step = .profile } }
        )
        .environment(\.colorScheme, adaptiveScheme)
    }

    @ViewBuilder private var introStepView: some View {
        AppIntroStep {
            requestOnboardingPermissions()
            withAnimation(.spring(response: 0.4)) { step = .done }
        }
        .environment(\.colorScheme, adaptiveScheme)
    }


    @ViewBuilder private var doneStepView: some View {
        Color.clear.onAppear {
            // Firebase UID persistent speichern für stabilen Drop-Filter
            if let uid = Auth.auth().currentUser?.uid {
                UserDefaults.standard.set(uid, forKey: "ud_firebaseUID")
            }
            // Admin-Check (Bootstrap-Credentials siehe AdminConfig)
            let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
            if AdminConfig.isBootstrapAdminEmail(authEmail) {
                store.isAdmin = true
            }
            // Gender-Filter nie automatisch aktivieren — muss manuell eingeschaltet werden
            store.genderFilterEnabled = false
            // Profil in Firebase speichern → Nutzer erscheint im Admin-Panel
            saveProfileToFirebase()
            store.isAuthenticated = true
        }
    }

    @ViewBuilder private var underageStepView: some View {
        UnderAgeBlockView { withAnimation(.spring(response: 0.4)) { step = .birthday } }
    }


    /// Fragt Benachrichtigungs- und Standort-Berechtigung am Ende des Onboardings an.
    /// Wird beim Erscheinen des Intro-Steps aufgerufen, damit der User bereits Kontext hat.
    private func requestOnboardingPermissions() {
        // 1. Push Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
        // 2. Standort (falls noch nicht bestimmt)
        // Property halten damit ARC den Manager nicht sofort freigibt
        let locManager = CLLocationManager()
        onboardingLocManager = locManager
        if locManager.authorizationStatus == .notDetermined {
            locManager.requestWhenInUseAuthorization()
        }
    }

    /// Verarbeitet das Ergebnis des Apple-Sign-In Profil-Checks.
    private func handleAppleSignInResult(exists: Bool) {
        if exists {
            // Bestehender Account — einloggen egal ob login- oder register-Modus
            loadProfileFromFirebase()
            hasOnboarded = true   // sicherstellen dass Onboarding nicht nochmal erscheint
            store.isAuthenticated = true
        } else {
            if isLoginMode {
                // Login-Modus aber kein Account gefunden
                try? Auth.auth().signOut()
                showNotFoundAlert = true
            } else {
                // Echter Neuzugang → Profil einrichten
                let firebaseEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
                let appleEmail = (capturedAppleEmail ?? "").lowercased()
                if AdminConfig.isBootstrapAdmin(authEmail: firebaseEmail, storedAppleEmail: appleEmail) {
                    store.isAdmin = true
                }
                withAnimation(.spring(response: 0.4)) { step = .profile }
            }
        }
    }


    private func finishOnboarding() {
        store.applyDefaultAgeGroups()
        hasOnboarded = true
        withAnimation(.spring(response: 0.4)) { step = .profile }
    }

    /// Speichert das vollständige Nutzerprofil in Firebase Realtime DB.
    /// Wird aufgerufen wenn step = .done.
    private func saveProfileToFirebase() {
        let email = (Auth.auth().currentUser?.email
                     ?? UserDefaults.standard.string(forKey: "ud_appleEmail"))
        RealtimeDBManager.shared.saveUserProfile(
            name:      store.currentUser.name,
            email:     email,
            birthdate: store.userBirthdate,
            gender:    store.userGender.isEmpty ? nil : store.userGender
        )
        store.saveAll()
    }

    /// Lädt das Profil aus Firebase und befüllt den Store (z.B. nach Re-Login).
    private func loadProfileFromFirebase() {
        // Admin-Check per E-Mail (Bootstrap-Credentials siehe AdminConfig)
        let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        if AdminConfig.isBootstrapAdmin(authEmail: authEmail, storedAppleEmail: storedApple) {
            self.store.isAdmin = true
        }
        RealtimeDBManager.shared.loadUserProfile { profile in
            guard let p = profile else { return }
            if let name = p.name, !name.isEmpty {
                self.store.currentUser.name = name
                // „Willkommen zurück"-Name direkt persistieren, unabhängig vom Logout-Zeitpunkt
                UserDefaults.standard.set(name, forKey: "ud_lastKnownName")
            }
            if let bd = p.birthdate             { self.store.userBirthdate = bd }
            if let gender = p.gender            { self.store.userGender = gender }
            if p.isAdmin                        { self.store.isAdmin = true }

        }
    }
}

// MARK: - Pulsing Dot Logo ("Dr[●]ps")

struct DropsLogo: View {
    var fontSize: CGFloat = 52
    var textColor: Color = .white
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            Text("Dr")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundColor(textColor)

            // "o" als App-Icon-Punkt: grüner Kreis + konzentrische Ringe + weißes Zentrum
            ZStack {
                // Konzentrische Ripple-Ringe (wie App Icon)
                ForEach(Array([0.88, 0.66, 0.50, 0.36].enumerated()), id: \.offset) { idx, ratio in
                    Circle()
                        .stroke(Color.brand.opacity(0.18 - Double(idx) * 0.03), lineWidth: 1)
                        .frame(width: fontSize * ratio)
                        .scaleEffect(pulse ? 1.05 : 0.96)
                        .animation(
                            .easeInOut(duration: 2.2 + Double(idx) * 0.35)
                            .repeatForever(autoreverses: true)
                            .delay(Double(idx) * 0.18),
                            value: pulse
                        )
                }
                // Grüner Haupt-Kreis
                Circle()
                    .fill(Color.brand)
                    .frame(width: fontSize * 0.38, height: fontSize * 0.38)
                    .shadow(color: Color.brand.opacity(0.5), radius: 8)
                // Weißer Kern-Punkt (wie App Icon)
                Circle()
                    .fill(Color.white)
                    .frame(width: fontSize * 0.13, height: fontSize * 0.13)
            }
            .frame(width: fontSize * 0.62, height: fontSize)

            Text("ps")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundColor(textColor)
        }
        .onAppear { pulse = true }
    }
}

struct PulsingRing: View {
    let delay: Double
    let baseSize: CGFloat
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 1.5)
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(animate ? 3.2 : 1.0)
            .opacity(animate ? 0 : 0.7)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 3.2).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            }
    }
}

// MARK: - Welcome Step (Dark & Light Variante)

// MARK: - Custom Apple Button (UIViewRepresentable)

/// Nativer ASAuthorizationAppleIDButton ohne automatisches System-Credential-Sheet.
/// Muss in OnboardingView.swift stehen, da UIViewRepresentable SwiftUI benötigt.
struct AppleSignInButtonView: UIViewRepresentable {
    let type: ASAuthorizationAppleIDButton.ButtonType
    let style: ASAuthorizationAppleIDButton.Style
    let cornerRadius: CGFloat
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let btn = ASAuthorizationAppleIDButton(type: type, style: style)
        btn.cornerRadius = cornerRadius
        btn.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return btn
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.cornerRadius = cornerRadius
    }

    class Coordinator: NSObject {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func tapped() { onTap() }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onPhone: () -> Void
    let onApple: (Bool, String?) -> Void  // isNewUser, appleEmail
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Binding var isLoginMode: Bool
    var savedPhone: String? = nil
    var onQuickLogin: (() -> Void)? = nil
    var onBetaLogin: (() -> Void)? = nil   // Beta-Bypass: anonym einloggen

    @Environment(\.colorScheme) var systemColorScheme
    @State private var appeared = false
    @State private var typedSlogan = ""
    @State private var showCursor = false
    @State private var typewriterTask: Task<Void, Never>? = nil
    @State private var biometricError: String? = nil
    @StateObject private var appleAuth = AppleSignInManager()

    private var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }
    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private let fullSlogan = "Join real life."

    /// System-Setting hat Vorrang; sonst entscheidet die Uhrzeit
    private var isLight: Bool {
        switch systemColorScheme {
        case .light: return true
        case .dark:  return false
        default:     return !isNightTime()
        }
    }

    // MARK: Farbsystem je Variante
    private var textPrimary: Color   { isLight ? Color(hex: "1C1C1E")             : .white }
    private var textSecondary: Color { isLight ? Color(hex: "1C1C1E").opacity(0.45) : .white.opacity(0.5) }
    private var overlayColor: Color  { isLight ? .white : .black }
    private var overlayOpacity: Double { isLight ? 0.60 : 0.72 }
    private var mapBlur: CGFloat     { isLight ? 9 : 16 }
    private var appleButtonStyle: ASAuthorizationAppleIDButton.Style { isLight ? .black : .white }
    private var screenH: CGFloat  { UIScreen.main.bounds.height }
    private var logoSize: CGFloat { screenH < 700 ? 52 : 68 }
    private var buttonPadV: CGFloat { screenH < 700 ? 12 : screenH < 850 ? 14 : 16 }

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ────────────────────────────────────
            AppAuroraBackground(isLight: isLight)

            // ── Inhalt ───────────────────────────────────────────────
            VStack(spacing: 0) {
                    Spacer()

                    // ── Logo-Block (Mitte) ─────────────────────────────
                    VStack(spacing: 0) {
                        // Icon-artiger Container — wirkt wie App-Icon auf Screen
                        ZStack {
                            // Großes Glow hinter dem Logo
                            Circle()
                                .fill(Color.brand.opacity(isLight ? 0.08 : 0.12))
                                .frame(width: 200, height: 200)
                                .blur(radius: 40)

                            DropsLogo(fontSize: logoSize, textColor: textPrimary)
                        }
                        .padding(.bottom, 18)

                        // Slogan Typewriter — oder „Willkommen zurück" wenn User bereits bekannt
                        if isLoginMode, let lastName = UserDefaults.standard.string(forKey: "ud_lastKnownName"),
                           !lastName.isEmpty {
                            Text("Willkommen zurück, \(lastName)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(textPrimary.opacity(isLight ? 0.65 : 0.60))
                                .kerning(0.3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            HStack(spacing: 0) {
                                Text(typedSlogan)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(textPrimary.opacity(isLight ? 0.55 : 0.50))
                                    .kerning(0.3)
                                if typedSlogan.count < fullSlogan.count {
                                    Text(tr("onboard.pipe"))
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(textPrimary.opacity(0.30))
                                        .opacity(showCursor ? 1 : 0)
                                        .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: showCursor)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // ── Buttons ───────────────────────────────────────
                    VStack(spacing: screenH < 700 ? 8 : 10) {

                        // Schnellzugriff — gespeicherte Nummer (nur im Login-Modus)
                        if isLoginMode, let phone = savedPhone, let quickLogin = onQuickLogin {
                            Button {
                                biometricError = nil
                                if biometricAvailable {
                                    loginWithBiometrics(onSuccess: quickLogin)
                                } else {
                                    quickLogin()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if biometricAvailable {
                                        Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                                            .font(.system(size: 18, weight: .medium))
                                    } else {
                                        Image(systemName: "bolt.fill").font(.system(size: 14))
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tr("onboard.continue_as_phone").replacingOccurrences(of: "{phone}", with: phone))
                                            .font(.system(size: screenH < 700 ? 13 : 14, weight: .semibold, design: .rounded))
                                        Text(biometricAvailable
                                             ? (biometricType == .faceID ? tr("onboard.continue_face_id") : tr("onboard.continue_touch_id"))
                                             : tr("onboard.saved_number"))
                                            .font(.system(size: 10))
                                            .opacity(0.7)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .opacity(0.6)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.brand.opacity(0.85))
                                        .shadow(color: Color.brand.opacity(0.3), radius: 10, y: 4)
                                )
                            }
                            .buttonStyle(.plain)

                            if let err = biometricError {
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundColor(.accentRed)
                                    .multilineTextAlignment(.center)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            HStack {
                                Rectangle().fill(textSecondary.opacity(0.2)).frame(height: 1)
                                Text(tr("common.or"))
                                    .font(.system(size: 11))
                                    .foregroundColor(textSecondary.opacity(0.5))
                                    .padding(.horizontal, 8)
                                Rectangle().fill(textSecondary.opacity(0.2)).frame(height: 1)
                            }
                        }

                        // Sign in with Apple — zwei native Buttons (type ist nach init nicht änderbar),
                        // immer nur einer sichtbar. Verhindert .id()-Reuse-Problem mit UIViewRepresentable.
                        ZStack {
                            // Login-Button (.signIn → "Mit Apple ID anmelden")
                            AppleSignInButtonView(
                                type: .signIn,
                                style: appleButtonStyle == .black ? .black : .white,
                                cornerRadius: screenH < 700 ? 22 : 25
                            ) {
                                appleAuth.signIn { success, isNewUser in
                                    if success { onApple(isNewUser, appleAuth.lastAppleEmail) }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 44 : 50, maxHeight: screenH < 700 ? 44 : 50)
                            .disabled(appleAuth.isLoading)
                            .opacity(isLoginMode ? 1 : 0)

                            // Registrieren-Button (.signUp → "Mit Apple ID registrieren")
                            AppleSignInButtonView(
                                type: .signUp,
                                style: appleButtonStyle == .black ? .black : .white,
                                cornerRadius: screenH < 700 ? 22 : 25
                            ) {
                                appleAuth.signIn { success, isNewUser in
                                    if success { onApple(isNewUser, appleAuth.lastAppleEmail) }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 44 : 50, maxHeight: screenH < 700 ? 44 : 50)
                            .disabled(appleAuth.isLoading)
                            .opacity(isLoginMode ? 0 : 1)

                            if appleAuth.isLoading {
                                Capsule().fill(.black.opacity(0.3))
                                    .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 44 : 50, maxHeight: screenH < 700 ? 44 : 50)
                                ProgressView().tint(.white)
                            }
                        }

                        // Apple-Fehler anzeigen
                        if let appleErr = appleAuth.errorMessage {
                            Text(appleErr)
                                .font(.system(size: 12))
                                .foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Toggle Login ↔ Registrieren
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { isLoginMode.toggle() }
                        }) {
                            HStack(spacing: 4) {
                                Text(isLoginMode ? tr("onboard.no_account_question") : tr("onboard.already_registered"))
                                    .foregroundColor(textSecondary.opacity(0.7))
                                Text(isLoginMode ? tr("onboard.register_now") : tr("common.sign_in"))
                                    .foregroundColor(Color.brand)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        // AGB nur bei Registrierung — opacity statt if, verhindert Layout-Shift
                        Text(tr("onboard.tos_notice"))
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .opacity(isLoginMode ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: isLoginMode)
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25), value: appeared)
                }
            .padding(.top, 12)
        }
        .onAppear {
            appeared = true
            showCursor = true
            startTypewriter()
        }
    }

    // MARK: Biometrie
    private func loginWithBiometrics(onSuccess: @escaping () -> Void) {
        let context = LAContext()
        let reason = biometricType == .faceID
            ? tr("onboard.faceid_reason")
            : tr("onboard.touchid_reason")
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    biometricError = nil
                    onSuccess()
                } else {
                    if let laErr = error as? LAError, laErr.code != .userCancel {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            biometricError = tr("onboard.biometric_failed")
                        }
                    }
                }
            }
        }
    }

    // MARK: Typewriter
    private func startTypewriter() {
        typewriterTask?.cancel()
        typewriterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            for char in fullSlogan {
                guard !Task.isCancelled else { return }
                typedSlogan.append(char)
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
        }
    }
}

struct OnboardingProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.brand : Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .animation(.spring(response: 0.4), value: current)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Simple Name Step (new: name only)

struct SimpleNameStep: View {
    @Binding var name: String
    let onNext: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"
    @FocusState private var focused: Bool
    @State private var appeared = false

    private let stepColor = Color.brand

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                Spacer()

                OnboardingPulseIcon(systemName: "person.fill", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text("Wie heißt du?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Dein Vorname erscheint für andere Nutzer.")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

                // Name field
                ZStack(alignment: .leading) {
                    if name.isEmpty {
                        Text("Vorname")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 17))
                            .padding(.leading, 20)
                    }
                    TextField("", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onNext() } }
                        .onChange(of: name) { newValue in
                            let filtered = newValue.filter { $0.isLetter }
                            if filtered != newValue { name = filtered }
                        }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(stepColor.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 28)

                Spacer()

                // Weiter-Button
                Button(action: onNext) {
                    Text("Weiter")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            Capsule().fill(name.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.brand.opacity(0.4) : Color.brand)
                        )
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }
}

// MARK: - Birthday Step

struct BirthdayStep: View {
    let onNext: (Date) -> Void
    let onBack: (() -> Void)?
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var appeared = false

    private let stepColor = Color.brand

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                // Back
                if let back = onBack {
                    HStack {
                        Button(action: back) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()

                OnboardingPulseIcon(systemName: "calendar", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text("Wann wurdest du geboren?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Drops ist ab 18 Jahren. Dein Alter bleibt privat.")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

                DatePicker(
                    "",
                    selection: $birthdate,
                    in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 20)

                Spacer()

                Button(action: { onNext(birthdate) }) {
                    Text("Weiter")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Capsule().fill(Color.brand))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Gender Step

struct GenderStep: View {
    @Binding var selected: String
    let onNext: () -> Void
    let onBack: (() -> Void)?
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    private let stepColor = Color.brand
    private let options: [(String, String, Bool)] = [
        ("Männlich", "♂",    false),
        ("Weiblich", "♀",    false),
        ("Divers",   "person.2.fill", true)   // true = SF Symbol statt Text
    ]

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                // Back
                if let back = onBack {
                    HStack {
                        Button(action: back) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()

                OnboardingPulseIcon(systemName: "person.2.fill", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text("Welches Geschlecht hast du?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Einmalig festgelegt — hilft bei der Suche.")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

                VStack(spacing: 12) {
                    ForEach(options, id: \.0) { label, symbol, isSFSymbol in
                        let isSelected = selected == label
                        Button(action: { selected = label }) {
                            HStack(spacing: 14) {
                                if isSFSymbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: 22, weight: .medium))
                                        .frame(width: 28)
                                } else {
                                    Text(symbol)
                                        .font(.system(size: 24))
                                        .frame(width: 28)
                                }
                                Text(label)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected ? Color.brand : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3), value: isSelected)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                Button(action: onNext) {
                    Text("Weiter")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            Capsule().fill(selected.isEmpty ? Color.brand.opacity(0.4) : Color.brand)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Profile Setup Step (Name + Geburtstag + Geschlecht + Foto + Telefon)

struct ProfileSetupStep: View {
    @Binding var name:   String
    @Binding var phone:  String
    @Binding var selfie: UIImage?
    /// name, birthdate, gender (lowercase), phone
    let onNext: (String, Date, String, String) -> Void
    let onBack: (() -> Void)?

    @State private var birthdateText = ""          // "TT.MM.JJJJ" — Zahleneingabe
    @State private var parsedBirthdate: Date? = nil
    @State private var gender:  String = ""
    @State private var appeared = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImageSourceSheet = false
    @FocusState private var nameFocused: Bool
    @FocusState private var dateFocused: Bool

    private let stepColor = Color.brand
    private let genderOptions: [(label: String, symbol: String, isSF: Bool)] = [
        ("Männlich", "♂", false),
        ("Weiblich", "♀", false),
        ("Divers",   "person.2.fill", true)
    ]

    /// Mindestens 18 Jahre alt
    private var dateIsValid: Bool { parsedBirthdate != nil }
    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !gender.isEmpty
            && dateIsValid
            && phoneIsValid
    }

    /// Handynummer ist Pflicht — mindestens 6 Ziffern (Länder-Präfix optional).
    /// Ohne Nummer finden dich deine Kontakte nicht, deshalb muss sie hinterlegt werden.
    private var phoneIsValid: Bool {
        phone.filter { $0.isNumber }.count >= 6
    }

    /// Formatiert Roheingabe zu "TT.MM.JJJJ"
    private func formatBirthdateInput(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var result = ""
        for (i, ch) in digits.prefix(8).enumerated() {
            if i == 2 || i == 4 { result += "." }
            result.append(ch)
        }
        return result
    }

    private func parseBirthdate(_ text: String) -> Date? {
        let parts = text.split(separator: ".").map { String($0) }
        guard parts.count == 3,
              let day   = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
              parts[2].count == 4
        else { return nil }
        // Explizite Bereichsprüfung — Calendar.date(from:) macht sonst Overflow
        let currentYear = Calendar.current.component(.year, from: Date())
        guard (1...12).contains(month),
              (1...31).contains(day),
              (1900...currentYear).contains(year)
        else { return nil }
        var comps = DateComponents()
        comps.day = day; comps.month = month; comps.year = year
        // date(from:) nochmal prüfen — fängt ungültige Tage ab (z.B. 31. Feb)
        guard let date = Calendar.current.date(from: comps),
              Calendar.current.component(.month, from: date) == month, // kein Overflow
              let min18 = Calendar.current.date(byAdding: .year, value: -18, to: Date()),
              date <= min18
        else { return nil }
        return date
    }

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Back-Button
                    if let back = onBack {
                        HStack {
                            Button(action: back) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.textSecondary).padding(12)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.top, 8)
                    }

                    // ── Profilfoto ────────────────────────────────────
                    Button { showImageSourceSheet = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 88, height: 88)
                            if let img = selfie {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 34))
                                    .foregroundColor(.textTertiary)
                            }
                            // Kamera-Badge
                            Circle()
                                .fill(stepColor)
                                .frame(width: 26, height: 26)
                                .overlay(Image(systemName: "camera.fill")
                                    .font(.system(size: 12)).foregroundColor(.white))
                                .offset(x: 30, y: 30)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24).padding(.bottom, 16)

                    VStack(spacing: 6) {
                        Text("Erzähl uns von dir")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary).multilineTextAlignment(.center)
                        Text("Dein Profil — einmalig, in einer Minute.")
                            .font(.system(size: 15)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 20) {

                        // ── Name ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Vorname", systemImage: "person.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            ZStack(alignment: .leading) {
                                if name.isEmpty {
                                    Text("Dein Vorname")
                                        .foregroundColor(.textTertiary).font(.system(size: 16))
                                        .padding(.leading, 16)
                                }
                                TextField("", text: $name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .focused($nameFocused)
                                    .autocorrectionDisabled()
                                    .textContentType(.givenName)
                                    .onChange(of: name) { v in
                                        let f = v.filter { $0.isLetter }
                                        if f != v { name = f }
                                    }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(stepColor.opacity(0.3), lineWidth: 1))
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                                Text("Kann nach der Registrierung nicht mehr geändert werden.")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // ── Geburtstag (Zahleneingabe) ────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Geburtstag", systemImage: "calendar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            ZStack(alignment: .leading) {
                                if birthdateText.isEmpty {
                                    Text("TT.MM.JJJJ")
                                        .foregroundColor(.textTertiary).font(.system(size: 16))
                                        .padding(.leading, 16)
                                }
                                TextField("", text: $birthdateText)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(dateIsValid ? .textPrimary : (birthdateText.count == 10 ? .red : .textPrimary))
                                    .keyboardType(.numberPad)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .focused($dateFocused)
                                    .onChange(of: birthdateText) { raw in
                                        let formatted = formatBirthdateInput(raw)
                                        if formatted != birthdateText { birthdateText = formatted }
                                        parsedBirthdate = parseBirthdate(birthdateText)
                                    }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(birthdateText.count == 10 && !dateIsValid
                                        ? Color.red.opacity(0.5) : stepColor.opacity(0.3), lineWidth: 1))
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                                Text("Kann nach der Registrierung nicht mehr geändert werden.")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // ── Geschlecht ────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Geschlecht", systemImage: "person.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            HStack(spacing: 10) {
                                ForEach(genderOptions, id: \.label) { opt in
                                    let isSelected = gender == opt.label
                                    Button { gender = opt.label } label: {
                                        VStack(spacing: 4) {
                                            if opt.isSF {
                                                Image(systemName: opt.symbol)
                                                    .font(.system(size: 18)).frame(height: 22)
                                            } else {
                                                Text(opt.symbol).font(.system(size: 20)).frame(height: 22)
                                            }
                                            Text(opt.label).font(.system(size: 12, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .foregroundColor(isSelected ? .white : .textPrimary)
                                        .background(RoundedRectangle(cornerRadius: 14)
                                            .fill(isSelected ? stepColor : Color.clear))
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.spring(response: 0.25), value: isSelected)
                                }
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                                Text("Kann nach der Registrierung nicht mehr geändert werden.")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // ── Telefonnummer (Pflicht) ──────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Handynummer", systemImage: "phone.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            ZStack(alignment: .leading) {
                                if phone.isEmpty {
                                    Text("+49 ...")
                                        .foregroundColor(.textTertiary).font(.system(size: 16))
                                        .padding(.leading, 16)
                                }
                                TextField("", text: $phone)
                                    .font(.system(size: 16))
                                    .foregroundColor(.textPrimary)
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            Text("Wird nicht öffentlich angezeigt. Deine Kontakte können dich nur so finden.")
                                .font(.system(size: 11)).foregroundColor(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)

                    // ── Weiter-Button ─────────────────────────────────
                    Button {
                        nameFocused = false
                        dateFocused = false
                        guard let bd = parsedBirthdate else { return }
                        onNext(name.trimmingCharacters(in: .whitespaces),
                               bd,
                               gender,
                               phone.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text("Weiter")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Capsule().fill(canContinue ? stepColor : stepColor.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .padding(.horizontal, 24)
                    .padding(.top, 28).padding(.bottom, 48)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                }
            }
        }
        .onAppear {
            appeared = true
            // Tastatur sofort beim Namen-Feld öffnen
            nameFocused = true
        }
        .confirmationDialog("Foto hinzufügen", isPresented: $showImageSourceSheet) {
            Button("Kamera") { imagePickerSource = .camera; showImagePicker = true }
            Button("Fotomediathek") { imagePickerSource = .photoLibrary; showImagePicker = true }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $selfie, isPresented: $showImagePicker,
                            sourceType: imagePickerSource)
        }
    }
}

// MARK: - Interests Step

struct InterestsStep: View {
    @Binding var selected: [String]
    let onNext: () -> Void
    let onBack: (() -> Void)?

    @State private var appeared = false
    @State private var shakeLimit = false
    private let maxSelections = 5
    private let stepColor = Color.brand

    private let options: [(key: String, icon: String, label: String)] = [
        ("interest.coffee",   "cup.and.saucer.fill",  "Kaffee"),
        ("interest.food",     "fork.knife",            "Essen"),
        ("interest.sport",    "figure.run",            "Sport"),
        ("interest.music",    "music.note",            "Musik"),
        ("interest.cinema",   "film.fill",             "Kino"),
        ("interest.gaming",   "gamecontroller.fill",   "Gaming"),
        ("interest.shopping", "bag.fill",              "Shopping"),
        ("interest.outdoor",  "leaf.fill",             "Outdoor"),
        ("interest.travel",   "airplane",              "Reisen"),
        ("interest.party",    "wineglass.fill",        "Ausgehen"),
        ("interest.photo",    "camera.fill",           "Fotos"),
        ("interest.cooking",  "flame.fill",            "Kochen"),
    ]

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)
            VStack(spacing: 0) {
                // Back
                if let back = onBack {
                    HStack {
                        Button(action: back) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary).padding(12)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }

                OnboardingPulseIcon(systemName: "star.fill", color: stepColor)
                    .padding(.top, 12).padding(.bottom, 16)

                VStack(spacing: 6) {
                    Text("Was interessiert dich?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary).multilineTextAlignment(.center)
                    // Counter hint
                    HStack(spacing: 4) {
                        Text(selected.isEmpty
                             ? "Bis zu 5 auswählen."
                             : "\(selected.count)/\(maxSelections) gewählt")
                            .font(.system(size: 15))
                            .foregroundColor(selected.count == maxSelections ? stepColor : .textSecondary)
                            .animation(.spring(response: 0.3), value: selected.count)
                    }
                    .offset(x: shakeLimit ? -6 : 0)
                    .animation(shakeLimit
                        ? .interpolatingSpring(stiffness: 600, damping: 8)
                        : .default, value: shakeLimit)
                }
                .padding(.horizontal, 28).padding(.bottom, 20)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(options, id: \.key) { opt in
                        let isSelected = selected.contains(opt.key)
                        let isDisabled = !isSelected && selected.count >= maxSelections
                        Button {
                            if isSelected {
                                selected.removeAll { $0 == opt.key }
                            } else if selected.count < maxSelections {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selected.append(opt.key)
                            } else {
                                // Already at max — shake the counter
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                shakeLimit = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shakeLimit = false }
                            }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : (isDisabled ? .textTertiary : stepColor))
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : (isDisabled ? .textTertiary : .textPrimary))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected ? stepColor : Color.clear)
                            )
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(isSelected ? Color.clear : Color.primary.opacity(isDisabled ? 0.06 : 0.12), lineWidth: 1))
                            .opacity(isDisabled ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.25), value: isSelected)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Button(action: onNext) {
                    Text(selected.isEmpty ? "Überspringen" : "Weiter")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Capsule().fill(stepColor))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24).padding(.bottom, 48)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}


// MARK: - Country Code Picker

struct CountryCode: Identifiable, Equatable {
    let id = UUID()
    let flag: String
    let name: String
    let dial: String
}

private let countryCodes: [CountryCode] = [
    CountryCode(flag: "🇩🇪", name: "Deutschland",    dial: "+49"),
    CountryCode(flag: "🇦🇹", name: "Österreich",     dial: "+43"),
    CountryCode(flag: "🇨🇭", name: "Schweiz",        dial: "+41"),
    CountryCode(flag: "🇺🇸", name: "USA",            dial: "+1"),
    CountryCode(flag: "🇬🇧", name: "Großbritannien", dial: "+44"),
    CountryCode(flag: "🇫🇷", name: "Frankreich",     dial: "+33"),
    CountryCode(flag: "🇮🇹", name: "Italien",        dial: "+39"),
    CountryCode(flag: "🇪🇸", name: "Spanien",        dial: "+34"),
    CountryCode(flag: "🇳🇱", name: "Niederlande",    dial: "+31"),
    CountryCode(flag: "🇧🇪", name: "Belgien",        dial: "+32"),
    CountryCode(flag: "🇵🇱", name: "Polen",          dial: "+48"),
    CountryCode(flag: "🇸🇪", name: "Schweden",       dial: "+46"),
    CountryCode(flag: "🇳🇴", name: "Norwegen",       dial: "+47"),
    CountryCode(flag: "🇩🇰", name: "Dänemark",       dial: "+45"),
    CountryCode(flag: "🇹🇷", name: "Türkei",         dial: "+90"),
    CountryCode(flag: "🇷🇺", name: "Russland",       dial: "+7"),
    CountryCode(flag: "🇯🇵", name: "Japan",          dial: "+81"),
    CountryCode(flag: "🇨🇳", name: "China",          dial: "+86"),
    CountryCode(flag: "🇮🇳", name: "Indien",         dial: "+91"),
    CountryCode(flag: "🇧🇷", name: "Brasilien",      dial: "+55"),
    CountryCode(flag: "🇦🇺", name: "Australien",     dial: "+61"),
    CountryCode(flag: "🇨🇦", name: "Kanada",         dial: "+1"),
    CountryCode(flag: "🇲🇽", name: "Mexiko",         dial: "+52"),
    CountryCode(flag: "🇰🇷", name: "Südkorea",       dial: "+82"),
    CountryCode(flag: "🇿🇦", name: "Südafrika",      dial: "+27"),
]

struct CountryPickerSheet: View {
    @Binding var selected: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var filtered: [CountryCode] {
        guard !search.isEmpty else { return countryCodes }
        return countryCodes.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.dial.contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { cc in
                Button {
                    selected = cc
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(cc.flag).font(.system(size: 22))
                        Text(cc.name)
                            .font(.system(size: 15))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(cc.dial)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                        if cc == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.brand)
                        }
                    }
                }
                .listRowBackground(Color.bgPrimary)
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Land suchen")
            .navigationTitle("Ländervorwahl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.brand)
                }
            }
        }
    }
}

// MARK: - Login View (für bereits registrierte Nutzer)

struct LoginView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @StateObject private var keyboard = KeyboardObserver()
    @StateObject private var auth = FirebaseAuthManager()
    @State private var phoneNumber = ""
    @State private var enteredCode = ""
    @State private var loginStep: LoginStep = .phone
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @FocusState private var fieldFocused: Bool
    @State private var appeared = false
    @State private var selectedCountry = countryCodes[0]
    @State private var showCountryPicker = false
    @State private var biometricError: String? = nil

    @Environment(\.colorScheme) var systemColorScheme

    enum LoginStep { case phone, code }

    // ── Identisches Farbsystem wie WelcomeStep ──
    private var isLight: Bool {
        switch systemColorScheme {
        case .light: return true
        case .dark:  return false
        default:     return !isNightTime()
        }
    }
    private var textPrimaryColor: Color   { isLight ? Color(hex: "1C1C1E") : .white }
    private var textSecondaryColor: Color { isLight ? Color(hex: "1C1C1E").opacity(0.45) : .white.opacity(0.5) }
    private var overlayColor: Color  { isLight ? .white : .black }
    private var overlayOpacity: Double { isLight ? 0.60 : 0.72 }
    private var mapBlur: CGFloat     { isLight ? 9 : 16 }
    private var fieldTint: Color     { isLight ? Color(hex: "1C1C1E").opacity(0.06) : Color.white.opacity(0.1) }
    private var fieldStroke: Color   { isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.14) }

    // ── Adaptive Größen je Gerät ──────────────────────────────────────────
    private var screenH: CGFloat { UIScreen.main.bounds.height }
    private var fieldPadV: CGFloat  { screenH < 700 ? 11 : screenH < 850 ? 13 : 15 }
    private var buttonPadV: CGFloat { screenH < 700 ? 12 : screenH < 850 ? 14 : 16 }
    private var formSpacing: CGFloat { screenH < 700 ? 10 : 14 }
    private var formFontSize: CGFloat { screenH < 700 ? 15 : 16 }
    private var logoSize: CGFloat { screenH < 700 ? 52 : 68 }

    // Biometrie-Typ ermitteln
    private var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ────────────────────────────────────
            AppAuroraBackground(isLight: isLight)

            VStack(spacing: 0) {
                    Spacer()

                    // ── Logo-Block ────────────────────────────────────────
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color.brand.opacity(isLight ? 0.08 : 0.12))
                                .frame(width: 200, height: 200)
                                .blur(radius: 40)

                            DropsLogo(fontSize: logoSize, textColor: textPrimaryColor)
                        }
                        .padding(.bottom, 18)

                        Text(tr("onboard.welcome_back"))
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(textSecondaryColor)
                            .kerning(0.3)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // ── Formular & Buttons ────────────────────────────────
                    VStack(spacing: formSpacing) {
                        if loginStep == .phone {
                            // Telefonnummer-Eingabe
                            HStack(spacing: 8) {
                                Button { showCountryPicker = true } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedCountry.flag).font(.system(size: 17))
                                        Text(selectedCountry.dial)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(textPrimaryColor)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(textSecondaryColor)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, fieldPadV)
                                    .background(fieldTint, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(fieldStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)

                                TextField("", text: $phoneNumber)
                                    .placeholder(when: phoneNumber.isEmpty) {
                                        Text(tr("onboard.phone_number")).foregroundColor(textSecondaryColor.opacity(0.6))
                                    }
                                    .font(.system(size: formFontSize))
                                    .foregroundColor(textPrimaryColor)
                                    .keyboardType(.phonePad)
                                    .focused($fieldFocused)
                                    .padding(.horizontal, 14).padding(.vertical, fieldPadV)
                                    .background(fieldTint, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(fieldFocused ? Color.brand.opacity(0.7) : fieldStroke,
                                                lineWidth: 1.5))
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button(action: { sendLoginSMS() }) {
                                HStack {
                                    if isLoading { ProgressView().tint(phoneNumber.count >= 6 ? .white : textPrimaryColor) }
                                    else { Text(tr("onboard.send_code_arrow")).font(.system(size: 16, weight: .semibold)) }
                                }
                                .foregroundColor(phoneNumber.count >= 6 ? .white : textSecondaryColor)
                                .frame(maxWidth: .infinity).padding(.vertical, buttonPadV)
                                .background(
                                    Capsule()
                                        .fill(phoneNumber.count >= 6 ? Color.brand : (isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.15)))
                                        .shadow(color: phoneNumber.count >= 6 ? Color.brand.opacity(0.4) : .clear,
                                                radius: 14, y: 6)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(phoneNumber.count < 6 || isLoading)
                            .animation(.easeInOut(duration: 0.2), value: phoneNumber.count >= 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            // ── Biometrie ────────────────────────────────
                            if biometricAvailable {
                                HStack(spacing: 10) {
                                    Rectangle().fill(textSecondaryColor.opacity(0.15)).frame(height: 1)
                                    Text(tr("common.or"))
                                        .font(.system(size: 12))
                                        .foregroundColor(textSecondaryColor.opacity(0.6))
                                    Rectangle().fill(textSecondaryColor.opacity(0.15)).frame(height: 1)
                                }

                                Button(action: { loginWithBiometrics() }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                                            .font(.system(size: 20))
                                        Text(biometricType == .faceID ? "Mit Face ID anmelden" : "Mit Touch ID anmelden")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(textPrimaryColor)
                                    .frame(maxWidth: .infinity).padding(.vertical, buttonPadV - 1)
                                    .background(fieldTint, in: Capsule())
                                    .overlay(Capsule().stroke(fieldStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }

                        } else {
                            // Code-Eingabe
                            Text("Code an \(selectedCountry.dial) \(phoneNumber) gesendet")
                                .font(.system(size: 13))
                                .foregroundColor(textSecondaryColor)
                                .transition(.opacity)

                            TextField("", text: $enteredCode)
                                .placeholder(when: enteredCode.isEmpty) {
                                    Text(tr("onboard.six_digit_code"))
                                        .foregroundColor(textSecondaryColor.opacity(0.6))
                                        .font(.system(size: 22, weight: .semibold))
                                }
                                .font(.system(size: 28, weight: .bold))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .foregroundColor(textPrimaryColor)
                                .focused($fieldFocused)
                                .onChange(of: enteredCode) { v in
                                    if v.count > 6 { enteredCode = String(v.prefix(6)) }
                                }
                                .padding(.vertical, fieldPadV)
                                .background(fieldTint, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.brand.opacity(0.5), lineWidth: 1.5))
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button(action: { verifyLoginCode() }) {
                                HStack {
                                    if isLoading { ProgressView().tint(enteredCode.count == 6 ? .white : textPrimaryColor) }
                                    else { Text(tr("onboard.sign_in_arrow")).font(.system(size: 16, weight: .semibold)) }
                                }
                                .foregroundColor(enteredCode.count == 6 ? .white : textSecondaryColor)
                                .frame(maxWidth: .infinity).padding(.vertical, buttonPadV)
                                .background(
                                    Capsule()
                                        .fill(enteredCode.count == 6 ? Color.brand : (isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.15)))
                                        .shadow(color: enteredCode.count == 6 ? Color.brand.opacity(0.4) : .clear,
                                                radius: 14, y: 6)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(enteredCode.count < 6 || isLoading)
                            .animation(.easeInOut(duration: 0.2), value: enteredCode.count == 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button("Andere Nummer") {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    loginStep = .phone; enteredCode = ""
                                }
                            }
                            .font(.system(size: 13)).foregroundColor(textSecondaryColor.opacity(0.7))
                            .transition(.opacity)
                        }

                        if let err = errorMessage ?? biometricError {
                            Text(err).font(.system(size: 12)).foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: loginStep)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25), value: appeared)

                    Button(action: { hasOnboarded = false }) {
                        Text(tr("onboard.no_account_register"))
                            .font(.system(size: 13))
                            .foregroundColor(textSecondaryColor.opacity(0.6))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, keyboard.height > 0 ? 16 : 40)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboard.height)
                }
            .padding(.top, 12)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onTapGesture { fieldFocused = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { fieldFocused = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brand)
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .onAppear {
            appeared = true
            // Tastatur NICHT automatisch öffnen
        }
    }

    private func loginWithBiometrics() {
        let context = LAContext()
        let reason = biometricType == .faceID
            ? "Mit Face ID in Drops einloggen"
            : "Mit Touch ID in Drops einloggen"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    biometricError = nil
                    store.isAuthenticated = true
                } else {
                    // Fehler nur zeigen wenn nicht abgebrochen (LAError.userCancel = -2)
                    if let laErr = error as? LAError, laErr.code != .userCancel {
                        biometricError = "Biometrie fehlgeschlagen – bitte mit SMS einloggen."
                    }
                }
            }
        }
    }

    private func sendLoginSMS() {
        guard phoneNumber.count >= 6 else {
            errorMessage = "Bitte gib eine gültige Nummer ein."
            return
        }
        isLoading = true; errorMessage = nil; biometricError = nil
        let fullNumber = selectedCountry.dial + phoneNumber
        Task {
            await auth.sendVerificationCode(to: fullNumber)
            isLoading = false
            if case .smsSent = auth.state {
                withAnimation(.easeInOut(duration: 0.22)) { loginStep = .code }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fieldFocused = true }
            } else if case .error(let msg) = auth.state {
                errorMessage = msg
            }
        }
    }

    private func verifyLoginCode() {
        isLoading = true; errorMessage = nil
        Task {
            let ok = await auth.verifyCode(enteredCode)
            isLoading = false
            if ok {
                store.isAuthenticated = true
            } else if case .error(let msg) = auth.state {
                errorMessage = msg
            }
        }
    }
}

// MARK: - App Intro Step (nach Registrierung)

struct AppIntroStep: View {
    let onFinish: () -> Void

    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    private let accentColor = Color(hex: "22c55e")

    private struct Feature {
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
    }

    private let features: [Feature] = [
        Feature(icon: "plus.circle.fill",      color: Color(hex: "22c55e"),
                title: "Drop erstellen",
                subtitle: "Wähle eine Aktivität, tippe auf ＋ — dein Drop erscheint sofort auf der Karte."),
        Feature(icon: "map.fill",              color: Color(hex: "06b6d4"),
                title: "In Echtzeit entdecken",
                subtitle: "Sieh welche Drops gerade aktiv sind und spring spontan rein."),
        Feature(icon: "lock.shield.fill",      color: Color(hex: "8b5cf6"),
                title: "Privatsphäre inklusive",
                subtitle: "Kein dauerhaftes Speichern. Drops laufen automatisch ab."),
    ]

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: accentColor)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // ── App-Icon + Titel ──────────────────────────────────────
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 88, height: 88)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: appeared)

                    VStack(spacing: 6) {
                        Text("Willkommen bei Drops")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Spontan treffen. Ohne Planung.")
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: appeared)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 32)

                // ── Feature-Reihen (Fitness+-Stil) ────────────────────────
                VStack(spacing: 0) {
                    ForEach(features.indices, id: \.self) { idx in
                        let f = features[idx]
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(f.color.opacity(0.14))
                                    .frame(width: 48, height: 48)
                                Image(systemName: f.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(f.color)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(f.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                            .delay(0.18 + Double(idx) * 0.08), value: appeared)

                        if idx < features.count - 1 {
                            Divider()
                                .padding(.leading, 88)
                                .opacity(0.5)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)

                Spacer(minLength: 32)

                // ── Los geht's Button ─────────────────────────────────────
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFinish()
                } label: {
                    Text(tr("onboard.lets_go"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.42), value: appeared)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - ID-Verifizierungsflow (disabled — verification removed)

#if false



#endif // ID verification removed
