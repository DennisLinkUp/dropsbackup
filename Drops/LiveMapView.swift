import SwiftUI
import MapKit
import FirebaseAuth

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
        // startUpdatingLocation() NUR wenn Berechtigung bereits erteilt.
        // iOS 17+ zeigt den Location-Dialog auch ohne explizites
        // requestWhenInUseAuthorization() sobald startUpdatingLocation()
        // bei Status .notDetermined aufgerufen wird — das würde den
        // Permission-Dialog vor dem WelcomeSheet auslösen.
        // locationManagerDidChangeAuthorization startet es automatisch
        // sobald der User in requestAllPermissions() (nach WelcomeSheet)
        // die Berechtigung erteilt hat.
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
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
    /// Drop für den der Quick-Reply-Sheet (Anfrage senden mit optionaler
    /// Schnellantwort) aktuell offen ist. Wird gesetzt wenn User auf
    /// dem Map-Pin-Detail-Sheet „Ich komme vorbei" tippt — geschickt
    /// wird erst nach Quick-Chip-Auswahl + „Senden"-Tap im Sheet.
    @State private var joinComposeItem: MapAnnotationItem? = nil
    @State private var joinedIDs: Set<UUID> = []
    @State private var showSafety = false
    @State private var mapId = UUID()
    /// Angetippte Community auf der Karte — öffnet CommunityJoinSheet.
    @State private var selectedCommunity: Community? = nil

    // MARK: - Clustering
    /// Fertige Cluster-Gruppen — werden bei Kamera-Bewegungsende neu berechnet.
    /// Jede Gruppe enthält ≥1 MapAnnotationItem. Gruppen mit 1 Item = normaler Pin.
    @State private var clusterGroups: [[MapAnnotationItem]] = []
    /// Pixel-Radius innerhalb dem zwei Pins zu einem Cluster zusammengefasst werden.
    private let clusterThreshold: CGFloat = 48

    /// Bündelt `filteredAnnotations` nach Bildschirm-Nähe.
    /// Eigene Drops (type == .myDrop) werden NIE geclustert — sie erscheinen immer einzeln.
    /// Algorithmus: greedy O(n²), reicht für ~100 Pins problemlos.
    func computeClusters(proxy: MapProxy) {
        let items = filteredAnnotations
        var groups:   [[MapAnnotationItem]] = []
        var clustered = Set<UUID>()

        for item in items {
            guard !clustered.contains(item.id) else { continue }
            // Eigene Drops: immer solo
            if item.type == .myDrop {
                groups.append([item])
                clustered.insert(item.id)
                continue
            }
            guard let pt = proxy.convert(item.coordinate, to: .local) else {
                groups.append([item])
                clustered.insert(item.id)
                continue
            }
            var group = [item]
            clustered.insert(item.id)
            for other in items where !clustered.contains(other.id) && other.type != .myDrop {
                guard let otherPt = proxy.convert(other.coordinate, to: .local) else { continue }
                if hypot(pt.x - otherPt.x, pt.y - otherPt.y) < clusterThreshold {
                    group.append(other)
                    clustered.insert(other.id)
                }
            }
            groups.append(group)
        }
        clusterGroups = groups
    }

    /// Geografischer Mittelpunkt einer Gruppe.
    private func centroid(of group: [MapAnnotationItem]) -> CLLocationCoordinate2D {
        let n = Double(group.count)
        let lat = group.map { $0.coordinate.latitude  }.reduce(0, +) / n
        let lon = group.map { $0.coordinate.longitude }.reduce(0, +) / n
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Zoomt die Kamera so, dass alle Pins im Cluster sichtbar sind.
    private func zoomToCluster(_ group: [MapAnnotationItem]) {
        let coords = group.map { $0.coordinate }
        guard let minLat = coords.map({ $0.latitude  }).min(),
              let maxLat = coords.map({ $0.latitude  }).max(),
              let minLon = coords.map({ $0.longitude }).min(),
              let maxLon = coords.map({ $0.longitude }).max() else { return }
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.003, (maxLat - minLat) * 3.0),
            longitudeDelta: max(0.003, (maxLon - minLon) * 3.0)
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// Eigener 8-Char BLE-Token — wird explizit an DropMapPin übergeben (nicht per @EnvironmentObject,
    /// da Map-Annotation-Content nicht zuverlässig den SwiftUI-Environment erbt).
    var myPinToken: String {
        // Konsistent mit dem AppStore.myBLEToken (firebaseUID-prefix).
        // Vorher nutzte das die lokale UUID — das hat NICHT mit den
        // BLE-confirmedTokens gematched, weil die Joiner ihren BLE-Token
        // aus firebaseUID ableiten. UI-Filter wie "p.token == myToken"
        // sahen dann nie eine Übereinstimmung → Joiner blieb auf
        // "Unterwegs" obwohl BLE bestätigt hatte.
        store.myBLEToken
    }

    var filteredAnnotations: [MapAnnotationItem] {
        // Volle Stranger-Drops von der Karte entfernen — sie sollen nicht
        // mehr beitretbar erscheinen. Im Umgebungstab bleiben sie aber
        // sichtbar (dort als „Voll" markiert), damit User sehen dass es
        // den Drop gibt. Eigene Drops und der gerade gejointe Drop bleiben
        // immer auf der Karte (sonst verschwindet er einem unter den
        // Füßen während man hinläuft).
        let joinedDropID = store.activeJoinedDropID?.uuidString
        let base = store.allMapAnnotations.filter { ann in
            guard ann.type == .stranger else { return true }
            if ann.id.uuidString == joinedDropID { return true }
            return !ann.isFull
        }
        // Der „Nur weiblich"-Filter läuft jetzt im Umgebungs-Tab, nicht mehr hier.
        guard !store.activityCategoryFilter.isEmpty else { return base }
        return base.filter {
            ActivityCategory.matches(filter: store.activityCategoryFilter,
                                     emoji: $0.emoji, activity: $0.activity)
        }
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

                    // Drops & Freunde — geclustert wenn Pins sich überlappen.
                    // clusterGroups wird bei Kamera-Stillstand neu berechnet.
                    // Gruppen mit 1 Item → normaler Pin; ≥2 → ClusterPin.
                    // HINWEIS: @EnvironmentObject ist in Map-Annotation-Content nicht
                    // zuverlässig (MapKit eigener View-Context). Wir übergeben alles explizit.
                    ForEach(clusterGroups, id: \.first?.id) { group in
                        if group.count == 1 {
                            let item = group[0]
                            Annotation("", coordinate: item.coordinate, anchor: .center) {
                                DropMapPin(
                                    item: item,
                                    isJoined: joinedIDs.contains(item.id)
                                        || store.hasJoinedDrop(dropID: item.id)
                                        || store.activeJoinedDropID == item.id,
                                    onTap: { selectedItem = item },
                                    myToken: myPinToken,
                                    confirmedTokens: store.bluetoothMeetup.confirmedTokens
                                )
                            }
                        } else {
                            Annotation("", coordinate: centroid(of: group), anchor: .center) {
                                DropClusterPin(group: group) {
                                    zoomToCluster(group)
                                }
                            }
                        }
                    }

                    // ── Community-Pins ────────────────────────────────────
                    // Genehmigte Sport-Communities fix auf der Karte.
                    // (Deaktiviert via FeatureFlags.communitiesEnabled)
                    if FeatureFlags.communitiesEnabled {
                        ForEach(store.nearbyCommunities) { community in
                            Annotation("", coordinate: community.coordinate, anchor: .bottom) {
                                CommunityMapPin(community: community) {
                                    selectedCommunity = community
                                }
                            }
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
                .onMapCameraChange(frequency: .onEnd) { _ in
                    // Cluster neu berechnen sobald Kamera zum Stillstand kommt.
                    // .onEnd statt .continuous: spart CPU — nur 1x nach Zoom/Pan.
                    computeClusters(proxy: proxy)
                }
                .onChange(of: filteredAnnotations.count) { _, _ in
                    // Neue Drops oder Filter-Änderung → sofort neu clustern.
                    computeClusters(proxy: proxy)
                }
                .onChange(of: store.activityCategoryFilter) { _, _ in
                    computeClusters(proxy: proxy)
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
                // Initialcluster nach kurzem Delay — MapProxy braucht
                // einen Render-Pass bevor convert() korrekte Werte liefert.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    // proxy ist hier nicht verfügbar — wird über .onMapCameraChange
                    // beim ersten Kamera-Stop gesetzt. Fallback: alle als solo.
                    if clusterGroups.isEmpty {
                        clusterGroups = filteredAnnotations.map { [$0] }
                    }
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
                // ── Activity-Indikator (links oben) ──────────────────────
                // Zeigt wie viele Drops in der gefilterten Sicht sichtbar
                // sind. Hilft dem User einzuschätzen ob's gerade „los ist"
                // ohne erst die Karte abzuscannen. Erscheint nur wenn ≥1
                // Drop sichtbar ist — bei Null würde die Empty-Map sich
                // selbst erklären.
                HStack {
                    let count = filteredAnnotations.filter {
                        $0.type == .stranger || $0.type == .friend || $0.type == .myDrop
                    }.count
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.onlineGreen)
                                .frame(width: 6, height: 6)
                            Text((count == 1 ? tr("map.drops_nearby_singular") : tr("map.drops_nearby_plural")).replacingOccurrences(of: "{count}", with: "\(count)"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .padding(.leading, 16)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                // ── Kategorie-Filter-Chips ────────────────────────────────
                ActivityFilterChipsView()
                    .padding(.top, 4)

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
                            .padding(.top, 4)
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
                            // Schmaler Single-Line-Pill — selbe Höhe wie der
                            // Recenter-Button daneben (16pt Icon + 13pt
                            // Padding = 42pt). Vorher: zwei-zeilige Wide-Pill
                            // mit 32pt-Bolt-Kreis, wirkte deutlich gewichtiger
                            // als der schlanke Glass-Circle daneben.
                            HStack(spacing: 7) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(store.isPowerHourActive
                                     ? tr("map.power_hour_pts").replacingOccurrences(of: "{pts}", with: "\(store.currentBoostBonus)")
                                     : tr("map.boost_active_pts").replacingOccurrences(of: "{pts}", with: "\(store.currentBoostBonus)"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        .accessibilityLabel(tr("map.boost_active_create"))
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
            // Joiner-Pin: das ist KEIN Drop, sondern eine Person die zu
            // unserem Drop unterwegs ist. DropJoinSheet würde fälschlich
            // "Ich komme vorbei" anzeigen — wir routen stattdessen auf
            // eine kompakte Info-Ansicht ohne CTA.
            if item.type == .joiner {
                JoinerLiveInfoSheet(item: item)
                    .environmentObject(store)
                    .presentationDetents([.fraction(0.4)])
                    .presentationDragIndicator(.visible)
                    .sheetBackground()
            } else {
                // isJoined deckt drei Quellen ab:
                //  - lokal: gerade eben angetappt (joinedIDs)
                //  - Pending/Accepted Request im Store
                //  - bereits aktiv gejoinder Drop (activeJoinedDropID)
                // Sonst wäre der Button "Ich komme vorbei" auch dann aktiv,
                // wenn der User den Drop schon gejoinder hat und nochmal tappt.
                DropJoinSheet(
                    item: item,
                    isJoined: joinedIDs.contains(item.id)
                        || store.hasJoinedDrop(dropID: item.id)
                        || store.activeJoinedDropID == item.id
                ) {
                    // Detail-Sheet schließen + Quick-Reply-Sheet öffnen.
                    // User wählt einen Schnellantwort-Chip und tippt
                    // „Senden" — erst dann geht die Anfrage raus.
                    // Konsistent zum FeedView-Pfad (FeedDropCard).
                    let toCompose = item
                    selectedItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        joinComposeItem = toCompose
                    }
                }
                .environmentObject(store)
                // Adaptives Sizing je nach Content-Dichte:
                //   fuzzy + keine Extras       → 0.42 (minimal: nur Header + Disclaimer + Button)
                //   myDrop / normaler Drop      → 0.48 (kompakt: Info + Button)
                //   mit Teilnehmern ODER Text   → 0.55 (mehr Platz für Participant-Row)
                // Zweiter Detent = hochziehbar für mehr Details.
                .presentationDetents({
                    let hasExtras = !item.participants.isEmpty
                        || (item.dropDescription.map { !$0.isEmpty } ?? false)
                    if item.isFuzzy && !hasExtras {
                        return [PresentationDetent.fraction(0.42), .fraction(0.60)]
                    } else if hasExtras {
                        return [.fraction(0.55), .fraction(0.72)]
                    } else {
                        return [.fraction(0.48), .fraction(0.65)]
                    }
                }())
                .presentationDragIndicator(.visible)
                .sheetBackground()
            }
        }
        // ── Quick-Reply-Sheet (Map-Pfad) ────────────────────────────────
        // Wird vom DropJoinSheet ausgelöst — User wählt einen Schnell-
        // antwort-Chip und sendet damit die Beitrittsanfrage. Identisch
        // zum FeedView-Pfad damit beide Wege gleichen UX bieten.
        .sheet(item: $joinComposeItem) { item in
            JoinConfirmSheet(item: item) {
                joinedIDs.insert(item.id)
            }
            .environmentObject(store)
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.hidden)
            .sheetBackground()
        }
        // Community Join Sheet — wird bei Tap auf einen Community-Map-Pin gezeigt.
        .sheet(item: $selectedCommunity) { community in
            CommunityJoinSheet(community: community)
                .environmentObject(store)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        // Hinweis: das `IncomingJoinRequestSheet` (Host-seitig) ist
        // auf MainTabView-Ebene angehängt, damit es egal in welchem
        // Tab der Host gerade ist auftaucht. Wäre es nur hier, würde
        // bei Host im Profil/Umgebung gar kein Pop-up kommen — nur
        // die Push-Notification.
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
            // hasSeenWelcome guard: PowerHourIntroSheet nicht zeigen während
            // WelcomeSheet noch offen ist — Presentation-Konflikt würde
            // WelcomeSheet vorzeitig dismissen und requestAllPermissions()
            // vor dem Walkthrough triggern.
            if !hasSeenPowerHourIntro,
               UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
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
    @State private var freshPulse = false
    /// Langsamer Atemeffekt auf dem Fog-Ring des Fuzzy-Pins.
    @State private var fogPulse = false

    /// Drop ist „frisch" wenn er weniger als 5 Min alt ist — bekommt
    /// einen pulsierenden Ring als „neu hier"-Signal. Greift nicht bei
    /// Boost-Drops (deren Gold-Ring hat Priorität).
    private var isFresh: Bool {
        Date().timeIntervalSince(item.createdAt) < 300
    }

    /// Nur bestätigte Teilnehmer anzeigen (BLE-confirmed oder eigener Token als Host).
    var confirmedParticipants: [DropParticipant] {
        item.participants.filter { p in
            p.token == myToken || confirmedTokens.contains(p.token)
        }
    }

    var pinColor: Color {
        // Community-Drops überschreiben die normale Farbe — sie erscheinen
        // immer in Clero-Grün, egal welcher type (myDrop/stranger).
        if item.isCommunityDrop { return .cleroGreen }
        switch item.type {
        case .friend:   return isJoined ? .onlineGreen : .brand
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger:
            return item.creatorAgeGroup?.color ?? Color.auroraCyan
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
                // ── Fuzzy-Pin: Aktivität sichtbar, Standort bewusst ungenau ──
                // Konzept: User soll neugierig werden (emoji + activity) aber
                // klar sehen: "Ort noch unbekannt — erst joinen".
                // WICHTIG: kein .glassEffect() / liquidGlassCapsule() hier —
                // iOS-26-Glas ist rein transparent und sieht auf der Karte grau aus.
                // Stattdessen: thinMaterial + pinColor-Tint → Farbe bleibt sichtbar.
                ZStack(alignment: .center) {

                    // Pulsierender Fog-Halo — groß genug um auf der Karte aufzufallen
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [pinColor.opacity(fogPulse ? 0.22 : 0.12),
                                         pinColor.opacity(0.0)],
                                center: .center,
                                startRadius: 8,
                                endRadius: 44
                            )
                        )
                        .frame(width: 88, height: 88)
                        .scaleEffect(fogPulse ? 1.06 : 1.0)

                    // Gestrichelter Rand — "ungefähre Zone"
                    Circle()
                        .stroke(
                            pinColor.opacity(fogPulse ? 0.60 : 0.35),
                            style: StrokeStyle(lineWidth: 1.8, dash: [6, 4])
                        )
                        .frame(width: 72, height: 72)
                        .scaleEffect(fogPulse ? 1.06 : 1.0)

                    // Der eigentliche Pin — gefärbte Material-Kapsel
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(pinColor.opacity(0.25))
                                .frame(width: 28, height: 28)
                            Circle()
                                .stroke(pinColor.opacity(0.60), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            Text(item.emoji)
                                .font(.system(size: 15))

                            // Kleines Standort-Badge — "Ort unbekannt"
                            Image(systemName: "location.slash.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white)
                                .padding(2.5)
                                .background(pinColor, in: Circle())
                                .offset(x: 10, y: 10)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.activity)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(tr("map.nearby"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(pinColor)
                        }
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    // Tinted material: sieht auf Karte eingefärbt aus (kein reines Grau)
                    .background {
                        ZStack {
                            Capsule().fill(.thinMaterial)
                            Capsule().fill(pinColor.opacity(0.18))
                        }
                    }
                    .overlay(Capsule().stroke(pinColor.opacity(0.55), lineWidth: 1.2))
                    .shadow(color: pinColor.opacity(0.45), radius: 12, y: 2)
                    .shadow(color: pinColor.opacity(0.20), radius: 24, y: 0)
                }
                .scaleEffect(pressed ? 1.06 : 1.0)
            } else {
                // Exakter Pin (normaler Nutzer oder verifizierter Nutzer)
                HStack(spacing: 6) {
                    ZStack {
                        // Frische-Pulse: Drop < 5 Min → pulsierender Ring
                        // außen rum. scaleEffect + opacity statt frame-
                        // Animation: am Loop-Snap ist opacity = 0, also
                        // kein sichtbarer Sprung zurück auf den Start-
                        // Zustand.
                        if isFresh {
                            Circle()
                                .stroke(pinColor.opacity(0.55), lineWidth: 1.8)
                                .frame(width: emojiCircleSize, height: emojiCircleSize)
                                .scaleEffect(freshPulse ? 1.7 : 0.9)
                                .opacity(freshPulse ? 0.0 : 0.8)
                        }

                        Circle()
                            .fill(pinColor.opacity(0.18))
                            .frame(width: emojiCircleSize, height: emojiCircleSize)
                        Circle()
                            .stroke(pinColor.opacity(0.5), lineWidth: 1.5)
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
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.type == .myDrop ? item.activity : (item.isStranger ? item.activity : item.name))
                            .font(.system(size: labelFontSize, weight: .semibold))
                            .foregroundColor(.textPrimary).lineLimit(1)
                        // Alter bei Stranger-Drops
                        if item.isStranger, let age = item.creatorAge {
                            Text(tr("map.years_abbrev").replacingOccurrences(of: "{age}", with: "\(age)"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(pinColor.opacity(0.85))
                        }
                    }
                    if item.type == .myDrop {
                        Text("· \(tr("map.you"))").font(.system(size: 10)).foregroundColor(.textSecondary)
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
        .onAppear {
            // Fresh-Pin-Pulse (< 5 Min alt)
            if isFresh {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    freshPulse = true
                }
            }
            // Fog-Ring-Atem (nur bei Fuzzy-Pins): langsamer Sinus-Loop
            // der den gestrichelten Ring leicht skaliert + blinkt.
            if item.isFuzzy {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    fogPulse = true
                }
            }
        }
    }
}

// MARK: - Drop Cluster Pin

/// Zeigt mehrere zusammengefasste Drops als einen Cluster-Pin.
/// Tap → zoomt rein bis alle Pins getrennt sichtbar sind.
struct DropClusterPin: View {
    let group:  [MapAnnotationItem]
    let onTap:  () -> Void

    /// Bis zu 3 Emojis aus der Gruppe für den visuellen Vorgeschmack.
    private var previewEmojis: [String] {
        Array(group.prefix(3).map { $0.emoji })
    }

    /// Alle Aktivitätsnamen — für AccessibilityLabel.
    private var activitiesLabel: String {
        group.prefix(5).map { $0.activity }.joined(separator: ", ")
    }

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Äußerer Glow-Ring
                Circle()
                    .fill(LinearGradient.aurora.opacity(0.25))
                    .frame(width: 58, height: 58)

                // Haupt-Kreis mit Aurora-Gradient
                Circle()
                    .fill(LinearGradient.aurora)
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.auroraOrange.opacity(0.45), radius: 8, x: 0, y: 3)

                // Weißer Innen-Rand
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 46, height: 46)

                VStack(spacing: 1) {
                    // Emoji-Stack (max 2 übereinander, sonst Zahl)
                    if previewEmojis.count <= 2 {
                        HStack(spacing: -4) {
                            ForEach(previewEmojis, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    // Anzahl
                    Text("\(group.count)")
                        .font(.system(size: previewEmojis.count <= 2 ? 11 : 17,
                                      weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel("\(group.count) Drops: \(activitiesLabel)")
        .accessibilityHint(tr("map.tap_to_zoom"))
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

            // ── Drag handle ───────────────────────────────────────
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // ── Header-Chip ───────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "person.fill.badge.plus")
                    .font(.system(size: 11, weight: .bold))
                Text(store.activeDrops.first?.activity.name ?? tr("map.join_request"))
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.5)
                    .textCase(.uppercase)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color.brand, Color.accentOrange],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: Color.brand.opacity(0.30), radius: 10, y: 3)
            )

            // Mehrere Anfragen in Queue
            let waitingCount = max(0, store.pendingJoinRequests.count - 1)
            if waitingCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text((waitingCount == 1 ? tr("map.more_requests_singular") : tr("map.more_requests_plural")).replacingOccurrences(of: "{count}", with: "\(waitingCount)"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.accentOrange)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentOrange.opacity(0.12), in: Capsule())
                .padding(.top, 8)
            }

            // ── Avatar + Name ─────────────────────────────────────
            let tierColor = ReliabilityScore.color(forPoints: request.joinerReliabilityPoints)
            VStack(spacing: 14) {
                // Avatar mit Tier-Ring
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [tierColor.opacity(0.7), tierColor.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 106, height: 106)

                    if let urlStr = request.joinerProfileImageURL, !urlStr.isEmpty {
                        RemoteProfileImage(url: urlStr, fallbackEmoji: request.joinerEmoji, size: 96)
                    } else {
                        ZStack {
                            Circle().fill(Color(.systemGray6)).frame(width: 96, height: 96)
                            Text(request.joinerEmoji).font(.system(size: 48))
                        }
                    }
                }
                .padding(.top, 20)

                // Name + Alter
                HStack(spacing: 6) {
                    Text(request.joinerName)
                        .font(.system(size: 24, weight: .bold))
                    if let age = request.joinerAge {
                        Text("\(age)")
                            .font(.system(size: 24, weight: .light))
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
                            LinearGradient(colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                    }
                }

                // Tier-Badge + Entfernung
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: ReliabilityScore.badgeIcon(forPoints: request.joinerReliabilityPoints))
                            .font(.system(size: 11, weight: .semibold))
                        Text(ReliabilityScore.badge(forPoints: request.joinerReliabilityPoints))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(tierColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tierColor.opacity(0.12), in: Capsule())

                    if let meters = joinerDistanceMeters {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.system(size: 10))
                            Text(formatDistance(meters))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.systemGray5), in: Capsule())
                    }
                }
            }

            // ── Nachricht ─────────────────────────────────────────
            if let msg = request.joinerMessage,
               !msg.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.brand)
                        .padding(.top, 1)
                    Text(msg)
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.brand.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }

            // ── Auto-Accept Timer ─────────────────────────────────
            if timeLeft > 0 {
                let total  = max(1, Double(Int(request.autoAcceptAt.timeIntervalSince1970
                    - request.autoAcceptAt.timeIntervalSinceNow + Double(timeLeft))))
                let progress = Double(timeLeft) / total

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 2.5)
                            .frame(width: 22, height: 22)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentOrange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: timeLeft)
                    }
                    Text(tr("map.auto_confirmed_in").replacingOccurrences(of: "{time}", with: "\(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 20)

            // ── Buttons ───────────────────────────────────────────
            HStack(spacing: 12) {
                Button {
                    store.declineJoinRequest(request)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(tr("map.reject"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.25), lineWidth: 1))
                }

                Button {
                    store.acceptJoinRequest(request)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(tr("map.confirm"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [Color.brand, Color.brand.opacity(0.80)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(color: Color.brand.opacity(0.30), radius: 8, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
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
    /// Wird bei Tap auf "Ich komme vorbei" gefeuert — Map-Pfad sendet
    /// die Anfrage ohne Nachricht; den Compose-Flow gibt's nur einmal,
    /// im FeedView-JoinConfirmSheet (DropJoinSheet ist primär Info-Sheet).
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
        if elapsed < 60 { return tr("map.active_since_mins").replacingOccurrences(of: "{mins}", with: "\(elapsed)") }
        let h = elapsed / 60
        let m = elapsed % 60
        return m > 0
            ? tr("map.active_since_hm").replacingOccurrences(of: "{h}", with: "\(h)").replacingOccurrences(of: "{m}", with: "\(m)")
            : tr("map.active_since_h").replacingOccurrences(of: "{h}", with: "\(h)")
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
        case .stranger: return item.creatorAgeGroup?.color ?? Color.auroraCyan
        default:        return .brand
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Share Button — System-DragIndicator übernimmt den Strich oben
            HStack {
                Spacer()
                DropShareButton(item: item)
                    .padding(.trailing, 16)
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
                    // ETA + Distanz — immer auf echtem Standort (effectiveCoordinate).
                    // Fuzzy-Drops: realCoordinate ist gesetzt → korrekte Walk-Time statt
                    // verfälschtem Wert durch den Karten-Versatz (800-1000m).
                    if item.type != .myDrop {
                        HStack(spacing: 10) {
                            Label(store.etaString(to: item.effectiveCoordinate) + " Weg",
                                  systemImage: "figure.walk")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(accentColor)
                            Label(store.distanceString(to: item.effectiveCoordinate),
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
                        // Single-Participant-Fall: Name + Alter inline,
                        // Verified-Check, Beta-Badge (nur wenn Self),
                        // dann Tier-Badge + "Ist bereits vor Ort" darunter.
                        if confirmedParticipants.count == 1, let p = confirmedParticipants.first {
                            HStack(spacing: 5) {
                                Text(nameWithAge(p))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                if isSelfParticipant(p) && store.qualifiesForBetaBadge {
                                    BetaBadge()
                                }
                            }
                            HStack(spacing: 5) {
                                Image(systemName: ReliabilityScore.badgeIcon(forPoints: p.reliabilityScore))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(ReliabilityScore.color(forPoints: p.reliabilityScore))
                                Text(ReliabilityScore.badge(forPoints: p.reliabilityScore))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(ReliabilityScore.color(forPoints: p.reliabilityScore))
                                Circle()
                                    .fill(Color.textTertiary)
                                    .frame(width: 2, height: 2)
                                Text(tr("map.already_on_site"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                        } else {
                            Text(participantNamesLabel(confirmedParticipants))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(tr("map.are_already_on_site"))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
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
                         ? tr("map.one_on_way")
                         : tr("map.x_on_way").replacingOccurrences(of: "{count}", with: "\(onTheWayCount)"))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.top, onTheWayCount > 0 && confirmedParticipants.isEmpty ? 12 : 4)
            }

            // Adresse / Fuzzy-Hinweis
            if item.isFuzzy {
                // Kein Reverse-Geocoding bei Fuzzy-Drops — die fuzzy Koordinate
                // liefert eine falsche Adresse, die echte würde den Host verraten.
                // Stattdessen: Hinweis dass der Drop näher ist als auf der Karte.
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor.opacity(0.75))
                    Text(tr("map.fuzzy_pos_info"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            } else if let address = resolvedAddress {
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
                            Text(trScheduledTime(time)).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
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
                        .background(Color.accentRed, in: RoundedRectangle(cornerRadius: Radius.lg))
                        .shadow(color: Color.accentRed.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
                .sheet(isPresented: $showCancelAlert) {
                    EndDropSheet(
                        activityEmoji: item.emoji,
                        activityName: item.activity,
                        participantCount: item.participants.count,
                        elapsedSeconds: Date().timeIntervalSince(item.createdAt)
                    ) {
                        store.cancelDrop(id: item.id)
                        showCancelAlert = false
                        dismiss()
                    } onCancel: {
                        showCancelAlert = false
                    }
                    // Sheet kompakter — vorher 0.82 (zu groß auf normalen
                    // iPhones, viel Leerraum). 0.62 reicht für das straffere
                    // Layout (kleineres Hero-Visual, engere Spacings) ohne
                    // zu scrollen.
                    .presentationDetents([.fraction(0.62)])
                    // Drop-Beenden-Warnung darf nicht versehentlich
                    // weggewischt werden — User muss bewusst Beenden
                    // oder Abbrechen tippen.
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
                    .sheetBackground()
                }
                .alert(tr("map.live_activity_disabled"), isPresented: $store.showLiveActivitySettingsHint) {
                    Button(tr("map.open_settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(tr("map.live_activities_info"))
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
                // Map-Pfad: schickt direkt ohne Compose-UI. Wer eine
                // Nachricht mitgeben will, geht über den Umgebungs-Tab
                // (FeedView → JoinConfirmSheet mit Quick-Chips + freier
                // Eingabe). Doppelte Compose-UI verwirrt nur.
                //
                // TimelineView refresht den Cooldown-Countdown sekündlich
                // — sonst zeigt der Button "X Min" stale bis das nächste
                // Sheet-Update kommt. Wichtig: nach Verlassen muss der User
                // sehen wie der Cooldown abläuft, sonst probiert er es
                // wieder und wieder.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let cooldown = store.joinCooldownRemaining(dropID: item.id)
                    let inCooldown = cooldown > 0 && !isJoined
                    Button {
                        guard !isJoined && !joining && !inCooldown else { return }
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
                            if inCooldown {
                                let mins = Int(cooldown / 60) + 1
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.fill").font(.system(size: 15))
                                    Text(tr("map.cooldown_mins").replacingOccurrences(of: "{mins}", with: "\(mins)"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.9))
                            } else if joining || isPending {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text(isPending ? tr("map.waiting_confirmation") : "")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            } else if isDeclined {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 17))
                                    Text(tr("map.not_confirmed")).font(.system(size: 16, weight: .bold))
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
                                inCooldown ? Color.textTertiary :
                                isDeclined ? Color.red.opacity(0.7) :
                                isJoined   ? Color.onlineGreen :
                                joining    ? accentColor.opacity(0.7) : accentColor
                            )
                            .shadow(color: (inCooldown ? Color.clear : accentColor).opacity(0.4), radius: 12, y: 5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isJoined || joining || inCooldown)
                    .animation(.spring(response: 0.3), value: isJoined)
                    .animation(.spring(response: 0.3), value: joining)
                    .animation(.spring(response: 0.3), value: inCooldown)
                    let _ = ctx.date  // hält die TimelineView am Tickern
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
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
            // Fallback auf item-Felder wenn participants leer (Fuzzy/Stranger-Drops
            // aus Firebase haben keine participants-Liste befüllt — nur hostUID/name/emoji).
            let creator = item.participants.first
            let profileName  = creator?.name           ?? item.name
            let profileEmoji = creator?.emoji          ?? item.emoji
            let profileUID   = creator?.firebaseUID    ?? item.hostUID
            let profileScore = creator?.reliabilityScore ?? item.hostReliabilityPoints ?? ReliabilityScore.startingPoints
            if #available(iOS 16.4, *) {
                MiniProfileSheet(
                    name: profileName,
                    emoji: profileEmoji,
                    selfie: creator?.selfie,
                    profileImageURL: creator?.profileImageURL,
                    reliabilityScore: profileScore,
                    accentColor: accentColor,
                    userUID: profileUID,
                    canBlock: true
                ) { dismiss() }
                .environmentObject(store)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
            } else {
                MiniProfileSheet(
                    name: profileName,
                    emoji: profileEmoji,
                    selfie: creator?.selfie,
                    profileImageURL: creator?.profileImageURL,
                    reliabilityScore: profileScore,
                    accentColor: accentColor,
                    userUID: profileUID,
                    canBlock: true
                ) { dismiss() }
                .environmentObject(store)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
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
            return tr("map.and_more").replacingOccurrences(of: "{names}", with: visible).replacingOccurrences(of: "{count}", with: "\(names.count - 2)")
        }
    }

    /// Name mit Alter im Format "Dennis, 30" wenn vorhanden, sonst nur Name.
    private func nameWithAge(_ p: DropParticipant) -> String {
        if let age = p.age { return "\(p.name), \(age)" }
        return p.name
    }

    /// Vergleicht ob der Teilnehmer der eigene User ist — Vergleich
    /// primär über firebaseUID, Fallback Name (z.B. wenn als Host
    /// registriert ohne explizite UID).
    private func isSelfParticipant(_ p: DropParticipant) -> Bool {
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
        return (p.firebaseUID != nil && p.firebaseUID == myUID)
            || (p.firebaseUID == nil && p.name == store.currentUser.name)
    }

    // MARK: - Reverse Geocoding

    private func geocodeAddress() {
        // Fuzzy-Drops: kein Geocoding.
        // • fuzzy coord → liefert falsche Adresse (800-1000m daneben)
        // • real  coord → würde den Host-Standort verraten
        // Der Fuzzy-Hinweis-Row ersetzt die Adresszeile im UI.
        guard !item.isFuzzy else { return }
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
                        ProgressView().tint(.brand)
                        Text(tr("map.calculating_route"))
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
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
                            Text(tr("map.walk_minutes").replacingOccurrences(of: "{mins}", with: "\(max(1, Int(route.expectedTravelTime / 60)))"))
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
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.lg))
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
    @State private var showRouteSheet = false
    @State private var lastExtendedAt: Date? = nil
    @State private var lastExtendCooldownSecs: Int = 0  // Hälfte der gewählten Verlängerung
    /// Sheet-State im Parent — überlebt Firebase-Updates ohne zu resetten.
    @State private var selectedProfileParticipant: DropParticipant? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Adaptive Farben

    var isOwnDrop: Bool { item.type == .myDrop }

    /// Eigener Token (8-stellig)
    /// Konsistent mit AppStore.myBLEToken (firebaseUID-prefix). Vorher nutzte
    /// dies die lokale UUID — das hat NICHT mit den BLE-confirmedTokens
    /// gematched, weil Joiner ihren BLE-Token aus firebaseUID ableiten.
    /// Folge: UI-Filter wie `p.token == myToken` sahen nie eine
    /// Übereinstimmung → Joiner blieb auf "Unterwegs", obwohl BLE bestätigt
    /// hatte.
    var myToken: String {
        store.myBLEToken
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

    /// Physisch bestätigte Teilnehmer (BLE-bestätigt ODER der Host bei
    /// fremden Drops, wenn der Joiner noch keine participants-Liste hat).
    /// Self (das eigene Token) zählt nur als „vor Ort", wenn `isArrived`
    /// wirklich greift — sonst stand der Host bei einem Pin-Drop oder
    /// der Joiner kurz nach Beitritt fälschlich auf „vor Ort", obwohl
    /// er noch unterwegs war.
    var confirmedHere: [DropParticipant] {
        var result: [DropParticipant]
        if item.participants.isEmpty && !isOwnDrop {
            // Host ist immer vor Ort — ggf. weitere BLE-bestätigte einfügen
            result = [syntheticHost]
            let bleConfirmed = store.bluetoothMeetup.confirmedTokens
            if !bleConfirmed.isEmpty {
                let extra = bleConfirmed.map { token in
                    DropParticipant(name: "", emoji: item.emoji, token: token)
                }
                result.append(contentsOf: extra)
            }
        } else {
            result = item.participants.filter { p in
                // Self: nur wenn physisch angekommen (GPS ≤ 20 m oder BLE).
                // Andere Teilnehmer: nur wenn BLE bestätigt hat.
                if p.token == myToken { return isArrived }
                return store.bluetoothMeetup.confirmedTokens.contains(p.token)
            }
        }

        // Fail-safe: wenn User im aktiven Drop ist UND als „vor Ort" gilt
        // (isArrived) aber Self fehlt in der Liste (Firebase-Sync-Lag o.ä.),
        // dann Self explizit anhängen. Sonst sieht der User sich selbst nicht
        // in seinem eigenen Drop — extrem irritierend.
        if isArrived && store.isInActiveDrop
           && !result.contains(where: { $0.token == myToken }) {
            result.append(DropParticipant(
                name: store.currentUser.name,
                emoji: store.currentUser.emoji,
                reliabilityScore: store.reliabilityScore.points,
                reliabilityCommits: store.reliabilityScore.totalCommits,
                age: store.userAge,
                token: myToken,
                profileImageURL: store.profileImageURL
            ))
        }

        return result
    }

    /// Unterwegs (beigetreten, aber noch nicht per BLE bestätigt).
    /// Self landet hier solange `isArrived` false ist — auch der Host,
    /// wenn er einen Pin-Drop fern vom aktuellen Standort erstellt hat.
    var onTheWay: [DropParticipant] {
        var result: [DropParticipant]
        if item.participants.isEmpty && !isOwnDrop {
            // Aktueller User ist unterwegs bis BLE bestätigt
            guard !isArrived else { return [] }
            return [DropParticipant(name: store.currentUser.name,
                                    emoji: store.currentUser.emoji,
                                    token: myToken)]
        } else {
            result = item.participants.filter { p in
                // Self: in „Unterwegs" wenn noch nicht angekommen.
                // Andere: in „Unterwegs" wenn BLE noch nicht bestätigt hat.
                if p.token == myToken { return !isArrived }
                return !store.bluetoothMeetup.confirmedTokens.contains(p.token)
            }
        }

        // Fail-safe: wenn User im aktiven Drop ist UND noch nicht „vor Ort"
        // ist (isArrived == false) UND Self fehlt in der Liste, Self in
        // „Unterwegs" anzeigen — sonst landet der Joiner zwischen den Stühlen
        // (weder in Vor Ort noch Unterwegs sichtbar).
        if !isArrived && store.isInActiveDrop
           && !result.contains(where: { $0.token == myToken }) {
            result.append(DropParticipant(
                name: store.currentUser.name,
                emoji: store.currentUser.emoji,
                reliabilityScore: store.reliabilityScore.points,
                reliabilityCommits: store.reliabilityScore.totalCommits,
                age: store.userAge,
                token: myToken,
                profileImageURL: store.profileImageURL
            ))
        }

        return result
    }

    var accentColor: Color {
        switch item.type {
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger: return item.creatorAgeGroup?.color ?? Color.auroraCyan
        default:        return .brand
        }
    }

    var activeSince: String {
        let e = Int(now.timeIntervalSince(item.createdAt) / 60)
        if e < 1 { return tr("drop.just_started") }
        if e < 60 { return tr("map.since_mins").replacingOccurrences(of: "{mins}", with: "\(e)") }
        let h = e / 60; let m = e % 60
        return m > 0
            ? tr("map.since_hm").replacingOccurrences(of: "{h}", with: "\(h)").replacingOccurrences(of: "{m}", with: "\(m)")
            : tr("map.since_h").replacingOccurrences(of: "{h}", with: "\(h)")
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
            Color.black.opacity((colorScheme == .dark ? 0.68 : 0.0))

            // Dezenter Akzent-Glow in Drop-Farbe
            RadialGradient(
                colors: [accentColor.opacity(colorScheme == .dark ? 0.22 : 0.15), Color.clear],
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

                    // Host bekommt IMMER die arrivedContent-View — auch wenn
                    // er physisch noch nicht am Drop ist (Drop wurde an einem
                    // Pin-Ort statt am aktuellen Standort erstellt). Vorher
                    // landete der Host in der Joiner-„Unterwegs"-View, die
                    // dann „Dein Host" zeigte (unsinnig — er IST der Host)
                    // und ihn weder bei Vor-Ort noch Unterwegs auflistete.
                    // Die Banner-Zeile in arrivedContent zeigt dem Host
                    // jetzt prominent „Du bist unterwegs zu deinem Drop".
                    if isOwnDrop || isArrived {
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
        .sheet(isPresented: $showCancelAlert) {
            EndDropSheet(
                activityEmoji: item.emoji,
                activityName: item.activity,
                participantCount: item.participants.count,
                elapsedSeconds: Date().timeIntervalSince(item.createdAt)
            ) {
                store.cancelDrop(id: item.id)
                showCancelAlert = false
            } onCancel: {
                showCancelAlert = false
            }
            // Sheet kompakter — vorher 0.82 (zu groß auf normalen
            // iPhones, viel Leerraum). 0.62 passt zum strafferen Layout.
            .presentationDetents([.fraction(0.62)])
            // Drop-Beenden-Warnung darf nicht versehentlich
            // weggewischt werden — User muss bewusst Beenden oder
            // Abbrechen tippen.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        // In-App-Route-Sheet — wird vom Joiner-Navigation-Button und
        // vom Host-Banner getriggert. Zeigt eine MKMapView mit
        // Walking-Polyline statt Apple Maps zu öffnen.
        .sheet(isPresented: $showRouteSheet) {
            InAppRouteSheet(
                destination: item.coordinate,
                destinationName: item.locationTitle.isEmpty ? item.activity : item.locationTitle,
                accentColor: accentColor
            )
            .environmentObject(store)
            .presentationDragIndicator(.visible)
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
                    Text(tr("map.drop_no_longer_visible"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(tr("map.no_new_joiners"))
                        .font(.system(size: 11))
                        .opacity(0.7)
                }
                Spacer()
            }
            .foregroundColor(.accentOrange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))
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
                    .foregroundColor(Color.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Color.auroraBlue).frame(width: 6, height: 6)
                    Text(isOwnDrop ? tr("drop.my_drop_active") : (isArrived ? tr("drop.arrived") : tr("drop.on_the_way")))
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Color.auroraBlue)
                    Text("· \(activeSince)").font(.system(size: 12)).foregroundColor(Color.textSecondary)
                }
                // Teilnehmer-Slots
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundColor(Color.textTertiary)
                    // Bei fremden Drops: mind. 1 (der Host), sonst echte Anzahl
                    let joined = isOwnDrop ? item.participants.count : max(1, confirmedHere.count + (isArrived ? 0 : 1))
                    let maxP   = item.maxParticipants
                    Text(tr("map.participants").replacingOccurrences(of: "{joined}", with: "\(joined)").replacingOccurrences(of: "{max}", with: "\(maxP)"))
                        .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                    if joined >= maxP {
                        Text("· \(tr("map.full"))").font(.system(size: 11, weight: .semibold)).foregroundColor(.accentOrange)
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
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Color.glassBorder, lineWidth: 1)
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
                    ProgressView().tint(.brand).scaleEffect(0.9)
                    Text(tr("map.calculating_route"))
                        .font(.system(size: 14)).foregroundColor(Color.textSecondary)
                }
            } else if let r = route {
                // Gehzeit kommt aus MKRoute (einmal berechnet, genauer weil
                // Gebäude-Umrundung), aber Distanz kommt LIVE aus dem GPS:
                // updated während man geht, nicht nur beim Tab-Switch.
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("map.walking_minutes").replacingOccurrences(of: "{mins}", with: "\(liveWalkMinutes ?? max(1, Int(r.expectedTravelTime / 60)))"))
                            .font(.system(size: 17, weight: .bold)).foregroundColor(Color.textPrimary)
                        Text({
                            let dist = liveDistanceMeters ?? r.distance
                            return dist < 1000
                                ? "\(Int(dist)) m entfernt"
                                : String(format: "%.1f km entfernt", dist / 1000)
                        }())
                            .font(.system(size: 13)).foregroundColor(Color.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: liveDistanceMeters)
                        if let addr = resolvedAddress {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin").font(.system(size: 9)).foregroundColor(Color.textTertiary)
                                Text(addr).font(.system(size: 11)).foregroundColor(Color.textTertiary).lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        // In-App-Route statt Apple Maps öffnen — siehe
                        // .sheet(isPresented: $showRouteSheet) am body.
                        showRouteSheet = true
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
                            .foregroundColor(Color.textPrimary)
                        if let age = item.creatorAge {
                            Text("\(age)")
                                .font(.system(size: 15))
                                .foregroundColor(Color.textSecondary)
                        }
                    }
                    Text(tr("map.your_host"))
                        .font(.system(size: 11))
                        .foregroundColor(Color.textTertiary)
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
                    Circle().fill(Color.textTertiary.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15)).foregroundColor(Color.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("drop.details_locked"))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    Text(tr("drop.arrive_for_unlock"))
                        .font(.system(size: 11)).foregroundColor(Color.textTertiary)
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
                            Text(tr("map.on_the_way_count").replacingOccurrences(of: "{count}", with: "\(onTheWay.count)"))
                                .font(.system(size: 12, weight: .medium)).foregroundColor(Color.textTertiary)
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

    // MARK: - Host-Unterwegs-Banner

    /// Banner für den Host, wenn er einen Drop an einem Pin-Ort erstellt
    /// hat und selbst noch nicht physisch dort ist (`isArrived == false`
    /// und `isOwnDrop`). Zeigt Distanz, Gehzeit und einen Maps-Button —
    /// damit man sofort sieht „aha, ich muss noch hin".
    @ViewBuilder
    private var hostOnTheWayBanner: some View {
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentOrange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    PulsingLiveDot()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("map.you_on_the_way"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                    HStack(spacing: 6) {
                        if let dist = liveDistanceMeters {
                            Text(dist < 1000
                                 ? tr("map.meters_away").replacingOccurrences(of: "{meters}", with: "\(Int(dist))")
                                 : tr("map.km_away").replacingOccurrences(of: "{km}", with: String(format: "%.1f", dist / 1000)))
                                .font(.system(size: 12))
                                .foregroundColor(Color.textSecondary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: liveDistanceMeters)
                        }
                        if let mins = liveWalkMinutes {
                            Text("· ~\(mins) \(tr("map.min_short"))")
                                .font(.system(size: 12))
                                .foregroundColor(Color.textTertiary)
                        }
                    }
                }
                Spacer()
                Button {
                    // In-App-Route statt Apple Maps öffnen
                    showRouteSheet = true
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.accentOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Vor-Ort-Ansicht (freigeschaltet)

    @ViewBuilder
    private var arrivedContent: some View {
        VStack(spacing: 0) {
            dropHeader

            // Host ist physisch noch nicht am Drop (Pin-Drop fern vom
            // aktuellen Standort) — prominent zeigen „du bist unterwegs"
            // mit Distanz + Apple-Maps-Button. Sobald er ≤ 20 m ist,
            // schaltet `isArrived` um und dieser Banner verschwindet.
            if isOwnDrop && !isArrived {
                hostOnTheWayBanner
            }

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
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
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
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Color.textSecondary)
                                Text("· \(tr("map.live"))").font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.auroraBlue)
                                Spacer()
                                Text("\(onTheWay.count) Person\(onTheWay.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
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
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
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
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Color.textSecondary)
                                Spacer()
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
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
                                .foregroundColor(Color.textPrimary)
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
                            .foregroundColor(Color.textSecondary)
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
                            .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                        Text(tr("map.x_of_y_participants").replacingOccurrences(of: "{used}", with: "\(used)").replacingOccurrences(of: "{total}", with: "\(total)"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    }
                    Spacer()
                    Text(free == 0 ? tr("map.full_red") : (free == 1 ? tr("map.spots_free_singular") : tr("map.spots_free_plural")).replacingOccurrences(of: "{count}", with: "\(free)"))
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
                            .foregroundColor(Color.auroraAmber)
                        Text("\(viewers.count) \(viewers.count == 1 ? "Person hat" : "Personen haben") geschaut")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        if !store.isDropsPlusActive {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color.textTertiary)
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
                                                .foregroundColor(Color.textPrimary)
                                            if let age = viewer.age {
                                                Text(", \(age)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(Color.textSecondary)
                                            }
                                        }
                                        Text(relativeTimeLabel(viewer.viewedAt))
                                            .font(.system(size: 11))
                                            .foregroundColor(Color.textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                            if viewers.count > 8 {
                                Text(tr("map.more_count").replacingOccurrences(of: "{count}", with: "\(viewers.count - 8)"))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.textTertiary)
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
                                Text(tr("map.unlock_with_plus"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color.auroraAmber, Color.auroraAmber],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: Radius.md)
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
        if elapsed < 60 { return tr("map.just_now") }
        if elapsed < 3600 { return tr("map.ago_mins").replacingOccurrences(of: "{mins}", with: "\(elapsed / 60)") }
        if elapsed < 86400 { return tr("map.ago_hours").replacingOccurrences(of: "{hours}", with: "\(elapsed / 3600)") }
        return tr("map.ago_days").replacingOccurrences(of: "{days}", with: "\(elapsed / 86400)")
    }

    // MARK: - Einladungs-Button (immer sichtbar)

    private var shareButtonCard: some View {
        sectionCard {
            Button { showShareSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text(tr("map.invite_friends"))
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
            // Wichtig: www-Subdomain nutzen weil drops-app.de → www.drops-app.de
            // mit 307 redirected wird. Apple Universal Links akzeptieren keine
            // Redirects — der Link würde sonst im Browser statt in der App
            // öffnen. Beide Hosts sind in den Entitlements als applinks
            // registriert, also gleich autoritativ.
            let dropLink = URL(string: "https://www.drops-app.de/drop/\(item.id.uuidString)")!
            let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
            let subject = "\(item.emoji) \(item.activity)\(location) — komm vorbei. 📍"
            ShareSheet(items: [dropLink], subject: subject)
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
                            .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                        Text(tr("map.time_left"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    }
                    Spacer()
                    Text(item.timeRemainingString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ratio > 0.85 ? .accentOrange : Color.textSecondary)
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
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                        Text(tr("drop.waiting_description"))
                            .font(.system(size: 11)).foregroundColor(Color.textSecondary)
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
        if secs < 60 { return tr("map.cooldown_s").replacingOccurrences(of: "{s}", with: "\(secs)") }
        let m = secs / 60
        let s = secs % 60
        return s > 0
            ? tr("map.cooldown_ms").replacingOccurrences(of: "{m}", with: "\(m)").replacingOccurrences(of: "{s}", with: "\(s)")
            : tr("map.cooldown_m").replacingOccurrences(of: "{m}", with: "\(m)")
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
                        Text(tr("map.extend_cooldown").replacingOccurrences(of: "{time}", with: formatCooldown(secs)))
                            .font(.system(size: 14, weight: .semibold))
                            .contentTransition(.numericText())
                    } else {
                        Text(tr("map.extend"))
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
                    in: RoundedRectangle(cornerRadius: Radius.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
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
                            in: RoundedRectangle(cornerRadius: Radius.lg))
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
                .foregroundColor(Color.textTertiary)
                .padding(.top, 6)
            }
        }
        .sheet(isPresented: $showLeaveConfirm) {
            // Elapsed seconds aus dem joinRequest des Stores — bei pending
            // Requests = 0 (kein Score-Risiko), bei akzeptierten 12+ min
            // löst die Score-Warnung aus.
            let elapsed: TimeInterval = {
                if let req = store.joinRequests.first(where: { $0.dropID == item.id }) {
                    return Date().timeIntervalSince(req.createdAt)
                }
                return 0
            }()
            LeaveDropSheet(
                activityEmoji: item.emoji,
                activityName: item.activity,
                elapsedSeconds: elapsed
            ) {
                store.leaveDropJoin(dropID: item.id)
                showLeaveConfirm = false
            } onCancel: {
                showLeaveConfirm = false
            }
            .presentationDetents([.fraction(0.65)])
            // Verlassen-Warnung darf nicht versehentlich weggewischt
            // werden — User muss bewusst Verlassen oder Abbrechen tippen.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        // ── MiniProfile für Teilnehmer — im Parent damit Firebase-Updates
        // den @State in ParticipantDetailRow nicht resetten.
        .sheet(item: $selectedProfileParticipant) { p in
            let agePart = p.age.map { ", \($0)" } ?? ""
            let subtitle = p.statusMessage.isEmpty
                ? "\(tr("map.drops_user"))\(agePart)"
                : "\(p.statusMessage)\(agePart)"
            MiniProfileSheet(
                name: p.name,
                emoji: p.emoji,
                selfie: p.selfie,
                profileImageURL: p.profileImageURL,
                reliabilityScore: p.reliabilityScore,
                totalCommits: p.reliabilityCommits,
                subtitle: subtitle,
                accentColor: ReliabilityScore.color(forPoints: p.reliabilityScore),
                userUID: p.firebaseUID,
                canBlock: true,
                onBlock: {}
            )
            .environmentObject(store)
            .presentationDetents([.medium])
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
    /// Callback zum Parent — Sheet wird dort verwaltet, damit Firebase-Updates
    /// den @State nicht zurücksetzen und das Sheet nicht schließen.
    var onTapProfile: ((DropParticipant) -> Void)? = nil
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var colorScheme
    @State private var showLiveLocation = false

    private var avatarBg: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06) }
    private var avatarStroke: Color { colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }

    // MARK: Helpers

    /// Direkte Display-Werte aus der echten Punktzahl. Frühere Rekonstruktion
    /// via showUps führte bei Punkten >100 dazu, dass `displayText` falsche
    /// Werte zeigte und die Progress-Bar überlief (Strikethrough-Effekt).
    private var displayPoints: Int { participant.reliabilityScore }
    private var displayColor: Color  { ReliabilityScore.color(forPoints: displayPoints) }
    private var displayBadge: String { ReliabilityScore.badge(forPoints: displayPoints) }
    private var displayBadgeIcon: String { ReliabilityScore.badgeIcon(forPoints: displayPoints) }
    /// Bar-Füllung: Fortschritt innerhalb des aktuellen Tiers (0–1).
    private var displayBarFill: Double {
        ReliabilityScore.tierProgress(forPoints: displayPoints)
    }

    /// Beta-Badge nur wenn der Teilnehmer der eigene User ist (für andere
    /// Teilnehmer ist `createdAt` aktuell nicht im DropParticipant-Schema
    /// propagiert). Vergleich über firebaseUID, Fallback Name.
    private var participantQualifiesForBetaBadge: Bool {
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
        let isMe = (participant.firebaseUID != nil && participant.firebaseUID == myUID)
            || (participant.firebaseUID == nil && participant.name == store.currentUser.name)
        guard isMe else { return false }
        return store.qualifiesForBetaBadge
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
                onTapProfile?(participant)
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
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.textPrimary).lineLimit(1)
                            if participantQualifiesForBetaBadge {
                                BetaBadge()
                            }
                        }
                        HStack(spacing: 7) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.textSecondary.opacity(0.3))
                                    RoundedRectangle(cornerRadius: 3).fill(displayColor)
                                        // Tier-Progress geclampt auf 0–1, damit
                                        // die Bar nicht über den 52pt-Frame
                                        // hinausläuft und den Punktetext
                                        // optisch durchstreicht.
                                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, displayBarFill))))
                                }
                            }
                            .frame(width: 52, height: 4)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text("\(displayPoints)")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(displayColor)
                            Image(systemName: displayBadgeIcon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(displayColor)
                            Text(displayBadge).font(.system(size: 10)).foregroundColor(Color.textSecondary)
                        }
                    }

                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Circle().fill(Color.onlineGreen).frame(width: 5, height: 5)
                        Text(tr("drop.arrived")).font(.system(size: 11, weight: .semibold)).foregroundColor(.onlineGreen)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.bgSecondary))
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
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Distanz + ETA kompakt
                    HStack(spacing: 6) {
                        if let dist = distanceLabel {
                            HStack(spacing: 3) {
                                Image(systemName: "figure.walk").font(.system(size: 9, weight: .medium))
                                Text(dist).font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color.textSecondary)
                        }
                        if let mins = etaMinutes {
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.system(size: 9))
                                Text(tr("map.walk_minutes").replacingOccurrences(of: "{mins}", with: "\(mins)")).font(.system(size: 11))
                            }
                            .foregroundColor(Color.textSecondary)
                        } else if distanceLabel == nil {
                            Text(tr("drop.on_the_way")).font(.system(size: 11)).foregroundColor(Color.textSecondary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.bgSecondary))
            }
        }
        .buttonStyle(.plain)
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
                        Text(tr("map.mins").replacingOccurrences(of: "{mins}", with: "\(mins)"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(tr("map.arrival_approx"))
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
                        Text(clock + tr("map.oclock_suffix"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(tr("map.expected"))
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
                    Text(tr("map.points_abbrev").replacingOccurrences(of: "{points}", with: "\(participant.reliabilityScore)"))
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
        case 200...: return .onlineGreen
        case 50..<200: return .accentOrange
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
    var accentColor: Color = Color.auroraCyan
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
    @State private var inviteSent: Bool = false
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

    /// „Dabei seit 3 Monaten" / „Neu dabei" — leitet Drops-Member-Status
    /// aus dem in Firebase gespeicherten `createdAt` ab (geladen in
    /// onAppear via `fetchUserMeta`). nil, wenn noch nicht geladen.
    private var memberSinceLabel: String? {
        guard let created = fetchedCreatedAt else { return nil }
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month, .day],
                                                     from: created, to: now)
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        let days = comps.day ?? 0
        if years >= 1 {
            return years == 1 ? tr("map.member_since_1y") : tr("map.member_since_y").replacingOccurrences(of: "{years}", with: "\(years)")
        }
        if months >= 1 {
            return months == 1 ? tr("map.member_since_1m") : tr("map.member_since_m").replacingOccurrences(of: "{months}", with: "\(months)")
        }
        if days >= 1 {
            return days == 1 ? tr("map.member_since_yesterday") : tr("map.member_since_d").replacingOccurrences(of: "{days}", with: "\(days)")
        }
        return tr("map.member_today")
    }

    /// Kompakte Info-Zeile innerhalb der Stats-Card.
    @ViewBuilder
    private func miniInfoRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 18)

            // ── Avatar mit Sunset-Glow-Ring ────────────────────────────
            // Vorher: dünner accentColor-Ring (Cyan/Brand-Grün, abh. vom
            // Caller). Jetzt: Sunset-Gradient-Ring (Orange→Grün) als
            // einheitliches Branding, plus subtiler doppelter Glow für
            // mehr Premium-Feeling. Avatar selbst etwas größer (84→92).
            ZStack {
                // Outer Glow (dezent)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange.opacity(0.20),
                                     Color.auroraGreen.opacity(0.16)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 116)
                    .blur(radius: 14)

                // Gradient-Ring (Sunset)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 96, height: 96)

                if let img = selfie {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                } else if let urlStr = profileImageURL {
                    RemoteProfileImage(url: urlStr, fallbackEmoji: emoji, size: 92,
                                       strokeColor: .clear)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.auroraOrange.opacity(0.14),
                                         Color.auroraGreen.opacity(0.10)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .overlay(Text(emoji).font(.system(size: 44)))
                }
            }
            .frame(height: 120)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                // Beta-Badge nur für Early-Adopter (registriert vor 04.05.2026)
                if qualifiesForBetaBadge {
                    BetaBadge()
                }
                // Community-Creator-Badge — wenn dieser User eine Community hat
                if FeatureFlags.communitiesEnabled,
                   let uid = userUID,
                   let community = store.communityForCreator(uid: uid) {
                    CommunityCreatorBadge(community: community, compact: true)
                }
                if isPlus || fetchedPlus {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        Text("PLUS").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(Color(hex: "7a4e05"))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [Color.auroraGoldLight, Color.auroraGoldDark],
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
            .padding(.bottom, 18)

            // ── Zuverlässigkeits-Ring + Member-Seit zusammen in 1 Card ──
            // Vorher: 1 separate Card pro Info. Jetzt: kompakter Combo-
            // Layout mit Divider — weniger vertikalem Platz, dichter Info.
            VStack(spacing: 0) {
                // Tier-Ring + Badge
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(tierColor.opacity(0.15), lineWidth: 5)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: CGFloat(tierProgress))
                            .stroke(tierColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.6), value: reliabilityScore)
                        Image(systemName: tierIcon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(tierColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tierLabel)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(totalCommits > 0
                             ? tr("map.points_drops").replacingOccurrences(of: "{points}", with: "\(reliabilityScore)").replacingOccurrences(of: "{drops}", with: "\(totalCommits)")
                             : tr("map.points_only").replacingOccurrences(of: "{points}", with: "\(reliabilityScore)"))
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)

                // Sekundär-Zeilen — Member-Seit, frühere Begegnungen.
                // Jeweils mit Divider und kompakter Icon-Spalte für visuelle
                // Konsistenz. Beides optional — nur rendern wenn Daten da.
                if let memberSince = memberSinceLabel {
                    Divider().padding(.leading, 52)
                    miniInfoRow(
                        icon: "sparkle",
                        tint: Color.auroraGreen,
                        text: memberSince
                    )
                }
                if priorEncountersCount > 0 {
                    Divider().padding(.leading, 52)
                    miniInfoRow(
                        icon: "person.2.wave.2.fill",
                        tint: Color.auroraOrange,
                        text: tr("map.met_count").replacingOccurrences(of: "{count}", with: "\(priorEncountersCount)")
                    )
                }
            }
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 20)

            Spacer()

            // Bei Freunden: "Freund entfernen" — bei Fremden: Melden + Blockieren.
            // Keine Aktionen auf sich selbst.
            if name != store.currentUser.name {
                // Einladen-Button — nur sichtbar wenn ich gerade hoste UND
                // der User ein Freund mit bekannter UID ist. Sonst hat der
                // Button keinen Adressaten oder Drop, zu dem eingeladen
                // werden könnte.
                if isFriend, !store.activeDrops.isEmpty,
                   let targetUID = userUID, !targetUID.isEmpty {
                    // Invite-Button mit Sunset-Gradient — fühlt sich an wie
                    // ein „big positive action" statt einfacher Brand-Pill.
                    Button {
                        store.inviteFriendToDrop(friendUID: targetUID)
                        withAnimation(.spring(response: 0.3)) { inviteSent = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: inviteSent ? "checkmark.circle.fill" : "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(inviteSent ? tr("map.invitation_sent") : tr("map.invite_to_my_drop"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                inviteSent
                                ? AnyShapeStyle(Color.onlineGreen)
                                : AnyShapeStyle(LinearGradient(
                                    colors: [Color.auroraOrange, Color.auroraGreen],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                            )
                        )
                        .shadow(color: Color.auroraOrange.opacity(inviteSent ? 0 : 0.35),
                                radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(inviteSent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                if isFriend {
                    Button { showRemoveFriendAlert = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.minus")
                                .font(.system(size: 13))
                            Text(tr("map.remove_friend"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.accentRed.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else if canBlock {
                    HStack(spacing: 10) {
                        Button { showReportSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "flag.fill").font(.system(size: 13))
                                Text(tr("map.report")).font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.accentOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.accentOrange.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button { showBlockAlert = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised.fill").font(.system(size: 13))
                                Text(tr("map.block")).font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.accentRed.opacity(0.25), lineWidth: 1))
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
            Button(tr("map.block"), role: .destructive) {
                store.blockUser(name: name)
                dismiss()
                onBlock()
            }
        } message: {
            Text(tr("profile.block_message").replacingOccurrences(of: "{name}", with: name))
        }
        .alert(tr("map.remove_friend_q"), isPresented: $showRemoveFriendAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button(tr("map.remove"), role: .destructive) {
                if let uid = userUID, !uid.isEmpty {
                    store.removeFriend(theirUID: uid)
                }
                dismiss()
            }
        } message: {
            Text(tr("map.unfriend_message").replacingOccurrences(of: "{name}", with: name))
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
                .fill(Color.auroraBlue.opacity(0.25))
                .frame(width: 12, height: 12)
                .scaleEffect(pulsing ? 1.8 : 1.0)
                .opacity(pulsing ? 0 : 0.6)
            Circle()
                .fill(Color.auroraBlue)
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
    var subject: String = ""
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if !subject.isEmpty { vc.setValue(subject, forKey: "subject") }
        return vc
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
                    Text(tr("map.boost_phase_active"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(tr("map.boost_phase_msg"))
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

            Text(tr("map.extend_drop"))
                .font(.system(size: 17, weight: .semibold))

            Text(tr("map.extend_drop_msg"))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            let options: [(String, Int)] = [
                (tr("map.extend_30min"), 30), (tr("map.extend_1h"), 60), (tr("map.extend_2h"), 120), (tr("map.extend_4h"), 240)
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
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: Radius.card))
                            .shadow(color: Color.brand.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Button(tr("map.cancel")) { dismiss() }
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

    private var reasons: [String] {
        [
            tr("map.report_reason_harassment"),
            tr("map.report_reason_fake"),
            tr("map.report_reason_spam"),
            tr("map.report_reason_offensive"),
            tr("map.report_reason_minor"),
            tr("map.report_reason_misc")
        ]
    }

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
                    Text(tr("map.reported_user"))
                }

                if submitted {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.brand)
                            Text(tr("map.report_received"))
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
                        Text(tr("map.reason"))
                    }

                    Section {
                        TextField(tr("map.optional_more_info"), text: $details, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text(tr("map.details_optional"))
                    }
                }
            }
            .navigationTitle(tr("map.report_user"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("map.cancel")) { dismiss(); onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitted {
                        Button(tr("map.done")) { dismiss(); onDismiss() }
                            .fontWeight(.semibold)
                    } else {
                        Button(tr("map.send")) {
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

// MARK: - JoinerLiveInfoSheet
// Kompakte Info-Ansicht wenn der Host auf einen Joiner-Pin auf seiner
// Karte tippt. KEIN "Ich komme vorbei"-Button (der Joiner kommt ja zu
// uns, nicht andersrum). Zeigt Avatar, Name, Alter, Reliability-Tier
// und — wenn GPS bekannt — Distanz / ETA zum eigenen Drop.
struct JoinerLiveInfoSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MapAnnotationItem

    /// Live-Info aus joinerLiveInfos via stableUUID-Match. item.id ist
    /// die hash-basierte UUID — wir suchen die UID rückwärts indem wir
    /// gegen alle bekannten Joiner-UIDs vergleichen.
    private var joinerInfo: JoinerLiveInfo? {
        for (uid, info) in store.joinerLiveInfos
        where AppStore.stableUUID(from: uid) == item.id {
            return info
        }
        return nil
    }

    /// Distanz zum eigenen Drop in km — Joiner ist unterwegs ZU uns.
    private var distanceKm: Double? {
        guard let info = joinerInfo,
              let myDrop = store.activeDrops.first else { return nil }
        let joiner = CLLocation(latitude: info.lat, longitude: info.lng)
        let drop = CLLocation(latitude: myDrop.location.coordinate.latitude,
                              longitude: myDrop.location.coordinate.longitude)
        return joiner.distance(from: drop) / 1000.0
    }

    /// ETA in Minuten — grobe Walking-Speed-Annahme (5 km/h).
    private var etaMinutes: Int? {
        guard let km = distanceKm else { return nil }
        return Int((km / 5.0) * 60.0)
    }

    private var reliabilityTier: String {
        guard let pts = joinerInfo?.reliabilityPoints else { return "" }
        return ReliabilityScore.badge(forPoints: pts)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Avatar + Name (+ Age) + "ist auf dem Weg"-Label
            HStack(spacing: 14) {
                ZStack {
                    if let url = joinerInfo?.profileImageURL, !url.isEmpty {
                        RemoteProfileImage(
                            url: url,
                            fallbackEmoji: item.emoji,
                            size: 60,
                            strokeColor: .clear
                        )
                    } else {
                        Circle()
                            .fill(Color.onlineGreen.opacity(0.14))
                            .frame(width: 60, height: 60)
                        Text(item.emoji.isEmpty ? "👤" : item.emoji)
                            .font(.system(size: 30))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if let age = joinerInfo?.age {
                            Text("· \(age)")
                                .font(.system(size: 15))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    HStack(spacing: 5) {
                        PulsingLiveDot()
                        Text(tr("map.on_the_way_to_drop"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    if !reliabilityTier.isEmpty {
                        Text(reliabilityTier)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.brand)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.brand.opacity(0.12), in: Capsule())
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)

            Divider().padding(.horizontal, 20)

            // Live-Stats: Distanz + ETA
            if let km = distanceKm, let eta = etaMinutes {
                HStack(spacing: 0) {
                    statBlock(
                        icon: "figure.walk",
                        value: tr("map.mins_short").replacingOccurrences(of: "{mins}", with: "\(eta)"),
                        label: tr("map.way"),
                        color: .brand
                    )
                    Divider().frame(height: 36)
                    statBlock(
                        icon: "location.fill",
                        value: String(format: "%.1f km", km),
                        label: tr("map.distance_short"),
                        color: .onlineGreen
                    )
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }

            Spacer(minLength: 12)

            // Schließen-Button — kein CTA, weil keine Aktion nötig ist.
            // Der Host beobachtet einfach wie der Joiner näher kommt.
            Button { dismiss() } label: {
                Text(tr("map.close"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func statBlock(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
