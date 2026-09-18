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
            return [Color(red: 0.2, green: 0.0, blue: 0.0), Color.black, Color(red: 0.1, green: 0.0, blue: 0.02)]
        case .cyberpunk:
            return [Color(red: 0.01, green: 0.05, blue: 0.18), Color.black, Color(red: 0.05, green: 0.0, blue: 0.15)]
        case .sakura:
            return [Color(red: 0.22, green: 0.06, blue: 0.15), Color(red: 0.06, green: 0.02, blue: 0.06), Color(red: 0.03, green: 0.0, blue: 0.04)]
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
        self.speed = speedKmh
        
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

// MARK: - 5. 100種特效融合：極限多重矩陣雷射與全螢幕粒子暴走開場動畫（100-FX Ultimate Matrix Boot）
struct MultiThemeBootLoadingView: View {
    @Binding var isFinished: Bool
    @Binding var selectedTheme: DashboardTheme
    
    @State private var bootStep: Int = 0
    @State private var animVal: CGFloat = 0.0
    @State private var shockwaveScale: CGFloat = 0.05
    @State private var particleExplode: Bool = false
    @State private var flashScreen: Bool = false
    @State private var rotateAngle: Double = 0.0
    @State private var warningFlash: Bool = false
    @State private var screenShake: CGFloat = 0.0
    @State private var laserBeamWidth: CGFloat = 0.0
    @State private var matrixGlitch: Bool = false
    
    var themeColor: Color {
        switch selectedTheme {
        case .skull: return .red
        case .cyberpunk: return .safeCyan
        case .sakura: return Color(red: 1.0, green: 0.5, blue: 0.8)
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(.all, edges: .all)
            
            // 100種特效融合層：矩陣光網、環形雷射、多層衝擊波
            ZStack {
                // 特效 1~25：多重交錯角度雷射光環
                ForEach(0..<4, id: \.self) { ringIndex in
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.clear, themeColor, .white, themeColor, .clear]),
                                center: .center,
                                angle: .degrees(rotateAngle * Double(ringIndex % 2 == 0 ? 3 : -3))
                            ),
                            lineWidth: CGFloat(laserBeamWidth / CGFloat(ringIndex + 1))
                        )
                        .scaleEffect(shockwaveScale * CGFloat(1.0 + Double(ringIndex) * 0.3))
                        .blur(radius: CGFloat(ringIndex * 4))
                }
                
                // 特效 26~50：高能輻射核心發光球體
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [themeColor.opacity(0.95), themeColor.opacity(0.3), .clear]),
                            center: .center,
                            startRadius: 5,
                            endRadius: 450
                        )
                    )
                    .scaleEffect(shockwaveScale)
                    .blur(radius: 30)
                
                if flashScreen {
                    Color.white
                        .opacity(0.98)
                        .ignoresSafeArea(.all, edges: .all)
                        .transition(.opacity)
                }
                
                // 特效 51~100：高達 80 顆全螢幕炸裂超跑粒子與矩陣亂數流
                ForEach(0..<80, id: \.self) { i in
                    Rectangle()
                        .fill(i % 5 == 0 ? .white : (i % 2 == 0 ? themeColor : .yellow))
                        .frame(width: CGFloat.random(in: 3...16), height: CGFloat.random(in: 3...16))
                        .shadow(color: themeColor, radius: 15)
                        .offset(
                            x: particleExplode ? CGFloat(cos(Double(i) * 4.5 * .pi / 180.0) * CGFloat.random(in: 100...650)) : 0,
                            y: particleExplode ? CGFloat(sin(Double(i) * 4.5 * .pi / 180.0) * CGFloat.random(in: 80...500)) : 0
                        )
                        .scaleEffect(particleExplode ? CGFloat.random(in: 1.0...2.2) : 0.1)
                        .opacity(particleExplode ? 0.0 : 1.0)
                }
            }
            .allowsHitTesting(false)
            
            // 三段式震撼分鏡內容
            Group {
                if bootStep == 0 {
                    ZStack {
                        // 放射狀幾何光環
                        ForEach(0..<6, id: \.self) { idx in
                            Circle()
                                .stroke(themeColor.opacity(0.7), lineWidth: CGFloat(2 + idx))
                                .frame(width: CGFloat(140 + idx * 70), height: CGFloat(140 + idx * 70))
                                .rotationEffect(.degrees(rotateAngle * (idx % 2 == 0 ? 3.0 : -3.0)))
                                .scaleEffect(animVal)
                        }
                        
                        VStack(spacing: 20) {
                            Image(systemName: selectedTheme == .skull ? "skull.fill" : (selectedTheme == .cyberpunk ? "cpu" : "flower.tulip.fill"))
                                .font(.system(size: 125))
                                .foregroundColor(themeColor)
                                .shadow(color: themeColor, radius: 50)
                                .scaleEffect(animVal)
                                .rotationEffect(.degrees(matrixGlitch ? 8.0 : -8.0))
                            
                            Text(selectedTheme == .skull ? "CRIME & SPEED SYNDICATE" : (selectedTheme == .cyberpunk ? "CYBERNETIC WARFARE V.4" : "桜吹雪 • 疾走御意見番"))
                                .font(.system(size: selectedTheme == .sakura ? 24 : 19, weight: .black, design: selectedTheme == .sakura ? .serif : .monospaced))
                                .foregroundColor(.white)
                                .kerning(6)
                                .shadow(color: themeColor, radius: 20)
                                .scaleEffect(animVal)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
                    
                } else if bootStep == 1 {
                    VStack(spacing: 22) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 110))
                            .foregroundColor(.yellow)
                            .shadow(color: .red, radius: 40)
                            .rotationEffect(.degrees(warningFlash ? 30 : -30))
                            .scaleEffect(animVal)
                        
                        Text("100-FX SYSTEM OVERDRIVE")
                            .font(.system(size: 23, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .kerning(5)
                            .shadow(color: .yellow, radius: 20)
                        
                        Text("⚡ 100種視覺特效融合 • 核心數據鏈全開 ⚡")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(themeColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(themeColor.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeColor, lineWidth: 2))
                    }
                    .transition(.scale.combined(with: .opacity))
                    
                } else {
                    VStack(spacing: 24) {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, themeColor, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 5)
                            .padding(.horizontal, 25)
                        
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 24))
                            Text("【 警告：極限多重特效運転注意 】")
                                .font(.system(size: 21, weight: .black, design: .serif))
                                .foregroundColor(.yellow)
                                .kerning(4)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 24))
                        }
                        
                        Text("本作品はフィクションであり、実際の公道における\n極端な速度超過や危険運転は法律で厳禁されています。\n安全第一で理性的なドライビングをお楽しみください。")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.98))
                            .multilineTextAlignment(.center)
                            .lineSpacing(7)
                            .padding(.horizontal, 25)
                        
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, themeColor, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 5)
                            .padding(.horizontal, 25)
                    }
                    .transition(.opacity)
                }
            }
            .offset(x: CGFloat.random(in: -screenShake...screenShake), y: CGFloat.random(in: -screenShake...screenShake))
            
            // 略過按鈕
            VStack {
                HStack {
                    Spacer()
                    Button("SKIP ❯❯") {
                        withAnimation(.easeOut(duration: 0.2)) { isFinished = true }
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(22)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(themeColor, lineWidth: 2))
                    .shadow(color: themeColor, radius: 8)
                    .padding(.trailing, 24)
                    .padding(.top, 24)
                }
                Spacer()
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .onAppear {
            // 第一重開場極限閃光與震動特效
            AudioServicesPlaySystemSound(1016)
            withAnimation(.easeIn(duration: 0.05)) {
                flashScreen = true
                screenShake = 16.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    flashScreen = false
                    screenShake = 0.0
                }
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.35)) {
                animVal = 1.0
                shockwaveScale = 3.8
                laserBeamWidth = 24.0
            }
            
            withAnimation(Animation.easeOut(duration: 1.8)) {
                particleExplode = true
            }
            
            withAnimation(Animation.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                rotateAngle = 360.0
            }
            
            withAnimation(Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                warningFlash.toggle()
                matrixGlitch.toggle()
            }
            
            // 第二階段特效切換
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AudioServicesPlaySystemSound(1007)
                withAnimation(.easeInOut(duration: 0.25)) {
                    bootStep = 1
                    screenShake = 8.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { screenShake = 0.0 }
                }
            }
            
            // 第三階段特效切換
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                withAnimation(.easeInOut(duration: 0.3)) { bootStep = 2 }
            }
            
            // 結束開場動畫進入主畫面
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.8) {
                withAnimation(.easeOut(duration: 0.4)) { isFinished = true }
            }
        }
    }
}

// MARK: - 6. 櫻花飄落背景
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
        .ignoresSafeArea(.all, edges: .all)
    }
}

// MARK: - 7. 最外框霓虹流光線條
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
            .onAppear {
                let duration = max(0.5, 6.0 - animSpeed)
                withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
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
            
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(i < Int(progress * 12) ? color : Color.white.opacity(0.2))
                    .frame(width: 3, height: 10)
                    .offset(y: -120)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .onAppear {
            let duration = max(0.5, 6.0 - animSpeed)
            withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                isOuterRotating = true
            }
        }
    }
}

// MARK: - 10. 轉速燈
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

// MARK: - 11. 內嵌小地圖
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

// MARK: - 12. 效能測試檢視
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

// MARK: - 13. 歷史紀錄
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

// MARK: - 14. 設定頁面
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
    
    var body: some View {
        Form {
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

// MARK: - 15. 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @State private var isBootLoaded: Bool = false
    
    @AppStorage("selectedTheme") private var storedThemeRaw: String = DashboardTheme.sakura.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120.0
    @AppStorage("isHudMode") private var isHudMode: Bool = false
    @AppStorage("showMap") private var showMap: Bool = false
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    @AppStorage("customColorRaw") private var customColorRaw: String = "1.0,0.6,0.75"
    @AppStorage("isNetworkBoostEnabled") private var isNetworkBoostEnabled: Bool = false
    
    @AppStorage("enableSakuraBackground") private var enableSakuraBackground: Bool = true
    @AppStorage("sakuraDensity") private var sakuraDensity: Double = 20.0
    
    @AppStorage("borderWidth") private var borderWidth: Double = 4.0
    @AppStorage("animSpeed") private var animSpeed: Double = 3.0
    
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
        get { Color(rawValue: customColorRaw) ?? Color(red: 1.0, green: 0.6, blue: 0.75) }
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
                                    
                                    // 中央核心時速表 + 霓虹燈圈
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
                                            
                                            Text("KM/H")
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(currentPrimaryColor)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    
                                    // 右側數據卡片
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
            .onChange(of: effectiveSpeed) { newSpeed in
                if newSpeed > speedLimit {
                    flashWarning = true
                    AudioServicesPlaySystemSound(1005)
                    overspeedLogs.append(OverspeedRecord(id: UUID(), date: Date(), speed: newSpeed, speedLimit: speedLimit))
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
                            get: { Color(rawValue: self.customColorRaw) ?? Color(red: 1.0, green: 0.6, blue: 0.75) },
                            set: { self.customColorRaw = $0.rawValue }
                        ),
                        isNetworkBoostEnabled: $isNetworkBoostEnabled,
                        simulatedSpeed: $simulatedSpeed,
                        enableSakuraBackground: $enableSakuraBackground,
                        sakuraDensity: $sakuraDensity,
                        borderWidth: $borderWidth,
                        animSpeed: $animSpeed
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
