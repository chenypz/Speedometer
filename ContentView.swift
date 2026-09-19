import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation
import UIKit

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

// MARK: - [新增] 動態模糊與 120Hz 順暢化模組 (Metal GPU 加速)
struct DynamicMotionBlurModifier: ViewModifier {
    var isEnabled: Bool
    var intensity: CGFloat // 根據速度動態決定模糊與殘影程度

    func body(content: Content) -> some View {
        if isEnabled && intensity > 0 {
            ZStack {
                // 殘影層 1 (向外擴展 + 模糊)
                content
                    .opacity(0.35 * Double(intensity))
                    .scaleEffect(1.0 + (intensity * 0.025))
                    .blur(radius: intensity * 3.0)
                    .offset(x: -intensity * 3, y: intensity * 2)
                
                // 殘影層 2 (反向錯位)
                content
                    .opacity(0.2 * Double(intensity))
                    .scaleEffect(1.0 + (intensity * 0.015))
                    .blur(radius: intensity * 5.0)
                    .offset(x: intensity * 4, y: -intensity * 2)

                // 主體層
                content
            }
            // 啟用 Metal GPU 渲染，大幅降低 iPhone 11 CPU 負擔，防止掉幀
            .drawingGroup() 
        } else {
            content
        }
    }
}

extension View {
    func dynamicMotionBlur(isEnabled: Bool, intensity: CGFloat) -> some View {
        self.modifier(DynamicMotionBlurModifier(isEnabled: isEnabled, intensity: intensity))
    }
    
    // 單純開啟 Metal 加速，用於靜態但複雜的向量圖形
    func metalAcceleration(isEnabled: Bool = true) -> some View {
        Group {
            if isEnabled { self.drawingGroup() }
            else { self }
        }
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
        case .sakura: return Color(red: 1.0, green: 0.3, blue: 0.4)
        }
    }
    
    var backgroundGradientColors: [Color] {
        switch self {
        case .skull:
            return [Color(red: 0.2, green: 0.0, blue: 0.0), Color.black, Color(red: 0.1, green: 0.0, blue: 0.02)]
        case .cyberpunk:
            return [Color(red: 0.01, green: 0.05, blue: 0.18), Color.black, Color(red: 0.05, green: 0.0, blue: 0.15)]
        case .sakura:
            return [Color(red: 0.15, green: 0.02, blue: 0.05), Color(red: 0.04, green: 0.01, blue: 0.03), Color.black]
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

// MARK: - 動態流動背景元件
struct AnimatedBackgroundView: View {
    var themeColors: [Color]
    var primaryColor: Color
    
    @State private var startPoint = UnitPoint(x: 0, y: 0)
    @State private var endPoint = UnitPoint(x: 1, y: 1)
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            LinearGradient(colors: themeColors, startPoint: startPoint, endPoint: endPoint)
                .ignoresSafeArea(.all, edges: .all)
            
            RadialGradient(
                gradient: Gradient(colors: [primaryColor.opacity(0.25), .clear]),
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .scaleEffect(pulseScale)
            .blur(radius: 30)
            .ignoresSafeArea(.all, edges: .all)
        }
        .metalAcceleration() // 加入 GPU 加速
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                startPoint = UnitPoint(x: 1, y: 0)
                endPoint = UnitPoint(x: 0, y: 1)
            }
            withAnimation(Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.35
            }
        }
    }
}

// MARK: - 3. 語音播報管理器
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

// MARK: - 4. GPS & 感應器管理器
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
    
    @Published var zeroTo100mTime: Double = 0.0
    @Published var isTesting0_100m: Bool = false
    private var distanceStartTime: Date? = nil
    private var startLocationFor100m: CLLocation? = nil
    private var hasReached100m: Bool = false
    
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
    
    @Published var speechManager = SpeechManager()
    
    private var lastSpokenCameraId: UUID? = nil
    private var lastLocation: CLLocation? = nil
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1.0
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
        
        zeroTo100mTime = 0.0
        isTesting0_100m = false
        hasReached100m = false
        distanceStartTime = nil
        startLocationFor100m = nil
        
        lastLocation = nil
        recordedPath.removeAll()
        lastSpokenCameraId = nil
        
        harshAccelerationCount = 0
        harshBrakingCount = 0
        overspeedDurationSeconds = 0.0
        lastRecordedSpeed = 0.0
    }
    
    func addCurrentLocationAsCamera(speedLimit: Double, description: String) {
        let newCam = SpeedCamera(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude,
            speedLimit: speedLimit,
            description: description.isEmpty ? "⚠️ 手動回報測速點" : description,
            isTemporary: true
        )
        speedCameras.append(newCam)
        nearestCameraAlert = "已成功加入目前測速點！"
        AudioServicesPlaySystemSound(1016)
        speechManager.speak("已成功加入目前測速點")
    }
    
    func removeNearestCamera() {
        guard let currentLoc = lastLocation else {
            speechManager.speak("目前沒有定位資訊")
            return
        }
        
        if let index = speedCameras.firstIndex(where: { camera in
            let camLoc = CLLocation(latitude: camera.latitude, longitude: camera.longitude)
            return currentLoc.distance(from: camLoc) <= 150.0
        }) {
            let removedCam = speedCameras.remove(at: index)
            nearestCameraAlert = "已移除最近測速點：\(removedCam.description)"
            AudioServicesPlaySystemSound(1016)
            speechManager.speak("已移除最近測速點")
        } else {
            nearestCameraAlert = "附近 150 公尺內沒有測速點可移除"
            speechManager.speak("附近沒有找到可移除的測速點")
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
        // 透過 SwiftUI Animation 讓速度變動平滑化，不卡頓
        withAnimation(.easeOut(duration: 0.3)) {
            self.speed = speedKmh
        }
        
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
        
        if speedKmh < 3 && !isTesting0_100m && !hasReached100m {
            isTesting0_100m = true
            distanceStartTime = Date()
            startLocationFor100m = newLocation
            zeroTo100mTime = 0.0
            hasReached100m = false
        } else if isTesting0_100m, let startLoc = startLocationFor100m, let startTime = distanceStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let distanceCovered = newLocation.distance(from: startLoc)
            zeroTo100mTime = elapsed
            if distanceCovered >= 100.0 {
                isTesting0_100m = false
                hasReached100m = true
            } else if elapsed > 30.0 {
                isTesting0_100m = false
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
        
        if nearestCameraAlert?.contains("已成功") == false && nearestCameraAlert?.contains("已移除") == false {
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

// MARK: - 5. 日式大威嚴神獸白狐向量繪圖（帶有紅色領巾與項圈）
struct MajesticWhiteFoxFaceView: View {
    var body: some View {
        ZStack {
            // 背景靈氣微光
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [Color.red.opacity(0.4), .clear]), center: .center, startRadius: 10, endRadius: 160))
                .frame(width: 320, height: 320)
            
            // 左耳外廓
            Path { path in
                path.move(to: CGPoint(x: 100, y: 150))
                path.addLine(to: CGPoint(x: 10, y: 10))
                path.addLine(to: CGPoint(x: 120, y: 80))
                path.closeSubpath()
            }
            .fill(Color.white)
            .shadow(color: .red, radius: 8)
            
            // 右耳外廓
            Path { path in
                path.move(to: CGPoint(x: 200, y: 150))
                path.addLine(to: CGPoint(x: 290, y: 10))
                path.addLine(to: CGPoint(x: 180, y: 80))
                path.closeSubpath()
            }
            .fill(Color.white)
            .shadow(color: .red, radius: 8)
            
            // 耳內暗紅紋路
            Path { path in
                path.move(to: CGPoint(x: 90, y: 120))
                path.addLine(to: CGPoint(x: 35, y: 35))
                path.addLine(to: CGPoint(x: 110, y: 85))
                path.closeSubpath()
            }
            .fill(Color(red: 0.7, green: 0.0, blue: 0.1))
            
            Path { path in
                path.move(to: CGPoint(x: 210, y: 120))
                path.addLine(to: CGPoint(x: 265, y: 35))
                path.addLine(to: CGPoint(x: 190, y: 85))
                path.closeSubpath()
            }
            .fill(Color(red: 0.7, green: 0.0, blue: 0.1))
            
            // 狐狸面部主輪廓
            Path { path in
                path.move(to: CGPoint(x: 150, y: 280)) // 下巴
                path.addLine(to: CGPoint(x: 40, y: 130))  // 左頰
                path.addLine(to: CGPoint(x: 90, y: 110))  // 左額
                path.addLine(to: CGPoint(x: 150, y: 140)) // 額頭中心
                path.addLine(to: CGPoint(x: 210, y: 110)) // 右額
                path.addLine(to: CGPoint(x: 260, y: 130)) // 右頰
                path.closeSubpath()
            }
            .fill(Color(red: 0.98, green: 0.98, blue: 1.0))
            .shadow(color: .white, radius: 12)
            
            // 威嚴紅瞳 (左)
            Ellipse()
                .fill(Color(red: 0.9, green: 0.1, blue: 0.2))
                .frame(width: 42, height: 18)
                .rotationEffect(.degrees(28))
                .position(x: 105, y: 165)
                .shadow(color: .red, radius: 10)
            
            // 威嚴紅瞳 (右)
            Ellipse()
                .fill(Color(red: 0.9, green: 0.1, blue: 0.2))
                .frame(width: 42, height: 18)
                .rotationEffect(.degrees(-28))
                .position(x: 195, y: 165)
                .shadow(color: .red, radius: 10)
            
            // 金黃瞳孔
            Circle().fill(Color.yellow).frame(width: 6, height: 6).position(x: 108, y: 163)
            Circle().fill(Color.yellow).frame(width: 6, height: 6).position(x: 192, y: 163)
            
            // 臉頰日式狐狸面具紅色印紋
            Path { path in
                path.move(to: CGPoint(x: 65, y: 180))
                path.addQuadCurve(to: CGPoint(x: 95, y: 200), control: CGPoint(x: 80, y: 170))
                path.move(to: CGPoint(x: 235, y: 180))
                path.addQuadCurve(to: CGPoint(x: 205, y: 200), control: CGPoint(x: 220, y: 170))
            }
            .stroke(Color.red, lineWidth: 5)
            
            // 脖子傳統紅色繩結與飾帶
            Path { path in
                path.move(to: CGPoint(x: 80, y: 250))
                path.addQuadCurve(to: CGPoint(x: 220, y: 250), control: CGPoint(x: 150, y: 290))
            }
            .stroke(Color(red: 0.8, green: 0.0, blue: 0.1), lineWidth: 16)
            
            Circle()
                .fill(Color.yellow)
                .frame(width: 22, height: 22)
                .position(x: 150, y: 272)
                .shadow(color: .orange, radius: 6)
        }
        .frame(width: 300, height: 320)
        .metalAcceleration() // 向量圖 GPU 渲染優化
    }
}

// MARK: - 6. 三種風格獨立開場動畫
struct MultiThemeBootLoadingView: View {
    @Binding var isFinished: Bool
    @Binding var selectedTheme: DashboardTheme

    enum BootTheme {
        case skull
        case cyberpunk
        case sakura
    }

    private var theme: BootTheme {
        switch selectedTheme {
        case .skull: return .skull
        case .cyberpunk: return .cyberpunk
        case .sakura: return .sakura
        }
    }

    @State private var bootStep = 0
    @State private var rotation: Double = 0
    @State private var speed: CGFloat = 0
    @State private var logoScale: CGFloat = 0.72
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 12
    @State private var flashOpacity: Double = 0
    @State private var shake: CGFloat = 0
    @State private var ringScale: CGFloat = 0.25
    @State private var ringOpacity: Double = 0
    @State private var scanOffset: CGFloat = 0
    @State private var pulse = false
    @State private var particleProgress: CGFloat = 0
    @State private var showParticles = false
    @State private var didStart = false

    private var themeColor: Color {
        switch theme {
        case .skull: return .red
        case .cyberpunk: return .safeCyan
        case .sakura: return .red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                switch theme {
                case .skull:
                    skullBoot(in: geo.size)
                case .cyberpunk:
                    cyberBoot(in: geo.size)
                case .sakura:
                    sakuraBoot(in: geo.size)
                }

                ScanlineOverlay(color: themeColor, offset: scanOffset)
                    .allowsHitTesting(false)

                if flashOpacity > 0 {
                    Rectangle()
                        .fill(Color.white)
                        .opacity(flashOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if showParticles {
                    BootParticlesView(
                        color: themeColor,
                        progress: particleProgress
                    )
                    .allowsHitTesting(false)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button("SKIP") {
                            finishBoot()
                        }
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(themeColor.opacity(0.5), lineWidth: 1)
                        )
                        .padding(.top, 18)
                        .padding(.trailing, 18)
                    }
                    Spacer()
                }
            }
            .offset(x: shake)
            .onAppear {
                guard !didStart else { return }
                didStart = true
                startBoot()
            }
        }
    }

    // MARK: Skull
    @ViewBuilder
    private func skullBoot(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, .red, .white, .red, .clear]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: min(size.width, size.height) * 0.68)
                .rotationEffect(.degrees(rotation))
                .opacity(0.75)

            Circle()
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
                .frame(width: min(size.width, size.height) * 0.86)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            Image(systemName: "skull.fill")
                .font(.system(size: min(size.width, size.height) * 0.20, weight: .black))
                .foregroundColor(.white)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .blur(radius: logoBlur)

            VStack(spacing: 5) {
                Spacer().frame(height: min(size.width, size.height) * 0.43)
                Text("CHEN")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(9)
                Text("SYSTEM ONLINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.red)
            }
            .opacity(logoOpacity)
        }
    }

    // MARK: Cyberpunk
    @ViewBuilder
    private func cyberBoot(in size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, .safeCyan, .white, .safeCyan, .clear]),
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(
                    width: min(size.width * 0.82, 430),
                    height: min(size.height * 0.54, 420)
                )
                .rotationEffect(.degrees(rotation * 0.45))
                .opacity(0.8)

            VStack(spacing: 12) {
                Text("CHEN // DRIVE")
                    .font(.system(size: 29, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.safeCyan)

                Text("NEURAL VEHICLE INTERFACE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.6))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .safeCyan, .white, .safeCyan, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(size.width * 0.68, 330), height: 2)
                    .scaleEffect(x: 0.4 + speed * 0.6, y: 1)

                HStack(spacing: 20) {
                    metric("BOOST", "MAX")
                    metric("RADAR", "ONLINE")
                    metric("GPS", "LOCK")
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
            .blur(radius: logoBlur)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.safeCyan)
        }
    }

    // MARK: Sakura / Racing
    @ViewBuilder
    private func sakuraBoot(in size: CGSize) -> some View {
        ZStack {
            RacingSpeedLines(
                color: .red,
                progress: speed,
                intensity: bootStep >= 2 ? 1 : 0.45
            )

            // 黑底紅框警示面板
            if bootStep <= 1 {
                VStack(spacing: 10) {
                    Text("⚠ WARNING")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(.red)

                    Text("極速領域")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(5)

                    Text("超速走行禁止")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .tracking(4)

                    Text("AUTOMATIC SPEED RADAR ACTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(2)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(pulse ? 1 : 0.38), lineWidth: pulse ? 3 : 1)
                        )
                )
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .blur(radius: logoBlur)
            }

            // 狐狸 Logo：從高速模糊中衝出，避免放大裁切
            if bootStep == 2 {
                ZStack {
                    Circle()
                        .stroke(Color.red.opacity(0.8), lineWidth: 2)
                        .frame(width: min(size.width * 0.66, 360))
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    MajesticWhiteFoxFaceView()
                        .frame(
                            width: min(size.width * 0.64, 330),
                            height: min(size.width * 0.64, 330)
                        )
                        .scaleEffect(1.0 + speed * 0.035)
                        .opacity(logoOpacity)
                        .blur(radius: logoBlur)
                        .shadow(color: .red.opacity(0.75), radius: 22)
                }

                VStack {
                    Spacer()
                    Text("CHEN")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(10)
                        .foregroundColor(.white)

                    Text("EXTREME MODE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .foregroundColor(.red)
                        .padding(.top, 3)
                        .padding(.bottom, 55)
                }
                .opacity(logoOpacity)
            }

            // 最後一拍：Logo → 系統啟動
            if bootStep >= 3 {
                VStack(spacing: 9) {
                    Text("SYSTEM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .foregroundColor(.red.opacity(0.8))

                    Text("全系統啟動")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Capsule().fill(Color.red).frame(width: 34, height: 3)
                        Capsule().fill(Color.white).frame(width: 34, height: 3)
                        Capsule().fill(Color.red).frame(width: 34, height: 3)
                    }

                    Text("DRIVE • RADAR • GPS • PERFORMANCE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(2)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .blur(radius: logoBlur)
            }
        }
    }

    // MARK: Finish
    private func finishBoot() {
        withAnimation(.easeOut(duration: 0.32)) {
            isFinished = true
        }
    }

    // MARK: Animation
    private func startBoot() {
        bootStep = 0
        speed = 0
        logoScale = 0.72
        logoOpacity = 0
        logoBlur = 12
        flashOpacity = 0
        shake = 0
        ringScale = 0.25
        ringOpacity = 0
        scanOffset = 0
        pulse = false
        particleProgress = 0
        showParticles = false

        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: true)) {
            scanOffset = 1
        }

        withAnimation(.easeInOut(duration: 0.24).repeatForever(autoreverses: true)) {
            pulse = true
        }

        // 第一拍：黑底警示
        withAnimation(.easeOut(duration: 0.38)) {
            logoOpacity = 1
            logoScale = 1.0
            logoBlur = 0
        }

        // 第二拍：加速、紅色速度線
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(.easeIn(duration: 0.28)) {
                speed = 1
            }
        }

        if theme == .sakura {
            // 0.95s：狐狸高速衝入
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                bootStep = 2
                ringScale = 1.0
                ringOpacity = 1
                logoScale = 1.0
                logoOpacity = 0
                logoBlur = 18

                withAnimation(.easeOut(duration: 0.24)) {
                    logoOpacity = 1
                    logoBlur = 0
                    ringScale = 1.18
                    ringOpacity = 0
                }

                // 模擬高速鏡頭震動
                withAnimation(.easeOut(duration: 0.06)) {
                    shake = -7
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.06)) {
                        shake = 6
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.08)) {
                        shake = -3
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    withAnimation(.easeOut(duration: 0.10)) {
                        shake = 0
                    }
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    flashOpacity = 0.8
                }
                withAnimation(.easeIn(duration: 0.28).delay(0.05)) {
                    flashOpacity = 0
                }
            }

            // 2.0s：Logo 短暫定格後進入系統
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    bootStep = 3
                    logoScale = 0.92
                    logoOpacity = 1
                    logoBlur = 0
                    speed = 0.25
                }
            }

            // 2.55s：紅色爆閃 + 粒子
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) {
                showParticles = true
                particleProgress = 0

                withAnimation(.easeOut(duration: 0.12)) {
                    flashOpacity = 1
                    shake = 4
                }
                withAnimation(.easeIn(duration: 0.34).delay(0.02)) {
                    flashOpacity = 0
                    shake = 0
                }
                withAnimation(.easeOut(duration: 0.55)) {
                    particleProgress = 1
                }
            }

            // 3.15s：淡出後進主畫面
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.15) {
                withAnimation(.easeIn(duration: 0.32)) {
                    logoOpacity = 0
                    logoBlur = 8
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.48) {
                finishBoot()
            }
        } else {
            // 其他兩個主題維持短版高速啟動
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    logoScale = 1.04
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.15) {
                withAnimation(.easeIn(duration: 0.24)) {
                    flashOpacity = 0.85
                    logoOpacity = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.43) {
                finishBoot()
            }
        }
    }
}

// MARK: - 掃描線
private struct ScanlineOverlay: View {
    let color: Color
    let offset: CGFloat

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<80, id: \.self) { _ in
                    Rectangle()
                        .fill(color.opacity(0.045))
                        .frame(height: 1)
                    Spacer(minLength: 7)
                }
            }
            .offset(y: offset * geo.size.height)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

// MARK: - 賽車高速線
private struct RacingSpeedLines: View {
    let color: Color
    let progress: CGFloat
    let intensity: CGFloat

    private let lines: [SpeedLine] = (0..<34).map { i in
        let x = CGFloat((i * 37) % 100) / 100.0
        let y = CGFloat((i * 61) % 100) / 100.0
        let length = CGFloat(70 + ((i * 29) % 150))
        let thickness = CGFloat(1 + (i % 3))
        let delay = CGFloat((i * 17) % 100) / 100.0
        return SpeedLine(x: x, y: y, length: length, thickness: thickness, delay: delay)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(lines) { line in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    color.opacity(0.18 * intensity),
                                    color.opacity(0.9 * intensity),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: line.length, height: line.thickness)
                        .position(
                            x: geo.size.width * line.x,
                            y: geo.size.height * (line.y + progress * (0.25 + line.delay * 0.35))
                        )
                        .rotationEffect(.degrees(-8))
                        .blur(radius: 0.4)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private struct SpeedLine: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let length: CGFloat
        let thickness: CGFloat
        let delay: CGFloat
    }
}

// MARK: - 爆閃粒子
private struct BootParticlesView: View {
    let color: Color
    let progress: CGFloat

    private let particles: [Particle] = (0..<36).map { i in
        let angle = Double(i) * (Double.pi * 2.0 / 36.0)
        let radius = CGFloat(90 + ((i * 31) % 180))
        let size = CGFloat(1.5 + Double(i % 4))
        return Particle(
            angle: angle,
            radius: radius,
            size: size,
            delay: CGFloat(i % 7) / 7.0
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Circle()
                        .fill(color.opacity(max(0, 1 - progress)))
                        .frame(width: p.size, height: p.size)
                        .position(
                            x: geo.size.width / 2 + cos(p.angle) * p.radius * progress,
                            y: geo.size.height / 2 + sin(p.angle) * p.radius * progress
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let radius: CGFloat
        let size: CGFloat
        let delay: CGFloat
    }
}

// MARK: - 7. 櫻花飄落背景
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
                        with: .color(Color(red: 1.0, green: 0.3, blue: 0.4))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(.all, edges: .all)
        .metalAcceleration() // 讓高密度櫻花交給 GPU 運算，防卡頓
    }
}

// MARK: - 8. 最外框霓虹流光線條
struct BackgroundNeonFlowView: View {
    var primaryColor: Color
    var borderWidth: Double
    var animSpeed: Double
    
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [primaryColor.opacity(0.2), primaryColor, .white, primaryColor, primaryColor.opacity(0.2)]),
                    center: .center,
                    angle: .degrees(isAnimating ? 360 : 0)
                ),
                lineWidth: CGFloat(borderWidth)
            )
            .shadow(color: primaryColor, radius: 10)
            .allowsHitTesting(false)
            .ignoresSafeArea(.all, edges: .all)
            .metalAcceleration() // GPU 加速渲染霓虹漸層
            .onAppear {
                let duration = max(0.5, 6.0 - animSpeed)
                withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - 9. 互動式導航地圖
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

// MARK: - 10. 動態速度環形儀表板
struct NeonSpeedGaugeRing: View {
    var speed: Double
    var maxDisplaySpeed: Double = 220.0
    var color: Color
    var outerBorderWidth: Double
    var animSpeed: Double
    
    @State private var isOuterRotating = false
    
    var progress: Double {
        return min(max(speed / maxDisplaySpeed, 0.0), 1.0)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.1), color, .white, color, color.opacity(0.1)]),
                        center: .center,
                        angle: .degrees(isOuterRotating ? 360 : 0)
                    ),
                    lineWidth: CGFloat(outerBorderWidth)
                )
                .frame(width: 295, height: 295)
                .shadow(color: color, radius: 8)
            
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 10)
                .frame(width: 255, height: 255)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [color.opacity(0.4), color, .white]), center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 255, height: 255)
                .rotationEffect(.degrees(-90))
                .shadow(color: color, radius: 10)
                // 加入 120Hz 順暢化的平滑動畫插值，防止每秒指針瞬跳
                .animation(.easeOut(duration: 0.35), value: speed)
            
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(i < Int(progress * 12) ? color : Color.white.opacity(0.2))
                    .frame(width: 3, height: 10)
                    .offset(y: -120)
                    .rotationEffect(.degrees(Double(i) * 30))
                    // 同步套用平滑插值
                    .animation(.easeOut(duration: 0.35), value: speed)
            }
        }
        .metalAcceleration() // 讓大量圓環使用 GPU 加速繪製
        .onAppear {
            let duration = max(0.5, 6.0 - animSpeed)
            withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                isOuterRotating = true
            }
        }
    }
}

// MARK: - 11. 轉速燈
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
        // 燈號隨速度變化時，也帶有微小漸變
        .animation(.linear(duration: 0.2), value: speed)
    }
    
    private func isLit(_ index: Int) -> Bool { speed >= Double(index + 1) * 25.0 }
    private func lightColor(for index: Int) -> Color {
        guard isLit(index) else { return Color.gray.opacity(0.25) }
        if index < 4 { return .green }
        if index < 6 { return .yellow }
        return .red
    }
}

// MARK: - 12. 內嵌小地圖
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
        .frame(width: 110, height: 110)
        .shadow(color: primaryColor.opacity(0.5), radius: 8)
    }
}

// MARK: - 13. 效能測試檢視
struct PerformanceTestDashboardView: View {
    @ObservedObject var vehicleManager: VehicleManager
    var primaryColor: Color
    
    var body: some View {
        TabView {
            ZStack {
                Color.black.ignoresSafeArea(.all, edges: .all)
                VStack(spacing: 24) {
                    Text("0 - 100 KM/H 加速測試")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    
                    ZStack {
                        Circle()
                            .stroke(primaryColor.opacity(0.3), lineWidth: 12)
                            .frame(width: 200, height: 200)
                        
                        VStack(spacing: 4) {
                            Text(String(format: "%.2f", vehicleManager.zeroToOneHundredTime))
                                .font(.system(size: 48, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Text("秒 (SEC)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(primaryColor)
                        }
                    }
                    
                    Text(vehicleManager.isTesting0_100 ? "測試中...請全油門加速！" : "車速低於 5 km/h 靜止後自動重置測試")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .tabItem {
                Label("0-100加速", systemImage: "timer")
            }
            
            ZStack {
                Color.black.ignoresSafeArea(.all, edges: .all)
                VStack(spacing: 24) {
                    Text("0 - 100 公尺短距加速")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    
                    ZStack {
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 12)
                            .frame(width: 200, height: 200)
                        
                        VStack(spacing: 4) {
                            Text(String(format: "%.2f", vehicleManager.zeroTo100mTime))
                                .font(.system(size: 48, weight: .black, design: .monospaced))
                                .foregroundColor(.orange)
                            Text("秒 / 100M")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(vehicleManager.isTesting0_100m ? "0-100公尺計測中..." : "車輛靜止後起步自動開始計測")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .tabItem {
                Label("100公尺測試", systemImage: "flag.checkered")
            }
        }
        .accentColor(primaryColor)
        .navigationTitle("車輛效能測試")
        .ignoresSafeArea(.all, edges: .all)
    }
}

// MARK: - 14. 歷史紀錄
struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(.all, edges: .all)
            List {
                ForEach(records) { record in
                    NavigationLink(destination: HistoryDetailMapView(record: record)) {
                        VStack(alignment: .leading) {
                            Text(record.date, formatter: dateFormatter).font(.system(size: 12)).foregroundColor(.gray)
                            Text(String(format: "極速: %.0f km/h | 0-100: %.2fs | 里程: %.2f km", record.maxSpeed, record.zeroToOneHundredTime, record.tripDistance))
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
        .ignoresSafeArea(.all, edges: .all)
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
        .ignoresSafeArea(.all, edges: .all)
        .navigationTitle("軌跡回放")
    }
}

// MARK: - 15. 設定頁面
struct SettingsView: View {
    @ObservedObject var vehicleManager: VehicleManager
    @Binding var selectedTheme: DashboardTheme
    @Binding var speedLimit: Double
    @Binding var isHudMode: Bool
    @Binding var useCustomColor: Bool
    @Binding var customColor: Color
    @Binding var isNetworkBoostEnabled: Bool
    @Binding var simulatedSpeed: Double
    @Binding var enableSakuraBackground: Bool
    @Binding var sakuraDensity: Double
    @Binding var borderWidth: Double
    @Binding var animSpeed: Double
    
    // [新增] 動態模糊控制綁定
    @Binding var enableMotionBlur: Bool
    
    var body: some View {
        Form {
            Section(header: Text("視覺特效與 120Hz 防卡頓設定")) {
                Toggle("啟用 120Hz 模擬動態模糊 (GPU 加速)", isOn: $enableMotionBlur)
                Text("這會在車速超過 40km/h 時自動產生殘影，並強制啟動 Metal 晶片渲染，大幅減少舊機型 (如 iPhone 11) 的畫面卡頓。")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("霓虹邊框與燈條設定")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("霓虹燈條粗度: \(Int(borderWidth)) pt")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $borderWidth, in: 2...12, step: 1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("霓虹旋轉速度: \(Int(animSpeed)) 級")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $animSpeed, in: 1...5, step: 1)
                }
            }
            
            Section(header: Text("語音播報與多國語系 (i18n)")) {
                Picker("語音語言", selection: $vehicleManager.speechManager.currentLanguage) {
                    Text("繁體中文").tag("zh-TW")
                    Text("English").tag("en-US")
                    Text("日本語").tag("ja-JP")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Button(action: {
                    vehicleManager.speechManager.announceWarning(speedLimit: 60, isOverspeed: true)
                }) {
                    Text("測試語音播報效果")
                        .foregroundColor(.blue)
                }
            }
            
            Section(header: Text("測速點位管理")) {
                Button("新增目前位置為測速點") {
                    vehicleManager.addCurrentLocationAsCamera(speedLimit: speedLimit, description: "手動回報測速點")
                }
                Button("移除最近測速點 (150m內)") {
                    vehicleManager.removeNearestCamera()
                }
                .foregroundColor(.red)
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

// MARK: - 16. 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @State private var isBootLoaded: Bool = false
    
    @AppStorage("selectedTheme") private var storedThemeRaw: String = DashboardTheme.sakura.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120.0
    @AppStorage("isHudMode") private var isHudMode: Bool = false
    @AppStorage("showMap") private var showMap: Bool = false
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    @AppStorage("customColorRaw") private var customColorRaw: String = "1.0,0.3,0.4"
    @AppStorage("isNetworkBoostEnabled") private var isNetworkBoostEnabled: Bool = false
    
    @AppStorage("enableSakuraBackground") private var enableSakuraBackground: Bool = true
    @AppStorage("sakuraDensity") private var sakuraDensity: Double = 20.0
    
    @AppStorage("borderWidth") private var borderWidth: Double = 4.0
    @AppStorage("animSpeed") private var animSpeed: Double = 3.0
    
    // [新增] 儲存動態模糊的開關狀態
    @AppStorage("enableMotionBlur") private var enableMotionBlur: Bool = true
    
    @State private var overspeedLogs: [OverspeedRecord] = []
    @State private var historyRecords: [HistoryRecord] = []
    
    @State private var showSettings: Bool = false
    @State private var showHistoryRecords: Bool = false
    @State private var showPerformanceView: Bool = false
    @State private var flashWarning: Bool = false
    
    @State private var simulatedSpeed: Double = 0.0
    
    @State private var showJapaneseOverspeedAlert: Bool = false
    @State private var overspeedTimer: Timer? = nil
    
    var customColor: Color {
        get { Color(rawValue: customColorRaw) ?? Color(red: 1.0, green: 0.3, blue: 0.4) }
        set { customColorRaw = newValue.rawValue }
    }
    
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
        // [新增] 根據時速計算動態模糊殘影強度 (時速超過40開始產生)
        let blurIntensity = enableMotionBlur && effectiveSpeed > 40.0 ? CGFloat(min((effectiveSpeed - 40.0) / 180.0, 1.0)) : 0.0
        
        NavigationView {
            ZStack {
                AnimatedBackgroundView(
                    themeColors: selectedTheme.backgroundGradientColors,
                    primaryColor: currentPrimaryColor
                )
                
                if selectedTheme == .sakura && enableSakuraBackground {
                    SakuraFallingView(density: sakuraDensity)
                        .ignoresSafeArea(.all, edges: .all)
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
                        BackgroundNeonFlowView(primaryColor: currentPrimaryColor, borderWidth: borderWidth, animSpeed: animSpeed)
                            .ignoresSafeArea(.all, edges: .all)
                            .zIndex(0)
                        
                        if flashWarning {
                            Color.red.opacity(0.35)
                                .ignoresSafeArea(.all, edges: .all)
                                .zIndex(10)
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
                                        
                                        HStack(spacing: 6) {
                                            Text(String(format: "%.0f", effectiveSpeed))
                                                .font(.system(size: 22, weight: .black, design: .monospaced))
                                                .foregroundColor(.white)
                                            Text("KM/H")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(currentPrimaryColor)
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 44)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(22)
                                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(currentPrimaryColor, lineWidth: 1))
                                        
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
                                    }
                                    .padding(.top, 24)
                                    .padding(.leading, 24)
                                }
                                .ignoresSafeArea(.all, edges: .all)
                            } else {
                                // [新增] 將核心儀表板套上「120Hz 動態模糊與 GPU 加速」特效
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
                                        
                                        Button(action: { showPerformanceView = true }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "timer").font(.system(size: 14))
                                                Text("測試").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.orange.opacity(0.25))
                                            .foregroundColor(.orange)
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
                                            simulatedSpeed = 0.0
                                        }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 14))
                                                Text("重置").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            }
                                            .frame(width: 50, height: 50)
                                            .background(Color.red.opacity(0.25))
                                            .foregroundColor(.red)
                                            .cornerRadius(14)
                                        }
                                    }
                                    .frame(width: 54)
                                    
                                    ZStack {
                                        NeonSpeedGaugeRing(
                                            speed: effectiveSpeed,
                                            color: currentPrimaryColor,
                                            outerBorderWidth: borderWidth,
                                            animSpeed: animSpeed
                                        )
                                        
                                        VStack(spacing: 4) {
                                            Text(simulatedSpeed > 0 ? "SIMULATED SPEED" : "GPS SPEED")
                                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                                .foregroundColor(simulatedSpeed > 0 ? .orange : .gray)
                                                .kerning(2)
                                            
                                            Text(String(format: "%.0f", effectiveSpeed))
                                                .font(.system(size: 78, weight: .black, design: .monospaced))
                                                .foregroundColor(.white)
                                                .shadow(color: currentPrimaryColor, radius: 12)
                                                // [新增] 時速跳動時的平滑過渡 (防卡頓瞬移)
                                                .animation(.easeOut(duration: 0.35), value: effectiveSpeed)
                                            
                                            Text("KM/H")
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(currentPrimaryColor)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    
                                    VStack(spacing: 10) {
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
                                            HStack {
                                                Text("0-100加速:").foregroundColor(.gray)
                                                Spacer()
                                                Text(String(format: "%.2fs", vehicleManager.zeroToOneHundredTime))
                                                    .foregroundColor(vehicleManager.isTesting0_100 ? .yellow : currentPrimaryColor)
                                            }
                                            HStack {
                                                Text("0-100m距:").foregroundColor(.gray)
                                                Spacer()
                                                Text(String(format: "%.2fs", vehicleManager.zeroTo100mTime))
                                                    .foregroundColor(vehicleManager.isTesting0_100m ? .yellow : .orange)
                                            }
                                            HStack {
                                                Text("行車里程:").foregroundColor(.gray)
                                                Spacer()
                                                Text(String(format: "%.2fkm", vehicleManager.tripDistance))
                                                    .foregroundColor(.green)
                                            }
                                            HStack {
                                                Text("最高極速:").foregroundColor(.gray)
                                                Spacer()
                                                Text(String(format: "%.0fkm/h", max(vehicleManager.maxSpeed, simulatedSpeed)))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                                // [新增] 套用動態模糊與硬體加速！
                                .dynamicMotionBlur(isEnabled: enableMotionBlur, intensity: blurIntensity)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarHidden(true)
            .statusBarHidden(true)
            .ignoresSafeArea(.all, edges: .all)
            .scaleEffect(x: isHudMode ? -1.0 : 1.0, y: 1.0)
            .onAppear {
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled: isNetworkBoostEnabled)
            }
            .onChange(of: effectiveSpeed) { newVal in
                if newVal > speedLimit {
                    flashWarning = true
                    AudioServicesPlaySystemSound(1005)
                    overspeedLogs.append(OverspeedRecord(id: UUID(), date: Date(), speed: newVal, speedLimit: speedLimit))
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
                        vehicleManager: vehicleManager,
                        selectedTheme: Binding(get: { self.selectedTheme }, set: { self.storedThemeRaw = $0.rawValue }),
                        speedLimit: $speedLimit,
                        isHudMode: $isHudMode,
                        useCustomColor: $useCustomColor,
                        customColor: Binding(
                            get: { Color(rawValue: self.customColorRaw) ?? Color(red: 1.0, green: 0.3, blue: 0.4) },
                            set: { self.customColorRaw = $0.rawValue }
                        ),
                        isNetworkBoostEnabled: $isNetworkBoostEnabled,
                        simulatedSpeed: $simulatedSpeed,
                        enableSakuraBackground: $enableSakuraBackground,
                        sakuraDensity: $sakuraDensity,
                        borderWidth: $borderWidth,
                        animSpeed: $animSpeed,
                        // 傳遞動態模糊設定至頁面
                        enableMotionBlur: $enableMotionBlur
                    ), isActive: $showSettings) { EmptyView() }
                    
                    NavigationLink(destination: HistoryRecordsView(records: $historyRecords), isActive: $showHistoryRecords) { EmptyView() }
                    
                    NavigationLink(destination: PerformanceTestDashboardView(vehicleManager: vehicleManager, primaryColor: currentPrimaryColor), isActive: $showPerformanceView) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden(true)
        .ignoresSafeArea(.all, edges: .all)
    }
}
