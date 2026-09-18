import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation

// MARK: - iOS 14 / 15 相容性色彩防護
extension Color {
    static var safeCyan: Color {
        if #available(iOS 15.0, *) { return Color.cyan }
        else { return Color(red: 0.0, green: 0.75, blue: 1.0) }
    }
}

extension UIColor {
    static var safeSystemCyan: UIColor {
        if #available(iOS 15.0, *) { return UIColor.systemCyan }
        else { return UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 1.0) }
    }
}

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

// 駕駛行為評分資料模型
struct DrivingScoreRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let totalScore: Int // 0 - 100 分
    let harshAccelerationCount: Int
    let harshBrakingCount: Int
    let overspeedSeconds: Double
    let tripDistance: Double
    
    var gradeLevel: String {
        switch totalScore {
        case 90...100: return "SSS 級 • 賽道神人"
        case 80..<90:  return "S 級 • 黃金右腳"
        case 70..<80:  return "A 級 • 安全駕駛"
        case 60..<70:  return "B 級 • 普通駕駛"
        default:       return "C 級 • 狂暴飆風者"
        }
    }
}

// 支援雲端 JSON 解碼的測速點模型
struct SpeedCamera: Identifiable, Codable {
    var id: UUID = UUID()
    let latitude: Double
    let longitude: Double
    let speedLimit: Double
    let description: String
    var isTemporary: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, speedLimit, description, isTemporary
    }
    
    init(latitude: Double, longitude: Double, speedLimit: Double, description: String, isTemporary: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedLimit = speedLimit
        self.description = description
        self.isTemporary = isTemporary
    }
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - 2. 佈景主題設定
enum DashboardTheme: String, CaseIterable, Identifiable {
    case skull = "骷髏暴力風"
    case cyberpunk = "賽伯戰爭風"
    case sakura = "日本櫻花風"
    
    var id: String { self.rawValue }
    
    func primaryColor(custom: Color?) -> Color {
        if let custom = custom { return custom }
        switch self {
        case .skull: return .red
        case .cyberpunk: return .safeCyan
        case .sakura: return Color(red: 1.0, green: 0.6, blue: 0.75)
        }
    }
    
    var backgroundGradientColors: [Color] {
        switch self {
        case .skull:
            return [Color(red: 0.1, green: 0.0, blue: 0.0), Color.black, Color(red: 0.05, green: 0.0, blue: 0.0)]
        case .cyberpunk:
            return [Color(red: 0.01, green: 0.02, blue: 0.08), Color.black, Color(red: 0.03, green: 0.0, blue: 0.1)]
        case .sakura:
            return [Color(red: 0.15, green: 0.05, blue: 0.1), Color(red: 0.05, green: 0.02, blue: 0.05), Color(red: 0.02, green: 0.0, blue: 0.02)]
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

// MARK: - 3. 語音播報與多國語系管理器 (Speech Manager)
class SpeechManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var currentLanguage: String = "zh-TW" {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage")
        }
    }
    
    init() {
        if let savedLang = UserDefaults.standard.string(forKey: "AppLanguage") {
            self.currentLanguage = savedLang
        }
    }
    
    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func announceWarning(speedLimit: Int, isOverspeed: Bool) {
        let text: String
        if currentLanguage.starts(with: "zh") {
            if isOverspeed {
                text = "注意，您已超速！前方速限 \(speedLimit) 公里"
            } else {
                text = "前方速限 \(speedLimit) 公里"
            }
        } else {
            if isOverspeed {
                text = "Warning! Speed limit is \(speedLimit). You are speeding!"
            } else {
                text = "Speed limit is \(speedLimit)."
            }
        }
        speak(text)
    }
}

// MARK: - 4. GPS、感應器與測速照相管理器 (含駕駛行為追蹤)
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
    
    // 駕駛行為評分追蹤變數
    @Published var harshAccelerationCount: Int = 0
    @Published var harshBrakingCount: Int = 0
    @Published var overspeedDurationSeconds: Double = 0.0
    private var lastRecordedSpeed: Double = 0.0
    
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
        SpeedCamera(latitude: 25.0330, longitude: 121.5654, speedLimit: 50, description: "台北信義路固定測速"),
        SpeedCamera(latitude: 25.0400, longitude: 121.5700, speedLimit: 60, description: "台北忠孝東路固定測速")
    ]
    
    let speechManager = SpeechManager()
    private var lastSpokenCameraId: UUID? = nil
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
        fetchCamerasFromCloud()
    }
    
    func fetchCamerasFromCloud() {
        guard let url = URL(string: "https://your-server.com/api/cameras.json") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            do {
                let decoded = try JSONDecoder().decode([SpeedCamera].self, from: data)
                DispatchQueue.main.async {
                    self?.speedCameras.append(contentsOf: decoded)
                }
            } catch {
                print("雲端測速點解析失敗: \(error)")
            }
        }.resume()
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
        lastSpokenCameraId = nil
        
        // 重置駕駛行為指標
        harshAccelerationCount = 0
        harshBrakingCount = 0
        overspeedDurationSeconds = 0.0
        lastRecordedSpeed = 0.0
    }
    
    func reportMobileSpeedTrap() {
        let newTrap = SpeedCamera(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude,
            speedLimit: 50,
            description: "⚠️ 用戶回報流動測速/三腳架",
            isTemporary: true
        )
        speedCameras.append(newTrap)
        nearestCameraAlert = "已成功回報流動測速點！"
        AudioServicesPlaySystemSound(1016)
        speechManager.speak(speechManager.currentLanguage.starts(with: "zh") ? "已成功回報流動測速點" : "Mobile speed trap reported")
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
        
        // 駕駛行為檢測：計算急加速與急煞車
        let speedDelta = speedKmh - lastRecordedSpeed
        if speedDelta > 18.0 {
            harshAccelerationCount += 1
        } else if speedDelta < -18.0 {
            harshBrakingCount += 1
        }
        lastRecordedSpeed = speedKmh
        
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
            let cameraLocation = CLLocation(latitude: camera.latitude, longitude: camera.longitude)
            let distance = currentLoc.distance(from: cameraLocation)
            
            if distance <= alertDistance {
                nearestCameraAlert = "\(camera.description) 剩 \(Int(distance))m (速限 \(Int(camera.speedLimit))km)"
                
                if distance <= 300, lastSpokenCameraId != camera.id {
                    lastSpokenCameraId = camera.id
                    let isOverspeed = currentSpeed > camera.speedLimit
                    speechManager.announceWarning(speedLimit: Int(camera.speedLimit), isOverspeed: isOverspeed)
                    
                    if isOverspeed {
                        AudioServicesPlaySystemSound(1007)
                    }
                }
                return
            }
        }
        
        if let lastId = lastSpokenCameraId,
           let camera = speedCameras.first(where: { $0.id == lastId }) {
            let cameraLocation = CLLocation(latitude: camera.latitude, longitude: camera.longitude)
            if currentLoc.distance(from: cameraLocation) > 500 {
                lastSpokenCameraId = nil
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

// MARK: - 5. 三種分類 5 秒開場動畫 + 日本電影警告語
struct MultiThemeBootLoadingView: View {
    @Binding var isFinished: Bool
    @Binding var selectedTheme: DashboardTheme
    
    @State private var step: Int = 0
    @State private var animVal: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if step == 0 {
                Group {
                    if selectedTheme == .skull {
                        VStack(spacing: 16) {
                            Image(systemName: "skull.fill")
                                .font(.system(size: 90))
                                .foregroundColor(.red)
                                .shadow(color: .red, radius: 20)
                                .scaleEffect(animVal)
                            Text("CRIME & SPEED SYNDICATE")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .kerning(4)
                        }
                    } else if selectedTheme == .cyberpunk {
                        VStack(spacing: 16) {
                            Image(systemName: "cpu")
                                .font(.system(size: 90))
                                .foregroundColor(.safeCyan)
                                .shadow(color: .safeCyan, radius: 20)
                                .rotationEffect(.degrees(Double(animVal * 360)))
                            Text("CYBERNETIC WARFARE V.4")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(.safeCyan)
                                .kerning(4)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "flower.tulip.fill")
                                .font(.system(size: 90))
                                .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.8))
                                .shadow(color: .pink, radius: 20)
                                .scaleEffect(animVal)
                            Text("桜吹雪 • 疾走御意見番")
                                .font(.system(size: 22, weight: .black, design: .serif))
                                .foregroundColor(.white)
                                .kerning(6)
                        }
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 20) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(height: 4)
                        .padding(.horizontal, 40)
                    
                    Text("【 警告：劇場型狂暴運転注意 】")
                        .font(.system(size: 20, weight: .black, design: .serif))
                        .foregroundColor(.yellow)
                        .kerning(3)
                    
                    Text("本作品はフィクションであり、実際の公道における\n極端な速度超過や危険運転は法律で厳禁されています。\n安全第一で理性的なドライビングをお楽しみください。")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(height: 4)
                        .padding(.horizontal, 40)
                }
                .transition(.opacity)
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button("SKIP ❯❯") {
                        withAnimation { isFinished = true }
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.trailing, 20)
                    .padding(.top, 40)
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) {
                animVal = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { step = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation { isFinished = true }
            }
        }
    }
}

// MARK: - 6. 櫻花飄落動態背景 (iOS 15+ 防護)
struct SakuraFallingView: View {
    var density: Double
    
    var body: some View {
        if #available(iOS 15.0, *) {
            SakuraFallingContentView(density: density)
        } else {
            EmptyView()
        }
    }
}

@available(iOS 15.0, *)
private struct SakuraFallingContentView: View {
    var density: Double
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let count = Int(density)
                for i in 0..<count {
                    let seed = Double(i) * 99.0
                    let time = timeline.date.timeIntervalSinceReferenceDate + seed
                    let x = (sin(time * 0.5 + seed) * 0.5 + 0.5) * size.width
                    let y = (fmod(time * 30.0 + seed * 50.0, size.height + 50.0)) - 25.0
                    let scale = 0.5 + (sin(seed) * 0.5)
                    
                    context.opacity = 0.75
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 12 * scale, height: 8 * scale)),
                        with: .color(Color(red: 1.0, green: 0.7, blue: 0.85))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - 7. 強化版超跑流光霓虹框
struct BackgroundNeonFlowView: View {
    @State private var isAnimating = false
    var primaryColor: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [primaryColor.opacity(0.2), primaryColor, .white, primaryColor, primaryColor.opacity(0.2)]),
                        center: .center,
                        angle: .degrees(isAnimating ? 360 : 0)
                    ),
                    lineWidth: 12
                )
                .padding(4)
                .shadow(color: primaryColor, radius: 30)
                .shadow(color: primaryColor.opacity(0.6), radius: 10)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(Animation.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - 8. 互動式導航地圖
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
        
        if let polyline = routePolyline { uiView.addOverlay(polyline) }
        
        if let path = historyPath, !path.isEmpty {
            let polyline = MKPolyline(coordinates: path, count: path.count)
            uiView.addOverlay(polyline)
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
                renderer.strokeColor = parent.historyPath != nil ? .systemOrange : .safeSystemCyan
                renderer.lineWidth = 6
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - 9. 動態速度環形儀表板
struct NeonSpeedGaugeRing: View {
    var speed: Double
    var maxDisplaySpeed: Double = 220.0
    var color: Color
    
    var progress: Double {
        return min(max(speed / maxDisplaySpeed, 0.0), 1.0)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 10)
                .frame(width: 270, height: 270)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [color.opacity(0.4), color, .white]), center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 270, height: 270)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
                .shadow(color: color, radius: 10)
            
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(i < Int(progress * 12) ? color : Color.white.opacity(0.2))
                    .frame(width: 3, height: 10)
                    .offset(y: -127)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
    }
}

// MARK: - 10. 專業轉速提示燈
struct ShiftLightsView: View {
    let speed: Double
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(lightColor(for: index))
                    .frame(width: 16, height: 6)
                    .cornerRadius(3)
                    .shadow(color: lightColor(for: index), radius: isLit(index) ? 6 : 0)
            }
        }
    }
    
    private func isLit(_ index: Int) -> Bool { speed >= Double(index + 1) * 25.0 }
    private func lightColor(for index: Int) -> Color {
        guard isLit(index) else { return Color.gray.opacity(0.25) }
        if index < 4 { return .green }
        if index < 6 { return .yellow }
        return .red
    }
}

// MARK: - 11. 內嵌小地圖元件
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
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(primaryColor, lineWidth: 2))
                
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(7)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .padding(8)
            }
        }
        .frame(width: 120, height: 120)
        .shadow(color: primaryColor.opacity(0.5), radius: 8)
    }
}

// MARK: - 12. 駕駛行為結算報告彈窗元件 (Eco/Sport Score Summary)
struct TripScoreSummaryView: View {
    let record: DrivingScoreRecord
    var primaryColor: Color
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🏁 行程表現結算報告")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            
            ZStack {
                Circle()
                    .stroke(primaryColor.opacity(0.3), lineWidth: 10)
                    .frame(width: 130, height: 130)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(Double(record.totalScore) / 100.0))
                    .stroke(primaryColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(record.totalScore)")
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("分")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(primaryColor)
                }
            }
            
            Text(record.gradeLevel)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(primaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(primaryColor.opacity(0.15))
                .cornerRadius(8)
            
            VStack(spacing: 10) {
                ScoreDetailRow(title: "行車總里程", value: String(format: "%.2f km", record.tripDistance))
                ScoreDetailRow(title: "急加速次數", value: "\(record.harshAccelerationCount) 次", isWarning: record.harshAccelerationCount > 3)
                ScoreDetailRow(title: "急煞車次數", value: "\(record.harshBrakingCount) 次", isWarning: record.harshBrakingCount > 3)
                ScoreDetailRow(title: "超速持續時間", value: String(format: "%.1f 秒", record.overspeedDurationSeconds), isWarning: record.overspeedDurationSeconds > 10)
            }
            .padding(.horizontal, 10)
            
            Button(action: onDismiss) {
                Text("確認並存檔")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primaryColor)
                    .cornerRadius(12)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.95))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(primaryColor, lineWidth: 2))
        .shadow(color: primaryColor.opacity(0.5), radius: 20)
        .padding(.horizontal, 30)
    }
}

struct ScoreDetailRow: View {
    let title: String
    let value: String
    var isWarning: Bool = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isWarning ? .red : .white)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - 13. 超速違規與歷史紀錄頁面
struct OverspeedLogsView: View {
    @Binding var logs: [OverspeedRecord]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(logs) { log in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(log.date, formatter: dateFormatter).font(.system(size: 12)).foregroundColor(.gray)
                            Text(String(format: "%.0f km/h", log.speed)).font(.system(size: 16, weight: .black)).foregroundColor(.red)
                        }
                        Spacer()
                        Text("速限: \(Int(log.speedLimit))").foregroundColor(.gray)
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { logs.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("超速違規紀錄")
    }
    private var dateFormatter: DateFormatter { let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium; return df }
}

struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(records) { record in
                    NavigationLink(destination: HistoryDetailMapView(record: record)) {
                        VStack(alignment: .leading) {
                            Text(record.date, formatter: dateFormatter).font(.system(size: 12)).foregroundColor(.gray)
                            Text(String(format: "極速: %.0f km/h | 里程: %.2f km", record.maxSpeed, record.tripDistance))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { records.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("行車歷史封存")
    }
    private var dateFormatter: DateFormatter { let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium; return df }
}

struct HistoryDetailMapView: View {
    let record: HistoryRecord
    var body: some View {
        InteractiveNavigationMapView(
            coordinate: record.routeCoordinates.first?.coordinate ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            historyPath: record.routeCoordinates.map { $0.coordinate },
            isInteractive: true,
            onMapTap: { _ in }
        )
        .ignoresSafeArea()
        .navigationTitle("軌跡回放")
    }
}

// MARK: - 14. 設定選單
struct SettingsView: View {
    @ObservedObject var speechManager: SpeechManager
    @Binding var selectedTheme: DashboardTheme
    @Binding var speedLimit: Double
    @Binding var isHudMode: Bool
    @Binding var useCustomColor: Bool
    @Binding var customColor: Color
    @Binding var isNetworkBoostEnabled: Bool
    @Binding var simulatedSpeed: Double
    @Binding var enableSakuraBackground: Bool
    @Binding var sakuraDensity: Double
    
    var body: some View {
        Form {
            Section(header: Text("語音播報與多國語系 (i18n)")) {
                Picker("語音語言 (Voice Language)", selection: $speechManager.currentLanguage) {
                    Text("繁體中文 (Traditional Chinese)").tag("zh-TW")
                    Text("English (英文)").tag("en-US")
                    Text("日本語 (日文)").tag("ja-JP")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Button(action: {
                    speechManager.announceWarning(speedLimit: 60, isOverspeed: true)
                }) {
                    Text("測試語音播報效果")
                        .foregroundColor(.blue)
                }
            }
            
            Section(header: Text("視覺主題與風格")) {
                Picker("佈景主題", selection: $selectedTheme) {
                    ForEach(DashboardTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("啟用自定義霓虹色", isOn: $useCustomColor)
                if useCustomColor {
                    ColorPicker("自定義主色調", selection: $customColor)
                }
            }
            
            if selectedTheme == .sakura {
                Section(header: Text("日本櫻花風動態背景設定")) {
                    Toggle("啟用主畫面櫻花飄落背景", isOn: $enableSakuraBackground)
                    if enableSakuraBackground {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("櫻花飄落密度: \(Int(sakuraDensity)) 片").font(.system(size: 13, weight: .bold))
                            Slider(value: $sakuraDensity, in: 5...50, step: 5)
                        }
                    }
                }
            }
            
            Section(header: Text("模擬速度測試（用於即時畫面測試）")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("模擬車速: \(Int(simulatedSpeed)) km/h").font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $simulatedSpeed, in: 0...220, step: 5)
                }
            }
            
            Section(header: Text("速限與警告設定")) {
                VStack(alignment: .leading) {
                    Text("超速警告閾值: \(Int(speedLimit)) km/h").font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $speedLimit, in: 10...180, step: 5)
                }
            }
            
            Section(header: Text("導航與定位")) {
                Toggle("網路定位增強精確度", isOn: $isNetworkBoostEnabled)
            }
            
            Section(header: Text("顯示模式")) {
                Toggle("HUD 投影模式 (鏡像反轉)", isOn: $isHudMode)
            }
        }
        .navigationTitle("儀表板設定")
    }
}

// MARK: - 15. 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @State private var isBootLoaded: Bool = false
    
    @AppStorage("selectedTheme") private var storedThemeRaw: String = DashboardTheme.sakura.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120.0
    @AppStorage("isHudMode") private var isHudMode: Bool = false
    @AppStorage("showMap") private var showMap: Bool = false
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    @AppStorage("customColor") private var customColor: Color = Color(red: 1.0, green: 0.6, blue: 0.75)
    @AppStorage("isNetworkBoostEnabled") private var isNetworkBoostEnabled: Bool = false
    
    @AppStorage("enableSakuraBackground") private var enableSakuraBackground: Bool = true
    @AppStorage("sakuraDensity") private var sakuraDensity: Double = 20.0
    
    @State private var overspeedLogs: [OverspeedRecord] = []
    @State private var historyRecords: [HistoryRecord] = []
    
    @State private var showSettings: Bool = false
    @State private var showOverspeedLogs: Bool = false
    @State private var showHistoryRecords: Bool = false
    @State private var flashWarning: Bool = false
    
    @State private var simulatedSpeed: Double = 0.0
    
    @State private var showJapaneseOverspeedAlert: Bool = false
    @State private var overspeedTimer: Timer? = nil
    
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    
    // 駕駛行為結算彈窗狀態
    @State private var latestTripScoreRecord: DrivingScoreRecord? = nil
    
    var effectiveSpeed: Double {
        return simulatedSpeed > 0 ? simulatedSpeed : vehicleManager.speed
    }
    
    var selectedTheme: DashboardTheme {
        get { DashboardTheme(rawValue: storedThemeRaw) ?? .sakura }
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
                .ignoresSafeArea(.all, edges: .all)
                
                if selectedTheme == .sakura && enableSakuraBackground {
                    SakuraFallingView(density: sakuraDensity)
                        .zIndex(1)
                }
                
                if !isBootLoaded {
                    MultiThemeBootLoadingView(
                        isFinished: $isBootLoaded,
                        selectedTheme: Binding(
                            get: { self.selectedTheme },
                            set: { self.storedThemeRaw = $0.rawValue }
                        )
                    )
                    .transition(.opacity)
                    .zIndex(50)
                } else {
                    ZStack {
                        BackgroundNeonFlowView(primaryColor: currentPrimaryColor)
                            .zIndex(0)
                        
                        if flashWarning {
                            Color.red.opacity(0.35)
                                .ignoresSafeArea()
                                .zIndex(10)
                        }
                        
                        // 駕駛行為結算彈窗
                        if let scoreRecord = latestTripScoreRecord {
                            Color.black.opacity(0.85)
                                .ignoresSafeArea()
                                .zIndex(100)
                            
                            TripScoreSummaryView(record: scoreRecord, primaryColor: currentPrimaryColor) {
                                latestTripScoreRecord = nil
                            }
                            .zIndex(101)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        if showJapaneseOverspeedAlert {
                            VStack {
                                Spacer()
                                VStack(spacing: 6) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: 20))
                                        Text("オービス警報発動")
                                            .font(.system(size: 16, weight: .black, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    Text("速度超過です！減速してください！")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(Color.black.opacity(0.92))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 2))
                                .cornerRadius(12)
                                .shadow(color: .red.opacity(0.9), radius: 12)
                                .padding(.bottom, 60)
                            }
                            .zIndex(60)
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
                                    .ignoresSafeArea(.all, edges: .all)
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Button(action: { showMap.toggle() }) {
                                            Image(systemName: "gauge.with.needle")
                                                .font(.system(size: 16, weight: .bold))
                                                .frame(width: 44, height: 44)
                                                .background(Color.black.opacity(0.8))
                                                .foregroundColor(currentPrimaryColor)
                                                .cornerRadius(22)
                                                .overlay(Circle().stroke(currentPrimaryColor, lineWidth: 2))
                                        }
                                        
                                        if vehicleManager.isNavigating {
                                            Button(action: { vehicleManager.cancelNavigation() }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .frame(width: 44, height: 44)
                                                    .background(Color.red.opacity(0.85))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(22)
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
                                                    .background(Color.black.opacity(0.8))
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(currentPrimaryColor, lineWidth: 2))
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
                                                .background(Color.black.opacity(0.9))
                                                .cornerRadius(22)
                                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(currentPrimaryColor, lineWidth: 1))
                                            }
                                        }
                                    }
                                    .padding(.top, 24)
                                    .padding(.leading, 24)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    VStack(spacing: 10) {
                                        Button(action: { showMap.toggle() }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "map.fill").font(.system(size: 14))
                                                Text("地圖").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.white.opacity(0.12))
                                            .foregroundColor(.white)
                                            .cornerRadius(14)
                                        }
                                        
                                        Button(action: { showSettings = true }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "gearshape.fill").font(.system(size: 14))
                                                Text("設定").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.white.opacity(0.12))
                                            .foregroundColor(currentPrimaryColor)
                                            .cornerRadius(14)
                                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(currentPrimaryColor.opacity(0.6), lineWidth: 1))
                                        }
                                        
                                        Button(action: { vehicleManager.reportMobileSpeedTrap() }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                                                Text("回報").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.red.opacity(0.35))
                                            .foregroundColor(.red)
                                            .cornerRadius(14)
                                        }
                                        
                                        Button(action: { showHistoryRecords = true }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "list.bullet.rectangle.portrait.fill").font(.system(size: 14))
                                                Text("紀錄").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.white.opacity(0.12))
                                            .foregroundColor(.white)
                                            .cornerRadius(14)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            // 計算評分演算法
                                            var baseScore = 100
                                            baseScore -= (vehicleManager.harshAccelerationCount * 5)
                                            baseScore -= (vehicleManager.harshBrakingCount * 5)
                                            baseScore -= Int(vehicleManager.overspeedDurationSeconds)
                                            let finalScore = max(baseScore, 0)
                                            
                                            let scoreRecord = DrivingScoreRecord(
                                                id: UUID(),
                                                date: Date(),
                                                totalScore: finalScore,
                                                harshAccelerationCount: vehicleManager.harshAccelerationCount,
                                                harshBrakingCount: vehicleManager.harshBrakingCount,
                                                overspeedDurationSeconds: vehicleManager.overspeedDurationSeconds,
                                                tripDistance: vehicleManager.tripDistance
                                            )
                                            
                                            // 儲存行車歷史
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
                                            
                                            // 彈出評分結算畫面
                                            withAnimation {
                                                latestTripScoreRecord = scoreRecord
                                            }
                                            
                                            vehicleManager.resetData()
                                            simulatedSpeed = 0.0
                                        }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 14))
                                                Text("重置").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.orange.opacity(0.25))
                                            .foregroundColor(.orange)
                                            .cornerRadius(14)
                                        }
                                    }
                                    .frame(width: 54)
                                    
                                    ZStack {
                                        NeonSpeedGaugeRing(speed: effectiveSpeed, color: currentPrimaryColor)
                                        
                                        VStack(spacing: 4) {
                                            Text(simulatedSpeed > 0 ? "SIMULATED SPEED" : "GPS SPEED")
                                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                                .foregroundColor(simulatedSpeed > 0 ? .orange : .gray)
                                                .kerning(2)
                                            
                                            Text(String(format: "%.0f", effectiveSpeed))
                                                .font(.system(size: 78, weight: .black, design: .monospaced))
                                                .foregroundColor(.white)
                                                .shadow(color: currentPrimaryColor, radius: 12)
                                            
                                            Text("KM/H")
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                                            ShiftLightsView(speed: effectiveSpeed)
                                            Text("RPM SHIFT LIGHTS").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack { Text("里程:").foregroundColor(.gray); Spacer(); Text(String(format: "%.2f km", vehicleManager.tripDistance)).foregroundColor(.green) }
                                            HStack { Text("極速:").foregroundColor(.gray); Spacer(); Text(String(format: "%.0f km/h", max(vehicleManager.maxSpeed, simulatedSpeed))).foregroundColor(currentPrimaryColor) }
                                            HStack { Text("急加速:").foregroundColor(.gray); Spacer(); Text("\(vehicleManager.harshAccelerationCount) 次").foregroundColor(.orange) }
                                            HStack { Text("急煞車:").foregroundColor(.gray); Spacer(); Text("\(vehicleManager.harshBrakingCount) 次").foregroundColor(.red) }
                                        }
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(8)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                        
                                        Spacer()
                                    }
                                    .frame(width: 135)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }
                            
                            if let cameraAlert = vehicleManager.nearestCameraAlert {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.yellow)
                                    Text(cameraAlert)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.red.opacity(0.92))
                                .cornerRadius(16)
                                .shadow(color: .red, radius: 10)
                                .padding(.top, 16)
                                .zIndex(50)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(.all, edges: .all)
            .scaleEffect(x: isHudMode ? -1.0 : 1.0, y: 1.0)
            .onAppear {
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled: isNetworkBoostEnabled)
            }
            .onChange(of: effectiveSpeed) { newSpeed in
                if newSpeed > speedLimit {
                    flashWarning = true
                    AudioServicesPlaySystemSound(1005)
                    overspeedLogs.append(OverspeedRecord(id: UUID(), date: Date(), speed: newSpeed, speedLimit: speedLimit))
                    
                    // 累計超速秒數（每次觸發 onChange 計算約 1 秒）
                    vehicleManager.overspeedDurationSeconds += 1.0
                    
                    overspeedTimer?.invalidate()
                    withAnimation {
                        showJapaneseOverspeedAlert = true
                    }
                    
                    overspeedTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { _ in
                        withAnimation {
                            showJapaneseOverspeedAlert = false
                        }
                    }
                } else {
                    flashWarning = false
                }
            }
            .background(
                Group {
                    NavigationLink(destination: SettingsView(
                        speechManager: vehicleManager.speechManager,
                        selectedTheme: Binding(get: { self.selectedTheme }, set: { self.storedThemeRaw = $0.rawValue }),
                        speedLimit: $speedLimit,
                        isHudMode: $isHudMode,
                        useCustomColor: $useCustomColor,
                        customColor: $customColor,
                        isNetworkBoostEnabled: $isNetworkBoostEnabled,
                        simulatedSpeed: $simulatedSpeed,
                        enableSakuraBackground: $enableSakuraBackground,
                        sakuraDensity: $sakuraDensity
                    ), isActive: $showSettings) { EmptyView() }
                    NavigationLink(destination: HistoryRecordsView(records: $historyRecords), isActive: $showHistoryRecords) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .ignoresSafeArea(.all, edges: .all)
    }
}
