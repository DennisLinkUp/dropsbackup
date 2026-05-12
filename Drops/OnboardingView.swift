import SwiftUI
import MapKit
import AuthenticationServices
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
                        print("[auth] Tombstone gefunden → fresh registration")
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }

                    // ── Doppelter Sicherheitscheck ───────────────────────
                    // Tombstone-Check kann fehlschlagen (RTDB-Permission,
                    // Network-Race, eventual consistency). Bevor wir bei
                    // isNewUser=false stumm einloggen, verifizieren wir
                    // dass das Profil tatsächlich noch in RTDB existiert.
                    // Falls nicht → Account wurde gelöscht, fresh registration.
                    let profileExists: Bool = await withCheckedContinuation { cont in
                        RealtimeDBManager.shared.hasExistingProfile { exists in
                            cont.resume(returning: exists)
                        }
                    }

                    if !isNewUser && profileExists {
                        // Echter Bestandsuser mit intaktem Profil → einloggen
                        handleAppleSignInResult(exists: true)
                        return
                    }

                    if !isNewUser && !profileExists {
                        // Firebase kennt den User, aber das Profil ist weg →
                        // resurrektion nach Account-Löschung. Fresh registration.
                        print("[auth] isNewUser=false aber kein Profil in RTDB → resurrection")
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }

                    // isNewUser=true → echte Neuregistrierung
                    if profileExists {
                        // Edge-Case: Firebase sagt "neu" aber Profil existiert (sollte
                        // selten sein, z.B. Conflict zwischen Auth-Methoden) → einloggen.
                        handleAppleSignInResult(exists: true)
                    } else {
                        handleAppleSignInResult(exists: false)
                    }
                }
            },
            isLoginMode: $isLoginMode,
            onBetaLogin: nil
        )
        // Default: immer Register-Modus (nicht hasOnboarded) — neue Marketing-
        // Strategie. User der schon Konto hat, klickt einfach den „Schon
        // registriert? Anmelden"-Toggle drunter.
        .onAppear { isLoginMode = false }
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
                // Content-Filter auf den Profilnamen — keine Slurs,
                // Beleidigungen oder Sexual-Solicitation als Anzeigename.
                if let match = ContentFilter.firstMatch(profileName: name) {
                    store.showInfoToast(
                        "Dieser Name enthält ein blockiertes Wort (\"\(match.word)\"). Bitte einen anderen wählen.",
                        icon: "exclamationmark.shield.fill"
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        .onAppear {
            // Vorname aus Apple-ID übernehmen — nur wenn das Namensfeld noch leer ist
            // und Apple ihn uns beim initialen Login geliefert hat. Apple sendet
            // fullName nur beim ersten Sign-In, deshalb persistieren wir ihn in
            // UserDefaults (siehe FirebaseAuthManager) und lesen ihn hier zurück.
            if userName.isEmpty {
                if let given = UserDefaults.standard.string(forKey: "ud_appleGivenName"),
                   !given.isEmpty {
                    userName = given
                } else if let display = Auth.auth().currentUser?.displayName,
                          let firstWord = display.split(separator: " ").first,
                          !firstWord.isEmpty {
                    // Fallback: Firebase displayName (wird aus Apple-fullName gesetzt)
                    userName = String(firstWord)
                    UserDefaults.standard.set(String(firstWord), forKey: "ud_appleGivenName")
                }
            }
        }
    }

    @ViewBuilder private var interestsStepView: some View {
        InterestsStep(
            selected: $store.userInterests,
            onNext: {
                store.saveAll()
                // Permissions (Push + Location) direkt hier anfragen — der
                // AppIntroStep ist entfernt, weil das MainTabView-WelcomeSheet
                // bereits die Features zeigt.
                requestOnboardingPermissions()
                withAnimation(.spring(response: 0.4)) { step = .done }
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
            // FCM-Token in RTDB schreiben — der Token kam ggf. schon vor Auth (OnApp-Start),
            // konnte aber mangels User-UID nicht persistiert werden. Jetzt nachholen.
            if let token = UserDefaults.standard.string(forKey: "fcmToken"), !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token)
            }
            // App-Invite-Bonus: wenn der User via Einladungs-Link hergekommen ist,
            // kriegt der Einladende (via Firebase-Transaction) +10 Punkte gutgeschrieben.
            // pendingInviteUsername enthält die UID des Einladenden (aus /invite/{uid}).
            if let inviterUID = store.pendingInviteUsername, !inviterUID.isEmpty {
                RealtimeDBManager.shared.creditAppInviteBonus(inviterUID: inviterUID)
                store.pendingInviteUsername = nil
            }
            // Freundes-Observer starten (noch keine Freunde, aber für zukünftige Adds)
            if let uid = Auth.auth().currentUser?.uid {
                store.startObservingFriends(ownerUID: uid)
                store.startObservingAdminNotices()
            }
            // Online-Heartbeat — sonst sieht einen Freunde nicht als "online" bis
            // zur ersten Background-Return.
            RealtimeDBManager.shared.markOnlineHeartbeat()
            store.isAuthenticated = true
        }
    }

    @ViewBuilder private var underageStepView: some View {
        UnderAgeBlockView { withAnimation(.spring(response: 0.4)) { step = .birthday } }
    }


    /// Fragt Push, Standort UND Bluetooth-Berechtigung am Ende des Onboardings
    /// an. Reihenfolge bewusst gewählt:
    ///   1. Push (am wenigsten kritisch, Default-Allow bei vielen Usern)
    ///   2. Standort (Drop-Suche kernfunktion, hohe Akzeptanz erwartet)
    ///   3. Bluetooth (Anwesenheits-Bestätigung — Drops-USP, vorher
    ///      vergessen → User wurde erst im Map-View beim ersten Join
    ///      gefragt, ohne Kontext)
    /// Alle 3 mit kurzem Stagger damit iOS die Sheets nicht aufeinanderstapelt.
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
        // 2. Standort (falls noch nicht bestimmt) — kurzer Versatz damit
        // das iOS-Sheet nicht das Push-Sheet überlappt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Property halten damit ARC den Manager nicht sofort freigibt
            let locManager = CLLocationManager()
            self.onboardingLocManager = locManager
            if locManager.authorizationStatus == .notDetermined {
                locManager.requestWhenInUseAuthorization()
            }
        }
        // 3. Bluetooth — Trigger durch *Touch* an den BluetoothMeetupManager,
        // der den CBCentralManager initialisiert. iOS zeigt dann automatisch
        // den Bluetooth-Permission-Prompt (NSBluetoothAlwaysUsageDescription
        // aus Info.plist). Wichtig: das passiert erst beim ersten Manager-
        // Zugriff — wir touchen den hier proaktiv, damit der User die
        // Berechtigung direkt im Onboarding-Flow setzt statt erst beim
        // ersten Drop-Join in der Map.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.store.bluetoothMeetup.warmUpForPermissionPrompt()
        }
    }

    /// Verarbeitet das Ergebnis des Apple-Sign-In Profil-Checks.
    private func handleAppleSignInResult(exists: Bool) {
        if exists {
            // Bestehender Account — einloggen egal ob login- oder register-Modus.
            //
            // WICHTIG: `isAuthenticated = true` **erst** feuern, wenn die Firebase-
            // Daten (Name, Radius, Altersfilter, Profilbild-URL) im Store liegen —
            // sonst mountet MainTabView mit stalem State, rendert Glass-Cards mit
            // der falschen Höhe, und nach dem Firebase-Update sitzt der Glass-
            // Hintergrund versetzt (v.a. iOS 26 `glassEffect`, das die Shape
            // beim Layout-Wechsel nicht sauber invalidiert).
            isLoading = true
            hasOnboarded = true
            // Welcome-Sheet nur bei echter Neuregistrierung — Re-Login skipt ihn.
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            // FCM-Token nachziehen (Token kam ggf. vor Login → noch nicht persistiert)
            if let token = UserDefaults.standard.string(forKey: "fcmToken"), !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token)
            }
            // Online-Heartbeat — markiert User als "online" für Freundes-Observer
            RealtimeDBManager.shared.markOnlineHeartbeat()
            // Profilbild-URL parallel zum Profil laden (beides hängt am selben UID-Token).
            store.loadProfileImageURL()

            // Safety: falls Firebase hängt, nach 3s trotzdem durchlassen —
            // der User soll nicht auf einer Loading-Spinner-Insel festsitzen.
            var didComplete = false
            let finishAuth: () -> Void = {
                guard !didComplete else { return }
                didComplete = true
                isLoading = false
                store.isAuthenticated = true
                // Freundes-Observer neu starten — `init()` läuft nur einmal,
                // nach Logout ist er gestoppt. Ohne das bleibt die Freundes-
                // liste bei Re-Login ohne App-Neustart leer.
                if let uid = Auth.auth().currentUser?.uid {
                    store.startObservingFriends(ownerUID: uid)
                store.startObservingAdminNotices()
                }
                // Profilbild-Re-Retrigger falls die erste Runde kein URL hatte
                // (z.B. Token-Race) — jetzt sollte Auth komplett durchgerouted sein.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [store] in
                    if store.profileImageURL == nil || (store.profileImageURL?.isEmpty ?? true) {
                        store.loadProfileImageURL()
                    }
                }
            }
            // Safety-Fallback: wenn Firebase unerwartet hängt, max 1.2s warten.
            // Normal returnt RTDB unter 500ms — der Timeout ist nur für Edge-Cases
            // (Netz weg, DB langsam) damit der User nicht auf dem Login-Screen
            // festsitzt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finishAuth() }

            loadProfileFromFirebase {
                finishAuth()
            }
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
        // Namen persistent für Quick-Login merken
        if !store.currentUser.name.isEmpty {
            UserDefaults.standard.set(store.currentUser.name, forKey: "ud_lastLoginName")
        }
    }

    /// Lädt das Profil aus Firebase und befüllt den Store (z.B. nach Re-Login).
    /// `completion` wird auf Main gefeuert, sobald die Daten (oder ein Fehler) verarbeitet
    /// wurden — Aufrufer können so warten, bevor sie `isAuthenticated = true` setzen.
    private func loadProfileFromFirebase(completion: (() -> Void)? = nil) {
        // Admin-Check per E-Mail (Bootstrap-Credentials siehe AdminConfig)
        let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        if AdminConfig.isBootstrapAdmin(authEmail: authEmail, storedAppleEmail: storedApple) {
            self.store.isAdmin = true
        }
        RealtimeDBManager.shared.loadUserProfile { profile in
            defer {
                DispatchQueue.main.async { completion?() }
            }
            guard let p = profile else { return }
            if let name = p.name, !name.isEmpty {
                self.store.currentUser.name = name
                // Persistiert den Namen für den Quick-Login-Button auf
                // dem Welcome-Screen — überlebt Logout (anders als UDKey.userName).
                UserDefaults.standard.set(name, forKey: "ud_lastLoginName")
            }
            if let bd = p.birthdate             { self.store.userBirthdate = bd }
            if let gender = p.gender            { self.store.userGender = gender }
            if p.isAdmin                        { self.store.isAdmin = true }

            // Benutzer-Einstellungen (Radius, Altersfilter, Interests, Blocklist …)
            // aus Firebase wiederherstellen — sonst fallen die nach Logout auf Default.
            self.store.applyRemoteUserSettings(p.settings)
        }
    }
}

// MARK: - Drops Logo (Cleane Wordmark — kein Mark)
// Reduziert auf nur das Wort "Drops" in lighter Schrift, ohne den Pulse-Mark
// daneben. Passt zur cleanen Website-Optik (Bricolage Grotesque 700 dort).
// Auf iOS: SF Pro Bold (700) statt Black (900) — leichter, eleganter.

struct DropsLogo: View {
    var fontSize: CGFloat = 52
    var textColor: Color = .white
    /// Wenn true → die Wordmark sitzt in einer Liquid-Glass-Capsule mit
    /// dezenter Text-Gradient. Default false damit Bestandsstellen
    /// (z.B. WelcomeSheet im Header) ihren cleaneren Look behalten.
    var glassy: Bool = false

    /// Schrift: `.rounded` + `.heavy` — chunkige, runde Buchstaben passen
    /// zum App-Icon-„D" (kompakter Halbkreis mit fetten Strichen).
    /// `.default` mit `.bold` war schlanker und passte nicht zur Icon-DNA.
    private var dropsFont: Font {
        .system(size: fontSize, weight: .heavy, design: .rounded)
    }

    var body: some View {
        if glassy {
            glassWordmark
        } else {
            plainText
        }
    }

    private var plainText: some View {
        Text("Drops")
            .font(dropsFont)
            .tracking(-fontSize * 0.015)
            .foregroundColor(textColor)
    }

    /// „Drops" mit Custom-D in Icon-Proportionen + „rops" als SF-Text.
    /// Das D ist ein Path-Render basierend auf dem App-Icon-LetterD-D.svg
    /// (chunky-runde Form, etwas breiter als ein normales SF-Heavy-D).
    /// Das gibt dem Wordmark sofort die Icon-Identity zurück.
    private var glassWordmark: some View {
        // D-Höhe sollte zur Cap-Height von "rops" passen (~70% fontSize bei
        // SF .heavy .rounded). Wir machen's leicht größer als cap-height
        // damit das D als Akzent etwas hervorsteht — wie im Logo.
        let dHeight = fontSize * 0.92
        // Aspect-Ratio des Icon-D-Pfads: Outer-Bounding x:264-792, y:232-792
        // → 528/560 ≈ 0.94 — ist also fast quadratisch, etwas breiter als
        // ein typisches SF-Heavy-D (das eher 0.72 wide ist).
        let dWidth = dHeight * 0.94

        return HStack(alignment: .firstTextBaseline, spacing: -fontSize * 0.04) {
            // Custom-D — solider Fill (LetterDShape hat Outer + Inner Path,
            // beide mit normaler .fill rendern den Outer-Pfad solide,
            // Inner liegt darin und wird überzeichnet). Vorher war hier
            // hartkodiert .white — das lässt die Wordmark im Light-Mode
            // verschwinden. Jetzt nutzt es `textColor` wie der plainText-
            // Pfad, damit die glassy-Variante auf dem LoginScreen im
            // Light-Mode mit dunklem Text und im Dark-Mode mit weiß
            // sauber rendert.
            LetterDShape()
                .fill(textColor)
                .frame(width: dWidth, height: dHeight)
                // Vertikales Alignment: D-Path-Top sitzt höher als die
                // Cap-Height vom Text, leichter Y-Offset zentriert ihn
                // visuell auf die Buchstabenlinie der "rops".
                .alignmentGuide(.firstTextBaseline) { d in d.height * 0.86 }

            Text("rops")
                .font(dropsFont)
                .tracking(-fontSize * 0.015)
                .foregroundColor(textColor)
        }
        // Orange-Glow oben-links — wie der Icon-Top
        .shadow(color: Color(hex: "E48C3A").opacity(0.65), radius: 24, x: -2, y: -3)
        // Grün-Glow unten-rechts — wie der Icon-Bottom
        .shadow(color: Color(hex: "5FA937").opacity(0.55), radius: 22, x: 3, y: 4)
        // Subtle dunkler Drop-Shadow für Boden-Definition
        .shadow(color: Color.black.opacity(0.22), radius: 10, y: 7)
    }
}

// MARK: - Drops Icon Hero
//
// SwiftUI-Replik des App-Icons als Login/Welcome-Hero. Spiegelt die
// Komposition aus icon.json wider:
//   - Orange→Grün Gradient (vertikal) als Hintergrund
//   - Hohler "D"-Buchstabe weiß zentriert
//   - Radar-Punkt + zwei pulsierende Wellen oben-rechts vom D
//
// Die Wellen pulsieren in 1.8s-Loops mit 0.6s Stagger — wirkt wie ein
// aktives "Sender"-Signal, passt zur Drops-Identity ("Spontan treffen").
// MARK: - Radar Pulse Divider
//
// Kleiner animierter Radar-Trenner für den Login: drei weiße Halbkreis-
// Wellen die direkt unterhalb der "Drops"-Wordmark entspringen und nach
// unten expandieren und faden — wie das Radar aus dem App-Icon, aber als
// horizontales Spacer-Element. Kein Sender-Dot, weil der Anker visuell
// die Wordmark selbst ist (Wellen "strömen" aus dem Text).
//
// Die Wellen sind staggered (0s/0.6s/1.2s Delay), jede einzelne Welle
// expandiert in 1.8s von 0.4× auf 1.0× Scale und fadet 80% → 0% Opacity.
// Repeat-forever erzeugt einen kontinuierlichen "Sendet"-Vibe.
struct RadarPulseDivider: View {
    var width: CGFloat = 140
    var color: Color = .white

    @State private var w0 = false
    @State private var w1 = false
    @State private var w2 = false

    /// Animation-Timing — zentral hier, damit Stagger und Loop synchron
    /// bleiben wenn man den Look anpasst. Werte gewählt für „natürliches"
    /// Radar/Wassertropfen-Feeling: lange Easing-Out-Kurve, viel Atemraum
    /// zwischen den Wellen. Cycle-Total = duration → wenn duration ein
    /// Vielfaches von stagger × 3 ist, läuft der Loop nahtlos.
    private static let waveDuration: Double = 4.5   // entspannter, natürlich
    private static let waveStagger: Double = 1.5    // 1.5s zwischen Wellen
    private static let waveBaseScale: CGFloat = 0.3
    private static let waveMaxScale: CGFloat = 1.7   // weit nach unten
    private static let waveLineWidth: CGFloat = 4.5  // dicker

    /// Halbkreis-Wave: ein 180°-Bogen am oberen Rand des Frames, mit
    /// Stroke-Round-Caps. Wird per `.scaleEffect(_:anchor: .top)`
    /// vom Top-Center aus expandiert (= Anker direkt am Wordmark-Bottom).
    @ViewBuilder
    private func wave(active: Bool, opacity: Double) -> some View {
        SemiCircleShape()
            .stroke(color, style: StrokeStyle(lineWidth: Self.waveLineWidth, lineCap: .round))
            .frame(width: width, height: width / 2)
            .scaleEffect(active ? Self.waveMaxScale : Self.waveBaseScale, anchor: .top)
            .opacity(active ? 0.0 : opacity)
    }

    var body: some View {
        // Frame bleibt schmal — Welle scaled über `waveMaxScale > 1`
        // visuell über das Frame raus, ohne das umgebende Layout
        // (Slogan, Buttons) nach unten zu verschieben.
        ZStack(alignment: .top) {
            wave(active: w2, opacity: 0.45)
            wave(active: w1, opacity: 0.65)
            wave(active: w0, opacity: 0.85)
        }
        .frame(width: width, height: width / 2)
        .onAppear {
            // Drei Wellen zeitversetzt anstoßen — Stagger 1s ergibt einen
            // ruhigen, kontinuierlichen Sweep statt hektischem Flackern.
            withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                w0 = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.waveStagger) {
                withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                    w1 = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.waveStagger * 2) {
                withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                    w2 = true
                }
            }
        }
    }
}

/// Halbkreis-Bogen am oberen Rand — Mittelpunkt zentral oben, Bogen
/// öffnet nach unten (180° Sweep von 0° → 180°).
private struct SemiCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: 0),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        return path
    }
}

struct DropsIconHero: View {
    var size: CGFloat = 120

    @State private var wave1Animate = false
    @State private var wave2Animate = false

    /// iOS-App-Icon-Ratio (~22.5% des kleineren Achsmaßes).
    private var cornerRadius: CGFloat { size * 0.225 }

    var body: some View {
        ZStack {
            // Gradient-Background (orange oben → grün unten, wie icon.json)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "E48C3A"), Color(hex: "5FA937")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: "E48C3A").opacity(0.35), radius: 30, y: 12)

            // Innerer Glanz-Stroke für Liquid-Glass-Feel
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

            // Letter-D — hohler Buchstabe, eo-Fill schneidet das Innere weg.
            // Subtle white shadow gibt einen kleinen Liquid-Glass-Glow.
            LetterDShape()
                .fill(Color.white, style: FillStyle(eoFill: true))
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: -size * 0.04, y: 0)
                .shadow(color: .white.opacity(0.35), radius: size * 0.04)

            // Radar-Wellen + Punkt oben-rechts vom D, gestaffelt animiert.
            ZStack {
                // Wave 2 (außen) — größer, dezenter
                Circle()
                    .trim(from: 0.0, to: 0.18)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .rotationEffect(.degrees(-25))
                    .frame(width: size * 0.36, height: size * 0.36)
                    .opacity(wave2Animate ? 0.0 : 0.65)
                    .scaleEffect(wave2Animate ? 1.3 : 0.85)

                // Wave 1 (innen) — kleiner, kräftiger
                Circle()
                    .trim(from: 0.0, to: 0.18)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .rotationEffect(.degrees(-25))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .opacity(wave1Animate ? 0.0 : 0.85)
                    .scaleEffect(wave1Animate ? 1.4 : 0.9)

                // Radar-Dot (Sender, statisch)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.07, height: size * 0.07)
            }
            .offset(x: size * 0.22, y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                wave1Animate = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    wave2Animate = true
                }
            }
        }
    }
}

/// Hohler D-Buchstabe als SwiftUI-Path — 1:1 Replik des LetterD-D.svg.
/// Outer-Path + Inner-Path, beide CW gezeichnet → mit `FillStyle(eoFill: true)`
/// bekommt der innere Pfad einen Cutout-Effekt (klassischer "donut hole").
private struct LetterDShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024.0
        var path = Path()

        // ── Outer D ────────────────────────────────────────────
        path.move(to: CGPoint(x: 314 * s, y: 232 * s))
        path.addLine(to: CGPoint(x: 512 * s, y: 232 * s))
        // Großer Halbkreis nach rechts (bulge)
        path.addArc(center: CGPoint(x: 512 * s, y: 512 * s),
                    radius: 280 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 314 * s, y: 792 * s))
        // Bottom-left rounded corner
        path.addArc(center: CGPoint(x: 314 * s, y: 742 * s),
                    radius: 50 * s,
                    startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 264 * s, y: 282 * s))
        // Top-left rounded corner
        path.addArc(center: CGPoint(x: 314 * s, y: 282 * s),
                    radius: 50 * s,
                    startAngle: .degrees(180), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()

        // ── Inner Cutout ───────────────────────────────────────
        path.move(to: CGPoint(x: 414 * s, y: 342 * s))
        path.addLine(to: CGPoint(x: 512 * s, y: 342 * s))
        path.addArc(center: CGPoint(x: 512 * s, y: 512 * s),
                    radius: 170 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 414 * s, y: 682 * s))
        path.addArc(center: CGPoint(x: 414 * s, y: 642 * s),
                    radius: 40 * s,
                    startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 374 * s, y: 382 * s))
        path.addArc(center: CGPoint(x: 414 * s, y: 382 * s),
                    radius: 40 * s,
                    startAngle: .degrees(180), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()

        return path
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
    var onBetaLogin: (() -> Void)? = nil   // Beta-Bypass: anonym einloggen

    @Environment(\.colorScheme) var systemColorScheme
    @State private var appeared = false
    @State private var typedSlogan = ""
    @State private var showCursor = false
    @State private var typewriterTask: Task<Void, Never>? = nil
    @StateObject private var appleAuth = AppleSignInManager()

    // Quick-Login: wenn der letzte User im UserDefaults persistiert ist,
    // zeigen wir oberhalb der Standard-Apple-Buttons einen großen "Weiter
    // als X"-Button mit Avatar + Name. Tap löst sofort Apple Sign In aus
    // (Face ID übernimmt in ~1-2s, keine weitere Eingabe nötig).
    @State private var showAlternativeLogin = false
    private var lastLoginName: String {
        UserDefaults.standard.string(forKey: "ud_lastLoginName") ?? ""
    }
    private var lastLoginImageURL: String? {
        let url = UserDefaults.standard.string(forKey: "ud_lastProfileImageURL") ?? ""
        return url.isEmpty ? nil : url
    }
    /// Quick-Login sichtbar, sobald ein Name persistiert ist. Bleibt auch
    /// sichtbar wenn der User "Anderes Konto verwenden" wählt — er sieht
    /// dann beide Optionen gleichzeitig (Quick-Login oben + alternative
    /// Apple-Sign-In/Sign-Up unten).
    private var hasQuickLogin: Bool {
        !lastLoginName.isEmpty
    }

    /// Slogan-Konstante — synchron zum Login-Block-Slogan und der App-
    /// Store-Subtitle „Drops — Triff Leute". Wird vom Typewriter konsumiert
    /// falls aktiviert. Vorher: "Sei dabei wenn's passiert." (out of sync).
    private let fullSlogan = "Triff Leute. Spontan."

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
    // Wordmark deutlich größer als vorher (52/68 → 64/82) — gibt dem
    // "Drops"-Hero mehr Präsenz auf dem Aurora, passt zur reduzierten
    // Layout-Hierarchie (kein Icon mehr drüber).
    private var logoSize: CGFloat { screenH < 700 ? 64 : 82 }
    private var buttonPadV: CGFloat { screenH < 700 ? 12 : screenH < 850 ? 14 : 16 }

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ────────────────────────────────────
            AppAuroraBackground(isLight: isLight)

            // ── Inhalt ───────────────────────────────────────────────
            VStack(spacing: 0) {
                    Spacer(minLength: screenH < 700 ? 30 : 60)

                    // ── Logo + Hero ────────────────────────────────────
                    VStack(spacing: screenH < 700 ? 18 : 26) {
                        // Wordmark mit Aurora-Glow als Background — die
                        // Glow-Circles sind rein dekorativ und expandieren
                        // das Layout NICHT (sonst würde der Slogan zu weit
                        // unten sitzen). Bewusst KEIN Radar-Pulse mehr —
                        // der globale `AppAuroraBackground` liefert schon
                        // ambient Bewegung, doppelte Animation hier wäre
                        // visuelle Überladung auf einem Welcome-Screen.
                        // Normale SF-Rounded-Heavy-Wordmark — der Custom-D
                        // (LetterDShape) wirkte mit dem Aurora-Glow drum
                        // herum zu busy. Auf User-Wunsch ein einheitlicher
                        // Look mit dem Login-Screen.
                        DropsLogo(fontSize: logoSize, textColor: textPrimary)
                            .background {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "E48C3A").opacity(isLight ? 0.14 : 0.20))
                                        .frame(width: 240, height: 240)
                                        .blur(radius: 48)
                                        .offset(x: -20, y: -30)
                                    Circle()
                                        .fill(Color(hex: "5FA937").opacity(isLight ? 0.10 : 0.14))
                                        .frame(width: 180, height: 180)
                                        .blur(radius: 38)
                                        .offset(x: 30, y: 30)
                                }
                                .allowsHitTesting(false)
                            }

                        // Hauptbotschaft — knüpft an den App-Store-Untertitel
                        // ("Drops — Triff Leute") an. Erste Zeile = Brand-Anker
                        // identisch zum Store, zweite Zeile pointiert den
                        // Spontan-Charakter der App.
                        VStack(spacing: 6) {
                            Text("Triff Leute.")
                                .font(.system(size: screenH < 700 ? 28 : 32, weight: .bold, design: .default))
                                .foregroundColor(textPrimary)
                            Text("Spontan.")
                                .font(.system(size: screenH < 700 ? 28 : 32, weight: .bold, design: .default))
                                .foregroundColor(textPrimary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 20)

                    // ── Buttons ───────────────────────────────────────
                    VStack(spacing: screenH < 700 ? 8 : 10) {

                        // Quick-Login bleibt immer oben sichtbar wenn ein Name
                        // persistiert ist — auch wenn der User "Anderes Konto
                        // verwenden" klickt (dann sieht er beide Optionen).
                        if hasQuickLogin {
                            quickLoginButton

                            if !showAlternativeLogin {
                                // Noch nicht aufgeklappt → zeig den Link zum Alternativ-Flow
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        showAlternativeLogin = true
                                    }
                                }) {
                                    Text("Anderes Konto verwenden")
                                        .font(.system(size: 13))
                                        .foregroundColor(textSecondary.opacity(0.7))
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 6)
                            } else {
                                // Sichtbarer Trenner zwischen Quick-Login und Alternativ-Flow
                                HStack(spacing: 8) {
                                    Rectangle().fill(textSecondary.opacity(0.15)).frame(height: 1)
                                    Text("oder")
                                        .font(.system(size: 11))
                                        .foregroundColor(textSecondary.opacity(0.5))
                                    Rectangle().fill(textSecondary.opacity(0.15)).frame(height: 1)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // Alternative Apple-Sign-In/Sign-Up-Buttons:
                        // — wenn Quick-Login NICHT verfügbar ist (Erstinstall) → immer anzeigen
                        // — wenn Quick-Login verfügbar ist → nur wenn User "Anderes Konto" geklickt hat
                        if !hasQuickLogin || showAlternativeLogin {
                            // ── Standard Apple Sign In / Sign Up ──────
                            // Conditional Rendering mit .id() — opacity-Lösung war
                            // unzuverlässig (iOS recycled den native UIView).
                            ZStack {
                                if isLoginMode {
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
                                    .id("apple-signin")
                                } else {
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
                                    .id("apple-signup")
                                }

                                if appleAuth.isLoading {
                                    Capsule().fill(.black.opacity(0.3))
                                        .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 44 : 50, maxHeight: screenH < 700 ? 44 : 50)
                                    ProgressView().tint(.white)
                                }
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
                        }

                        // Apple-Fehler anzeigen (für beide Varianten)
                        if let appleErr = appleAuth.errorMessage {
                            Text(appleErr)
                                .font(.system(size: 12))
                                .foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

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
        }
    }

    // MARK: Quick-Login-Button
    /// Großer Button "Weiter als [Name]" mit Avatar. Wenn Firebase noch
    /// eine gültige Auth-Session hat (was beim normalen Logout der Fall
    /// ist), wird das Apple-System-Sheet **übersprungen** und direkt
    /// re-authentifiziert. Sonst Fallback auf Apple Sign In mit Face ID.
    @ViewBuilder private var quickLoginButton: some View {
        Button(action: {
            // Silent re-auth wenn Firebase-Session noch lebt (kein Apple-Sheet)
            if Auth.auth().currentUser != nil {
                onApple(false, nil)   // exists=true Pfad in handleAppleSignInResult
                return
            }
            // Fallback: Firebase-Session weg → Apple Sign In nötig
            appleAuth.signIn { success, isNewUser in
                if success { onApple(isNewUser, appleAuth.lastAppleEmail) }
            }
        }) {
            HStack(spacing: 12) {
                // Avatar (letztes Profilbild aus UserDefaults, sonst Fallback-Emoji)
                ZStack {
                    Circle()
                        .fill(isLight ? Color.white.opacity(0.9) : Color.white.opacity(0.12))
                        .frame(width: 40, height: 40)
                    if let urlStr = lastLoginImageURL {
                        RemoteProfileImage(
                            url: urlStr,
                            fallbackEmoji: "👋",
                            size: 40,
                            strokeColor: .clear
                        )
                        .clipShape(Circle())
                    } else {
                        Text("👋").font(.system(size: 22))
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Weiter als")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textSecondary.opacity(0.8))
                    Text(lastLoginName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                // Apple-Logo rechts — signalisiert "Apple Sign In"
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textPrimary.opacity(0.85))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .frame(height: screenH < 700 ? 52 : 58)
            .background(
                Capsule()
                    .fill(isLight ? Color.white.opacity(0.75) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.brand.opacity(0.35), lineWidth: 1.2)
            )
            .shadow(color: Color.brand.opacity(0.15), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(appleAuth.isLoading)
        .overlay(
            Group {
                if appleAuth.isLoading {
                    Capsule().fill(.black.opacity(0.3))
                    ProgressView().tint(.white)
                }
            }
        )
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
                        .onChange(of: name) { _, newValue in
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

    /// Handynummer ist optional. Wenn der User eine angibt, müssen es ≥ 6 Ziffern sein.
    /// Ohne Nummer können Kontakte aus dem Adressbuch den User nicht finden.
    private var phoneIsValid: Bool {
        let digits = phone.filter { $0.isNumber }.count
        return digits == 0 || digits >= 6
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
                                    .onChange(of: name) { _, v in
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
                                    .onChange(of: birthdateText) { _, raw in
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

                        // ── Telefonnummer (optional) ─────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Label("Handynummer", systemImage: "phone.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                Text("(optional)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            }
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
                            if phone.filter({ $0.isNumber }).count == 0 {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentOrange)
                                    Text("Ohne Nummer können dich Kontakte aus deinem Adressbuch nicht finden.")
                                        .font(.system(size: 11)).foregroundColor(.accentOrange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                Text("Wird nicht öffentlich angezeigt. Nur damit Kontakte dich finden können.")
                                    .font(.system(size: 11)).foregroundColor(.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ────────────────────────────────────
            AppAuroraBackground(isLight: isLight)

            VStack(spacing: 0) {
                    Spacer()

                    // ── Logo-Block ────────────────────────────────────────
                    // Aurora-Glow im Stil des App-Icons: Orange + Grün
                    // statt einfarbig brand-grün — ergibt warme Sunset-
                    // Begrüßung passend zum Icon.
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "E48C3A").opacity(isLight ? 0.10 : 0.14))
                                .frame(width: 200, height: 200)
                                .blur(radius: 40)
                                .offset(x: -15, y: -20)
                            Circle()
                                .fill(Color(hex: "5FA937").opacity(isLight ? 0.08 : 0.10))
                                .frame(width: 160, height: 160)
                                .blur(radius: 36)
                                .offset(x: 25, y: 25)

                            // Normale SF-Rounded-Heavy-Wordmark (kein Custom-D
                            // mit LetterDShape). Auf User-Wunsch — die Icon-D-
                            // Variante wirkte auf dem Login-Screen too busy
                            // neben dem Aurora-Glow.
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
                                .onChange(of: enteredCode) { _, v in
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

                        if let err = errorMessage {
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

    private func sendLoginSMS() {
        guard phoneNumber.count >= 6 else {
            errorMessage = "Bitte gib eine gültige Nummer ein."
            return
        }
        isLoading = true; errorMessage = nil
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

    /// Sunset-Palette aus dem App-Branding (matched zu Logo, Buttons, Aurora-BG).
    private let orange = Color(hex: "E48C3A")
    private let green  = Color(hex: "5FA937")
    private var brandGradient: LinearGradient {
        LinearGradient(colors: [orange, green],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private struct Feature {
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    /// Konkretere Features mit Brand-konformer Palette (Sunset-Orange-Akzente,
    /// kein Cyan/Purple mehr — passt nicht zu Drops). Subtitles sind präziser:
    /// statt „Privatsphäre inklusive" jetzt klar „BLE-Bestätigung" — der USP.
    private let features: [Feature] = [
        Feature(icon: "plus.circle.fill",
                tint: Color(hex: "E48C3A"),
                title: "Drop in 2 Tipps",
                subtitle: "Aktivität wählen, Standort bestätigen — dein Drop erscheint sofort live auf der Karte."),
        Feature(icon: "dot.radiowaves.left.and.right",
                tint: Color(hex: "5FA937"),
                title: "Bluetooth-Bestätigung",
                subtitle: "Ankunft wird automatisch bestätigt — kein Check-In, keine GPS-Fakes."),
        Feature(icon: "lock.shield.fill",
                tint: Color(hex: "B49BE0"),
                title: "Privacy by default",
                subtitle: "Keine Profile, keine Bilderdatenbank. Drops laufen ab — du bist nicht dauer-trackbar."),
    ]

    var body: some View {
        ZStack {
            // Aurora-Background statt OnboardingStepBackground — matched zum
            // Welcome-Step und der gesamten App. Sieht hochwertiger aus als
            // ein statischer RadialGradient.
            AppAuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // ── App-Icon-Replik + Titel ───────────────────────────────
                VStack(spacing: 16) {
                    // Stylisierte App-Icon-Tile mit Sunset-Gradient + Custom-D
                    // (LetterDShape) — visuell deckungsgleich zum echten
                    // App-Icon ohne Asset-Referenz. Plus Sunset-Glow.
                    ZStack {
                        Circle()
                            .fill(orange.opacity(0.18))
                            .frame(width: 130, height: 130)
                            .blur(radius: 14)
                        Circle()
                            .fill(green.opacity(0.14))
                            .frame(width: 110, height: 110)
                            .blur(radius: 18)
                            .offset(x: 8, y: 8)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(brandGradient)
                            .frame(width: 88, height: 88)
                            .shadow(color: orange.opacity(0.35), radius: 14, y: 6)
                            .overlay(
                                LetterDShape()
                                    .fill(Color.white)
                                    .frame(width: 48, height: 48)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: appeared)

                    VStack(spacing: 6) {
                        Text("Willkommen bei Drops")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Triff Leute. Spontan.")
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
                                    .fill(f.tint.opacity(0.14))
                                    .frame(width: 48, height: 48)
                                Image(systemName: f.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(f.tint)
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

                // ── „Los geht's"-Button mit Sunset-Gradient ───────────────
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFinish()
                } label: {
                    HStack(spacing: 8) {
                        Text(tr("onboard.lets_go"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(brandGradient, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: orange.opacity(0.35), radius: 14, y: 5)
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
