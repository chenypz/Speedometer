import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation

// MARK: - 1. 資料模型與歷史紀錄
struct OverspeedRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let speed: Double
    let speedLimit: Double
}

struct HistoryRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let maxSpeed: Double
    let zeroToOneHundredTime: Double
    let maxGForce: Double
    let tripDistance: Double
    let routeCoordinates: [CodableCoordinate]
}

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - 測速照相資料結構
struct SpeedCamera: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let speedLimit: Double
    let description: String
    var isTemporary: Bool = false
}

// MARK: - 2. 佈景主題設定
enum DashboardTheme: String, CaseIterable, Identifiable {
    case porsche = "保時捷經典"
    case cyberpunk = "賽博朋克"
    case arcade = "極速電玩"
    
    var id: String { self.rawValue }
    
    func primaryColor(custom: Color?) -> Color {
        if let custom = custom { return custom }
        switch self {
        case .porsche: return .orange
        case .cyberpunk: return Color(red: 0.0, green: 0.8, blue: 1.0)
        case .arcade: return Color(red: 0.8, green: 0.1, blue: 0.9)
        }
    }
    
    var backgroundGradientColors: [Color] {
        switch self {
        case .porsche:
            return [Color(red: 0.08, green: 0.04, blue: 0.0), Color.black, Color(red: 0.12, green: 0.06, blue: 0.0)]
        case .cyberpunk:
            return [Color(red: 0.02, green: 0.03, blue: 0.1), Color(red: 0.01, green: 0.01, blue: 0.04), Color(red: 0.05, green: 0.0, blue: 0.12)]
        case .arcade:
            return [Color(red: 0.08, green: 0.0, blue: 0.12), Color(red: 0.02, green: 0.0, blue: 0.05), Color(red: 0.0, green: 0.05, blue: 0.1)]
        }
    }
}

extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        let components = rawValue.components(separatedBy: ",")
        guard components.count == 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]) else {
            return nil
        }
        self.init(red: red, green: green, blue: blue)
    }

    public var rawValue: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(red),\(green),\(blue)"
    }
}

// MARK: - 3. GPS、感應器與測速照相管理器
class VehicleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    
    @Published var speed: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var tripDistance: Double = 0.0
    @Published var heading: Double = 0.0
    
    @Published var currentGForceX: Double = 0.0
    @Published var currentGForceY: Double = 0.0
    @Published var maxGForce: Double = 0.0
    
    @Published var zeroToOneHundredTime: Double = 0.0
    @Published var isTesting0_100: Bool = false
    private var accelStartTime: Date? = nil
    private var hasReached100: Bool = false
    
    @Published var currentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    @Published var isNavigating: Bool = false
    @Published var routePolyline: MKPolyline? = nil
    @Published var currentInstruction: String = "搜尋目的地或點擊地圖"
    @Published var distanceToNextStep: Double = 0.0
    @Published var destinationCoordinate: CLLocationCoordinate2D? = nil
    
    @Published var nearestCameraAlert: String? = nil
    @Published var recordedPath: [CLLocationCoordinate2D] = []
    
    @Published var speedCameras: [SpeedCamera] = [
        SpeedCamera(coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654), speedLimit: 50, description: "台北信義路固定測速"),
        SpeedCamera(coordinate: CLLocationCoordinate2D(latitude: 25.0400, longitude: 121.5700), speedLimit: 60, description: "台北忠孝東路固定測速")
    ]
    
    private var lastLocation: CLLocation? = nil
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = kCLHeadingFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        startMotionUpdates()
    }
    
    func updateLocationAccuracy(isNetworkBoostEnabled: Bool) {
        if isNetworkBoostEnabled {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 1.0
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = kCLDistanceFilterNone
        }
    }
    
    func resetData() {
        tripDistance = 0.0
        maxSpeed = 0.0
        maxGForce = 0.0
        zeroToOneHundredTime = 0.0
        isTesting0_100 = false
        hasReached100 = false
        accelStartTime = nil
        lastLocation = nil
        recordedPath.removeAll()
    }
    
    func reportMobileSpeedTrap() {
        let newTrap = SpeedCamera(
            coordinate: currentLocation,
            speedLimit: 50,
            description: "⚠️ 用戶回報流動測速/三腳架",
            isTemporary: true
        )
        speedCameras.append(newTrap)
        nearestCameraAlert = "已成功回報流動測速點！"
        AudioServicesPlaySystemSound(1016)
    }
    
    func searchAndNavigate(query: String) {
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: currentLocation, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self, let item = response?.mapItems.first else {
                self?.currentInstruction = "找不到指定地點"
                return
            }
            self.setDestination(item.placemark.coordinate)
            self.currentInstruction = "目的地: \(item.name ?? query)"
        }
    }
    
    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        self.destinationCoordinate = coordinate
        self.isNavigating = true
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self, let route = response?.routes.first else {
                self?.currentInstruction = "路線計算失敗"
                return
            }
            
            self.routePolyline = route.polyline
            if let firstStep = route.steps.first(where: { !$0.instructions.isEmpty }) {
                self.currentInstruction = firstStep.instructions
                self.distanceToNextStep = firstStep.distance
            }
        }
    }
    
    func cancelNavigation() {
        isNavigating = false
        routePolyline = nil
        destinationCoordinate = nil
        currentInstruction = "導航已結束"
        distanceToNextStep = 0.0
    }
    
    private func startMotionUpdates() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] (data: CMAccelerometerData?, error: Error?) in
                guard let self = self, let acceleration = data?.acceleration else { return }
                self.currentGForceX = acceleration.x
                self.currentGForceY = acceleration.y
                let currentG = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y)
                if currentG > self.maxGForce {
                    self.maxGForce = currentG
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        currentLocation = newLocation.coordinate
        recordedPath.append(newLocation.coordinate)
        
        let speedKmh = max(0, newLocation.speed * 3.6)
        self.speed = speedKmh
        
        checkSpeedCameras(currentLoc: newLocation, currentSpeed: speedKmh)
        if speedKmh > maxSpeed { maxSpeed = speedKmh }
        
        if let last = lastLocation {
            let distanceInMeters = newLocation.distance(from: last)
            if distanceInMeters > 0 { tripDistance += distanceInMeters / 1000.0 }
        }
        lastLocation = newLocation
        
        if speedKmh < 5 && !isTesting0_100 && !hasReached100 {
            isTesting0_100 = true
            accelStartTime = Date()
            zeroToOneHundredTime = 0.0
            hasReached100 = false
        } else if isTesting0_100, let startTime = accelStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            zeroToOneHundredTime = elapsed
            if speedKmh >= 100.0 {
                isTesting0_100 = false
                hasReached100 = true
            } else if elapsed > 30.0 {
                isTesting0_100 = false
            }
        }
    }
    
    private func checkSpeedCameras(currentLoc: CLLocation, currentSpeed: Double) {
        let alertDistance: CLLocationDistance = 400.0
        for camera in speedCameras {
            let cameraLocation = CLLocation(latitude: camera.coordinate.latitude, longitude: camera.coordinate.longitude)
            let distance = currentLoc.distance(from: cameraLocation)
            
            if distance <= alertDistance {
                nearestCameraAlert = "\(camera.description) 剩 \(Int(distance))m (速限 \(Int(camera.speedLimit))km)"
                if currentSpeed > camera.speedLimit {
                    AudioServicesPlaySystemSound(1007)
                }
                return
            }
        }
        if nearestCameraAlert?.contains("已成功回報") == false {
            nearestCameraAlert = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - 4. 擴充 10 秒多階段高科技開場動畫（附右下角 SKIP 按鈕）
struct BootLoadingView: View {
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0.0
    @State private var textStep = 0
    @State private var showWarningScreen: Bool = false
    @State private var warningOpacity: Double = 0.0
    
    @State private var armorScale: CGFloat = 0.2
    @State private var armorRotation: Double = -180.0
    @State private var coreGlow: CGFloat = 0.0
    @State private var shockwaveScale: CGFloat = 0.1
    @State private var shockwaveOpacity: Double = 0.0
    
    let steps = [
        "CYBERTRON MATRIX CORE INITIALIZING...",
        "CALIBRATING QUANTUM GPS & SATELLITE UPLINK...",
        "ASSEMBLING KINETIC SHIELDS & DUAL-BLADE HUD...",
        "ESTABLISHING SECURE NEURAL OVERDRIVE...",
        "DIAGNOSTIC COMPLETE. ALL SYSTEMS NOMINAL.",
        "AUTOBOT PROTOCOL 901 ENGAGED. PREPARE FOR LAUNCH."
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.08), Color.black, Color(red: 0.06, green: 0.01, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            // 右下角 SKIP 跳過按鈕
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isFinished = true
                        }
                    }) {
                        Text("SKIP ❯❯")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.cyan.opacity(0.3))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.cyan, lineWidth: 1.5))
                            .cornerRadius(16)
                            .shadow(color: .cyan, radius: 5)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
            .zIndex(30)
            
            if !showWarningScreen {
                VStack(spacing: 30) {
                    ZStack {
                        Circle()
                            .stroke(.cyan, lineWidth: 4)
                            .frame(width: 180, height: 180)
                            .scaleEffect(shockwaveScale)
                            .opacity(shockwaveOpacity)
                        
                        ForEach(0..<6, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.cyan, Color(red: 0.8, green: 0.1, blue: 0.9)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 24, height: 75)
                                .offset(y: -55)
                                .rotationEffect(.degrees(Double(i) * 60.0 + armorRotation))
                                .shadow(color: .cyan, radius: 8)
                        }
                        
                        Circle()
                            .fill(RadialGradient(gradient: Gradient(colors: [.white, .cyan, .clear]), center: .center, startRadius: 2, endRadius: 50))
                            .frame(width: 100, height: 100)
                            .scaleEffect(coreGlow)
                            .shadow(color: .cyan, radius: 20)
                        
                        Image(systemName: "cpu")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(armorScale)
                    }
                    .frame(height: 180)
                    
                    Text("AUTOBOT QUANTUM HUD")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .kerning(8)
                        .foregroundColor(.cyan)
                        .shadow(color: .cyan, radius: 10)
                        .opacity(Double(progress))
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 300, height: 6)
                                .cornerRadius(3)
                            
                            Rectangle()
                                .fill(LinearGradient(colors: [.cyan, Color(red: 0.8, green: 0.1, blue: 0.9), .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 300 * progress, height: 6)
                                .cornerRadius(3)
                                .shadow(color: .cyan, radius: 8)
                        }
                        
                        Text(steps[min(textStep, steps.count - 1)])
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("安全規範")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                        Spacer()
                        Text("CYBERTRON PROTOCOL")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("道路安全與速度測試免責聲明")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.red)
                        
                        Text("本系統提供之GPS速度、測速照相預警與加速測試數據僅供參考。駕駛時請嚴格遵守當地交通法規，確保行車安全。")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(5)
                        
                        Text("SEC. 901 - MATRIX OF LEADERSHIP VERIFIED")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)
                }
                .frame(width: min(UIScreen.main.bounds.width - 40, 500))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 3))
                .cornerRadius(12)
                .shadow(color: .red.opacity(0.6), radius: 15)
                .opacity(warningOpacity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.6)) {
                armorScale = 1.0
                armorRotation = 0.0
                coreGlow = 1.2
            }
            
            withAnimation(.easeOut(duration: 0.8)) {
                shockwaveScale = 2.2
                shockwaveOpacity = 0.8
            }
            
            withAnimation(.easeInOut(duration: 9.0)) {
                progress = 1.0
            }
            
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
                if textStep < steps.count - 1 {
                    textStep += 1
                } else {
                    timer.invalidate()
                    withAnimation(.easeInOut(duration: 0.4)) { showWarningScreen = true }
                    withAnimation(.easeIn(duration: 0.6)) { warningOpacity = 1.0 }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeOut(duration: 0.6)) { warningOpacity = 0.0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            withAnimation(.easeInOut(duration: 0.8)) { isFinished = true }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 5. 背景流光霓虹燈條特效
struct BackgroundNeonFlowView: View {
    @State private var isAnimating = false
    var primaryColor: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [primaryColor.opacity(0.2), primaryColor, Color(red: 0.8, green: 0.1, blue: 0.9), primaryColor.opacity(0.2), Color.clear]),
                        center: .center,
                        angle: .degrees(isAnimating ? 360 : 0)
                    ),
                    lineWidth: 5
                )
                .padding(4)
                .shadow(color: primaryColor.opacity(0.8), radius: 12)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(Animation.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - 6. 互動式導航地圖
struct InteractiveNavigationMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?
    var destinationCoordinate: CLLocationCoordinate2D?
    var historyPath: [CLLocationCoordinate2D]?
    var isInteractive: Bool = true
    var onMapTap: (CLLocationCoordinate2D) -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = isInteractive ? .followWithHeading : .none
        mapView.isZoomEnabled = isInteractive
        mapView.isScrollEnabled = isInteractive
        mapView.isRotateEnabled = isInteractive
        mapView.showsCompass = false
        mapView.showsTraffic = false
        mapView.delegate = context.coordinator
        
        if isInteractive {
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            mapView.addGestureRecognizer(tapGesture)
        }
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if isInteractive && uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
        }
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)
        
        if let polyline = routePolyline {
            uiView.addOverlay(polyline)
        }
        
        if let path = historyPath, !path.isEmpty {
            let polyline = MKPolyline(coordinates: path, count: path.count)
            uiView.addOverlay(polyline)
            if let firstCoord = path.first {
                let region = MKCoordinateRegion(center: firstCoord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                uiView.setRegion(region, animated: true)
            }
        }
        
        if let dest = destinationCoordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = dest
            annotation.title = "目的地"
            uiView.addAnnotation(annotation)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveNavigationMapView
        init(_ parent: InteractiveNavigationMapView) { self.parent = parent }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap(coord)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = parent.historyPath != nil ? UIColor.systemOrange : UIColor.systemCyan
                renderer.lineWidth = 6
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - 7. 炫光流光圓形線條
struct NeonArcFlowView: View {
    @State private var animate = false
    var color: Color
    var size: CGFloat = 260
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0.0, to: 0.35)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.clear, color, .white]), center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .animation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false), value: animate)
        }
        .onAppear { animate = true }
    }
}

// MARK: - 8. 專業轉速提示燈
struct ShiftLightsView: View {
    let speed: Double
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(lightColor(for: index))
                    .frame(width: 16, height: 5)
                    .cornerRadius(2)
                    .shadow(color: lightColor(for: index).opacity(0.8), radius: isLit(index) ? 4 : 0)
            }
        }
    }
    
    private func isLit(_ index: Int) -> Bool { speed >= Double(index + 1) * 25.0 }
    private func lightColor(for index: Int) -> Color {
        guard isLit(index) else { return Color.gray.opacity(0.3) }
        if index < 4 { return .green }
        if index < 6 { return .yellow }
        return .red
    }
}

// MARK: - 9. 內嵌小地圖元件
struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?
    var destinationCoordinate: CLLocationCoordinate2D?
    var primaryColor: Color
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                InteractiveNavigationMapView(
                    coordinate: coordinate,
                    routePolyline: routePolyline,
                    destinationCoordinate: destinationCoordinate,
                    isInteractive: false,
                    onMapTap: { _ in }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(primaryColor.opacity(0.8), lineWidth: 2))
                
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .frame(width: 120, height: 120)
        .shadow(color: primaryColor.opacity(0.4), radius: 6)
    }
}

// MARK: - 10. 科幻粒子凝聚特效外框
struct SciFiParticleAssembleView<Content: View>: View {
    let content: Content
    @State private var assembleProgress: CGFloat = 0.0
    
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        ZStack {
            content
                .opacity(Double(assembleProgress))
                .scaleEffect(0.92 + (assembleProgress * 0.08))
            
            if assembleProgress < 1.0 {
                ZStack {
                    ForEach(0..<25, id: \.self) { i in
                        let angle = Double(i) * (Double.pi * 2 / 25.0)
                        let distance = (1.0 - assembleProgress) * 250.0
                        Circle()
                            .fill(i % 2 == 0 ? .cyan : Color.white)
                            .frame(width: 4, height: 4)
                            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                            .shadow(color: .cyan, radius: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) { assembleProgress = 1.0 }
        }
    }
}

// MARK: - 11. 超速違規清單頁面
struct OverspeedLogsView: View {
    @Binding var logs: [OverspeedRecord]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(logs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.date, formatter: dateFormatter).font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                            Text(log.date, formatter: timeFormatter).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.0f km/h", log.speed)).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.red)
                            Text(String(format: "速限: %.0f", log.speedLimit)).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { logs.remove(atOffsets: $0) }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("超速違規紀錄")
        .navigationBarItems(trailing: Button("全部刪除") { logs.removeAll() }.foregroundColor(.red))
    }
    private var dateFormatter: DateFormatter { let df = DateFormatter(); df.dateStyle = .medium; return df }
    private var timeFormatter: DateFormatter { let df = DateFormatter(); df.timeStyle = .medium; return df }
}

// MARK: - 12. 行程歷史封存與軌跡回放頁面
struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(records) { record in
                    NavigationLink(destination: HistoryDetailMapView(record: record)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(record.date, formatter: dateFormatter).font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.2f km", record.tripDistance)).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.green)
                            }
                            HStack(spacing: 20) {
                                VStack(alignment: .leading) {
                                    Text("最高速度").font(.system(size: 10)).foregroundColor(.gray)
                                    Text(String(format: "%.0f", record.maxSpeed)).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.white)
                                }
                                VStack(alignment: .leading) {
                                    Text("0-100加速").font(.system(size: 10)).foregroundColor(.gray)
                                    Text(record.zeroToOneHundredTime > 0 ? String(format: "%.1fs", record.zeroToOneHundredTime) : "---").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.orange)
                                }
                                Spacer()
                                Text("點擊回放軌跡 ➔").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { records.remove(atOffsets: $0) }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("行車歷史封存")
        .navigationBarItems(trailing: Button("全部刪除") { records.removeAll() }.foregroundColor(.red))
    }
    private var dateFormatter: DateFormatter { let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium; return df }
}

// MARK: - 行車軌跡詳細回放畫面
struct HistoryDetailMapView: View {
    let record: HistoryRecord
    
    var body: some View {
        ZStack(alignment: .bottom) {
            InteractiveNavigationMapView(
                coordinate: record.routeCoordinates.first?.coordinate ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
                historyPath: record.routeCoordinates.map { $0.coordinate },
                isInteractive: true,
                onMapTap: { _ in }
            )
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("行程軌跡回放數據").font(.system(size: 14, weight: .bold)).foregroundColor(.cyan)
                HStack {
                    Text("極速: \(Int(record.maxSpeed)) km/h")
                    Spacer()
                    Text("總里程: \(String(format: "%.2f", record.tripDistance)) km")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding()
        }
        .navigationTitle("軌跡地圖回放")
    }
}

// MARK: - 13. 設定選單
struct SettingsView: View {
    @Binding var selectedTheme: DashboardTheme
    @Binding var speedLimit: Double
    @Binding var isHudMode: Bool
    @Binding var useCustomColor: Bool
    @Binding var customColor: Color
    @Binding var isNetworkBoostEnabled: Bool
    
    var body: some View {
        Form {
            Section(header: Text("視覺主題與動態背景")) {
                Picker("主題", selection: $selectedTheme) {
                    ForEach(DashboardTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("啟用自定義霓虹色", isOn: $useCustomColor)
                if useCustomColor {
                    ColorPicker("主色調", selection: $customColor)
                }
            }
            
            Section(header: Text("安全警示")) {
                VStack(alignment: .leading) {
                    Text("速限警告: \(Int(speedLimit)) km/h").font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $speedLimit, in: 40...180, step: 5)
                }
            }
            
            Section(header: Text("導航與定位")) {
                Toggle("網路定位增強", isOn: $isNetworkBoostEnabled)
            }
            
            Section(header: Text("顯示模式")) {
                Toggle("HUD 投影模式 (鏡像反轉)", isOn: $isHudMode)
            }
        }
        .navigationTitle("儀表板設定")
    }
}

// MARK: - 14. 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @State private var isBootLoaded: Bool = false
    
    @AppStorage("selectedTheme") private var storedThemeRaw: String = DashboardTheme.cyberpunk.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120.0
    @AppStorage("isHudMode") private var isHudMode: Bool = false
    @AppStorage("showMap") private var showMap: Bool = false
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    @AppStorage("customColor") private var customColor: Color = Color(red: 0.0, green: 0.8, blue: 1.0)
    @AppStorage("isNetworkBoostEnabled") private var isNetworkBoostEnabled: Bool = false
    
    @AppStorage("overspeedLogsData") private var overspeedLogsData: Data = Data()
    @AppStorage("historyRecordsData") private var historyRecordsData: Data = Data()
    
    @State private var overspeedLogs: [OverspeedRecord] = []
    @State private var historyRecords: [HistoryRecord] = []
    
    @State private var showSettings: Bool = false
    @State private var showOverspeedLogs: Bool = false
    @State private var showHistoryRecords: Bool = false
    @State private var flashWarning: Bool = false
    
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    
    var selectedTheme: DashboardTheme {
        get { DashboardTheme(rawValue: storedThemeRaw) ?? .cyberpunk }
        set { storedThemeRaw = newValue.rawValue }
    }
    
    var currentPrimaryColor: Color {
        selectedTheme.primaryColor(custom: useCustomColor ? customColor : nil)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: selectedTheme.backgroundGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if !isBootLoaded {
                    BootLoadingView(isFinished: $isBootLoaded)
                        .transition(.opacity)
                        .zIndex(20)
                } else {
                    SciFiParticleAssembleView {
                        ZStack {
                            BackgroundNeonFlowView(primaryColor: currentPrimaryColor)
                                .zIndex(0)
                            
                            if flashWarning {
                                Color.red.opacity(0.3)
                                    .ignoresSafeArea()
                                    .animation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: flashWarning)
                                    .zIndex(10)
                            }
                            
                            ZStack(alignment: .top) {
                                if showMap {
                                    ZStack(alignment: .topLeading) {
                                        InteractiveNavigationMapView(
                                            coordinate: vehicleManager.currentLocation,
                                            routePolyline: vehicleManager.routePolyline,
                                            destinationCoordinate: vehicleManager.destinationCoordinate,
                                            isInteractive: true,
                                            onMapTap: { clickedCoord in vehicleManager.setDestination(clickedCoord) }
                                        )
                                        .ignoresSafeArea()
                                        
                                        HStack(alignment: .top, spacing: 12) {
                                            Button(action: { showMap.toggle() }) {
                                                Image(systemName: "gauge.with.needle")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .frame(width: 44, height: 44)
                                                    .background(Color.black.opacity(0.75))
                                                    .foregroundColor(currentPrimaryColor)
                                                    .cornerRadius(22)
                                                    .overlay(Circle().stroke(currentPrimaryColor.opacity(0.8), lineWidth: 2))
                                            }
                                            
                                            if vehicleManager.isNavigating {
                                                Button(action: { vehicleManager.cancelNavigation() }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .frame(width: 44, height: 44)
                                                        .background(Color.red.opacity(0.8))
                                                        .foregroundColor(.white)
                                                        .cornerRadius(22)
                                                        .shadow(color: .red, radius: 4)
                                                }
                                            }
                                            
                                            HStack(spacing: 8) {
                                                Button(action: {
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                        isSearchExpanded.toggle()
                                                    }
                                                }) {
                                                    Image(systemName: "magnifyingglass")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(currentPrimaryColor)
                                                        .frame(width: 44, height: 44)
                                                        .background(Color.black.opacity(0.75))
                                                        .clipShape(Circle())
                                                        .overlay(Circle().stroke(currentPrimaryColor.opacity(0.8), lineWidth: 2))
                                                }
                                                
                                                if isSearchExpanded {
                                                    HStack {
                                                        TextField("搜尋目的地", text: $searchText, onCommit: {
                                                            vehicleManager.searchAndNavigate(query: searchText)
                                                            withAnimation { isSearchExpanded = false }
                                                            searchText = ""
                                                        })
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(.white)
                                                        
                                                        Button(action: {
                                                            vehicleManager.searchAndNavigate(query: searchText)
                                                            withAnimation { isSearchExpanded = false }
                                                            searchText = ""
                                                        }) {
                                                            Text("前往")
                                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                                .padding(.horizontal, 10)
                                                                .padding(.vertical, 6)
                                                                .background(currentPrimaryColor)
                                                                .foregroundColor(.black)
                                                                .cornerRadius(8)
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .frame(width: 210, height: 44)
                                                    .background(Color.black.opacity(0.85))
                                                    .cornerRadius(22)
                                                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(currentPrimaryColor.opacity(0.6), lineWidth: 1))
                                                }
                                            }
                                        }
                                        .padding(.top, 12)
                                        .padding(.leading, 12)
                                    }
                                } else {
                                    HStack(spacing: 15) {
                                        VStack(spacing: 12) {
                                            Button(action: { showMap.toggle() }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "map.fill").font(.system(size: 14))
                                                    Text("地圖").font(.system(size: 8, weight: .bold, design: .monospaced))
                                                }
                                                .frame(width: 52, height: 52)
                                                .background(Color.white.opacity(0.1))
                                                .foregroundColor(.white)
                                                .cornerRadius(12)
                                            }
                                            
                                            Button(action: { vehicleManager.reportMobileSpeedTrap() }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                                                    Text("回報照相").font(.system(size: 8, weight: .bold, design: .monospaced))
                                                }
                                                .frame(width: 52, height: 52)
                                                .background(Color.red.opacity(0.3))
                                                .foregroundColor(.red)
                                                .cornerRadius(12)
                                            }
                                            
                                            Button(action: { showHistoryRecords = true }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "list.bullet.rectangle.portrait.fill").font(.system(size: 14))
                                                    Text("紀錄").font(.system(size: 8, weight: .bold, design: .monospaced))
                                                }
                                                .frame(width: 52, height: 52)
                                                .background(Color.white.opacity(0.1))
                                                .foregroundColor(.white)
                                                .cornerRadius(12)
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                let history = HistoryRecord(
                                                    id: UUID(),
                                                    date: Date(),
                                                    maxSpeed: vehicleManager.maxSpeed,
                                                    zeroToOneHundredTime: vehicleManager.zeroToOneHundredTime,
                                                    maxGForce: vehicleManager.maxGForce,
                                                    tripDistance: vehicleManager.tripDistance,
                                                    routeCoordinates: vehicleManager.recordedPath.map { CodableCoordinate($0) }
                                                )
                                                historyRecords.append(history)
                                                vehicleManager.resetData()
                                            }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 14))
                                                    Text("重置").font(.system(size: 8, weight: .bold, design: .monospaced))
                                                }
                                                .frame(width: 52, height: 52)
                                                .background(Color.orange.opacity(0.2))
                                                .foregroundColor(.orange)
                                                .cornerRadius(12)
                                            }
                                        }
                                        .frame(width: 60)
                                        
                                        ZStack {
                                            NeonArcFlowView(color: currentPrimaryColor, size: 260)
                                            
                                            VStack(spacing: 4) {
                                                Text("GPS SPEED")
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.gray)
                                                    .kerning(2)
                                                
                                                Text(String(format: "%.0f", vehicleManager.speed))
                                                    .font(.system(size: 78, weight: .black, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .shadow(color: currentPrimaryColor.opacity(0.8), radius: 10)
                                                
                                                Text("KM/H")
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundColor(currentPrimaryColor)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        
                                        VStack(spacing: 12) {
                                            MiniMapView(
                                                coordinate: vehicleManager.currentLocation,
                                                routePolyline: vehicleManager.routePolyline,
                                                destinationCoordinate: vehicleManager.destinationCoordinate,
                                                primaryColor: currentPrimaryColor
                                            ) { showMap = true }
                                            
                                            VStack(spacing: 4) {
                                                ShiftLightsView(speed: vehicleManager.speed)
                                                Text("RPM LIGHTS").font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack { Text("距離:").foregroundColor(.gray); Spacer(); Text(String(format: "%.2f km", vehicleManager.tripDistance)).foregroundColor(.green) }
                                                HStack { Text("極速:").foregroundColor(.gray); Spacer(); Text(String(format: "%.0f km/h", vehicleManager.maxSpeed)).foregroundColor(currentPrimaryColor) }
                                            }
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(10)
                                            .background(Color.white.opacity(0.05))
                                            .cornerRadius(10)
                                            
                                            Spacer()
                                        }
                                        .frame(width: 140)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                                
                                if let cameraAlert = vehicleManager.nearestCameraAlert {
                                    HStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.yellow)
                                        Text(cameraAlert)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.9))
                                    .cornerRadius(16)
                                    .shadow(color: .red, radius: 8)
                                    .padding(.top, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .zIndex(50)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea()
            .scaleEffect(x: isHudMode ? -1.0 : 1.0, y: 1.0)
            .onAppear {
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled: isNetworkBoostEnabled)
            }
            .onChange(of: vehicleManager.speed) { newSpeed in
                if newSpeed > speedLimit {
                    if !flashWarning {
                        flashWarning = true
                        AudioServicesPlaySystemSound(1005)
                        overspeedLogs.append(OverspeedRecord(id: UUID(), date: Date(), speed: newSpeed, speedLimit: speedLimit))
                    }
                } else {
                    flashWarning = false
                }
            }
            .background(
                Group {
                    NavigationLink(destination: SettingsView(selectedTheme: Binding(get: { self.selectedTheme }, set: { self.storedThemeRaw = $0.rawValue }), speedLimit: $speedLimit, isHudMode: $isHudMode, useCustomColor: $useCustomColor, customColor: $customColor, isNetworkBoostEnabled: $isNetworkBoostEnabled), isActive: $showSettings) { EmptyView() }
                    NavigationLink(destination: HistoryRecordsView(records: $historyRecords), isActive: $showHistoryRecords) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .ignoresSafeArea()
    }
}
