import SwiftUI
import MapKit

// MARK: - Map Style Helper

enum MapStyleMode: String, CaseIterable {
    case auto   = "auto"
    case light  = "hell"
    case dark   = "dunkel"

    var label: String {
        switch self {
        case .auto:  return tr("map.style.auto")
        case .light: return  tr("map.style.light")
        case .dark:  return tr("map.style.dark")
        }
    }

    func isDark(for date: Date = Date()) -> Bool {
        switch self {
        case .light: return false
        case .dark:  return true
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 6 || hour >= 20
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D? = nil
    /// Horizontale GPS-Genauigkeit in Metern — für den Accuracy-Ring um den Pin.
    @Published var horizontalAccuracy: CLLocationAccuracy = 0
    /// Zeitpunkt des letzten akzeptierten Updates — für die Stale-Detection.
    private var lastAcceptedAt: Date? = nil

    /// Ab dieser Accuracy (in Metern) gilt ein Update als "schlechter Empfang".
    private let maxAcceptableAccuracy: CLLocationAccuracy = 250
    /// Wenn letzter guter Fix älter als X Sekunden → schlechte Updates akzeptieren
    /// (sonst bleibt der Pin nach langer U-Bahn-Fahrt am alten Standort hängen).
    private let staleThresholdSeconds: TimeInterval = 60
    /// Wenn neuer Punkt weiter als X Meter vom alten entfernt ist → akzeptieren,
    /// egal wie schlecht die Accuracy ist (User ist offensichtlich woanders).
    private let bigJumpThresholdMeters: CLLocationDistance = 500

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Negative Accuracy = ungültig (Simulator-Feature oder Hardwarefehler)
        guard loc.horizontalAccuracy >= 0 else { return }

        let isPoorAccuracy = loc.horizontalAccuracy > maxAcceptableAccuracy

        if let prev = userLocation, let lastAt = lastAcceptedAt, isPoorAccuracy {
            // Wir haben schon eine Position + das neue Update ist schlecht.
            // Verwerfen nur wenn der alte Fix **frisch** ist UND der neue
            // Punkt **nicht weit** weg ist. Sonst: U-Bahn-Fahrt → Pin updaten.
            let secsSinceLast = Date().timeIntervalSince(lastAt)
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let movedDistance = prevLoc.distance(from: loc)

            let isStillFresh = secsSinceLast < staleThresholdSeconds
            let isSmallJump = movedDistance < bigJumpThresholdMeters

            if isStillFresh && isSmallJump {
                return  // kurzer Empfangsausfall, alten Pin behalten
            }
            // Sonst: entweder der alte Fix ist schon veraltet (>60s) oder der
            // neue Punkt ist >500m weg → Update akzeptieren auch wenn unscharf.
        }

        userLocation = loc.coordinate
        horizontalAccuracy = loc.horizontalAccuracy
        lastAcceptedAt = Date()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

struct LiveMapView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    /// Einmaliger Power-Hour-Hinweis nach Update. Wird auf true gesetzt
    /// sobald der User den Hinweis-Sheet einmal gesehen hat.
    @AppStorage("hasSeenPowerHourIntro") private var hasSeenPowerHourIntro = false
    @State private var showPowerHourIntro = false
    @StateObject private var locationManager = LocationManager()
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
    ))
    /// Vorberechnete Bildschirmpunkte der GeoZone-Grenze.
    /// Werden ausschließlich in onMapCameraChange aktualisiert (synchron mit MapKit),
    /// nicht im 60fps-Animations-Loop → kein Jitter mehr.
    @State private var munichBoundaryPts: [CGPoint] = []
    /// Pro-Stadt-Polygone in Screen-Koordinaten (5 Städte beim Launch).
    /// Wird in onMapCameraChange synchron aktualisiert.
    @State private var cityPolygonsPts: [[CGPoint]] = []
    @State private var hasInitiallyZoomed = false
    @State private var selectedItem: MapAnnotationItem? = nil
    @State private var selectedActivity = "Alle"
    @State private var joinedIDs: Set<UUID> = []
    @State private var showSafety = false
    @State private var mapId = UUID()
    let activities = ["Alle", "☕️ Kaffee", "🍺 Drink", "🏃 Sport", "🍕 Essen", "🎮 Zocken"]

    /// Eigener 8-Char BLE-Token — wird explizit an DropMapPin übergeben (nicht per @EnvironmentObject,
    /// da Map-Annotation-Content nicht zuverlässig den SwiftUI-Environment erbt).
    var myPinToken: String {
        String(store.currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    var filteredAnnotations: [MapAnnotationItem] {
        let base = store.allMapAnnotations
        // Der „Nur weiblich"-Filter läuft jetzt im Umgebungs-Tab, nicht mehr hier.
        guard selectedActivity != "Alle" else { return base }
        return base.filter { selectedActivity.contains($0.emoji) }
    }

    /// Konvertiert die Polygone ALLER Launch-Städte in eine flache Liste von
    /// Screen-Koordinaten, mit `nil`-Separator zwischen Städten (damit der
    /// Overlay weiß, wo ein Polygon endet und das nächste beginnt).
    ///
    /// Wir geben `[[CGPoint]]` zurück — also ein Array von Polygonen. Der
    /// Canvas-Overlay iteriert und zeichnet jedes einzeln, mit gemeinsamer
    /// Ausgrauung außerhalb aller Zonen.
    static func allCityPolygonsPts(proxy: MapProxy) -> [[CGPoint]] {
        ServiceCities.all.map { city in
            var closed = city.polygon
            if let first = closed.first { closed.append(first) }
            return closed.compactMap { proxy.convert($0, to: .local) }
        }
    }

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $mapPosition) {
                    // Eigener Standort — bei schlechtem GPS-Empfang ausblenden,
                    // damit kein irreführender exakter Punkt suggeriert wird.
                    // Nur den Accuracy-Ring zeigen → User sieht ungefähren Bereich.
                    if locationManager.horizontalAccuracy > 0,
                       locationManager.horizontalAccuracy <= 100 {
                        UserAnnotation()
                    }

                    // GPS-Accuracy-Ring um den User.
                    // Bei gutem Empfang erst ab 20m sichtbar, bei schlechtem (>100m)
                    // immer — als einziger Standort-Hinweis statt des Punkts.
                    if let loc = locationManager.userLocation,
                       locationManager.horizontalAccuracy > 20 {
                        MapCircle(center: loc, radius: locationManager.horizontalAccuracy)
                            .foregroundStyle(Color.brand.opacity(0.12))
                            .stroke(Color.brand.opacity(0.35), lineWidth: 1)
                    }

                    // Drops & Freunde
                    // HINWEIS: @EnvironmentObject ist in Map-Annotation-Content nicht
                    // zuverlässig (MapKit eigener View-Context). Wir übergeben alles explizit.
                    ForEach(filteredAnnotations) { item in
                        Annotation("", coordinate: item.coordinate, anchor: .center) {
                            DropMapPin(
                                item: item,
                                isJoined: joinedIDs.contains(item.id),
                                onTap: { selectedItem = item },
                                myToken: myPinToken,
                                confirmedTokens: store.bluetoothMeetup.confirmedTokens
                            )
                        }
                    }
                }
                .id(mapId)
                .ignoresSafeArea()
                // ── Punkte aktualisieren synchron mit jedem Kamera-Frame ─
                // .continuous feuert für jeden MapKit-Render-Frame während
                // Scroll/Zoom → Overlay-Geometrie ist immer in sync.
                .onMapCameraChange(frequency: .continuous) { _ in
                    // Alle 5 Launch-Städte als Polygon-Overlay — damit man beim
                    // Rauszoomen auf Deutschland alle Service-Zones sieht.
                    cityPolygonsPts = Self.allCityPolygonsPts(proxy: proxy)
                }
                // ── Aurora-Grenzen um alle 5 Launch-Städte ──────────────
                .overlay {
                    MultiZoneOverlay(polygons: cityPolygonsPts)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if let loc = locationManager.userLocation {
                    if !hasInitiallyZoomed {
                        mapPosition = .region(MKCoordinateRegion(
                            center: loc,
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        ))
                        hasInitiallyZoomed = true
                    }
                    store.updateUserLocation(loc)
                }
            }
            .onChange(of: locationManager.userLocation) { _, loc in
                guard let loc = loc else { return }
                if !hasInitiallyZoomed {
                    withAnimation {
                        mapPosition = .region(MKCoordinateRegion(
                            center: loc,
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        ))
                    }
                    hasInitiallyZoomed = true
                }
                store.updateUserLocation(loc)
            }
            .onChange(of: store.pendingDropID) { _, dropID in
                guard let dropID = dropID else { return }
                store.pendingDropID = nil
                // Drop auf der Karte finden und Sheet öffnen
                if let match = store.allMapAnnotations.first(where: { $0.id == dropID }) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        mapPosition = .region(MKCoordinateRegion(
                            center: match.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                        ))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedItem = match
                    }
                }
            }
            .onChange(of: store.focusedDropCoordinate) { _, coord in
                guard let coord = coord else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    mapPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    ))
                }
                // Reset nach dem Fokussieren, damit erneutes Tippen erneut feuert
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    store.focusedDropCoordinate = nil
                }
            }

            VStack {
                // ── Power-Hour Countdown-Pille (oben) ────────────────────
                // Auto-updates jede Minute via TimelineView. Sichtbar in
                // zwei Phasen:
                //   – ≤60 Min vor Start → "Power-Hour in 47 Min"
                //   – ≤60 Min vor Ende eines aktiven Slots → "endet in 23 Min"
                // Sonst nil → keine Pille.
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    if let cd = AppStore.powerHourCountdown(at: ctx.date) {
                        PowerHourCountdownPill(countdown: cd)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Spacer()

                // ── Bottom-Row: Boost-Phase-Banner (links, full-width) +
                //               Recenter-Button (rechts) ──────────────────
                // Banner ist DAUERHAFT solange Boost-Phase aktiv ist:
                //   – nicht aus-/einklappbar
                //   – nicht draggable / verschiebbar
                //   – Tap überall am Banner → öffnet Drop-Erstellen
                // Banner spannt von der linken Bildschirmkante bis kurz vor
                // dem Recenter-Button (`maxWidth: .infinity` im HStack
                // teilt sich den verfügbaren Platz gegen den Recenter).
                HStack(alignment: .center, spacing: 10) {
                    // Banner zeigt sich bei Boost-Phase ODER Power-Hour —
                    // beides sind unabhängige Trigger für den Bonus.
                    if store.isBoostPhaseActive || store.isPowerHourActive {
                        Button {
                            store.selectedTab = .create
                        } label: {
                            HStack(spacing: 12) {
                                // Bolt im weißen Glas-Kreis links
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle().fill(Color.white.opacity(0.18))
                                    )

                                // Power-Hour ändert NUR Titel + Punktzahl —
                                // Bonus wird in store.currentBoostBonus
                                // berechnet (15 normal, 25 in Power-Hour).
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.isPowerHourActive
                                         ? "Power-Hour aktiv"
                                         : "Boost-Phase aktiv")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("+\(store.currentBoostBonus) Punkte für jeden Drop, den du jetzt erstellst")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.88))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Capsule statt RoundedRectangle → maximal runde
                            // Ecken (Radius = Hälfte der Höhe), so wie die
                            // iOS 26 Tab Bar es auch macht.
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.accentOrange, Color.brand],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                            )
                            .shadow(color: Color.accentOrange.opacity(0.35), radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Boost-Phase aktiv – Drop erstellen")
                    }

                    Button(action: {
                        let loc = locationManager.userLocation
                            ?? CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)
                        withAnimation(.easeInOut(duration: 0.4)) {
                            mapPosition = .region(MKCoordinateRegion(
                                center: loc,
                                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                            ))
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.brand)
                            .padding(13)
                            .liquidGlassCircle()
                    }
                    .accessibilityLabel(tr("map.recenter"))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $selectedItem) { item in
            DropJoinSheet(item: item, isJoined: joinedIDs.contains(item.id)) {
                joinedIDs.insert(item.id)
                store.sendJoinRequest(to: item)   // Request statt Direkt-Join
            }
            .environmentObject(store)
            .presentationDetents([.fraction(0.45)])
            .presentationDragIndicator(.hidden)
            .sheetBackground()
        }
        // Host: eingehende Beitrittsanfrage
        .sheet(item: $store.activeIncomingRequest) { req in
            IncomingJoinRequestSheet(request: req)
                .environmentObject(store)
                .presentationDetents([.fraction(0.52)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        .sheet(isPresented: $showSafety) {
            SafetySheetView().environmentObject(store)
        }
        // Power-Hour Onboarding-Hinweis: einmalig nach Update.
        // Verzögerter Trigger im onAppear, damit er nicht direkt mit dem
        // Map-Camera-Setup konkurriert.
        .sheet(isPresented: $showPowerHourIntro) {
            PowerHourIntroSheet {
                hasSeenPowerHourIntro = true
                showPowerHourIntro = false
            }
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)
            .sheetBackground()
        }
        .onAppear {
            if !hasSeenPowerHourIntro {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showPowerHourIntro = true
                }
            }
        }
    }

}

// MARK: - Drop Map Pin

struct DropMapPin: View {
    let item: MapAnnotationItem
    var isJoined: Bool
    let onTap: () -> Void
    /// Eigener 8-Char-Token (vom Parent übergeben, da @EnvironmentObject in Map-Annotations nicht zuverlässig ist)
    var myToken: String = ""
    /// BLE-bestätigte Partner-Tokens (vom Parent übergeben)
    var confirmedTokens: Set<String> = []
    @State private var pressed = false

    /// Nur bestätigte Teilnehmer anzeigen (BLE-confirmed oder eigener Token als Host).
    var confirmedParticipants: [DropParticipant] {
        item.participants.filter { p in
            p.token == myToken || confirmedTokens.contains(p.token)
        }
    }

    var pinColor: Color {
        switch item.type {
        case .friend:   return isJoined ? .onlineGreen : .brand
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger:
            return item.creatorAgeGroup?.color ?? Color(hex: "06b6d4")
        }
    }

    // Skalierung basierend auf bestätigten Teilnehmern
    var emojiCircleSize: CGFloat {
        let count = confirmedParticipants.count
        switch count {
        case 0, 1: return 24
        case 2, 3: return 28
        case 4, 5: return 32
        default:   return 38
        }
    }

    var emojiFontSize: CGFloat { emojiCircleSize * 0.54 }
    var labelFontSize: CGFloat { emojiCircleSize < 30 ? 12 : 13 }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pressed = false }
            onTap()
        }) {
            if item.isFuzzy {
                // Ungenaue Position: großer Radius-Kreis + verschleierter Pin
                ZStack {
                    // Unscharfer Umkreis — zeigt "könnte hier irgendwo sein"
                    Circle()
                        .fill(Color(UIColor.systemGray).opacity(0.07))
                        .frame(width: 90, height: 90)
                        .overlay(
                            Circle().stroke(
                                Color(UIColor.systemGray).opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                        )

                    // Kleiner verschwommener Drop-Pin in der Mitte
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color(UIColor.systemGray3).opacity(0.4))
                                .frame(width: 22, height: 22)
                            Text(item.emoji)
                                .font(.system(size: 12))
                                .blur(radius: 1.5)
                        }
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule().stroke(Color(UIColor.systemGray4).opacity(0.5), lineWidth: 0.5)
                    )
                }
                .scaleEffect(pressed ? 1.06 : 1.0)
            } else {
                // Exakter Pin (normaler Nutzer oder verifizierter Nutzer)
                HStack(spacing: 6) {
                    ZStack {
                        // Drops+ Boost: goldener Glow-Ring
                        if item.isBoosted {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b"), Color(hex: "fcd34d")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: emojiCircleSize + 8, height: emojiCircleSize + 8)
                                .shadow(color: Color(hex: "f59e0b").opacity(0.7), radius: 6)
                        }
                        Circle()
                            .fill(item.isBoosted ? Color(hex: "f59e0b").opacity(0.18) : pinColor.opacity(0.18))
                            .frame(width: emojiCircleSize, height: emojiCircleSize)
                        Circle()
                            .stroke(item.isBoosted ? Color(hex: "f59e0b").opacity(0.6) : pinColor.opacity(0.5), lineWidth: 1.5)
                            .frame(width: emojiCircleSize, height: emojiCircleSize)
                        Text(item.emoji).font(.system(size: emojiFontSize))
                        if confirmedParticipants.count >= 2 {
                            Text("\(confirmedParticipants.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(pinColor, in: Circle())
                                .offset(x: emojiCircleSize * 0.3, y: emojiCircleSize * 0.3)
                        }
                        // Boost-Badge oben rechts
                        if item.isBoosted {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(hex: "f59e0b"))
                                .padding(3)
                                .background(Color.black.opacity(0.6), in: Circle())
                                .offset(x: emojiCircleSize * 0.38, y: -emojiCircleSize * 0.38)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.type == .myDrop ? item.activity : (item.isStranger ? item.activity : item.name))
                            .font(.system(size: labelFontSize, weight: .semibold))
                            .foregroundColor(.textPrimary).lineLimit(1)
                        // Alter bei Stranger-Drops
                        if item.isStranger, let age = item.creatorAge {
                            Text("\(age) J.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(pinColor.opacity(0.85))
                        }
                    }
                    if item.type == .myDrop {
                        Text("· Du").font(.system(size: 10)).foregroundColor(.textSecondary)
                    } else if item.type == .joiner {
                        // Unterwegs-Indikator
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10))
                            .foregroundColor(.onlineGreen)
                    } else if item.isStranger {
                        Circle().fill(pinColor.opacity(0.7)).frame(width: 5, height: 5)
                    } else {
                        Circle().fill(Color.onlineGreen).frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, 7).padding(.horizontal, 11)
                .liquidGlassCapsule()
                .overlay(Capsule().stroke(pinColor.opacity(0.45), lineWidth: 1))
                .scaleEffect(pressed ? 1.08 : 1.0)
                .shadow(color: pinColor.opacity(0.55), radius: 14, y: 0)
                .shadow(color: pinColor.opacity(0.25), radius: 28, y: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drop Join Sheet

// MARK: - Incoming Join Request Sheet (Host)

struct IncomingJoinRequestSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let request: IncomingJoinRequest

    @State private var timeLeft: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var autoAcceptSeconds: Int {
        max(0, Int(request.autoAcceptAt.timeIntervalSinceNow))
    }

    /// Entfernung Joiner → Drop-Standort, berechnet aus Live-Koordinaten.
    private var joinerDistanceMeters: Double? {
        guard let coord = store.joinerLiveCoordinates[request.id],
              let drop  = store.activeDrops.first(where: { $0.id.uuidString == request.dropID })
        else { return nil }
        let joinerLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let dropLoc   = CLLocation(latitude: drop.location.coordinate.latitude,
                                    longitude: drop.location.coordinate.longitude)
        return joinerLoc.distance(from: dropLoc)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters)) m entfernt" }
        return String(format: "%.1f km entfernt", meters / 1000)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Anfrage-Header ─────────────────────────────────────
            VStack(spacing: 6) {
                Text("Beitrittsanfrage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(store.activeDrops.first?.activity.name ?? "Dein Drop")
                    .font(.system(size: 17, weight: .bold))
            }
            .padding(.top, 20).padding(.bottom, 24)

            // ── Profil ────────────────────────────────────────────
            VStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 88, height: 88)
                    if let urlStr = request.joinerProfileImageURL, !urlStr.isEmpty {
                        RemoteProfileImage(url: urlStr, fallbackEmoji: request.joinerEmoji,
                                           size: 88)
                    } else {
                        Text(request.joinerEmoji)
                            .font(.system(size: 44))
                    }
                }
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5))

                HStack(spacing: 6) {
                    Text(request.joinerName)
                        .font(.system(size: 22, weight: .bold))
                    if let age = request.joinerAge {
                        Text("\(age)")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                    if request.joinerIsPlus {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                            Text("PLUS").font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(Color(hex: "7a4e05"))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            LinearGradient(colors: [Color(hex: "d4a017"), Color(hex: "a87408")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                    }
                }

                // Tier + Entfernung in einer Zeile
                HStack(spacing: 10) {
                    let tierColor = ReliabilityScore.color(forPoints: request.joinerReliabilityPoints)
                    HStack(spacing: 4) {
                        Image(systemName: ReliabilityScore.badgeIcon(forPoints: request.joinerReliabilityPoints))
                            .font(.system(size: 11, weight: .semibold))
                        Text(ReliabilityScore.badge(forPoints: request.joinerReliabilityPoints))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(tierColor)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tierColor.opacity(0.14), in: Capsule())

                    if let meters = joinerDistanceMeters {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.system(size: 10))
                            Text(formatDistance(meters))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.textSecondary.opacity(0.10), in: Capsule())
                    }
                }
                .padding(.top, 4)

                // Auto-Accept Countdown
                if timeLeft > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("Automatisch bestätigt in \(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)

            // ── Buttons ───────────────────────────────────────────
            HStack(spacing: 14) {
                // Ablehnen
                Button {
                    store.declineJoinRequest(request)
                    dismiss()
                } label: {
                    Label("Ablehnen", systemImage: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }

                // Bestätigen
                Button {
                    store.acceptJoinRequest(request)
                    dismiss()
                } label: {
                    Label("Bestätigen", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onReceive(timer) { _ in
            timeLeft = autoAcceptSeconds
            if timeLeft <= 0 { dismiss() }
        }
        .onAppear { timeLeft = autoAcceptSeconds }
    }
}

struct DropJoinSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"
    let item: MapAnnotationItem
    var isJoined: Bool
    let onJoin: () -> Void

    @State private var joining = false
    @State private var resolvedAddress: String? = nil
    @State private var now = Date()
    @State private var showCancelAlert = false
    @State private var showCreatorProfile = false

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Nur BLE-bestätigte Teilnehmer (+ eigener Host-Token) anzeigen.
    private var confirmedParticipants: [DropParticipant] {
        let myToken = String(store.currentUser.id.uuidString
            .replacingOccurrences(of: "-", with: "").prefix(8))
        return item.participants.filter { p in
            p.token == myToken || store.bluetoothMeetup.confirmedTokens.contains(p.token)
        }
    }

    // Ist der Nutzer bereits in einem anderen Drop aktiv?
    private var blockedByOtherDrop: Bool {
        guard let active = store.activeJoinedDropID else { return false }
        return active != item.id
    }

    private var activeSince: String {
        let elapsed = Int(now.timeIntervalSince(item.createdAt) / 60)
        if elapsed < 1 { return tr("drop.just_started") }
        if elapsed < 60 { return "Seit \(elapsed) Min aktiv" }
        let h = elapsed / 60
        let m = elapsed % 60
        return m > 0 ? "Seit \(h)h \(m)min aktiv" : "Seit \(h)h aktiv"
    }

    private var startTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return "Gestartet \(f.string(from: item.createdAt)) Uhr"
    }

    var accentColor: Color {
        switch item.type {
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger: return item.creatorAgeGroup?.color ?? Color(hex: "06b6d4")
        default:        return .brand
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle + Share Button
            ZStack {
                Capsule().fill(Color(UIColor.systemGray4))
                    .frame(width: 36, height: 4)
                HStack {
                    Spacer()
                    DropShareButton(item: item)
                        .padding(.trailing, 16)
                }
            }
            .padding(.top, 10).padding(.bottom, 16)

            // Header: Aktivitäts-Emoji + Info (Profilbild beim Teilnehmer-Row)
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    // Fallback ✨ wenn beim Drop-Erstellen kein Emoji gewählt
                    Text(item.emoji.isEmpty ? "✨" : item.emoji)
                        .font(.system(size: 28))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Aktivität als Haupttitel — bei Fremden und Freunden
                        Text(item.type == .myDrop ? item.activity : (item.isStranger ? item.activity : item.name))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if item.isStranger {
                            Text(tr("drop.open_to_all"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accentColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    // Host-Name + Avatar — tappbar bei allen fremden Drops
                    // (Stranger oder Friend), öffnet das Mini-Profil.
                    if item.type != .myDrop {
                        Button { showCreatorProfile = true } label: {
                            HStack(spacing: 5) {
                                // Host-Avatar — Profilbild mit Fallback
                                if let creator = item.participants.first {
                                    ZStack {
                                        if let img = creator.selfie {
                                            Image(uiImage: img)
                                                .resizable().scaledToFill()
                                                .frame(width: 18, height: 18)
                                                .clipShape(Circle())
                                        } else if creator.profileImageURL != nil {
                                            RemoteProfileImage(
                                                url: creator.profileImageURL,
                                                fallbackEmoji: creator.emoji,
                                                size: 18,
                                                strokeColor: .clear
                                            )
                                        } else {
                                            Circle()
                                                .fill(accentColor.opacity(0.18))
                                                .frame(width: 18, height: 18)
                                                .overlay(Text(creator.emoji).font(.system(size: 10)))
                                        }
                                    }
                                }
                                Text(item.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Label(tr("drop.my_drop"), systemImage: "star.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentOrange)
                    }
                    // ETA + Distanz
                    if item.type != .myDrop {
                        HStack(spacing: 10) {
                            Label(store.etaString(to: item.coordinate) + " Weg",
                                  systemImage: "figure.walk")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(accentColor)
                            Label(store.distanceString(to: item.coordinate),
                                  systemImage: "mappin.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)

            // Teilnehmer-Avatare — nur BLE-bestätigte (physisch vor Ort)
            if !confirmedParticipants.isEmpty {
                HStack(spacing: 10) {
                    ParticipantAvatars(participants: confirmedParticipants)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(participantNamesLabel(confirmedParticipants))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text(confirmedParticipants.count == 1
                             ? "Ist bereits vor Ort"
                             : "Sind bereits vor Ort")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            // Unterwegs-Anzeige: Beitritt aber noch nicht per BLE bestätigt
            let onTheWayCount = item.participants.count - confirmedParticipants.count
            if onTheWayCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    Text(onTheWayCount == 1
                         ? "1 Person ist unterwegs"
                         : "\(onTheWayCount) Personen sind unterwegs")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.top, onTheWayCount > 0 && confirmedParticipants.isEmpty ? 12 : 4)
            }

            // Adresse (Reverse Geocoding)
            if let address = resolvedAddress {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            // Aktiv-Dauer (ohne Startzeit)
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.onlineGreen)
                    .frame(width: 6, height: 6)
                Text(activeSince)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.onlineGreen)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .onReceive(timer) { _ in now = Date() }

            // Optionale Zusatzinfos (Uhrzeit nur bei geplanten Drops, nicht bei "Jetzt")
            let showTimeTile = item.scheduledTime != nil && item.scheduledTime != "Jetzt"
            if showTimeTile || item.dropDescription != nil {
                VStack(spacing: 8) {
                    if showTimeTile, let time = item.scheduledTime {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12)).foregroundColor(.brand)
                            Text(time).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                        }
                    }
                    if let desc = item.dropDescription, !desc.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            Text(desc).font(.system(size: 13)).foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }

            Spacer(minLength: 0)

            // Bottom
            if item.type == .myDrop {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 13)).foregroundColor(.accentOrange)
                        Text(tr("drop.waiting_for_joiners"))
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                    }

                    // ── Drops+ Boost Button — Premium-Light Gold ────────
                    // Aus für den initialen Launch (FeatureFlags.dropsPlusEnabled).
                    if FeatureFlags.dropsPlusEnabled {
                        Button {
                            if item.isBoosted {
                                store.unboostActiveDrop()
                            } else {
                                store.boostActiveDrop()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.isBoosted ? "bolt.circle.fill" : "bolt.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(item.isBoosted ? "Boost aktiv" : "Drop boosten")
                                    .font(.system(size: 15, weight: .semibold))
                                if !store.isPlusUser {
                                    Text("Drops+")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "7a4e05"))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.white.opacity(0.35), in: Capsule())
                                }
                            }
                            .foregroundColor(item.isBoosted ? Color(hex: "a87408") : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Group {
                                    if item.isBoosted {
                                        Color(hex: "d4a017").opacity(0.15)
                                    } else {
                                        LinearGradient(
                                            colors: [Color(hex: "d4a017"), Color(hex: "a87408")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        item.isBoosted
                                            ? Color(hex: "d4a017").opacity(0.5)
                                            : Color.white.opacity(0.20),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color(hex: "a87408").opacity(item.isBoosted ? 0 : 0.25),
                                    radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .sheet(isPresented: $store.showDropsPlusPaywall) {
                            DropsPlusView()
                        }
                    }

                    Button {
                        showCancelAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            Text(tr("drop.end_drop")).font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentRed, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accentRed.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
                .alert(tr("drop.confirm_end_title"), isPresented: $showCancelAlert) {
                    Button(tr("common.cancel"), role: .cancel) {}
                    Button(tr("common.done"), role: .destructive) {
                        store.cancelDrop(id: item.id)
                        dismiss()
                    }
                } message: {
                    Text(tr("drop.end_drop_message"))
                }
                .alert("Live Activity deaktiviert", isPresented: $store.showLiveActivitySettingsHint) {
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Dynamic Island und Sperrbildschirm-Anzeige sind für Drops deaktiviert. Aktiviere sie unter Einstellungen → Drops → Live Activities.")
                }
            } else if blockedByOtherDrop {
                // Bereits in einem anderen Drop aktiv
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.textTertiary)
                        Text(tr("drop.already_active"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(tr("drop.leave_active_first"))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            } else {
                Button {
                    guard !isJoined && !joining else { return }
                    joining = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        joining = false
                        onJoin()
                        dismiss()
                        // Sofort auf den Aktiv-Tab wechseln
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            store.selectedTab = .create
                        }
                    }
                } label: {
                    let isPending = store.myJoinRequestStatus == "pending" && isJoined
                    let isDeclined = store.myJoinRequestStatus == "declined" && isJoined
                    ZStack {
                        if joining || isPending {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white).scaleEffect(0.85)
                                Text(isPending ? "Warte auf Bestätigung…" : "")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        } else if isDeclined {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 17))
                                Text("Nicht bestätigt").font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                        } else if isJoined {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 17))
                                Text(tr("drop.im_in")).font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.walk.arrival").font(.system(size: 17))
                                Text(tr("drop.coming_by")).font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule().fill(
                            isDeclined ? Color.red.opacity(0.7) :
                            isJoined   ? Color.onlineGreen :
                            joining    ? accentColor.opacity(0.7) : accentColor
                        )
                        .shadow(color: accentColor.opacity(0.4), radius: 12, y: 5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isJoined || joining)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.3), value: isJoined)
                .animation(.spring(response: 0.3), value: joining)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            geocodeAddress()
            // Drop-View für Drops+ „wer hat geschaut" erfassen
            store.viewDrop(item)
        }
        .sheet(isPresented: $showCreatorProfile) {
            if let creator = item.participants.first {
                if #available(iOS 16.4, *) {
                    MiniProfileSheet(
                        name: creator.name,
                        emoji: creator.emoji,
                        selfie: creator.selfie,
                        profileImageURL: creator.profileImageURL,
                        reliabilityScore: creator.reliabilityScore,
                        accentColor: accentColor,
                        isVerified: creator.isVerified,
                        userUID: creator.firebaseUID,
                        canBlock: true
                    ) { dismiss() }
                    .environmentObject(store)
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.hidden)
                    .sheetBackground()
                } else {
                    MiniProfileSheet(
                        name: creator.name,
                        emoji: creator.emoji,
                        selfie: creator.selfie,
                        profileImageURL: creator.profileImageURL,
                        reliabilityScore: creator.reliabilityScore,
                        accentColor: accentColor,
                        isVerified: creator.isVerified,
                        userUID: creator.firebaseUID,
                        canBlock: true
                    ) { dismiss() }
                    .environmentObject(store)
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.hidden)
                }
            }
        }
    }

    // MARK: - Teilnehmer-Namen

    private func participantNamesLabel(_ participants: [DropParticipant]) -> String {
        let names = participants.map { $0.name }
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        case 3: return "\(names[0]), \(names[1]) & \(names[2])"
        default:
            let visible = names.prefix(2).joined(separator: ", ")
            return "\(visible) & \(names.count - 2) weitere"
        }
    }

    // MARK: - Reverse Geocoding

    private func geocodeAddress() {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            let street = [p.thoroughfare, p.subThoroughfare]
                .compactMap { $0 }.joined(separator: " ")
            let city = p.locality ?? ""
            DispatchQueue.main.async {
                resolvedAddress = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
    }
}

// MARK: - In-App Route Sheet

struct InAppRouteSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let destination: CLLocationCoordinate2D
    let destinationName: String
    let accentColor: Color

    @State private var route: MKRoute? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Topbar
            HStack {
                Button(tr("common.close")) { dismiss() }
                    .font(.system(size: 15)).foregroundColor(accentColor)
                Spacer()
                Text(tr("map.route"))
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                Spacer()
                Text(tr("common.close")).foregroundColor(.clear) // balance
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color.bgPrimary)

            Divider()

            // Karte mit Route
            ZStack {
                RouteMapView(
                    userCoordinate: store.currentUser.coordinate,
                    destination: destination,
                    route: route
                )
                if isLoading {
                    Color.black.opacity(0.08)
                    VStack(spacing: 10) {
                        ProgressView().tint(accentColor)
                        Text(tr("map.calculating_route"))
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(edges: .horizontal)

            // Info + Button
            VStack(spacing: 14) {
                // Reisezeit + Distanz
                if let route = route {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("map.walking"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            Text("~\(max(1, Int(route.expectedTravelTime / 60))) Min")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Divider().frame(height: 44)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tr("map.distance"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            Text(route.distance < 1000
                                 ? "\(Int(route.distance)) m"
                                 : String(format: "%.1f km", route.distance / 1000))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Ziel-Adresse
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(accentColor).font(.system(size: 14))
                    Text(destinationName)
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                    Spacer()
                }

                // Schließen-Button (Hauptaktion)
                Button { dismiss() } label: {
                    Text(tr("common.close"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                // Sekundär: Turn-by-Turn in Apple Maps
                Button {
                    let placemark = MKPlacemark(coordinate: destination)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = destinationName
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                    ])
                } label: {
                    Label(tr("map.open_in_maps"),
                          systemImage: "arrow.triangle.turn.up.right.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .background(Color.bgPrimary)
        }
        .background(Color.bgPrimary)
        .onAppear { calculateRoute() }
    }

    private func calculateRoute() {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: store.currentUser.coordinate)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: destination)
        )
        request.transportType = .walking
        MKDirections(request: request).calculate { response, _ in
            DispatchQueue.main.async {
                isLoading = false
                route = response?.routes.first
            }
        }
    }
}

// MARK: - Route Map View (UIViewRepresentable)

struct RouteMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let route: MKRoute?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        // Ziel-Pin
        let pin = MKPointAnnotation()
        pin.coordinate = destination
        map.addAnnotation(pin)

        if let route = route {
            map.addOverlay(route.polyline, level: .aboveRoads)
            // Sichtbereich an Route anpassen
            let rect = route.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.size.width * 0.25,
                                      dy: -rect.size.height * 0.25)
            map.setVisibleMapRect(padded,
                edgePadding: UIEdgeInsets(top: 60, left: 24, bottom: 60, right: 24),
                animated: true)
        } else {
            // Fallback: beide Punkte zeigen
            let coords = [userCoordinate, destination]
            let points = coords.map { MKMapPoint($0) }
            var rect = MKMapRect.null
            for p in points {
                let r = MKMapRect(x: p.x - 500, y: p.y - 500, width: 1000, height: 1000)
                rect = rect.union(r)
            }
            map.setVisibleMapRect(rect,
                edgePadding: UIEdgeInsets(top: 60, left: 24, bottom: 60, right: 24),
                animated: false)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemGreen
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "DropPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            if let marker = view as? MKMarkerAnnotationView {
                marker.markerTintColor = UIColor.systemGreen
                marker.glyphImage = UIImage(systemName: "mappin.circle.fill")
            }
            return view
        }
    }
}

// MARK: - Active Drop Tab View

struct ActiveDropTabView: View {
    @EnvironmentObject var store: AppStore
    let item: MapAnnotationItem
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Eigene LocationManager-Instanz — für GPS-basierte Ankunfts-Erkennung.
    @StateObject private var locationManager = LocationManager()
    @State private var route: MKRoute? = nil
    @State private var isLoadingRoute = true
    @State private var resolvedAddress: String? = nil
    @State private var showCancelAlert = false
    @State private var showLeaveConfirm = false
    @State private var showExtendSheet = false
    @State private var now = Date()
    @State private var arrivedAnimated = false
    @State private var showShareSheet = false
    @State private var lastExtendedAt: Date? = nil
    @State private var lastExtendCooldownSecs: Int = 0  // Hälfte der gewählten Verlängerung

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Adaptive Farben
    private var isDark: Bool { colorScheme == .dark }
    private var textPrimary:   Color { isDark ? .white                  : Color(hex: "111827") }
    private var textSecondary: Color { isDark ? .white.opacity(0.65)    : Color(hex: "374151") }
    private var textTertiary:  Color { isDark ? .white.opacity(0.42)    : Color(hex: "6b7280") }
    private var cardFill:      Color { isDark ? Color(hex: "1c1f28")    : Color.white.opacity(0.88) }
    private var cardStroke:    Color { isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    private var rowFill:       Color { isDark ? Color(hex: "1e2430")    : Color.white.opacity(0.72) }
    private var scrimOpacity:  Double { isDark ? 0.68 : 0.0 }

    var isOwnDrop: Bool { item.type == .myDrop }

    /// Eigener Token (8-stellig)
    var myToken: String {
        String(store.currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    /// Schwelle in Metern, ab der GPS-Nähe als „vor Ort" gilt.
    /// Eng gesetzt (< 20 m) damit der Host erst wirklich am Ziel ankommt — nicht
    /// schon beim Vorbeifahren auf „angekommen" springt.
    private static let gpsArrivalThresholdMeters: Double = 20

    /// Prüft ob GPS-Position nahe genug am Drop-Ort ist.
    private var isNearDropByGPS: Bool {
        guard let dist = liveDistanceMeters else { return false }
        return dist <= Self.gpsArrivalThresholdMeters
    }

    /// Live Luftlinien-Distanz zum Drop in Metern. Re-berechnet sich bei jedem
    /// GPS-Update (locationManager.userLocation ist @Published), daher updated
    /// die Anzeige im Aktiv-Tab **live** während man läuft — statt nur beim
    /// Tab-Switch wie vorher mit der statischen Route-Distanz.
    private var liveDistanceMeters: Double? {
        guard let user = locationManager.userLocation else { return nil }
        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let dropLoc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        return userLoc.distance(from: dropLoc)
    }

    /// Geschätzte Gehzeit basierend auf liveDistanceMeters (~1.25 m/s = 75 m/min
    /// Fußgänger-Durchschnitt in der Stadt).
    private var liveWalkMinutes: Int? {
        guard let dist = liveDistanceMeters else { return nil }
        return max(1, Int(dist / 75))
    }

    /// Host ist „angekommen" sobald eine dieser Bedingungen zutrifft:
    ///   1. Drop wurde am aktuellen Standort erstellt (`dropLocationType == .current`)
    ///   2. GPS-Position ist ≤ 100 m vom Drop-Koordinaten entfernt
    ///   3. Mindestens eine BLE-Bestätigung mit einem anderen Teilnehmer
    /// Joiner: ebenfalls via GPS oder BLE.
    var isArrived: Bool {
        let hostAutoArrived = isOwnDrop && item.dropLocationType == .current
        return hostAutoArrived
            || isNearDropByGPS
            || !store.bluetoothMeetup.confirmedTokens.isEmpty
    }

    /// Synthetischer Host-Teilnehmer für fremde Drops (Firebase liefert keine Participants).
    private var syntheticHost: DropParticipant {
        DropParticipant(name: item.name, emoji: item.emoji, token: "__host__")
    }

    /// Physisch bestätigte Teilnehmer (BLE + Host immer "vor Ort" bei fremden Drops).
    var confirmedHere: [DropParticipant] {
        if item.participants.isEmpty && !isOwnDrop {
            // Host ist immer vor Ort — ggf. weitere BLE-bestätigte einfügen
            var result = [syntheticHost]
            let bleConfirmed = store.bluetoothMeetup.confirmedTokens
            if !bleConfirmed.isEmpty {
                let extra = bleConfirmed.map { token in
                    DropParticipant(name: "", emoji: item.emoji, token: token)
                }
                result.append(contentsOf: extra)
            }
            return result
        }
        return item.participants.filter { p in
            p.token == myToken || store.bluetoothMeetup.confirmedTokens.contains(p.token)
        }
    }

    /// Unterwegs (beigetreten, aber noch nicht per BLE bestätigt).
    var onTheWay: [DropParticipant] {
        if item.participants.isEmpty && !isOwnDrop {
            // Aktueller User ist unterwegs bis BLE bestätigt
            guard !isArrived else { return [] }
            return [DropParticipant(name: store.currentUser.name,
                                    emoji: store.currentUser.emoji,
                                    token: myToken)]
        }
        return item.participants.filter { p in
            p.token != myToken && !store.bluetoothMeetup.confirmedTokens.contains(p.token)
        }
    }

    var accentColor: Color {
        switch item.type {
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger: return item.creatorAgeGroup?.color ?? Color(hex: "06b6d4")
        default:        return .brand
        }
    }

    var activeSince: String {
        let e = Int(now.timeIntervalSince(item.createdAt) / 60)
        if e < 1 { return tr("drop.just_started") }
        if e < 60 { return "Seit \(e) Min" }
        let h = e / 60; let m = e % 60
        return m > 0 ? "Seit \(h)h \(m)min" : "Seit \(h)h"
    }

    // Kompakter Header-Emoji: kleiner wenn Unterwegs-Personen da sind
    private var headerEmojiSize: CGFloat {
        onTheWay.count > 0 ? 160 : 220
    }

    @ViewBuilder
    private var activeDropBackground: some View {
        ZStack {
            // Aurora-Hintergrund — folgt System-ColorScheme
            AppAuroraBackground()

            // Scrim: im Dark-Mode abdunkeln, im Light-Mode nix
            Color.black.opacity(scrimOpacity)

            // Dezenter Akzent-Glow in Drop-Farbe
            RadialGradient(
                colors: [accentColor.opacity(isDark ? 0.22 : 0.15), Color.clear],
                center: UnitPoint(x: 0.5, y: 0.15),
                startRadius: 0, endRadius: 380
            )
        }
    }

    var body: some View {
        ZStack {
            // ── Vollflächiger Aurora-Hintergrund ──────────────────────
            activeDropBackground
                .ignoresSafeArea()

            // ── Scrollbarer Inhalt ────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top-Spacer für Safe Area
                    Color.clear.frame(height: 16)

                    if isArrived {
                        arrivedContent
                    } else {
                        onTheWayContent
                    }
                }
            }
        }
        .onAppear {
            calculateRoute()
            geocodeAddress()
            if isArrived { arrivedAnimated = true }
        }
        .onReceive(timer) { _ in now = Date() }
        .onChange(of: isArrived) { _, arrived in
            if arrived { withAnimation(.spring(response: 0.5)) { arrivedAnimated = true } }
        }
        .alert(tr("drop.confirm_end_title"), isPresented: $showCancelAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button(tr("common.done"), role: .destructive) { store.cancelDrop(id: item.id) }
        } message: {
            Text(tr("drop.end_drop_message"))
        }
    }

    // MARK: - Shared Header + Card Helper

    @ViewBuilder
    private var dropHeader: some View {
        let hasParticipants = !confirmedHere.isEmpty || !onTheWay.isEmpty
        // ── Abgelaufen-Banner (Drop unsichtbar für neue User, aber noch aktiv) ──
        if isOwnDrop && item.isTimeExpired {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Drop nicht mehr sichtbar")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Neue Leute können nicht mehr beitreten")
                        .font(.system(size: 11))
                        .opacity(0.7)
                }
                Spacer()
            }
            .foregroundColor(.accentOrange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        HStack(spacing: 16) {
            // Emoji-Kreis — kleiner wenn Personen vorhanden
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: hasParticipants ? 62 : 90,
                           height: hasParticipants ? 62 : 90)
                Text(item.emoji)
                    .font(.system(size: hasParticipants ? 32 : 46))
            }
            .animation(.spring(response: 0.4), value: hasParticipants)

            // Titel + Status
            VStack(alignment: .leading, spacing: 5) {
                Text(item.activity)
                    .font(.system(size: hasParticipants ? 20 : 24, weight: .bold))
                    .foregroundColor(textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "3b82f6")).frame(width: 6, height: 6)
                    Text(isOwnDrop ? tr("drop.my_drop_active") : (isArrived ? tr("drop.arrived") : tr("drop.on_the_way")))
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "3b82f6"))
                    Text("· \(activeSince)").font(.system(size: 12)).foregroundColor(textSecondary)
                }
                // Teilnehmer-Slots
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundColor(textTertiary)
                    // Bei fremden Drops: mind. 1 (der Host), sonst echte Anzahl
                    let joined = isOwnDrop ? item.participants.count : max(1, confirmedHere.count + (isArrived ? 0 : 1))
                    let maxP   = item.maxParticipants
                    Text("\(joined)/\(maxP) Teilnehmer")
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                    if joined >= maxP {
                        Text("· Voll").font(.system(size: 11, weight: .semibold)).foregroundColor(.accentOrange)
                    }
                }

            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, hasParticipants ? 10 : 20)
        .animation(.spring(response: 0.4), value: hasParticipants)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Unterwegs-Ansicht

    @ViewBuilder
    private var onTheWayContent: some View {
        // Header
        dropHeader

        // Route-Info Card
        sectionCard {
            if isLoadingRoute {
                HStack(spacing: 10) {
                    ProgressView().tint(accentColor).scaleEffect(0.85)
                    Text(tr("map.calculating_route"))
                        .font(.system(size: 14)).foregroundColor(textSecondary)
                }
            } else if let r = route {
                // Gehzeit kommt aus MKRoute (einmal berechnet, genauer weil
                // Gebäude-Umrundung), aber Distanz kommt LIVE aus dem GPS:
                // updated während man geht, nicht nur beim Tab-Switch.
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("~\(liveWalkMinutes ?? max(1, Int(r.expectedTravelTime / 60))) Min zu Fuß")
                            .font(.system(size: 17, weight: .bold)).foregroundColor(textPrimary)
                        Text({
                            let dist = liveDistanceMeters ?? r.distance
                            return dist < 1000
                                ? "\(Int(dist)) m entfernt"
                                : String(format: "%.1f km entfernt", dist / 1000)
                        }())
                            .font(.system(size: 13)).foregroundColor(textSecondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: liveDistanceMeters)
                        if let addr = resolvedAddress {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin").font(.system(size: 9)).foregroundColor(textTertiary)
                                Text(addr).font(.system(size: 11)).foregroundColor(textTertiary).lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        let mi = MKMapItem(placemark: MKPlacemark(coordinate: item.coordinate))
                        mi.name = item.activity
                        mi.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        Label(tr("map.navigation"), systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(accentColor)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Host-Vorschau (immer sichtbar für den Joiner — damit man weiß zu wem man geht)
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.brand.opacity(0.14)).frame(width: 44, height: 44)
                    Text(item.emoji).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(textPrimary)
                        if let age = item.creatorAge {
                            Text("\(age)")
                                .font(.system(size: 15))
                                .foregroundColor(textSecondary)
                        }
                    }
                    Text("Dein Host")
                        .font(.system(size: 11))
                        .foregroundColor(textTertiary)
                }
                Spacer()
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color.brand)
            }
        }

        // Gesperrte Teilnehmer-Vorschau
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(textTertiary.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15)).foregroundColor(textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("drop.details_locked"))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(textPrimary)
                    Text(tr("drop.arrive_for_unlock"))
                        .font(.system(size: 11)).foregroundColor(textTertiary)
                }
                Spacer()
            }
            if !confirmedHere.isEmpty || !onTheWay.isEmpty {
                HStack(spacing: 16) {
                    if !confirmedHere.isEmpty {
                        Label("\(confirmedHere.count) vor Ort", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.onlineGreen)
                    }
                    if !onTheWay.isEmpty {
                        HStack(spacing: 4) {
                            PulsingLiveDot()
                            Text("\(onTheWay.count) unterwegs")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(textTertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 10)
            }
        }

        VStack(spacing: 8) {
            extendButton
            leaveButton
        }
        .padding(.top, 16).padding(.bottom, 32)
    }

    // MARK: - Vor-Ort-Ansicht (freigeschaltet)

    @ViewBuilder
    private var arrivedContent: some View {
        VStack(spacing: 0) {
            dropHeader

            if isOwnDrop {
                // ── Standort + Beschreibung ───────────────────────────
                locationDescriptionCard

                // ── Plätze-Balken ─────────────────────────────────────
                spotsCard

                // ── „Wer hat deinen Drop gesehen" (Drops+ Feature) ─────
                dropViewersCard

                // ── Einladungslink (immer sichtbar) ───────────────────
                shareButtonCard

                // ── Vor Ort ───────────────────────────────────────────
                if !confirmedHere.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(tr("drop.arrived"), systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.onlineGreen)
                                Spacer()
                                Text("\(confirmedHere.count) Person\(confirmedHere.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity))
                            }
                        }
                    }
                    .animation(.spring(response: 0.45), value: confirmedHere.count)
                }

                // ── Unterwegs ─────────────────────────────────────────
                if !onTheWay.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                PulsingLiveDot()
                                Text(tr("drop.on_the_way"))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(textSecondary)
                                Text("· Live").font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "3b82f6"))
                                Spacer()
                                Text("\(onTheWay.count) Person\(onTheWay.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(textTertiary)
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate)
                            }
                        }
                    }
                }

                // ── Restzeit-Balken ───────────────────────────────────
                if item.durationMinutes > 0 { timeBarCard }

                // ── Verlängern + Beenden ──────────────────────────────
                VStack(spacing: 8) {
                    extendButton
                    leaveButton
                }
                .padding(.top, 12).padding(.bottom, 32)

            } else {
                // Joiner-Ansicht (vor Ort, nicht eigener Drop)
                inviteCard

                if !confirmedHere.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(tr("drop.arrived"), systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.onlineGreen)
                                Spacer()
                                Text("\(confirmedHere.count) Person\(confirmedHere.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate)
                            }
                        }
                    }
                }

                if !onTheWay.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                PulsingLiveDot()
                                Text(tr("drop.on_the_way"))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(textSecondary)
                                Spacer()
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate)
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    extendButton
                    leaveButton
                }
                .padding(.top, 16).padding(.bottom, 32)
            }
        }
    }

    // MARK: - Standort + Beschreibung

    @ViewBuilder
    private var locationDescriptionCard: some View {
        let address = resolvedAddress ?? (item.locationTitle.isEmpty ? nil : item.locationTitle)
        let hasDesc = ((item.dropDescription?.isEmpty) == nil)
        if address != nil || hasDesc {
            sectionCard {
                VStack(alignment: .leading, spacing: hasDesc && address != nil ? 10 : 0) {
                    if let addr = address {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(accentColor)
                            Text(addr)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(textPrimary)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                    if hasDesc {
                        if address != nil {
                            Divider().opacity(0.4)
                        }
                        Text(item.dropDescription ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Plätze-Balken

    private var spotsCard: some View {
        let used  = item.participants.count
        let total = max(1, item.maxParticipants)
        let free  = max(0, total - used)
        let ratio = Double(used) / Double(total)
        return sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11)).foregroundColor(textTertiary)
                        Text("\(used) von \(total) Teilnehmern")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(textPrimary)
                    }
                    Spacer()
                    Text(free == 0 ? "Voll 🔴" : "\(free) \(free == 1 ? "Platz" : "Plätze") frei")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(free == 0 ? .accentOrange : .onlineGreen)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(free == 0 ? Color.accentOrange : accentColor)
                            .frame(width: geo.size.width * ratio, height: 6)
                            .animation(.spring(response: 0.5), value: used)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - „Wer hat deinen Drop gesehen" — Drops+ Feature

    /// Zeigt die Anzahl der Viewer. Free-User sehen nur die Zahl + CTA zur Paywall.
    /// Drops+ Mitglieder sehen zusätzlich Avatare + Namen.
    @ViewBuilder
    private var dropViewersCard: some View {
        // "Wer hat geschaut" ist eine Drops+ Feature → für den Launch komplett aus.
        let viewers = FeatureFlags.dropsPlusEnabled
            ? (store.dropViewersByDropID[item.id.uuidString] ?? [])
            : []
        if !viewers.isEmpty {
            sectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "f59e0b"))
                        Text("\(viewers.count) \(viewers.count == 1 ? "Person hat" : "Personen haben") geschaut")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(textPrimary)
                        Spacer()
                        if !store.isDropsPlusActive {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(textTertiary)
                        }
                    }

                    if store.isDropsPlusActive {
                        // Plus: Avatare + Namen
                        VStack(spacing: 8) {
                            ForEach(viewers.prefix(8)) { viewer in
                                HStack(spacing: 10) {
                                    RemoteProfileImage(
                                        url: viewer.profileImageURL,
                                        fallbackEmoji: viewer.emoji,
                                        size: 34,
                                        strokeColor: Color.white.opacity(0.12)
                                    )
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            Text(viewer.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(textPrimary)
                                            if let age = viewer.age {
                                                Text(", \(age)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(textSecondary)
                                            }
                                        }
                                        Text(relativeTimeLabel(viewer.viewedAt))
                                            .font(.system(size: 11))
                                            .foregroundColor(textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                            if viewers.count > 8 {
                                Text("+ \(viewers.count - 8) weitere")
                                    .font(.system(size: 11))
                                    .foregroundColor(textTertiary)
                            }
                        }
                    } else {
                        // Free: verschwommene Avatare + Upgrade-Prompt
                        HStack(spacing: -10) {
                            ForEach(viewers.prefix(5)) { viewer in
                                RemoteProfileImage(
                                    url: viewer.profileImageURL,
                                    fallbackEmoji: viewer.emoji,
                                    size: 36,
                                    strokeColor: Color.white.opacity(0.15)
                                )
                                .blur(radius: 6)
                                .overlay(Circle().fill(Color.black.opacity(0.12)))
                            }
                            Spacer()
                        }
                        .frame(height: 40)

                        Button {
                            store.showDropsPlusPaywall = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Mit Drops+ aufdecken")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func relativeTimeLabel(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "gerade eben" }
        if elapsed < 3600 { return "vor \(elapsed / 60) Min" }
        if elapsed < 86400 { return "vor \(elapsed / 3600) Std" }
        return "vor \(elapsed / 86400) Tagen"
    }

    // MARK: - Einladungs-Button (immer sichtbar)

    private var shareButtonCard: some View {
        sectionCard {
            Button { showShareSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Freunde einladen")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12)).opacity(0.4)
                }
                .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showShareSheet) {
            let dropLink = URL(string: "https://drops-app.de/drop/\(item.id.uuidString)")!
            let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
            let text = "\(item.emoji) \(item.activity)\(location) — komm vorbei. 📍"
            ShareSheet(items: [text, dropLink])
        }
    }

    // MARK: - Restzeit-Balken

    private var timeBarCard: some View {
        let total   = Double(item.durationMinutes) * 60
        let elapsed = now.timeIntervalSince(item.createdAt)
        let ratio   = min(1, max(0, elapsed / total))
        return sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11)).foregroundColor(textTertiary)
                        Text("Restzeit")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(textPrimary)
                    }
                    Spacer()
                    Text(item.timeRemainingString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ratio > 0.85 ? .accentOrange : textSecondary)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ratio > 0.85 ? Color.accentOrange : accentColor)
                            .frame(width: geo.size.width * ratio, height: 6)
                            .animation(.linear(duration: 1), value: ratio)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Invite Card (Joiner-Ansicht, oder wenn keine Teilnehmer)

    @ViewBuilder
    private var inviteCard: some View {
        if item.participants.count <= 1 {
            sectionCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(accentColor.opacity(0.18)).frame(width: 40, height: 40)
                        Image(systemName: "person.wave.2.fill")
                            .font(.system(size: 17)).foregroundColor(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("drop.waiting_title"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(textPrimary)
                        Text(tr("drop.waiting_description"))
                            .font(.system(size: 11)).foregroundColor(textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Extend Button (nur Host)

    /// Verbleibende Cooldown-Sekunden nach dem letzten Verlängern (nil = bereit).
    /// Drops+ Bypass ist als Feature angekündigt aber noch nicht aktiv.
    private var extendCooldownRemaining: Int? {
        guard let last = lastExtendedAt, lastExtendCooldownSecs > 0 else { return nil }
        let elapsed = Int(now.timeIntervalSince(last))
        let remaining = lastExtendCooldownSecs - elapsed
        return remaining > 0 ? remaining : nil
    }

    private func formatCooldown(_ secs: Int) -> String {
        if secs < 60 { return "noch \(secs)s" }
        let m = secs / 60
        let s = secs % 60
        return s > 0 ? "noch \(m)m \(s)s" : "noch \(m) Min"
    }

    @ViewBuilder
    private var extendButton: some View {
        if isOwnDrop && item.durationMinutes > 0 {
            let onCooldown = extendCooldownRemaining != nil
            Button {
                guard !onCooldown else { return }
                showExtendSheet = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: onCooldown ? "clock" : "clock.arrow.circlepath")
                        .font(.system(size: 14))
                    if let secs = extendCooldownRemaining {
                        Text("Verlängern (\(formatCooldown(secs)))")
                            .font(.system(size: 14, weight: .semibold))
                            .contentTransition(.numericText())
                    } else {
                        Text("Verlängern")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(onCooldown ? .textTertiary : .brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    onCooldown
                        ? Color(UIColor.systemGray5)
                        : Color.brand.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            onCooldown ? Color.clear : Color.brand.opacity(0.25),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(onCooldown)
            .padding(.horizontal, 18)
            .sheet(isPresented: $showExtendSheet) {
                ExtendDropSheet(dropID: item.id, onExtended: { chosenMinutes in
                    lastExtendedAt = Date()
                    lastExtendCooldownSecs = (chosenMinutes / 2) * 60
                })
                .environmentObject(store)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Shared Leave Button

    private var leaveButton: some View {
        VStack(spacing: 0) {
            Button {
                if isOwnDrop { showCancelAlert = true }
                else { showLeaveConfirm = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOwnDrop ? "xmark.circle.fill" : "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15))
                    Text(isOwnDrop ? tr("drop.end_drop") : tr("drop.leave_drop"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isOwnDrop ? Color.accentRed : Color.accentOrange,
                            in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: (isOwnDrop ? Color.accentRed : Color.accentOrange).opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            // Info: wann der Drop automatisch endet (nur bei gesetzter Dauer)
            if item.durationMinutes > 0 && !item.timeRemainingString.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text(item.timeRemainingString)
                        .font(.system(size: 11))
                }
                .foregroundColor(textTertiary)
                .padding(.top, 6)
            }
        }
        .confirmationDialog(tr("drop.confirm_leave_title"), isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button(tr("common.back"), role: .destructive) { store.leaveDropJoin(dropID: item.id) }
            Button(tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(tr("drop.leave_warning"))
        }
    }

    // MARK: - Helpers

    private func geocodeAddress() {
        let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            DispatchQueue.main.async {
                resolvedAddress = [street, p.locality].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
    }

    private func calculateRoute() {
        let req = MKDirections.Request()
        req.source      = MKMapItem(placemark: MKPlacemark(coordinate: store.currentUser.coordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: item.coordinate))
        req.transportType = .walking
        MKDirections(request: req).calculate { response, _ in
            DispatchQueue.main.async {
                isLoadingRoute = false
                route = response?.routes.first
            }
        }
    }
}

// MARK: - Participant Detail Row

struct ParticipantDetailRow: View {
    let participant: DropParticipant
    let isArrived: Bool
    /// Standort des Drops — für die Live-Karte der unterwegs-Person
    let dropCoordinate: CLLocationCoordinate2D
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var colorScheme
    @State private var showProfile = false
    @State private var showLiveLocation = false

    private var isDark: Bool { colorScheme == .dark }
    private var rowText:  Color { isDark ? .white                : Color(hex: "111827") }
    private var rowSub:   Color { isDark ? .white.opacity(0.55)  : Color(hex: "6b7280") }
    private var rowBg:    Color { isDark ? Color(hex: "1e2430")  : Color.white.opacity(0.72) }
    private var avatarBg: Color { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06) }
    private var avatarStroke: Color { isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }

    // MARK: Helpers

    private var score: ReliabilityScore {
        let s = participant.reliabilityScore
        let total = participant.reliabilityCommits
        guard total > 0 else {
            // Neue User ohne Commit-Historie → Drop-Entdecker, nicht fiktives 100%
            return ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0)
        }
        let shows = Int(Double(s) / 100.0 * Double(total))
        return ReliabilityScore(totalCommits: total, showUps: shows, noShows: total - shows)
    }

    /// Gehgeschwindigkeit ~5 km/h = 83 m/min
    private var etaMinutes: Int? {
        guard let dist = participant.simulatedDistance else { return nil }
        return max(1, Int(dist / 83.0))
    }

    private var etaClockString: String? {
        guard let mins = etaMinutes,
              let arrival = Calendar.current.date(byAdding: .minute, value: mins, to: Date())
        else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: arrival)
    }

    private var distanceLabel: String? {
        guard let dist = participant.simulatedDistance else { return nil }
        return dist < 1000
            ? "~\(Int(dist)) m"
            : String(format: "~%.1f km", dist / 1000)
    }

    private var nameLabel: String {
        if let age = participant.age { return "\(participant.name), \(age)" }
        return participant.name
    }

    // MARK: Body

    var body: some View {
        Button {
            if !isArrived && participant.liveCoordinate != nil {
                showLiveLocation = true
            } else {
                showProfile = true
            }
        } label: {
            if isArrived {
                // ── Vor Ort: volle Darstellung ────────────────────────
                HStack(spacing: 13) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let img = participant.selfie {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 50, height: 50).clipShape(Circle())
                            } else {
                                RemoteProfileImage(
                                    url: participant.profileImageURL,
                                    fallbackEmoji: participant.emoji,
                                    size: 50,
                                    strokeColor: Color.onlineGreen.opacity(0.55)
                                )
                            }
                        }
                        .overlay(Circle().stroke(Color.onlineGreen.opacity(0.55), lineWidth: 2))

                        Circle().fill(Color.onlineGreen).frame(width: 17, height: 17)
                            .overlay(Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                            .offset(x: 2, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(nameLabel)
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(rowText).lineLimit(1)
                            if participant.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11)).foregroundColor(Color(hex: "3b82f6"))
                            }
                        }
                        HStack(spacing: 7) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(rowSub.opacity(0.3))
                                    RoundedRectangle(cornerRadius: 3).fill(score.color)
                                        .frame(width: geo.size.width * CGFloat(participant.reliabilityScore) / 100)
                                }
                            }
                            .frame(width: 52, height: 4)
                            Text(score.displayText)
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(score.color)
                            Image(systemName: score.badgeIcon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(score.color)
                            Text(score.badge).font(.system(size: 10)).foregroundColor(rowSub)
                        }
                    }

                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Circle().fill(Color.onlineGreen).frame(width: 5, height: 5)
                        Text(tr("drop.arrived")).font(.system(size: 11, weight: .semibold)).foregroundColor(.onlineGreen)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(rowBg))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.onlineGreen.opacity(0.30), lineWidth: 1))

            } else {
                // ── Unterwegs: kompakte einzeilige Darstellung ────────
                HStack(spacing: 10) {
                    // Kleiner Avatar
                    Group {
                        if let img = participant.selfie {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 36, height: 36).clipShape(Circle())
                        } else if participant.profileImageURL != nil {
                            RemoteProfileImage(
                                url: participant.profileImageURL,
                                fallbackEmoji: participant.emoji,
                                size: 36,
                                strokeColor: Color.clear
                            )
                        } else {
                            ZStack {
                                Circle().fill(avatarBg)
                                Text(participant.emoji).font(.system(size: 16))
                            }
                        }
                    }
                    .frame(width: 36, height: 36).clipShape(Circle())
                    .overlay(Circle().stroke(avatarStroke, lineWidth: 1))
                    .opacity(0.8)

                    // Name
                    Text(nameLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(rowText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Distanz + ETA kompakt
                    HStack(spacing: 6) {
                        if let dist = distanceLabel {
                            HStack(spacing: 3) {
                                Image(systemName: "figure.walk").font(.system(size: 9, weight: .medium))
                                Text(dist).font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(rowSub)
                        }
                        if let mins = etaMinutes {
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.system(size: 9))
                                Text("~\(mins) Min").font(.system(size: 11))
                            }
                            .foregroundColor(rowSub)
                        } else if distanceLabel == nil {
                            Text(tr("drop.on_the_way")).font(.system(size: 11)).foregroundColor(rowSub)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(rowSub.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(rowBg))
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            let agePart = participant.age.map { ", \($0)" } ?? ""
            let subtitle = participant.statusMessage.isEmpty
                ? "Drops-Nutzer\(agePart)"
                : "\(participant.statusMessage)\(agePart)"
            MiniProfileSheet(
                name: participant.name,
                emoji: participant.emoji,
                selfie: participant.selfie,
                profileImageURL: participant.profileImageURL,
                reliabilityScore: participant.reliabilityScore,
                totalCommits: participant.reliabilityCommits,
                subtitle: subtitle,
                accentColor: score.color,
                isVerified: participant.isVerified,
                userUID: participant.firebaseUID,
                canBlock: true,
                onBlock: {}
            )
            .environmentObject(store)
            .presentationDetents([.medium])
        }
        // Live-Standort-Sheet für Unterwegs-Personen
        .sheet(isPresented: $showLiveLocation) {
            ParticipantLiveLocationSheet(
                participant: participant,
                dropCoordinate: dropCoordinate
            )
            .presentationDetents([.height(480)])
            .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - Participant Live Location Sheet

struct ParticipantLiveLocationSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    let participant: DropParticipant
    let dropCoordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss

    @State private var route: MKRoute? = nil
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    private var liveCoord: CLLocationCoordinate2D {
        participant.liveCoordinate ?? dropCoordinate
    }

    private var etaMinutes: Int? {
        guard let dist = participant.simulatedDistance else { return nil }
        return max(1, Int(dist / 83.0))
    }

    private var etaClockString: String? {
        guard let mins = etaMinutes,
              let arrival = Calendar.current.date(byAdding: .minute, value: mins, to: Date())
        else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: arrival)
    }

    private var distanceLabel: String? {
        guard let dist = participant.simulatedDistance else { return nil }
        return dist < 1000 ? "~\(Int(dist)) m" : String(format: "~%.1f km", dist / 1000)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Handle ────────────────────────────────────────────────
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)

            // ── Header ────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 46, height: 46)
                    Text(participant.emoji).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(participant.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if let age = participant.age {
                            Text("\(age)")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    Label(tr("drop.heading_to_drop"), systemImage: "figure.walk")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.brand)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(UIColor.systemGray3))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)

            // ── Karte ─────────────────────────────────────────────────
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(fitRegion(from: liveCoord, to: dropCoordinate))) {
                    ForEach(mapAnnotations) { ann in
                        Annotation("", coordinate: ann.coordinate) {
                            if ann.isPersonPin {
                                // Joiner-Pin
                                ZStack {
                                    Circle()
                                        .fill(Color.brand.opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Circle()
                                        .stroke(Color.brand.opacity(0.6), lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                    Text(participant.emoji)
                                        .font(.system(size: 20))
                                }
                                .shadow(color: Color.brand.opacity(0.4), radius: 8)
                            } else {
                                // Drop-Pin
                                ZStack {
                                    Circle()
                                        .fill(Color.accentOrange.opacity(0.18))
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .stroke(Color.accentOrange.opacity(0.6), lineWidth: 2)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentOrange)
                                }
                            }
                        }
                    }
                }
                .frame(height: 240)
                .cornerRadius(20)
                .padding(.horizontal, 16)

                // Distanz-Overlay unten auf der Karte
                if let dist = distanceLabel {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 11))
                        Text(dist + " entfernt")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 10)
                }
            }
            .padding(.bottom, 14)

            // ── ETA-Karte ─────────────────────────────────────────────
            HStack(spacing: 0) {
                // ETA
                VStack(spacing: 4) {
                    if let mins = etaMinutes {
                        Text("~\(mins) Min")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Ankunft ca.")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text("–")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Uhrzeit
                VStack(spacing: 4) {
                    if let clock = etaClockString {
                        Text(clock + " Uhr")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Voraussichtlich")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text("–")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Score
                VStack(spacing: 4) {
                    Text("\(participant.reliabilityScore)%")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(scoreColor)
                    Text(tr("profile.reliability"))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)

            Spacer(minLength: 20)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch participant.reliabilityScore {
        case 90...100: return .onlineGreen
        case 70..<90:  return .accentOrange
        default:       return .accentRed
        }
    }

    private struct MapPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let isPersonPin: Bool
    }

    private var mapAnnotations: [MapPin] {
        [MapPin(coordinate: liveCoord, isPersonPin: true),
         MapPin(coordinate: dropCoordinate, isPersonPin: false)]
    }

    private func fitRegion(from: CLLocationCoordinate2D,
                           to: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let minLat = min(from.latitude,  to.latitude)
        let maxLat = max(from.latitude,  to.latitude)
        let minLon = min(from.longitude, to.longitude)
        let maxLon = max(from.longitude, to.longitude)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let spanLat = max(0.008, (maxLat - minLat) * 1.6)
        let spanLon = max(0.008, (maxLon - minLon) * 1.6)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: spanLat,
                                                         longitudeDelta: spanLon))
    }
}

// MARK: - Rounded Corners Helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Participant Avatars (überlappende Kreise)

struct ParticipantAvatars: View {
    let participants: [DropParticipant]
    private let maxVisible = 4
    private let size: CGFloat = 32
    private let border: CGFloat = 2

    private var visible: [DropParticipant] { Array(participants.prefix(maxVisible)) }
    private var extra: Int { max(0, participants.count - maxVisible) }

    var body: some View {
        HStack(spacing: -(size * 0.35)) {
            ForEach(Array(visible.enumerated()), id: \.offset) { i, p in
                avatarCircle(for: p)
                    .zIndex(Double(maxVisible - i))
            }
            if extra > 0 {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(Color.bgPrimary, lineWidth: border))
                    Text("+\(extra)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                .zIndex(0)
            }
        }
    }

    @ViewBuilder
    private func avatarCircle(for participant: DropParticipant) -> some View {
        ZStack {
            Circle()
                .fill(Color.bgPrimary)
                .frame(width: size + border * 2, height: size + border * 2)

            if let img = participant.selfie {
                // Echtes Selfie-Foto
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if participant.profileImageURL != nil {
                // Remote-Profilbild über RemoteProfileImage (mit Cache)
                RemoteProfileImage(
                    url: participant.profileImageURL,
                    fallbackEmoji: participant.emoji,
                    size: size,
                    strokeColor: Color.clear
                )
            } else {
                // Emoji-Fallback
                Circle()
                    .fill(Color.brand.opacity(0.1))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(participant.emoji)
                            .font(.system(size: size * 0.5))
                    )
            }
        }
    }
}

// MARK: - Mini Profile Sheet (Freunde & Fremde)

struct MiniProfileSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let name: String
    let emoji: String
    var selfie: UIImage? = nil
    var profileImageURL: String? = nil
    var reliabilityScore: Int = 85
    var totalCommits: Int = 0
    var subtitle: String = "Drops-Nutzer"
    var accentColor: Color = Color(hex: "06b6d4")
    var isVerified: Bool = false
    var isPlus: Bool = false
    /// Wenn gesetzt, wird der Drops+ Status live aus Firebase nachgezogen — dadurch
    /// zeigt das Sheet auch bei Freunden / Teilnehmern korrekt das Plus-Badge.
    var userUID: String? = nil
    /// Optionales Alter — wird im Subtitle angezeigt. Wenn nil, wird's via userUID aus
    /// `users/{uid}/birthdate` nachgezogen.
    var userAge: Int? = nil
    var canBlock: Bool = true
    /// True wenn dieser User in deiner Freundesliste ist → zeigt
    /// "Freund entfernen"-Button statt Block/Melden.
    var isFriend: Bool = false
    let onBlock: () -> Void

    @State private var showBlockAlert = false
    @State private var showReportSheet = false
    @State private var showRemoveFriendAlert = false
    @State private var fetchedPlus: Bool = false
    /// Aus Firebase nachgezogen — für Beta-Badge-Cutoff und Alter im Subtitle.
    @State private var fetchedCreatedAt: Date? = nil
    @State private var fetchedAge: Int? = nil

    /// Beta-Badge-Cutoff: Nutzer ab 04.05.2026 (Europe/Berlin) bekommen kein Badge mehr.
    /// Frühere Nutzer (Early Adopter) behalten den Badge dauerhaft. Wenn createdAt
    /// nicht ermittelbar ist, wird der Badge zur Sicherheit NICHT gezeigt.
    private var qualifiesForBetaBadge: Bool {
        guard let created = fetchedCreatedAt else { return false }
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Europe/Berlin")
        let cutoff = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return created < cutoff
    }

    /// Effektives Alter — übergeben oder aus Firebase nachgezogen.
    private var displayAge: Int? { userAge ?? fetchedAge }

    // Tier aus Punktzahl direkt — unabhängig von Event-Historie.
    private var tierLabel: String { ReliabilityScore.badge(forPoints: reliabilityScore) }
    private var tierIcon:  String { ReliabilityScore.badgeIcon(forPoints: reliabilityScore) }
    private var tierColor: Color  { ReliabilityScore.color(forPoints: reliabilityScore) }
    private var tierProgress: Double { ReliabilityScore.tierProgress(forPoints: reliabilityScore) }

    /// Anzahl früherer bestätigter Begegnungen mit diesem Nutzer (aus lokalen Daten).
    private var priorEncountersCount: Int {
        store.encounters.filter { $0.friendName == name && $0.confirmed }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 22)

            // Avatar
            ZStack {
                if let img = selfie {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(accentColor.opacity(0.35), lineWidth: 2.5))
                } else if let urlStr = profileImageURL {
                    RemoteProfileImage(url: urlStr, fallbackEmoji: emoji, size: 84,
                                       strokeColor: accentColor.opacity(0.35))
                } else {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 84, height: 84)
                        .overlay(Text(emoji).font(.system(size: 42)))
                        .overlay(Circle().stroke(accentColor.opacity(0.25), lineWidth: 2))
                }
            }
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.brand)
                }
                // Beta-Badge nur für Early-Adopter (registriert vor 04.05.2026)
                if qualifiesForBetaBadge {
                    BetaBadge()
                }
                if isPlus || fetchedPlus {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        Text("PLUS").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(Color(hex: "7a4e05"))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [Color(hex: "d4a017"), Color(hex: "a87408")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                }
            }
            HStack(spacing: 6) {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                if let age = displayAge {
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                    Text("\(age)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.bottom, 20)

            // Zuverlässigkeits-Ring mit Tier-Icon + Badge-Name
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(tierColor.opacity(0.15), lineWidth: 5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(tierProgress))
                        .stroke(tierColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: reliabilityScore)
                    Image(systemName: tierIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tierColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tierLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("\(reliabilityScore) Pkt\(totalCommits > 0 ? " · \(totalCommits) Drops" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 20)

            // Frühere Begegnungen — nur wenn > 0
            if priorEncountersCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.accentOrange)
                    Text("Schon \(priorEncountersCount == 1 ? "1× getroffen" : "\(priorEncountersCount)× getroffen")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .liquidGlass(cornerRadius: 12)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Spacer()

            // Bei Freunden: "Freund entfernen" — bei Fremden: Melden + Blockieren.
            // Keine Aktionen auf sich selbst.
            if name != store.currentUser.name {
                if isFriend {
                    Button { showRemoveFriendAlert = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.minus")
                                .font(.system(size: 13))
                            Text("Freund entfernen")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentRed.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else if canBlock {
                    HStack(spacing: 10) {
                        Button { showReportSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "flag.fill").font(.system(size: 13))
                                Text("Melden").font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.accentOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentOrange.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button { showBlockAlert = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised.fill").font(.system(size: 13))
                                Text("Blockieren").font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentRed.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else {
                    Spacer(minLength: 20)
                }
            } else {
                Spacer(minLength: 20)
            }
        }
        .background(.ultraThinMaterial)
        .alert(tr("profile.confirm_block_title"), isPresented: $showBlockAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button("Blockieren", role: .destructive) {
                store.blockUser(name: name)
                dismiss()
                onBlock()
            }
        } message: {
            Text(tr("profile.block_message").replacingOccurrences(of: "{name}", with: name))
        }
        .alert("Freund entfernen?", isPresented: $showRemoveFriendAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button("Entfernen", role: .destructive) {
                if let uid = userUID, !uid.isEmpty {
                    store.removeFriend(theirUID: uid)
                }
                dismiss()
            }
        } message: {
            Text("\(name) wird aus deiner Freundesliste entfernt. Ihr seht eure Drops nicht mehr gegenseitig.")
        }
        .sheet(isPresented: $showReportSheet) {
            ReportUserSheet(reportedName: name, reportedUID: userUID) {
                showReportSheet = false
            }
        }
        .onAppear {
            // Plus-Status aus Firebase ziehen, falls nicht schon übergeben und UID vorhanden
            if !isPlus, let uid = userUID, !uid.isEmpty {
                RealtimeDBManager.shared.fetchPlusStatus(uid: uid) { plus in
                    fetchedPlus = plus
                }
            }
            // createdAt + birthdate für Beta-Badge & Alter laden
            if let uid = userUID, !uid.isEmpty {
                RealtimeDBManager.shared.fetchUserMeta(uid: uid) { created, birthdate in
                    fetchedCreatedAt = created
                    if let bd = birthdate, userAge == nil {
                        let comps = Calendar.current.dateComponents([.year], from: bd, to: Date())
                        if let years = comps.year, years > 0, years < 120 {
                            fetchedAge = years
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Munich Zone Overlay (Aurora-Grenze + Ausgrauung)

/// Weiche Aurora-Grenzlinie — vollständig jitter-frei.
///
/// Geometrie (pts) kommt von außen (LiveMapView via onMapCameraChange) und
/// wird synchron mit MapKit aktualisiert. Der Canvas berührt proxy.convert
/// NICHT mehr → keine Frame-Versätze möglich.
/// Farb-Loop: 20 s (langsam und ruhig).
struct MunichZoneOverlay: View {
    /// Vorkonvertierte Bildschirmpunkte — von LiveMapView bereitgestellt.
    let pts: [CGPoint]

    // HSB-Hue-Stützpunkte (geschlossen): cyan → grün → violet → pink → amber → cyan
    private static let hueStops: [Double] = [0.530, 0.370, 0.720, 0.920, 0.100, 0.530]

    /// Farbe für eine Bogenlängen-Position (0–1) + laufende Phase.
    private func hue(at arcPos: Double, phase: Double) -> Color {
        let t = (arcPos + phase).truncatingRemainder(dividingBy: 1.0)
        let stops = Self.hueStops
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Double(i)
        let h = stops[i] + (stops[i + 1] - stops[i]) * f
        return Color(hue: h, saturation: 0.78, brightness: 0.92)
    }

    /// Vorberechnete normalisierte Positionen (0..1) je Punkt um das Polygon
    /// — basiert auf dem **Punkt-Index**, nicht auf Screen-Distanz, damit
    /// wir das nicht pro Frame neu rechnen müssen. Der Farbverlauf wandert
    /// gleichmäßig entlang der Punkt-Reihenfolge — für 161-Punkte-Polygon
    /// mit halbwegs gleichmäßiger Punktdichte sieht das gleichwertig aus.
    private var normalizedPositions: [Double] {
        let n = pts.count
        guard n > 1 else { return [] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    var body: some View {
        // 12 fps für Farbwechsel — 20s-Loop, sehr langsam, halbierte CPU-Last
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 20.0) / 20.0

            Canvas { ctx, size in
                guard pts.count > 3 else { return }

                // ── Zone-Path bauen (wird 2× gebraucht) ─────────────────
                var zonePath = Path()
                zonePath.move(to: pts[0])
                for pt in pts.dropFirst() { zonePath.addLine(to: pt) }
                zonePath.closeSubpath()

                // ── Ausgrauung außerhalb (Even-Odd-Loch) ──────────────
                var outerPath = Path()
                outerPath.addRect(CGRect(x: -600, y: -600,
                                        width: size.width + 1200,
                                        height: size.height + 1200))
                outerPath.addPath(zonePath)
                ctx.fill(outerPath,
                         with: .color(.primary.opacity(0.12)),
                         style: FillStyle(eoFill: true))

                // ── Index-basierte Farbpositionen (keine Arc-Length-
                //     Berechnung pro Frame mehr!) ────────────────────
                let n = pts.count
                let positions = normalizedPositions

                // ── Breiter Glow-Layer ──────────────────────────────
                // Jeder Segment bekommt eine Mischfarbe aus Start und Ende —
                // sieht flüssiger aus als harte Segment-Grenzen.
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 8))
                    for i in 0..<(n - 1) {
                        let col = hue(at: positions[i], phase: phase)
                        var seg = Path()
                        seg.move(to: pts[i])
                        seg.addLine(to: pts[i + 1])
                        layer.stroke(seg,
                                     with: .color(col.opacity(0.48)),
                                     style: StrokeStyle(lineWidth: 10,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                    }
                }

                // ── Feine Mittellinie ──────────────────────────────
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.0))
                    for i in 0..<(n - 1) {
                        let col = hue(at: positions[i], phase: phase)
                        var seg = Path()
                        seg.move(to: pts[i])
                        seg.addLine(to: pts[i + 1])
                        layer.stroke(seg,
                                     with: .color(col.opacity(0.42)),
                                     style: StrokeStyle(lineWidth: 1.5,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Multi-Zone Overlay (alle 5 Launch-Städte gleichzeitig)

/// Zeichnet mehrere Service-Zones (Polygone) mit Aurora-Borders und
/// einer gemeinsamen Ausgrauung außerhalb aller Zonen. Even-Odd-Fill mit
/// N+1 Subpaths (Außen-Rechteck + N Polygone) erzeugt N Löcher im Grau.
struct MultiZoneOverlay: View {
    let polygons: [[CGPoint]]

    private static let hueStops: [Double] = [0.530, 0.370, 0.720, 0.920, 0.100, 0.530]

    private func hue(at arcPos: Double, phase: Double) -> Color {
        let t = (arcPos + phase).truncatingRemainder(dividingBy: 1.0)
        let stops = Self.hueStops
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Double(i)
        let h = stops[i] + (stops[i + 1] - stops[i]) * f
        return Color(hue: h, saturation: 0.78, brightness: 0.92)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 20.0) / 20.0

            Canvas { ctx, size in
                guard !polygons.isEmpty else { return }

                // ── Ausgrauung: Außen-Rechteck + jede Zone als Loch (even-odd) ──
                var outerPath = Path()
                outerPath.addRect(CGRect(x: -600, y: -600,
                                        width: size.width + 1200,
                                        height: size.height + 1200))
                for pts in polygons where pts.count > 2 {
                    var zone = Path()
                    zone.move(to: pts[0])
                    for pt in pts.dropFirst() { zone.addLine(to: pt) }
                    zone.closeSubpath()
                    outerPath.addPath(zone)
                }
                ctx.fill(outerPath,
                         with: .color(.primary.opacity(0.12)),
                         style: FillStyle(eoFill: true))

                // ── Aurora-Border pro Zone ───────────────────────────
                for pts in polygons where pts.count > 2 {
                    let n = pts.count
                    // Index-basierte Farbpositionen (performant)
                    let positions = (0..<n).map { Double($0) / Double(n - 1) }

                    // Breiter Glow
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        for i in 0..<(n - 1) {
                            let col = hue(at: positions[i], phase: phase)
                            var seg = Path()
                            seg.move(to: pts[i])
                            seg.addLine(to: pts[i + 1])
                            layer.stroke(seg,
                                         with: .color(col.opacity(0.48)),
                                         style: StrokeStyle(lineWidth: 10,
                                                            lineCap: .round,
                                                            lineJoin: .round))
                        }
                    }

                    // Feine Mittellinie
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 1.0))
                        for i in 0..<(n - 1) {
                            let col = hue(at: positions[i], phase: phase)
                            var seg = Path()
                            seg.move(to: pts[i])
                            seg.addLine(to: pts[i + 1])
                            layer.stroke(seg,
                                         with: .color(col.opacity(0.42)),
                                         style: StrokeStyle(lineWidth: 1.5,
                                                            lineCap: .round,
                                                            lineJoin: .round))
                        }
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Pulsierender Live-Dot (Unterwegs-Anzeige)

struct PulsingLiveDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "3b82f6").opacity(0.25))
                .frame(width: 12, height: 12)
                .scaleEffect(pulsing ? 1.8 : 1.0)
                .opacity(pulsing ? 0 : 0.6)
            Circle()
                .fill(Color(hex: "3b82f6"))
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - UIKit ShareSheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Drag-Damping Helper

/// Liquid-Glass-Style Drag-Damping: Drag nach unten passiert weich,
/// nach Schwellwert wird's elastisch gebremst (rubber-band). Drag nach oben
/// (negativer Wert) wird stark gedämpft → fühlt sich „klebrig" an wie bei
/// Apple's Tab-Bar-Pull.
fileprivate func dampedDragOffset(_ raw: CGFloat) -> CGFloat {
    if raw <= 0 {
        // Drag nach oben → starke Resistance
        return raw * 0.25
    }
    let threshold: CGFloat = 80
    if raw <= threshold { return raw }
    // Über Schwellwert: zunehmender Widerstand (rubber-band)
    let extra = raw - threshold
    return threshold + extra * (1 / (1 + extra / 220))
}

// MARK: - Map Boost Card
//
// Schwebt überm Recenter-Button wenn Boost-Phase aktiv ist (<5 Drops in
// Reichweite). Drag-Handle oben, Bolt-Icon mit Gradient links, Text rechts.
// Bei Drag → folgt rubber-band-mäßig dem Finger; bei Loslassen >60pt tropft
// die Karte zur kleinen Pille links neben dem Recenter-Button (matchedGeometryEffect).
struct MapBoostCard: View {
    var onCollapse: (() -> Void)? = nil

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            // Drag-Handle + Collapse-Chevron
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.textPrimary.opacity(0.20))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                if onCollapse != nil {
                    Button {
                        onCollapse?()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary.opacity(0.45))
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Einklappen")
                }
            }
            .padding(.top, -2)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentOrange, Color.brand],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(
                            color: Color.accentOrange.opacity(pulse ? 0.55 : 0.25),
                            radius: pulse ? 14 : 6
                        )
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Boost-Phase aktiv")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("+15 Punkte für jeden Drop, den du jetzt erstellst oder triffst.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.textPrimary.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .liquidGlass(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Extend Drop Sheet

private struct ExtendDropSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let dropID: UUID
    let onExtended: (Int) -> Void  // übergibt die gewählten Minuten

    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("Drop verlängern")
                .font(.system(size: 17, weight: .semibold))

            Text("Um wie viel Zeit soll der Drop verlängert werden?")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            let options: [(String, Int)] = [
                ("+30 Min", 30), ("+1 Std", 60), ("+2 Std", 120), ("+4 Std", 240)
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(options, id: \.1) { label, minutes in
                    Button {
                        store.extendDrop(id: dropID, byMinutes: minutes)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onExtended(minutes)
                        dismiss()
                    } label: {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.brand.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Button("Abbrechen") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Report User Sheet
// Ermöglicht Nutzern, andere Profile wegen Verstoßes zu melden.
// Schreibt einen Eintrag unter `reports/{autoID}` → wird im Admin-Panel geprüft.
// Pflicht für App Review (Guideline 1.2 — UGC-Apps).

struct ReportUserSheet: View {
    let reportedName: String
    let reportedUID: String?
    let onDismiss: () -> Void

    init(reportedName: String, reportedUID: String? = nil, onDismiss: @escaping () -> Void) {
        self.reportedName = reportedName
        self.reportedUID = reportedUID
        self.onDismiss = onDismiss
    }

    @State private var selectedReason: String = ""
    @State private var details: String = ""
    @State private var submitted: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let reasons: [String] = [
        "Belästigung / Bedrohung",
        "Fake-Profil / Identitätsklau",
        "Spam / Werbung",
        "Anstößige Inhalte",
        "Minderjährig",
        "Sonstiges"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.accentOrange)
                        Text(reportedName).font(.system(size: 15, weight: .semibold))
                    }
                } header: {
                    Text("Gemeldeter Nutzer")
                }

                if submitted {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.brand)
                            Text("Meldung erhalten — wir prüfen sie innerhalb von 24 Stunden.")
                                .font(.system(size: 14))
                        }
                    }
                } else {
                    Section {
                        ForEach(reasons, id: \.self) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack {
                                    Text(reason).foregroundColor(.textPrimary)
                                    Spacer()
                                    if selectedReason == reason {
                                        Image(systemName: "checkmark").foregroundColor(.brand)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Grund")
                    }

                    Section {
                        TextField("Optional: weitere Infos", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("Details (optional)")
                    }
                }
            }
            .navigationTitle("Nutzer melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss(); onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitted {
                        Button("Fertig") { dismiss(); onDismiss() }
                            .fontWeight(.semibold)
                    } else {
                        Button("Senden") {
                            RealtimeDBManager.shared.submitReport(
                                reportedUID: reportedUID,
                                reportedName: reportedName,
                                reason: selectedReason,
                                details: details
                            )
                            withAnimation { submitted = true }
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedReason.isEmpty)
                    }
                }
            }
        }
    }
}
