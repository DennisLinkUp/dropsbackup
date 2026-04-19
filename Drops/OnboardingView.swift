import SwiftUI
import MapKit
import AuthenticationServices
import Vision
import AVFoundation
import LocalAuthentication
import FirebaseAuth
import UserNotifications
import CoreLocation

// MARK: - UIImage.Orientation → CGImagePropertyOrientation

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

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

enum IDDocType {
    case personalausweis, reisepass
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

// MARK: – Adaptive Glow-Hintergrund (Step 3 – Selfie)

struct SelfieGlowBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color(hex: "FFF0F5")).ignoresSafeArea()
            Circle()
                .fill(Color(hex: "FF2D55").opacity(dark ? 0.35 : 0.18))
                .frame(width: 420)
                .offset(x: animate ? 20 : -20, y: animate ? -180 : -140)
                .blur(radius: 110)
            Circle()
                .fill(Color(hex: "AF52DE").opacity(dark ? 0.30 : 0.14))
                .frame(width: 340)
                .offset(x: -130, y: animate ? 260 : 300)
                .blur(radius: 100)
            Circle()
                .fill(Color(hex: "FF9500").opacity(dark ? 0.20 : 0.10))
                .frame(width: 200)
                .offset(x: 150, y: animate ? 80 : 120)
                .blur(radius: 70)
        }
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: – Adaptive Glow-Hintergrund (ID-Scan + Consent)

struct IDGlowBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Heller Hintergrund wie App Icon
            Color(hex: "f5f7fe").ignoresSafeArea()
            // Grün oben links (wie App Icon)
            Circle()
                .fill(Color(hex: "34D36E").opacity(0.35))
                .frame(width: 420)
                .offset(x: animate ? -120 : -80, y: animate ? -260 : -220)
                .blur(radius: 90)
            // Lila oben rechts
            Circle()
                .fill(Color(hex: "A78BFA").opacity(0.28))
                .frame(width: 360)
                .offset(x: animate ? 160 : 120, y: animate ? -240 : -200)
                .blur(radius: 80)
            // Teal unten links
            Circle()
                .fill(Color(hex: "2DD4BF").opacity(0.22))
                .frame(width: 300)
                .offset(x: animate ? -140 : -100, y: animate ? 320 : 280)
                .blur(radius: 75)
            // Amber unten rechts
            Circle()
                .fill(Color(hex: "FBBF24").opacity(0.18))
                .frame(width: 260)
                .offset(x: animate ? 130 : 90, y: animate ? 300 : 260)
                .blur(radius: 70)
        }
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate)
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

/// Wird angezeigt wenn das gescannte Geburtsdatum ein Alter unter 16 ergibt.
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

                Text("Drops ist ausschließlich für Personen ab 16 Jahren.\n\nDein Ausweis zeigt, dass du diese Altersgrenze noch nicht erreicht hast. Eine Nutzung ist leider nicht möglich.")
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
    return age < 16
}

struct IDConsentStep: View {
    let onNext: (IDDocType) -> Void
    var onBack: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false
    @State private var agreed = false
    @State private var showPrivacy = false
    @State private var docType: IDDocType = .personalausweis

    private let stepColor = Color(hex: "007AFF")

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // Pulsierendes Icon — kompakt
                        OnboardingPulseIcon(systemName: "person.text.rectangle.fill",
                                            color: stepColor, size: 62, iconSize: 24)
                            .padding(.top, 4)
                            .padding(.bottom, 16)

                        Text(tr("onboard.confirm_identity"))
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)

                        Text(tr("onboard.choose_id_document"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 18)

                        // ── Dokumenttyp-Auswahl (vertikal gestapelt, große Karten) ─
                        VStack(spacing: 10) {
                            docTypeCard(type: .personalausweis,
                                        icon: "person.text.rectangle.fill",
                                        title: "Personalausweis")
                            docTypeCard(type: .reisepass,
                                        icon: "globe.europe.africa.fill",
                                        title: "Reisepass")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                        // ── Info-Zeilen ─────────────────────────────────
                        VStack(spacing: 0) {
                            infoRow(icon: "lock.fill",
                                    title: "Nur MRZ-Daten",
                                    sub: "Vorname + Geburtsdatum — nichts weiter")
                            Divider().padding(.leading, 40)
                            infoRow(icon: "trash.fill",
                                    title: "Jederzeit löschbar",
                                    sub: "Konto löschen = alle Daten sofort weg")
                            Divider().padding(.leading, 40)
                            infoRow(icon: "xmark.circle.fill",
                                    title: "Keine Weitergabe",
                                    sub: "Deine Daten bleiben ausschließlich bei uns")
                        }
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                        // ── Einwilligungs-Checkbox ─────────────────────
                        Button {
                            withAnimation(.spring(response: 0.3)) { agreed.toggle() }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(agreed ? stepColor : Color.primary.opacity(0.06))
                                        .frame(width: 22, height: 22)
                                    if agreed {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(agreed ? stepColor : Color.primary.opacity(0.2), lineWidth: 1))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr("onboard.id_consent"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button { showPrivacy = true } label: {
                                        Text(tr("onboard.privacy_policy_link"))
                                            .font(.system(size: 11))
                                            .foregroundColor(stepColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // ── Primär-Button ───────────────────────────────
                        Button(action: { onNext(docType) }) {
                            HStack(spacing: 8) {
                                Text(docType == .reisepass ? tr("onboard.scan_passport") : tr("onboard.scan_id"))
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(stepColor.opacity(agreed ? 1 : 0.4),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .disabled(!agreed)
                        .animation(.easeInOut(duration: 0.2), value: agreed)

                        if let skip = onSkip {
                            Button(action: skip) {
                                Text(tr("common.skip"))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        }

                        OnboardingDotProgress(current: 3, total: 5, color: stepColor)
                            .padding(.top, 20)
                            .padding(.bottom, 32)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
        .sheet(isPresented: $showPrivacy) {
            LegalView(type: .privacy)
        }
    }

    private func docTypeCard(type: IDDocType, icon: String, title: String) -> some View {
        let selected = docType == type
        return Button { withAnimation(.spring(response: 0.3)) { docType = type } } label: {
            HStack(spacing: 16) {
                // Icon in eigenem Kreis
                ZStack {
                    Circle()
                        .fill(selected ? stepColor.opacity(0.15) : Color.primary.opacity(0.06))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(selected ? stepColor : Color.primary.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selected ? .primary : Color.primary.opacity(0.5))
                    Text(type == .personalausweis ? "Rückseite · MRZ-Streifen" : "Datenseite mit Foto · MRZ")
                        .font(.system(size: 12))
                        .foregroundColor(selected ? .secondary : Color.primary.opacity(0.3))
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? stepColor : Color.primary.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? stepColor.opacity(0.07) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? stepColor.opacity(0.55) : Color.primary.opacity(0.09),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func infoRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(stepColor.opacity(0.7))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(sub)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
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
                // Firebase weiß sicher ob der Account neu ist.
                // isNewUser = false → Account existiert definitiv → sofort einloggen, kein DB-Check nötig.
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
                if !phone.isEmpty { store.userPhone = phone }
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
            // Admin-Check
            let adminEmails: Set<String> = ["dennisone95@hotmail.de", "ww688nmjp8@privaterelay.appleid.com"]
            let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
            if adminEmails.contains(authEmail) {
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
                let adminEmails: Set<String> = ["dennisone95@hotmail.de", "ww688nmjp8@privaterelay.appleid.com"]
                let firebaseEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
                let appleEmail = (capturedAppleEmail ?? "").lowercased()
                if adminEmails.contains(firebaseEmail) || adminEmails.contains(appleEmail) {
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
        // Admin-Check per E-Mail
        let adminEmails: Set<String> = ["dennisone95@hotmail.de", "ww688nmjp8@privaterelay.appleid.com"]
        let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        if adminEmails.contains(authEmail) || adminEmails.contains(storedApple) {
            self.store.isAdmin = true
        }
        RealtimeDBManager.shared.loadUserProfile { profile in
            guard let p = profile else { return }
            if let name = p.name, !name.isEmpty { self.store.currentUser.name = name }
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

                        // Slogan Typewriter
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !gender.isEmpty && dateIsValid
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

                        // ── Telefonnummer (optional) ──────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Handynummer (optional)", systemImage: "phone.fill")
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
                            Text("Wird nicht öffentlich angezeigt.")
                                .font(.system(size: 11)).foregroundColor(.textTertiary)
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

// MARK: - Inline Camera Preview (UIViewRepresentable)

struct InlineCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}


// MARK: - Age Verify Step

struct AgeVerifyStep: View {
    let onNext: (Date) -> Void

    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var birthdate: Date = Calendar.current.date(
        byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var appeared = false

    private var age: Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    }
    private var isValid: Bool { age >= 18 }

    private var ageLabel: String {
        if age < 18 { return "Du musst mindestens 18 Jahre alt sein." }
        return "\(age) Jahre"
    }
    private var ageLabelColor: Color {
        age < 16 ? .accentRed : .onlineGreen
    }

    // Kalender mit deutschem Locale
    private var germanCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        return cal
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(current: 3, total: 5)

            Spacer()

            VStack(spacing: 8) {
                Text(tr("onboard.your_birthdate"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(tr("onboard.birthdate_usage"))
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 36)

            // DatePicker in Kartenoptik
            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $birthdate,
                    in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .accentColor(.brand)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 24)

            // Alter-Anzeige
            HStack(spacing: 6) {
                Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(ageLabelColor)
                Text(ageLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ageLabelColor)
            }
            .padding(.top, 16)
            .animation(.easeInOut(duration: 0.2), value: age)

            Spacer()

            // Info-Badges
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.brand)
                    Text(tr("onboard.age_private"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                }
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Das Alter kann nach der Registrierung nicht mehr geändert werden.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)

            PrimaryButton(title: tr("onboard.continue_ellipsis")) {
                guard isValid else { return }
                onNext(birthdate)
            }
            .padding(.horizontal, 24)
            .opacity(isValid ? 1 : 0.4)
            .padding(.bottom, 36)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - ID Camera Controller (Back Camera, Photo + Live-Erkennung)

class IDCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue  = DispatchQueue(label: "de.drops.id.session",   qos: .userInitiated)
    private let detectionQueue = DispatchQueue(label: "de.drops.id.detection", qos: .userInitiated)

    var onCapture: ((UIImage?) -> Void)?
    /// Wird auf dem Main-Thread aufgerufen, wenn ≥ 2 MRZ-Zeilen im Live-Frame erkannt wurden.
    var onMRZDetected: (() -> Void)?

    private var isConfigured = false
    private var captureDevice: AVCaptureDevice?

    // Live-Erkennung
    private var mrzDetectionEnabled = false
    private var mrzFiredOnce = false
    private var lastDetectionTime: Date = .distantPast
    private let detectionThrottle: TimeInterval = 0.35   // max 3 Checks/Sekunde

    // MARK: – Setup

    func requestAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            self.sessionQueue.async { self.setupAndRun() }
        }
    }

    private func setupAndRun() {
        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video, position: .back),
                let input  = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { session.commitConfiguration(); return }

            session.addInput(input)
            captureDevice = device

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            // Video-Output für Live-MRZ-Erkennung
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: detectionQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            isConfigured = true
        }

        // Session ZUERST starten — danach Fokus setzen.
        // iOS kann Device-Settings beim Session-Start zurücksetzen,
        // daher müssen Fokuseinstellungen nach startRunning() angewendet werden.
        if !session.isRunning { session.startRunning() }

        // Kleiner Delay damit die Session vollständig hochgefahren ist
        // bevor wir lockForConfiguration aufrufen
        sessionQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            self.applyFocusSettings(device)
        }
    }

    private func applyFocusSettings(_ device: AVCaptureDevice) {
        guard let _ = try? device.lockForConfiguration() else { return }
        defer { device.unlockForConfiguration() }

        // Fokus-Punkt: Bildmitte — Ausweis liegt mittig im Rahmen
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }

        // continuousAutoFocus ohne Range-Restriction.
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }

        // 2× Zoom: Ausweis (85,6 mm) füllt den Rahmen bei ~20 cm Abstand.
        // Ohne Zoom deckt die Weitwinkelkamera bei 20 cm ca. 27 cm Breite ab —
        // der Ausweis füllt dann nur ~32 % des Frames und man muss auf <10 cm ran,
        // was außerhalb des Fokusbereichs liegt. Mit 2× Zoom korrekt bei 20 cm.
        let desiredZoom: CGFloat = 2.0
        let clampedZoom = max(device.minAvailableVideoZoomFactor,
                              min(desiredZoom, device.maxAvailableVideoZoomFactor))
        device.videoZoomFactor = clampedZoom

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    // MARK: – MRZ-Live-Erkennung ein/aus

    func startMRZDetection() {
        mrzFiredOnce = false
        lastDetectionTime = .distantPast
        mrzDetectionEnabled = true
    }

    func stopMRZDetection() {
        mrzDetectionEnabled = false
    }

    // MARK: – Foto aufnehmen

    func stop() {
        stopMRZDetection()
        sessionQueue.async { self.session.stopRunning() }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: – Foto-Delegate

extension IDCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async { self.session.stopRunning() }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let img  = UIImage(data: data) else {
            DispatchQueue.main.async { self.onCapture?(nil) }
            return
        }
        DispatchQueue.main.async { self.onCapture?(img) }
    }
}

// MARK: – Live-Frame MRZ-Erkennung

extension IDCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard mrzDetectionEnabled, !mrzFiredOnce else { return }

        // Throttle: nicht jeden Frame analysieren
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionThrottle else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Schnelle OCR (.fast) reicht für Erkennung — genaue OCR kommt erst nach Capture
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        req.minimumTextHeight = 0.012

        // iPhone im Hochformat → Kamerabild kommt als .right-Orientierung
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right, options: [:])
        try? handler.perform([req])

        let observations = req.results ?? []

        // Zähle potenzielle MRZ-Zeilen: 18-44 Zeichen, nur [A-Z0-9<]
        var mrzCount = 0
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let cleaned = text.uppercased()
                .replacingOccurrences(of: " ", with: "")
                .filter { $0.isUppercase || $0.isNumber || $0 == "<" }
            guard cleaned.count >= 18 else { continue }
            // Mindestens 70 % MRZ-konforme Zeichen
            let ratio = Double(cleaned.count) / Double(max(text.count, 1))
            if ratio >= 0.70 { mrzCount += 1 }
        }

        if mrzCount >= 2 {
            mrzFiredOnce = true
            DispatchQueue.main.async { [weak self] in
                self?.onMRZDetected?()
            }
        }
    }
}

// MARK: - ID Verify Step

struct IDVerifyStep: View {
    var docType: IDDocType = .personalausweis
    var onBack: (() -> Void)? = nil
    let onNext: (String?, Date?) -> Void

    private let accentColor = Color(hex: "4D9FFF")

    @AppStorage("appLanguage") private var appLanguage = "de"
    @StateObject private var camera = IDCameraController()
    @State private var appeared = false
    @State private var capturedImage: UIImage? = nil
    @State private var scanAnimating = false

    enum ScanMode { case idle, previewing, captured }
    @State private var scanMode: ScanMode = .idle

    /// Status der Live-MRZ-Erkennung während der Kamera-Vorschau
    enum DetectionState { case searching, detected }
    @State private var detectionState: DetectionState = .searching

    // OCR-Status: Name + Geburtsdatum aus MRZ
    enum OCRState { case idle, scanning, found(name: String, birthdate: Date?), failed }
    @State private var ocrState: OCRState = .idle

    // Gesichtsvergleich Selfie ↔ Ausweis
    enum FaceMatchState { case idle, checking, matched(Int), noFace, mismatch(Int) }
    @State private var faceMatchState: FaceMatchState = .idle
    // Explizite Bestätigung wenn Gesicht nicht erkennbar
    @State private var ownershipConfirmed: Bool = false

    // MRZ-Scan-Fenster: TD1 (Personalausweis) 85.6×28mm, TD3 (Reisepass) 88×25mm
    private var cardRatio: CGFloat { docType == .reisepass ? 88.0 / 25.0 : 85.6 / 28.0 }
    var body: some View {
        ZStack {
            // Always-dark background
            LinearGradient(
                colors: [Color(hex: "0A1628"), Color(hex: "0D2040")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(hex: "1D6EF5").opacity(0.4), Color.clear],
                center: .top, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()

            // Content (back button removed — swipe to go back)
            VStack(spacing: 0) {
                GeometryReader { geo in
                // Karte: max 320pt breit → kompaktes MRZ-Scan-Fenster
                let cardW = min(geo.size.width - 48, 320)
                let cardH = cardW / cardRatio

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Dynamisches Top-Padding für vertikale Zentrierung
                        let contentH: CGFloat = 100 + 60 + cardH + 240
                        let topPad = max((geo.size.height - contentH) / 2, 8)
                        Spacer().frame(height: topPad)

                        // ── Icon ────────────────────────────────────────────
                        if scanMode == .idle {
                            ZStack {
                                Circle()
                                    .fill(accentColor.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: docType == .reisepass ? "book.pages.fill" : "creditcard.viewfinder")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundColor(accentColor)
                            }
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }

                        // ── Titel ───────────────────────────────────────────
                        VStack(spacing: 6) {
                            Text(docType == .reisepass ? tr("onboard.scan_passport") : tr("onboard.scan_id_back"))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                            Text(scanMode == .previewing
                                 ? "MRZ-Streifen in den Rahmen legen"
                                 : (docType == .reisepass
                                    ? "Datenseite — untere 2 Zeilen halten"
                                    : "Rückseite — untere 3 Zeilen halten"))
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                            if scanMode == .idle {
                                Text(docType == .reisepass
                                     ? "Datenseite (mit Foto) · MRZ-Streifen unten halten"
                                     : "ca. 15–20 cm Abstand · nur der untere Streifen sichtbar")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding(.bottom, 20)
                        .padding(.horizontal, 16)

                    // ── Kamera-/Vorschau-Karte ──────────────────────────
                    ZStack {
                        // Live-Vorschau
                        if scanMode == .previewing {
                            InlineCameraPreview(session: camera.session)
                                .frame(width: cardW, height: cardH)
                                .cornerRadius(16)
                                .clipped()
                                .overlay(idCardOverlay(w: cardW, h: cardH))
                        }

                        // Aufgenommenes Foto
                        if scanMode == .captured, let img = capturedImage {
                            let scanOK: Bool = { if case .found = ocrState { return true }; return false }()
                            let scanFail: Bool = { if case .failed = ocrState { return true }; return false }()
                            let frameColor: Color = scanFail ? .accentRed : scanOK ? .onlineGreen : .white.opacity(0.4)
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: cardW, height: cardH)
                                .clipped()
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(frameColor, lineWidth: 2.5)
                                )
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.black.opacity(0.25))
                                .frame(width: cardW, height: cardH)
                            if scanOK {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundColor(.onlineGreen)
                            } else if scanFail {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundColor(.accentRed)
                            } else {
                                ProgressView().tint(.white).scaleEffect(1.5)
                            }
                        }

                        // Idle-Zustand: Kamera starten
                        if scanMode == .idle {
                            Button {
                                detectionState = .searching
                                withAnimation(.spring(response: 0.4)) { scanMode = .previewing }
                                camera.requestAndStart()
                                // Kurze Vorlaufzeit bis Kamera scharf ist, dann MRZ-Erkennung starten
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    camera.startMRZDetection()
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white.opacity(0.10))
                                        .frame(width: cardW, height: cardH)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    style: StrokeStyle(lineWidth: 2, dash: [10, 5])
                                                )
                                                .foregroundColor(.white.opacity(0.4))
                                        )
                                    VStack(spacing: 8) {
                                        Image(systemName: docType == .reisepass ? "book.pages.fill" : "creditcard.viewfinder")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                        Text(tr("onboard.start_camera"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 14)

                            // Skip-Button — immer sichtbar im Idle-Zustand
                            Button { onNext(nil, nil) } label: {
                                Text("Ausweis gerade nicht zur Hand")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.45))
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: cardW, height: cardH)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 6)
                    .animation(.spring(response: 0.35), value: scanMode)
                    .frame(maxWidth: .infinity)

                    // ── MRZ-Erkennungs-Status ──────────────────────────
                    if scanMode == .previewing {
                        VStack(spacing: 12) {
                            if detectionState == .searching {
                                // Suche läuft — Puls-Indikator + manueller Auslöser
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white.opacity(0.7))
                                        .scaleEffect(0.85)
                                    Text(tr("onboard.searching_mrz"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.white.opacity(0.08), in: Capsule())

                                Button { triggerCapture() } label: {
                                    Text(tr("onboard.manual_trigger"))
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            } else {
                                // MRZ erkannt — kurzer Feedback-Flash, dann Auto-Capture
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.onlineGreen)
                                    Text(tr("onboard.mrz_detected"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.onlineGreen)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.onlineGreen.opacity(0.15), in: Capsule())
                                .overlay(Capsule().stroke(Color.onlineGreen.opacity(0.4), lineWidth: 1))
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 20)
                        .animation(.spring(response: 0.35), value: detectionState == .detected)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // ── OCR-Ergebnis nach Capture ────────────────────────
                    if scanMode == .captured {
                        VStack(spacing: 10) {
                            if case .scanning = ocrState {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white.opacity(0.7)).scaleEffect(0.9)
                                    Text(tr("onboard.analyzing_id"))
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(.top, 16)
                            } else if case .found(let name, let birthdate) = ocrState {
                                VStack(spacing: 12) {
                                    VStack(spacing: 6) {
                                        idResultBadge(icon: "person.fill", color: .onlineGreen,
                                                      label: "Vorname: \(name)")
                                        if let bd = birthdate {
                                            idResultBadge(icon: "calendar", color: .onlineGreen,
                                                          label: "Geburtsdatum: \(formattedDate(bd))")
                                        } else {
                                            // Geburtsdatum nicht erkannt → Warnung + Scan erneut erforderlich
                                            idResultBadge(icon: "exclamationmark.triangle.fill", color: .accentOrange,
                                                          label: "Geburtsdatum nicht erkannt — bitte nochmal scannen")
                                        }
                                        // MRZ-Badge: Prüfziffern validiert
                                        idResultBadge(icon: "checkmark.seal.fill", color: Color(hex: "007AFF"),
                                                      label: "MRZ-Prüfziffern validiert")
                                        // Ownership-Bestätigung (Pflicht)
                                        Button(action: { ownershipConfirmed.toggle() }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: ownershipConfirmed ? "checkmark.square.fill" : "square")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(ownershipConfirmed ? .onlineGreen : .white.opacity(0.5))
                                                Text(tr("onboard.id_ownership"))
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.85))
                                            }
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10)
                                                .stroke(ownershipConfirmed ? Color.onlineGreen.opacity(0.5) : .white.opacity(0.15), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
                                    }
                                    .padding(.top, 14)
                                    Button(action: { onNext(name, birthdate) }) {
                                        HStack(spacing: 8) {
                                            Text(tr("common.continue"))
                                                .font(.system(size: 17, weight: .semibold))
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        .foregroundColor(Color(hex: "0A1628"))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(
                                            LinearGradient(
                                                colors: [Color(hex: "5BA8FF"), Color(hex: "3D8EF0")],
                                                startPoint: .leading, endPoint: .trailing
                                            ),
                                            in: RoundedRectangle(cornerRadius: 16)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(ownershipConfirmed && birthdate != nil ? 1 : 0.4)
                                    .disabled(!ownershipConfirmed || birthdate == nil)
                                    .padding(.top, 4)
                                    retryButton
                                }
                            } else if case .failed = ocrState {
                                VStack(spacing: 10) {
                                    idResultBadge(icon: "exclamationmark.circle.fill", color: .accentRed,
                                                  label: "Kein gültiger Ausweis erkannt")
                                        .padding(.top, 14)
                                    retryButton
                                    Button { onNext(nil, nil) } label: {
                                        Text(tr("onboard.skip_verification"))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.5))
                                            .underline()
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: ocrStateKey)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer(minLength: 36)

                    // ── MRZ-Illustration ────────────────────────────────
                    MRZGuideView()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text(tr("onboard.id_benefits"))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
            }
                } // end GeometryReader

                OnboardingDotProgress(current: 4, total: 5, color: .white)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: UIScreen.main.bounds.width)
        } // end ZStack
        .onAppear {
            appeared = true
            camera.onCapture = { img in
                capturedImage = img
                withAnimation { scanMode = .captured }
                if let img {
                    runOCR(on: img)
                    // Kein Gesichtsvergleich mehr — MRZ-Rückseite hat kein Foto.
                }
            }
            camera.onMRZDetected = {
                guard scanMode == .previewing else { return }
                camera.stopMRZDetection()
                withAnimation(.spring(response: 0.35)) { detectionState = .detected }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { triggerCapture() }
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func triggerCapture() {
        guard scanMode == .previewing else { return }
        camera.capturePhoto()
    }

    // MARK: – Hilfs-Views

    private var retryButton: some View {
        Button {
            capturedImage = nil
            ocrState = .idle
            faceMatchState = .idle
            ownershipConfirmed = false
            detectionState = .searching
            withAnimation { scanMode = .previewing }
            camera.requestAndStart()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                camera.startMRZDetection()
            }
        } label: {
            Text(tr("onboard.retake"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    /// "Weiter" nur freigeben wenn Gesicht erkannt und >= 55% Übereinstimmung
    private var faceMatchOK: Bool {
        switch faceMatchState {
        case .matched:          return true
        // Kein Gesicht erkannt: Ausweis-Druckfotos sind für Vision schwer zu lesen.
        // Erlaubt, aber nur mit expliziter Besitz-Bestätigung.
        case .noFace:           return ownershipConfirmed
        // Gesicht erkannt, aber zu geringe Übereinstimmung → blockieren
        case .mismatch:         return false
        case .idle, .checking:  return false
        }
    }

    @ViewBuilder
    private var faceMatchBadge: some View {
        switch faceMatchState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().tint(.white.opacity(0.7)).scaleEffect(0.75)
                Text(tr("onboard.comparing_face"))
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
            }
        case .matched(let pct):
            idResultBadge(icon: "face.smiling.inverse", color: .onlineGreen,
                          label: "Gesicht: \(pct)% Übereinstimmung")
        case .mismatch(let pct):
            VStack(spacing: 8) {
                idResultBadge(icon: "exclamationmark.circle.fill", color: .accentRed,
                              label: "Gesicht stimmt nicht überein (\(pct)%)")
                Text(tr("onboard.scan_again"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        case .noFace:
            VStack(spacing: 8) {
                idResultBadge(icon: "questionmark.circle", color: Color(hex: "FF9500"),
                              label: "Foto nicht automatisch erkennbar")
                // Pflicht-Bestätigung
                Button(action: { ownershipConfirmed.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: ownershipConfirmed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundColor(ownershipConfirmed ? .onlineGreen : .white.opacity(0.5))
                        Text(tr("onboard.id_is_mine"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(ownershipConfirmed ? Color.onlineGreen.opacity(0.4) : .white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func idResultBadge(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateStyle = .medium
        return df.string(from: date)
    }

    private var ocrStateKey: Int {
        switch ocrState {
        case .idle: return 0; case .scanning: return 1
        case .found: return 2; case .failed: return 3
        }
    }

    // MARK: – OCR / MRZ-Parsing

    private func runOCR(on image: UIImage) {
        ocrState = .scanning
        guard let cgImage = image.cgImage else { ocrState = .failed; return }

        // Bildausrichtung aus UIImage übernehmen damit Vision korrekt orientiert
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async {
            // iPhone in Hochformat + Ausweis im Querformat → Kamerabild kommt als .right-Orientierung.
            // .right zuerst probieren, dann die restlichen Orientierungen als Fallback.
            // Doppelte Orientierungen im Array werden automatisch durch Set-Deduplizierung vermieden
            // (behalten aber Reihenfolge bei — daher manuell deduplizieren).
            var seenOrients = Set<UInt32>()
            let prioritized: [CGImagePropertyOrientation] = [.right, orientation, .up, .left, .down]
            let orientQueue = prioritized.filter { seenOrients.insert($0.rawValue).inserted }

            var result: (name: String, birthdate: Date?)? = nil
            for orient in orientQueue {
                // Rückseite: nur MRZ-Erkennung, kein Language-Correction (MRZ ≠ natürlicher Text)
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                req.minimumTextHeight = 0.01
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orient, options: [:])
                try? handler.perform([req])
                let obsMRZ = req.results ?? []
                if let r = self.parseMRZ(from: obsMRZ) { result = r; break }
            }
            DispatchQueue.main.async {
                if let r = result {
                    self.ocrState = .found(name: r.name, birthdate: r.birthdate)
                } else {
                    self.ocrState = .failed
                }
            }
        }
    }

    /// Extrahiert Vorname + Geburtsdatum aus MRZ-Zeilen.
    /// TD1 (Personalausweis): 3 Zeilen à 30 Zeichen.
    ///   Zeile 1: IDD<<NACHNAME<<VORNAME<<<...
    ///   Zeile 2: YYMMDD<SEX<EXPIRY<NAT<<<...
    ///   Zeile 3: DOKUMENTNR<<<...
    private func parseMRZ(from observations: [VNRecognizedTextObservation]) -> (name: String, birthdate: Date?)? {
        // MRZ-Zeilen: 18–44 Zeichen, nur Großbuchstaben, Ziffern und "<"
        // Wir akzeptieren auch leicht kürzere Zeilen (OCR schneidet manchmal Ränder ab)
        guard let mrzRegex = try? NSRegularExpression(pattern: "^[A-Z0-9<]{18,44}$") else { return nil }
        var mrzLines: [String] = []

        for obs in observations {
            // Top-3-Kandidaten testen
            for raw in obs.topCandidates(3).map({ $0.string }) {
                // Bereinigen: Leerzeichen entfernen, Großbuchstaben, nur erlaubte Zeichen
                // KEIN O→0-Replace: in Namenzeilen sind echte O-Buchstaben vorhanden
                let cleaned = raw.uppercased()
                    .replacingOccurrences(of: " ", with: "")
                    .filter { $0.isUppercase || $0.isNumber || $0 == "<" }
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                if mrzRegex.firstMatch(in: cleaned, range: range) != nil {
                    mrzLines.append(cleaned)
                    break   // besten Kandidaten dieser Observation genommen
                }
            }
        }

        guard mrzLines.count >= 2 else { return nil }

        var extractedName: String?
        var extractedBirthdate: Date?
        var extractedExpiry: Date?
        var line2: String? = nil   // gespeichert für Checksummen-Validierung

        for line in mrzLines {
            // ── Namenszeile: enthält "<<", nur Buchstaben + "<", keine Ziffern ──
            let isNameLine = !line.contains(where: { $0.isNumber })
            if line.contains("<<") && extractedName == nil && isNameLine {
                let parts = line.components(separatedBy: "<<")
                let givenPart = parts.dropFirst().first(where: { !$0.isEmpty }) ?? ""
                let givenRaw = givenPart
                    .replacingOccurrences(of: "<", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                guard !givenRaw.isEmpty else { continue }
                let firstName = String(givenRaw.split(separator: " ").first ?? Substring(givenRaw))
                if firstName.count >= 2 {
                    extractedName = firstName.prefix(1).uppercased() + firstName.dropFirst().lowercased()
                }
            }

            // ── Datumszeile: TD1 (Pos 0-5 = YYMMDD, Sex Pos 7) oder TD3 (Pos 13-18 = YYMMDD, Sex Pos 20) ──
            if extractedBirthdate == nil && line.count >= 15 {
                var chars = Array(line)

                // Normalisierungs-Positionen je Format:
                // TD1: Geburtsdatum 0-5, Check 6, Sex 7, Ablauf 8-13, Check 14
                // TD3: Dok-Nr 0-8, Check 9, Land 10-12, Geburtsdatum 13-18, Check 19, Sex 20, Ablauf 21-26
                let isTD3Candidate = chars.count >= 44
                let digitPositions = isTD3Candidate
                    ? [0,1,2,3,4,5,6,7,8,9,13,14,15,16,17,18,19,21,22,23,24,25,26,27]
                    : [0,1,2,3,4,5,6,8,9,10,11,12,13,14]
                for i in digitPositions where i < chars.count {
                    switch chars[i] {
                    case "O", "U": chars[i] = "0"
                    case "B":      chars[i] = "8"
                    case "I", "L": chars[i] = "1"
                    case "Z":      chars[i] = "2"
                    case "S":      chars[i] = "5"
                    case "G":      chars[i] = "6"
                    case "T":      chars[i] = "7"
                    case "A":      chars[i] = "4"
                    default: break
                    }
                }

                // TD1: Geburtsdatum an Position 0-5, Geschlecht an Position 7
                let first6Digits = chars[0...5].allSatisfy(\.isNumber)
                let sexChar = chars.count > 7 ? chars[7] : Character(" ")
                if !isTD3Candidate && first6Digits && (sexChar == "M" || sexChar == "F" || sexChar == "<") {
                    if let bd = mrzDate(chars: Array(chars[0...5])) {
                        extractedBirthdate = bd
                        if chars.count >= 15, chars[8...13].allSatisfy(\.isNumber) {
                            let expCheckOK = mrzCheckDigit(String(chars[8...13])) == chars[14].wholeNumberValue
                            if expCheckOK, let exp = mrzDate(chars: Array(chars[8...13])) {
                                extractedExpiry = exp
                            }
                        }
                        line2 = String(chars)
                    }
                }

                // TD3 (Reisepass): Geburtsdatum an Position 13-18, Geschlecht an Position 20
                if isTD3Candidate && chars.count >= 27 {
                    let bdChars = Array(chars[13...18])
                    let sexCharTD3 = chars[20]
                    if bdChars.allSatisfy(\.isNumber)
                        && (sexCharTD3 == "M" || sexCharTD3 == "F" || sexCharTD3 == "<") {
                        if let bd = mrzDate(chars: bdChars) {
                            extractedBirthdate = bd
                            // Ablaufdatum TD3: Position 21-26
                            let expChars = Array(chars[21...26])
                            if expChars.allSatisfy(\.isNumber) {
                                extractedExpiry = mrzDate(chars: expChars)
                            }
                            line2 = String(chars)
                        }
                    }
                }
            }
        }

        // Ablaufdatum prüfen: abgelaufener Ausweis → abgelehnt
        // Abgelaufener Ausweis blockiert nicht mehr — Geburtsdatum wird trotzdem übernommen.
        // (Ablauf-Check entfernt, da OCR-Fehler im Ablaufdatum fälschlicherweise nil zurückgeben würden.)

        guard let name = extractedName else { return nil }
        return (name, extractedBirthdate)
    }

    /// Berechnet MRZ-Prüfziffer (ICAO 9303): Zeichen → Werte (A-Z=10-35, 0-9=0-9, <=0), Gewichte 7,3,1.
    private func mrzCheckDigit(_ s: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (i, c) in s.enumerated() {
            let val: Int
            if let n = c.wholeNumberValue { val = n }
            else if c == "<" { val = 0 }
            else if c >= "A" && c <= "Z" { val = Int(c.asciiValue! - 55) }
            else { val = 0 }
            sum += val * weights[i % 3]
        }
        return sum % 10
    }

    /// Konvertiert 6 MRZ-Ziffern (YYMMDD) in ein Date.
    private func mrzDate(chars: [Character]) -> Date? {
        guard chars.count == 6, chars.allSatisfy(\.isNumber) else { return nil }
        let yy = Int(String(chars[0...1])) ?? -1
        let mm = Int(String(chars[2...3])) ?? -1
        let dd = Int(String(chars[4...5])) ?? -1
        guard yy >= 0, mm >= 1, mm <= 12, dd >= 1, dd <= 31 else { return nil }
        let currentYY = Calendar.current.component(.year, from: Date()) % 100
        let year = yy <= currentYY ? 2000 + yy : 1900 + yy
        var comps = DateComponents()
        comps.year = year; comps.month = mm; comps.day = dd
        return Calendar.current.date(from: comps)
    }

    // MARK: – Vorderseiten-Parsing (nicht mehr aktiv, behalten für eventuelle Nutzung)

    /// Liest Vorname + Geburtsdatum direkt vom Klartext der Ausweisvorderseite.
    /// Funktioniert für den deutschen Personalausweis (Kreditkartenformat, ab 2010):
    ///   Label "Vornamen / Given names" → nächste Zeile = Vorname(n) in Großbuchstaben
    ///   Geburtsdatum im Format DD.MM.YYYY
    private func parseFrontFace(from observations: [VNRecognizedTextObservation]) -> (name: String, birthdate: Date?)? {
        // Vision: y=0 ist unten, y=1 ist oben → absteigendes minY = von oben nach unten
        let lines = observations
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var givenName: String? = nil
        var birthdate: Date?   = nil

        let df = DateFormatter()
        df.locale     = Locale(identifier: "de_DE")
        df.dateFormat = "dd.MM.yyyy"

        // Wörter die KEIN Vor-/Nachname sind, auch wenn in Großbuchstaben
        let skipWords = ["BUNDESREPUBLIK", "DEUTSCHLAND", "PERSONALAUSWEIS",
                         "IDENTITY", "CARD", "BUNDESDRUCKEREI", "CARTE", "IDENTITE",
                         "FAMILIENNAME", "SURNAME", "VORNAMEN", "GIVEN",
                         "NATIONALITY", "STAATSANGEHÖRIGKEIT", "GEBURTSDATUM",
                         "DATE", "BIRTH", "GEBURTSORT", "PLACE", "ANSCHRIFT",
                         "ADDRESS", "GÜLTIG", "VALID", "DEUTSCH", "GERMAN", "DEU"]

        for (i, line) in lines.enumerated() {
            let up = line.uppercased()

            // ── Vorname: Zeile nach "VORNAMEN" / "GIVEN" Label ──
            if givenName == nil && (up.contains("VORNAMEN") || up.contains("GIVEN")) {
                for j in (i + 1)..<min(i + 4, lines.count) {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    let lettersOnly = candidate.filter { $0.isLetter }
                    // Muss: mind. 2 Buchstaben, alles Großbuchstaben, kein bekanntes Stichwort
                    guard lettersOnly.count >= 2,
                          lettersOnly.uppercased() == lettersOnly,
                          !skipWords.contains(where: { candidate.uppercased().contains($0) }) else { continue }
                    let firstName = String(candidate.split(separator: " ").first ?? Substring(candidate))
                    if firstName.count >= 2 {
                        givenName = firstName.prefix(1).uppercased() + firstName.dropFirst().lowercased()
                    }
                    break
                }
            }

            // ── Geburtsdatum: DD.MM.YYYY Muster ──
            if birthdate == nil {
                let pat = #"(\d{1,2})\.(\d{1,2})\.(\d{4})"#
                if let range = line.range(of: pat, options: .regularExpression) {
                    let rawDate = String(line[range])
                    // Einstellige Tage/Monate auf 2 Stellen bringen für DateFormatter
                    let parts = rawDate.components(separatedBy: ".")
                    if parts.count == 3 {
                        let d = String(format: "%02d", Int(parts[0]) ?? 0)
                        let m = String(format: "%02d", Int(parts[1]) ?? 0)
                        let y = parts[2]
                        birthdate = df.date(from: "\(d).\(m).\(y)")
                    }
                }
            }
        }

        guard let name = givenName else { return nil }
        return (name, birthdate)
    }

    // MARK: – Gesichtsvergleich (Vision Landmarks)

    private func compareFaces(selfie: UIImage, idPhoto: UIImage) {
        faceMatchState = .checking
        getFaceLandmarks(from: selfie) { selfiePoints in
            guard let sp = selfiePoints else { self.faceMatchState = .noFace; return }
            // Ausweis-Foto: mehrere Crops probieren (linkes Drittel = Fotobreich, Ganzes Bild, Mitte)
            let crops = self.idPhotoCrops(from: idPhoto)
            self.findFaceLandmarksInCrops(crops) { idPoints in
                guard let ip = idPoints else {
                    DispatchQueue.main.async { self.faceMatchState = .noFace }
                    return
                }
                let pct = self.landmarkSimilarity(sp, ip)
                DispatchQueue.main.async {
                    if pct >= 30 { self.faceMatchState = .matched(pct) }
                    else         { self.faceMatchState = .mismatch(pct) }
                }
            }
        }
    }

    /// Erzeugt mehrere Kandidaten-Crops des Ausweis-Bildes (von spezifisch zu allgemein).
    private func idPhotoCrops(from image: UIImage) -> [UIImage] {
        guard let cg = image.cgImage else { return [image] }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var crops: [UIImage] = []
        // 1. Linkes Drittel (typische Position des Fotos auf EU-Ausweis)
        let leftThird = CGRect(x: 0, y: 0, width: w * 0.38, height: h)
        if let c = cg.cropping(to: leftThird) { crops.append(UIImage(cgImage: c)) }
        // 2. Linke Hälfte
        let leftHalf = CGRect(x: 0, y: 0, width: w * 0.5, height: h)
        if let c = cg.cropping(to: leftHalf) { crops.append(UIImage(cgImage: c)) }
        // 3. Ganzes Bild (Fallback)
        crops.append(image)
        // 4. 90°-gedreht (falls Ausweis quer gescannt)
        if let rotated = rotatedImage(image, degrees: 90) { crops.append(rotated) }
        return crops
    }

    /// Dreht ein Bild um die gegebene Gradzahl.
    private func rotatedImage(_ image: UIImage, degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: radians)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                              width: image.size.width, height: image.size.height))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Sucht Landmarks in einer Liste von Crop-Kandidaten (stoppt beim ersten Treffer).
    private func findFaceLandmarksInCrops(_ crops: [UIImage], completion: @escaping ([CGPoint]?) -> Void) {
        func tryNext(_ index: Int) {
            guard index < crops.count else { completion(nil); return }
            getFaceLandmarks(from: crops[index]) { pts in
                if let pts = pts { completion(pts) }
                else             { tryNext(index + 1) }
            }
        }
        tryNext(0)
    }

    /// Extrahiert normalisierte Gesichts-Landmarks (relativ zur Face-BoundingBox).
    private func getFaceLandmarks(from image: UIImage, completion: @escaping ([CGPoint]?) -> Void) {
        guard let cg = image.cgImage else { completion(nil); return }
        let req = VNDetectFaceLandmarksRequest { req, _ in
            guard let obs  = (req.results as? [VNFaceObservation])?.first,
                  let marks = obs.landmarks?.allPoints else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Punkte relativ zur Face-BoundingBox normalisieren → größen-/positionsunabhängig
            let bb   = obs.boundingBox
            let pts  = marks.normalizedPoints.map { p -> CGPoint in
                CGPoint(x: (CGFloat(p.x) - bb.minX) / bb.width,
                        y: (CGFloat(p.y) - bb.minY) / bb.height)
            }
            DispatchQueue.main.async { completion(pts) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        }
    }

    /// Berechnet Ähnlichkeit 0–100 % aus mittlerer Landmark-Distanz.
    private func landmarkSimilarity(_ a: [CGPoint], _ b: [CGPoint]) -> Int {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var total: Double = 0
        for i in 0..<n {
            let dx = Double(a[i].x - b[i].x), dy = Double(a[i].y - b[i].y)
            total += sqrt(dx*dx + dy*dy)
        }
        // avg ≈ 0.02–0.04 = gleiche Person | > 0.10 = andere Person
        let avg = total / Double(n)
        let score = max(0.0, 1.0 - avg / 0.09) * 100
        return Int(min(100, score))
    }

    // Eck-Rahmen + Scan-Linie als Overlay
    @ViewBuilder
    /// Scan-Overlay: grün = MRZ erkannt, blau = Suche läuft
    private func idCardOverlay(w: CGFloat, h: CGFloat) -> some View {
        let detected = detectionState == .detected
        let c: Color = detected ? .onlineGreen : Color(hex: "007AFF")
        let m: CGFloat = 10
        let t: CGFloat = 3.0
        let cornerL: CGFloat = 20

        return ZStack {
            // Äußerer Rahmen — grün bei Erkennung
            RoundedRectangle(cornerRadius: 12)
                .stroke(c.opacity(detected ? 0.9 : 0.65), lineWidth: detected ? 2.5 : 1.5)
                .animation(.spring(response: 0.35), value: detected)

            // Grüner Fill-Overlay bei Erkennung
            if detected {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.onlineGreen.opacity(0.08))
                    .transition(.opacity)
            }

            // Scan-Linie (nur bei Suche sichtbar)
            if !detected {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [c.opacity(0), c.opacity(0.9), c.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
                    .offset(x: scanAnimating ? w * 0.42 : -w * 0.42)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: scanAnimating
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }

            // Eck-Markierungen (alle vier Ecken)
            Group {
                Path { p in
                    p.move(to: CGPoint(x: m, y: m + cornerL))
                    p.addLine(to: CGPoint(x: m, y: m))
                    p.addLine(to: CGPoint(x: m + cornerL, y: m))
                }.stroke(c, style: StrokeStyle(lineWidth: t, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: w - m - cornerL, y: m))
                    p.addLine(to: CGPoint(x: w - m, y: m))
                    p.addLine(to: CGPoint(x: w - m, y: m + cornerL))
                }.stroke(c, style: StrokeStyle(lineWidth: t, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: m, y: h - m - cornerL))
                    p.addLine(to: CGPoint(x: m, y: h - m))
                    p.addLine(to: CGPoint(x: m + cornerL, y: h - m))
                }.stroke(c, style: StrokeStyle(lineWidth: t, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: w - m - cornerL, y: h - m))
                    p.addLine(to: CGPoint(x: w - m, y: h - m))
                    p.addLine(to: CGPoint(x: w - m, y: h - m - cornerL))
                }.stroke(c, style: StrokeStyle(lineWidth: t, lineCap: .round))
            }
            .animation(.spring(response: 0.35), value: detected)

            // Badge oben-links
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        if detected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.onlineGreen)
                        }
                        Text(detected ? "Erkannt" : "MRZ")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(c)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(c.opacity(0.18))
                    .cornerRadius(5)
                    .padding(.top, 8).padding(.leading, 12)
                    .animation(.spring(response: 0.35), value: detected)
                    Spacer()
                }
                Spacer()
            }

            // MRZ-Linien-Andeutungen (nur Suche)
            if !detected {
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(c.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear { scanAnimating = true }
    }
}

// MARK: - MRZ Guide View (Illustration des MRZ-Streifens)

struct MRZGuideView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var pulse = false

    // Beispiel-MRZ Zeilen (anonymisiert, echter TD1-Stil)
    private let line1 = "IDDEUT1234567890<<<<<<<<<<<<<<"
    private let line2 = "6408125M2701015D<<<<<<<<<<<<<<4"
    private let line3 = "MUSTERMANN<<ERIKA<<<<<<<<<<<<"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Überschrift ─────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text(tr("onboard.mrz_example"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }

            // ── Ausweis-Illustration ────────────────────────────────
            ZStack(alignment: .bottom) {
                // Ausweis-Körper
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2A2A3E"), Color(hex: "1E1E2E")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Oberer Bereich: Fotobereich + Textfelder
                VStack {
                    HStack(spacing: 8) {
                        // Foto-Placeholder
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 28, height: 36)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.2))
                            )
                        // Datenfelder
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: CGFloat([80, 60, 50][i % 3]), height: 5)
                            }
                        }
                        Spacer()
                        // D-Emblem
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 24, height: 24)
                            Text(tr("onboard.id_country_code"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    Spacer()
                }

                // ── MRZ-Streifen (hervorgehoben) ────────────────────
                VStack(spacing: 0) {
                    // Pfeil-Hinweis
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Text(tr("onboard.mrz_label"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(hex: "007AFF"))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(Color(hex: "007AFF"))
                        }
                        .padding(.trailing, 8)
                    }
                    .padding(.bottom, 2)

                    // MRZ-Streifen
                    VStack(spacing: 1) {
                        ForEach([line1, line2, line3], id: \.self) { line in
                            Text(line)
                                .font(.system(size: 5.5, weight: .regular, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(
                        ZStack {
                            Color(hex: "007AFF").opacity(pulse ? 0.18 : 0.10)
                            // Pulsierender Rahmen
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "007AFF").opacity(pulse ? 0.7 : 0.3), lineWidth: 1)
                        }
                    )
                    .cornerRadius(4)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }

            // ── Legende ─────────────────────────────────────────────
            HStack(spacing: 0) {
                legendItem(color: Color(hex: "007AFF"), label: "MRZ-Streifen → in den Rahmen halten")
                Spacer()
                legendItem(color: Color.white.opacity(0.15), label: "Rest des Ausweises")
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

struct SelfieHintBadge: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}

// MARK: - Name Step (Bestätigung für Verifizierte / Formular für Unverifizierte)

struct NameStep: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Binding var name: String
    let extractedName: String?
    let extractedBirthdate: Date?
    /// Rückgabe: geparste manuelle Geburtsdatum (nil wenn verifiziert oder Parsing fehlschlägt)
    let onNext: (Date?) -> Void
    var onBack: (() -> Void)? = nil

    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var nameFocused: Bool
    @FocusState private var bdayFocused: Bool
    @StateObject private var keyboard = KeyboardObserver()
    @State private var appeared = false
    @State private var manualBirthdate = ""        // für unverifizierte Eingabe: TT.MM.JJJJ
    @State private var profileImage: UIImage? = nil
    @State private var showPhotoPicker = false

    private var isVerified: Bool { extractedName != nil }
    private var dark: Bool { colorScheme == .dark }
    private var fieldBg: Color { Color.primary.opacity(0.06) }

    private var canContinue: Bool {
        if isVerified { return true }   // Name + Datum kommen vom Ausweis-Step
        return name.count >= 2 && isValidManualBirthdate
    }

    private var isValidManualBirthdate: Bool {
        let parts = manualBirthdate.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]),
              d >= 1 && d <= 31, m >= 1 && m <= 12, y >= 1900 && y <= 2010
        else { return false }
        return true
    }

    private let stepColor = Color.brand

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)
            // Tap außerhalb → Tastatur schließen
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { nameFocused = false; bdayFocused = false }
        VStack(spacing: 0) {
            // Zurück-Button
            if let back = onBack {
                HStack {
                    Button(action: back) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text(tr("common.back"))
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }

            GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Zentrierung mit dynamischem Padding oben
                    let topPad = max((geo.size.height
                                     - (keyboard.height > 0 ? keyboard.height : 0)
                                     - 520) / 2, 16)
                    Spacer().frame(height: topPad)

                    VStack(spacing: 28) {

                        // ── Icon ─────────────────────────────────────────
                        ZStack {
                            Circle()
                                .fill(Color.brand.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: isVerified ? "checkmark.shield.fill" : "person.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(.brand)
                        }

                        // ── Titel ────────────────────────────────────────
                        VStack(spacing: 6) {
                            Text(isVerified ? "Alles bestätigen" : "Deine Angaben")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)

                            if isVerified {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onlineGreen)
                                    Text(tr("onboard.from_id_check"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.onlineGreen)
                                }
                            } else {
                                Text(tr("onboard.enter_real_name"))
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        // ── Felder ────────────────────────────────────────
                        VStack(spacing: 12) {
                            if isVerified {
                                // ── Verifiziert: gesperrte Anzeige ─────
                                verifiedField(
                                    icon: "person.fill",
                                    label: "Vorname",
                                    value: name
                                )
                                if let bd = extractedBirthdate {
                                    verifiedField(
                                        icon: "calendar",
                                        label: "Geburtsdatum",
                                        value: formattedDate(bd)
                                    )
                                }
                            } else {
                                // ── Unverifiziert: freie Eingabe ────────
                                // Vorname
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tr("onboard.first_name"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                        .padding(.leading, 4)
                                    TextField("Dein echter Vorname", text: $name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                        .autocapitalization(.words)
                                        .disableAutocorrection(true)
                                        .focused($nameFocused)
                                        .submitLabel(.next)
                                        .onSubmit { bdayFocused = true }
                                        .onChange(of: name) { newValue in
                                            let filtered = newValue.filter { $0.isLetter }
                                            if filtered != newValue { name = filtered }
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 14)
                                        .background(fieldBg, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(nameFocused ? Color.brand.opacity(0.55) : Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                }
                                // Geburtsdatum
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tr("onboard.birthdate"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                        .padding(.leading, 4)
                                    TextField("TT.MM.JJJJ", text: $manualBirthdate)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                        .keyboardType(.numberPad)
                                        .focused($bdayFocused)
                                        .onChange(of: manualBirthdate) { val in
                                            manualBirthdate = formatBirthdateInput(val)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 14)
                                        .background(fieldBg, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(bdayFocused ? Color.brand.opacity(0.55) : Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                }
                            }

                            // ── Weiter-Button ────────────────────────
                            PrimaryButton(title: isVerified ? "Bestätigen →" : "Los geht's →") {
                                nameFocused = false
                                bdayFocused = false
                                if isVerified {
                                    onNext(nil)   // Datum bereits via ID-Scan bekannt
                                } else {
                                    // Manuelles Datum parsen und übergeben
                                    let parts = manualBirthdate.split(separator: ".").map(String.init)
                                    var parsed: Date? = nil
                                    if parts.count == 3,
                                       let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) {
                                        var comps = DateComponents()
                                        comps.day = d; comps.month = m; comps.year = y
                                        parsed = Calendar.current.date(from: comps)
                                    }
                                    onNext(parsed)
                                }
                            }
                            .disabled(!canContinue)
                            .opacity(canContinue ? 1 : 0.4)
                            .animation(.easeInOut(duration: 0.2), value: canContinue)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                    // Dot-Progress + Keyboard-Spacer
                    if keyboard.height == 0 {
                        OnboardingDotProgress(current: 4, total: 5, color: stepColor)
                            .padding(.top, 20)
                    }
                    Spacer().frame(
                        height: max(keyboard.height > 0 ? keyboard.height + 12 : geo.safeAreaInsets.bottom + 24, 24)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboard.height)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        } // outer VStack
        } // ZStack
        .onAppear {
            appeared = true
            if !isVerified {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true }
            }
        }
    }

    // MARK: – Helpers

    @ViewBuilder
    private func verifiedField(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.onlineGreen.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(.onlineGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.textTertiary)
                Text(value)
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.textPrimary)
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14)).foregroundColor(.onlineGreen)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.onlineGreen.opacity(0.35), lineWidth: 1)
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateStyle = .medium
        return df.string(from: date)
    }

    /// Auto-formatiert Eingabe als TT.MM.JJJJ
    private func formatBirthdateInput(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var result = ""
        for (i, c) in digits.enumerated() {
            if i == 2 || i == 4 { result += "." }
            if i < 8 { result.append(c) }
        }
        return result
    }
}

struct PinLocationStep: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Binding var coordinate: CLLocationCoordinate2D?
    let onNext: () -> Void
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                OnboardingProgress(current: 4, total: 4)
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(tr("onboard.where_are_you"))
                            .font(.system(size: geo.size.width < 375 ? 24 : 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(tr("onboard.tap_map_to_set_location"))
                            .font(.system(size: 14)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    .padding(.top, 20).padding(.bottom, 16)

                    ZStack {
                        InteractivePinMap(region: $region, coordinate: $coordinate)
                            .frame(maxWidth: .infinity)
                            .frame(height: geo.size.height * 0.46)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 0.5))

                        if coordinate == nil {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 32)).foregroundColor(.textPrimary.opacity(0.5))
                                Text(tr("onboard.tap_to_place"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 12)

                    VStack(spacing: 10) {
                        if coordinate != nil {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill").foregroundColor(.onlineGreen)
                                Text(tr("onboard.location_set"))
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.onlineGreen)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        PrimaryButton(title: "Drops starten 🚀") { onNext() }
                            .disabled(coordinate == nil)
                            .opacity(coordinate != nil ? 1 : 0.45)
                            .animation(.spring(response: 0.3), value: coordinate != nil)

                        Button(action: onNext) {
                            Text(tr("common.skip"))
                                .font(.system(size: 14)).foregroundColor(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 24)
                    .animation(.spring(), value: coordinate != nil)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
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
struct IDVerificationJourneyView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var cs

    enum JourneyStep { case consent, verify, name, underage }

    @State private var step: JourneyStep = .consent
    @State private var idDocType: IDDocType = .personalausweis
    @State private var extractedName: String? = nil
    @State private var extractedBirthdate: Date? = nil
    @State private var userName: String = ""
    @State private var showBirthdateMismatch = false

    private var prefersDark: Bool {
        switch cs {
        case .dark:  return true
        case .light: return false
        default:     return isNightTime()
        }
    }
    private var adaptiveScheme: ColorScheme { prefersDark ? .dark : .light }

    var body: some View {
        ZStack {
            // Hintergrund (IDConsent + IDVerify haben eigenen Hintergrund)
            switch step {
            case .name:             GreenGlowBackground()
            case .underage:         Color(hex: "1C1C1E").ignoresSafeArea()
            default:                Color.clear
            }

            // Step-Inhalt (Verification Journey — kein interests-Step hier)
            switch step {
            case .consent:
                IDConsentStep(
                    onNext: { chosenType in idDocType = chosenType; step = .verify },
                    onSkip: { store.showVerificationJourney = false }
                )

            case .verify:
                IDVerifyStep(
                    docType: idDocType,
                    onBack: { withAnimation(.spring(response: 0.4)) { step = .consent } }
                ) { name, birthdate in
                    // ── Minderjährigen-Check ──────────────────────────────
                    if let bd = birthdate, isUserUnderage(birthdate: bd) {
                        store.userBirthdate = bd
                        store.isIdVerified  = false
                        withAnimation(.spring(response: 0.4)) { step = .underage }
                        return
                    }

                    // ── Geburtsdatum-Mismatch Check ───────────────────────
                    // War der User bisher unverifiziert und hat ein manuelles Datum eingetragen,
                    // muss dieses mit dem Ausweis übereinstimmen.
                    if let existingBD = store.userBirthdate,
                       !store.isIdVerified,
                       let idBD = birthdate {
                        let cal = Calendar.current
                        let existing = cal.dateComponents([.year, .month, .day], from: existingBD)
                        let fromId   = cal.dateComponents([.year, .month, .day], from: idBD)
                        if existing.year != fromId.year || existing.month != fromId.month || existing.day != fromId.day {
                            // Mismatch → neues Konto erforderlich
                            showBirthdateMismatch = true
                            return
                        }
                    }

                    // ── Alterscheck bestanden → normal weiter ─────────────
                    // Nur als verifiziert gelten wenn BEIDE Felder erkannt wurden
                    store.isIdVerified  = (name != nil && birthdate != nil)
                    store.userBirthdate = birthdate
                    extractedName       = name
                    extractedBirthdate  = birthdate
                    if let n = name { userName = n }
                    step = .name
                }
                .alert("Geburtsdatum stimmt nicht überein", isPresented: $showBirthdateMismatch) {
                    Button("Neues Konto erstellen", role: .destructive) {
                        store.showVerificationJourney = false
                        store.isAuthenticated = false
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text(tr("onboard.birthdate_mismatch"))
                }

            case .name:
                NameStep(
                    name: Binding(
                        get: { userName.isEmpty ? store.currentUser.name : userName },
                        set: { userName = $0 }
                    ),
                    extractedName: extractedName,
                    extractedBirthdate: extractedBirthdate,
                    onNext: { manualBirthdate in
                        // Alterscheck für manuelle Eingabe
                        if let bd = manualBirthdate, isUserUnderage(birthdate: bd) {
                            store.userBirthdate = bd
                            store.isIdVerified  = false
                            withAnimation(.spring(response: 0.4)) { step = .underage }
                            return
                        }
                        if let bd = manualBirthdate { store.userBirthdate = bd }
                        if !userName.isEmpty { store.currentUser.name = userName }
                        store.showVerificationJourney = false
                    },
                    onBack: { withAnimation(.spring(response: 0.4)) { step = .verify } }
                )
                .environment(\.colorScheme, adaptiveScheme)

            case .underage:
                // Sperre — kein Schließen-Button, kein Weiterkommen
                UnderAgeBlockView {
                    // Nur zurück zum ID-Scan, kein Schließen der Journey
                    withAnimation(.spring(response: 0.4)) { step = .verify }
                }
            }

            // ── X-Button ganz oben im ZStack (letztes Element = höchste Z-Ebene) ──
            if step != .underage {
                VStack {
                    HStack {
                        Button {
                            store.showVerificationJourney = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(true)
                .zIndex(999)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}



#endif // ID verification removed
