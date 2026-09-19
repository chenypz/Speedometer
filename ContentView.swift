import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation
import UIKit

// MARK: - iOS 14/15 相容色彩
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

// MARK: - 資料模型
struct OverspeedRecord: Identifiable, Codable {
    let id: UUID; let date: Date; let speed: Double; let speedLimit: Double
}
struct HistoryRecord: Identifiable, Codable {
    let id: UUID; let date: Date; let maxSpeed: Double
    let zeroToOneHundredTime: Double; let maxGForce: Double
    let tripDistance: Double; let routeCoordinates: [CodableCoordinate]
}
struct CodableCoordinate: Codable {
    let latitude: Double; let longitude: Double
    init(_ c: CLLocationCoordinate2D) { latitude = c.latitude; longitude = c.longitude }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
struct SpeedCamera: Identifiable, Codable {
    var id: UUID = UUID()
    let latitude: Double; let longitude: Double
    let speedLimit: Double; let description: String
    var isTemporary: Bool = false
    enum CodingKeys: String, CodingKey { case latitude, longitude, speedLimit, description, isTemporary }
    init(latitude: Double, longitude: Double, speedLimit: Double, description: String, isTemporary: Bool = false) {
        self.latitude = latitude; self.longitude = longitude
        self.speedLimit = speedLimit; self.description = description; self.isTemporary = isTemporary
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

// MARK: - 主題
enum DashboardTheme: String, CaseIterable, Identifiable {
    case skull = "骷髏暴力風"
    case cyberpunk = "賽伯戰爭風"
    case sakura = "日本櫻花風"
    var id: String { rawValue }
    func primaryColor(custom: Color?) -> Color {
        if let c = custom { return c }
        switch self {
        case .skull:     return .red
        case .cyberpunk: return .safeCyan
        case .sakura:    return Color(red: 1.0, green: 0.3, blue: 0.4)
        }
    }
    var backgroundGradientColors: [Color] {
        switch self {
        case .skull:
            return [Color(red: 0.18, green: 0.0, blue: 0.0), Color.black, Color(red: 0.08, green: 0.0, blue: 0.02)]
        case .cyberpunk:
            return [Color(red: 0.01, green: 0.04, blue: 0.16), Color.black, Color(red: 0.04, green: 0.0, blue: 0.14)]
        case .sakura:
            return [Color(red: 0.14, green: 0.02, blue: 0.05), Color(red: 0.03, green: 0.01, blue: 0.03), Color.black]
        }
    }
}
extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        let c = rawValue.components(separatedBy: ",")
        guard c.count == 3, let r = Double(c[0]), let g = Double(c[1]), let b = Double(c[2]) else { return nil }
        self.init(red: r, green: g, blue: b)
    }
    public var rawValue: String {
        let u = UIColor(self); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a); return "\(r),\(g),\(b)"
    }
}

// MARK: - ★ 統一動畫計時器（iOS 14 相容）
class AnimationClock: ObservableObject {
    @Published var tick: Double = 0
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    init() { start() }

    private func start() {
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        // ★ iOS 14 相容：只在 iOS 15+ 設定高刷率
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func update() {
        tick = CACurrentMediaTime() - startTime
    }

    deinit { displayLink?.invalidate() }
}

// MARK: - ★ 骷髏主題：血色霧氣（iOS 14 ForEach 版）
struct SkullBloodFogView: View {
    let tick: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<18, id: \.self) { i in
                    let seed = Double(i) * 137.5
                    let phase = tick * 0.38 + seed
                    let xFrac = (sin(phase * 0.31 + seed * 0.07) * 0.5 + 0.5)
                    let yFrac = (cos(phase * 0.19 + seed * 0.11) * 0.5 + 0.5)
                    let radius = CGFloat(55 + sin(phase * 0.5 + seed) * 35)
                    let opacity = 0.05 + abs(sin(phase * 0.27 + seed * 0.3)) * 0.12

                    Circle()
                        .fill(Color(red: 0.85, green: 0.0, blue: 0.05))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: CGFloat(xFrac) * geo.size.width,
                                  y: CGFloat(yFrac) * geo.size.height)
                        .opacity(opacity)
                        .blur(radius: 18)
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - ★ 賽伯主題：矩陣數字流（iOS 15+ Canvas，iOS 14 fallback）
struct CyberpunkMatrixRainView: View {
    let tick: Double

    var body: some View {
        if #available(iOS 15.0, *) {
            CyberpunkMatrixRainCanvas(tick: tick)
        } else {
            CyberpunkMatrixRainFallback(tick: tick)
        }
    }
}

@available(iOS 15.0, *)
private struct CyberpunkMatrixRainCanvas: View {
    let tick: Double
    private let columns = 22
    private let chars = ["0","1","ア","イ","ウ","エ","オ","カ","キ","ク","ケ","コ",
                         "サ","シ","ス","△","◇","╬","░","▓","∑","∞","π","Ω"]

    var body: some View {
        Canvas { ctx, size in
            let colWidth = size.width / CGFloat(columns)
            for col in 0..<columns {
                let seed = Double(col) * 73.1
                let speed = 0.6 + fmod(seed * 0.031, 0.8)
                let phase = fmod(tick * speed + seed * 0.4, 1.0)
                let rows = 12
                for row in 0..<rows {
                    let rowFrac = (CGFloat(row) / CGFloat(rows) + CGFloat(phase)).truncatingRemainder(dividingBy: 1.0)
                    let y = rowFrac * (size.height + 60) - 30
                    let x = CGFloat(col) * colWidth + colWidth / 2
                    let fade = 1.0 - Double(row) / Double(rows)
                    let charIdx = (col * 7 + row + Int(tick * 8)) % chars.count
                    ctx.opacity = (row == 0 ? 1.0 : fade * 0.55) * 0.85
                    ctx.draw(
                        Text(chars[charIdx])
                            .font(.system(size: CGFloat(9 + col % 3 * 2), weight: .bold, design: .monospaced))
                            .foregroundColor(row == 0 ? .white : .safeCyan),
                        at: CGPoint(x: x, y: y)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .blendMode(.screen)
    }
}

// iOS 14 fallback：簡化版矩陣列
private struct CyberpunkMatrixRainFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<12, id: \.self) { col in
                    let seed = Double(col) * 73.1
                    let phase = CGFloat(fmod(tick * 0.7 + seed * 0.4, 1.0))
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color.safeCyan.opacity(0.5), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5, height: geo.size.height * 0.4)
                        .position(x: CGFloat(col) / 12.0 * geo.size.width,
                                  y: phase * geo.size.height)
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - ★ 賽伯主題：霓虹網格地面（iOS 15+ Canvas，iOS 14 fallback）
struct CyberpunkNeonGridView: View {
    let tick: Double

    var body: some View {
        if #available(iOS 15.0, *) {
            CyberpunkNeonGridCanvas(tick: tick)
        } else {
            CyberpunkNeonGridFallback(tick: tick)
        }
    }
}

@available(iOS 15.0, *)
private struct CyberpunkNeonGridCanvas: View {
    let tick: Double
    var body: some View {
        Canvas { ctx, size in
            let vp = CGPoint(x: size.width / 2, y: size.height * 0.55)
            let cols = 10; let rows = 8
            let pulse = 0.7 + sin(tick * 2.2) * 0.3
            for c in 0...cols {
                let t = CGFloat(c) / CGFloat(cols)
                var path = Path()
                path.move(to: vp)
                path.addLine(to: CGPoint(x: t * size.width, y: size.height))
                ctx.opacity = 0.18 * pulse
                ctx.stroke(path, with: .color(.safeCyan), style: StrokeStyle(lineWidth: 0.8))
            }
            for r in 1...rows {
                let t = CGFloat(r) / CGFloat(rows)
                let eased = t * t
                let leftX = vp.x - (vp.x) * eased
                let rightX = vp.x + (size.width - vp.x) * eased
                let y = vp.y + (size.height - vp.y) * eased
                var path = Path()
                path.move(to: CGPoint(x: leftX, y: y))
                path.addLine(to: CGPoint(x: rightX, y: y))
                ctx.opacity = (0.08 + eased * 0.2) * pulse
                ctx.stroke(path, with: .color(.safeCyan), style: StrokeStyle(lineWidth: 0.9))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .blendMode(.screen)
    }
}

private struct CyberpunkNeonGridFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 簡化透視線條
                ForEach(0..<6, id: \.self) { i in
                    let t = CGFloat(i) / 5.0
                    let y = geo.size.height * 0.55 + (geo.size.height * 0.45) * t
                    Rectangle()
                        .fill(Color.safeCyan.opacity(0.12 * Double(t)))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: y)
                        .frame(width: geo.size.width * (0.2 + t * 0.8))
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - ★ 櫻花主題：金光粒子（iOS 15+ Canvas，iOS 14 ForEach 版）
struct SakuraGoldParticlesView: View {
    let tick: Double

    var body: some View {
        if #available(iOS 15.0, *) {
            SakuraGoldParticlesCanvas(tick: tick)
        } else {
            SakuraGoldParticlesFallback(tick: tick)
        }
    }
}

@available(iOS 15.0, *)
private struct SakuraGoldParticlesCanvas: View {
    let tick: Double
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<30 {
                let seed = Double(i) * 111.3
                let phase = fmod(tick * (0.25 + fmod(seed * 0.009, 0.3)) + seed * 0.6, 1.0)
                let x = (sin(seed * 0.47 + tick * 0.12) * 0.5 + 0.5) * size.width
                let y = (1.0 - phase) * (size.height + 40) - 20
                let s = CGFloat(2.5 + sin(seed * 1.7 + tick) * 1.5)
                let fade = sin(phase * Double.pi)
                let shimmer = sin(tick * 4.0 + seed) * 0.5 + 0.5
                ctx.opacity = fade * 0.85
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s*2, height: s*2)),
                    with: .color(Color(red: 1.0, green: 0.82 + shimmer * 0.1, blue: 0.2))
                )
                let glowR = s * 3.5
                ctx.opacity = fade * 0.18
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR*2, height: glowR*2)),
                    with: .color(Color(red: 1.0, green: 0.9, blue: 0.4))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .blendMode(.screen)
    }
}

private struct SakuraGoldParticlesFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<20, id: \.self) { i in
                    let seed = Double(i) * 111.3
                    let phase = CGFloat(fmod(tick * 0.3 + seed * 0.6, 1.0))
                    let x = CGFloat(sin(seed * 0.47 + tick * 0.12) * 0.5 + 0.5) * geo.size.width
                    let y = (1.0 - phase) * (geo.size.height + 40) - 20
                    let s = CGFloat(2.5 + sin(seed * 1.7 + tick) * 1.5)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.85, blue: 0.25))
                        .frame(width: s*2, height: s*2)
                        .position(x: x, y: y)
                        .opacity(Double(sin(phase * .pi)) * 0.85)
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - ★ 升級版動態背景（iOS 14/15 相容）
struct AnimatedBackgroundView: View {
    var themeColors: [Color]
    var primaryColor: Color
    var theme: DashboardTheme
    @ObservedObject var clock: AnimationClock

    var body: some View {
        ZStack {
            LinearGradient(
                colors: themeColors,
                startPoint: UnitPoint(x: 0.5 + CGFloat(sin(clock.tick * 0.15)) * 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5 + CGFloat(cos(clock.tick * 0.12)) * 0.5, y: 1)
            )
            .ignoresSafeArea()

            // 金屬光澤 mesh（iOS 14 ForEach 版）
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        let seed = Double(i) * 90.0
                        let cx = CGFloat(sin(clock.tick * 0.22 + seed) * 0.5 + 0.5) * geo.size.width
                        let cy = CGFloat(cos(clock.tick * 0.17 + seed) * 0.5 + 0.5) * geo.size.height
                        let r = CGFloat(120 + sin(clock.tick * 0.5 + seed) * 60)
                        let op = 0.06 + abs(sin(clock.tick * 0.3 + seed)) * 0.08
                        Circle()
                            .fill(primaryColor)
                            .frame(width: r * 2, height: r * 2)
                            .position(x: cx, y: cy)
                            .opacity(op)
                            .blur(radius: 22)
                    }
                }
            }
            .blendMode(.screen)
            .ignoresSafeArea()

            // 主題專屬環境粒子
            switch theme {
            case .skull:
                SkullBloodFogView(tick: clock.tick)
            case .cyberpunk:
                CyberpunkNeonGridView(tick: clock.tick)
                CyberpunkMatrixRainView(tick: clock.tick)
                    .opacity(0.35)
            case .sakura:
                SakuraGoldParticlesView(tick: clock.tick)
            }
        }
        .drawingGroup()
    }
}

// MARK: - 語音播報
class SpeechManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var currentLanguage: String = "zh-TW" {
        didSet { UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage") }
    }
    init() {
        if let s = UserDefaults.standard.string(forKey: "AppLanguage") { currentLanguage = s }
    }
    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        u.rate = 0.52; u.pitchMultiplier = 1.0
        synthesizer.speak(u)
    }
    func announceWarning(speedLimit: Int, isOverspeed: Bool) {
        let text: String
        if currentLanguage.starts(with: "zh") {
            text = isOverspeed ? "注意，您已超速！前方速限 \(speedLimit) 公里" : "前方速限 \(speedLimit) 公里"
        } else {
            text = isOverspeed ? "Warning! Speed limit \(speedLimit). You are speeding!" : "Speed limit \(speedLimit)."
        }
        speak(text)
    }
}

// MARK: - GPS & 感應器管理器
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
        locationManager.desiredAccuracy = isNetworkBoostEnabled ? kCLLocationAccuracyBest : kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = isNetworkBoostEnabled ? 1.0 : kCLDistanceFilterNone
    }
    func resetData() {
        tripDistance = 0; maxSpeed = 0; maxGForce = 0
        zeroToOneHundredTime = 0; isTesting0_100 = false; hasReached100 = false; accelStartTime = nil
        zeroTo100mTime = 0; isTesting0_100m = false; hasReached100m = false
        distanceStartTime = nil; startLocationFor100m = nil
        lastLocation = nil; recordedPath.removeAll(); lastSpokenCameraId = nil
        harshAccelerationCount = 0; harshBrakingCount = 0
        overspeedDurationSeconds = 0; lastRecordedSpeed = 0
    }
    func addCurrentLocationAsCamera(speedLimit: Double, description: String) {
        let cam = SpeedCamera(latitude: currentLocation.latitude, longitude: currentLocation.longitude,
                              speedLimit: speedLimit,
                              description: description.isEmpty ? "⚠️ 手動回報測速點" : description,
                              isTemporary: true)
        speedCameras.append(cam)
        nearestCameraAlert = "已成功加入目前測速點！"
        AudioServicesPlaySystemSound(1016)
        speechManager.speak("已成功加入目前測速點")
    }
    func removeNearestCamera() {
        guard let loc = lastLocation else { speechManager.speak("目前沒有定位資訊"); return }
        if let idx = speedCameras.firstIndex(where: {
            loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 150
        }) {
            let removed = speedCameras.remove(at: idx)
            nearestCameraAlert = "已移除最近測速點：\(removed.description)"
            AudioServicesPlaySystemSound(1016); speechManager.speak("已移除最近測速點")
        } else {
            nearestCameraAlert = "附近 150 公尺內沒有測速點可移除"
            speechManager.speak("附近沒有找到可移除的測速點")
        }
    }
    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        destinationCoordinate = coordinate; isNavigating = true
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        req.transportType = .automobile
        MKDirections(request: req).calculate { [weak self] resp, _ in
            guard let self = self, let route = resp?.routes.first else {
                self?.currentInstruction = "路線計算失敗"; return
            }
            self.routePolyline = route.polyline
            if let step = route.steps.first(where: { !$0.instructions.isEmpty }) {
                self.currentInstruction = step.instructions
                self.distanceToNextStep = step.distance
            }
        }
    }
    func cancelNavigation() {
        isNavigating = false; routePolyline = nil; destinationCoordinate = nil
        currentInstruction = "導航已結束"; distanceToNextStep = 0
    }
    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let acc = data?.acceleration else { return }
            self.currentGForceX = acc.x; self.currentGForceY = acc.y
            let g = sqrt(acc.x*acc.x + acc.y*acc.y)
            if g > self.maxGForce { self.maxGForce = g }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc.coordinate
        recordedPath.append(loc.coordinate)
        let kmh = max(0, loc.speed * 3.6)
        speed = kmh
        let delta = kmh - lastRecordedSpeed
        if delta > 18 { harshAccelerationCount += 1 } else if delta < -18 { harshBrakingCount += 1 }
        lastRecordedSpeed = kmh
        checkSpeedCameras(currentLoc: loc, currentSpeed: kmh)
        if kmh > maxSpeed { maxSpeed = kmh }
        if let last = lastLocation {
            let d = loc.distance(from: last)
            if d > 0 { tripDistance += d / 1000.0 }
        }
        lastLocation = loc
        if kmh < 5 && !isTesting0_100 && !hasReached100 {
            isTesting0_100 = true; accelStartTime = Date(); zeroToOneHundredTime = 0; hasReached100 = false
        } else if isTesting0_100, let t = accelStartTime {
            zeroToOneHundredTime = Date().timeIntervalSince(t)
            if kmh >= 100 { isTesting0_100 = false; hasReached100 = true }
            else if zeroToOneHundredTime > 30 { isTesting0_100 = false }
        }
        if kmh < 3 && !isTesting0_100m && !hasReached100m {
            isTesting0_100m = true; distanceStartTime = Date(); startLocationFor100m = loc; zeroTo100mTime = 0
        } else if isTesting0_100m, let sl = startLocationFor100m, let st = distanceStartTime {
            zeroTo100mTime = Date().timeIntervalSince(st)
            if loc.distance(from: sl) >= 100 { isTesting0_100m = false; hasReached100m = true }
            else if zeroTo100mTime > 30 { isTesting0_100m = false }
        }
    }
    private func checkSpeedCameras(currentLoc: CLLocation, currentSpeed: Double) {
        for cam in speedCameras {
            let camLoc = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
            let dist = currentLoc.distance(from: camLoc)
            if dist <= 400 {
                nearestCameraAlert = "\(cam.description) 剩 \(Int(dist))m (速限 \(Int(cam.speedLimit))km)"
                if dist <= 300, lastSpokenCameraId != cam.id {
                    lastSpokenCameraId = cam.id
                    speechManager.announceWarning(speedLimit: Int(cam.speedLimit), isOverspeed: currentSpeed > cam.speedLimit)
                    if currentSpeed > cam.speedLimit { AudioServicesPlaySystemSound(1007) }
                }
                return
            }
        }
        if let id = lastSpokenCameraId, let cam = speedCameras.first(where: { $0.id == id }) {
            if currentLoc.distance(from: CLLocation(latitude: cam.latitude, longitude: cam.longitude)) > 500 {
                lastSpokenCameraId = nil
            }
        }
        if nearestCameraAlert?.contains("已成功") == false && nearestCameraAlert?.contains("已移除") == false {
            nearestCameraAlert = nil
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - ★ 白狐靈獸（drawingGroup 優化）
struct MajesticWhiteFoxFaceView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.5), Color.orange.opacity(0.15), .clear]),
                    center: .center, startRadius: 10, endRadius: 180))
                .frame(width: 360, height: 360)
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.08), .clear]),
                    center: .center, startRadius: 50, endRadius: 170))
                .frame(width: 340, height: 340)
            Path { p in
                p.move(to: CGPoint(x: 100, y: 150))
                p.addLine(to: CGPoint(x: 10, y: 10))
                p.addLine(to: CGPoint(x: 120, y: 80))
                p.closeSubpath()
            }.fill(Color.white).shadow(color: .red, radius: 10)
            Path { p in
                p.move(to: CGPoint(x: 200, y: 150))
                p.addLine(to: CGPoint(x: 290, y: 10))
                p.addLine(to: CGPoint(x: 180, y: 80))
                p.closeSubpath()
            }.fill(Color.white).shadow(color: .red, radius: 10)
            Path { p in
                p.move(to: CGPoint(x: 90, y: 120))
                p.addLine(to: CGPoint(x: 35, y: 35))
                p.addLine(to: CGPoint(x: 110, y: 85))
                p.closeSubpath()
            }.fill(Color(red: 0.7, green: 0.0, blue: 0.1))
            Path { p in
                p.move(to: CGPoint(x: 210, y: 120))
                p.addLine(to: CGPoint(x: 265, y: 35))
                p.addLine(to: CGPoint(x: 190, y: 85))
                p.closeSubpath()
            }.fill(Color(red: 0.7, green: 0.0, blue: 0.1))
            Path { p in
                p.move(to: CGPoint(x: 150, y: 280))
                p.addLine(to: CGPoint(x: 40, y: 130))
                p.addLine(to: CGPoint(x: 90, y: 110))
                p.addLine(to: CGPoint(x: 150, y: 140))
                p.addLine(to: CGPoint(x: 210, y: 110))
                p.addLine(to: CGPoint(x: 260, y: 130))
                p.closeSubpath()
            }.fill(Color(red: 0.98, green: 0.98, blue: 1.0)).shadow(color: .white, radius: 16)
            Ellipse().fill(Color(red: 0.9, green: 0.1, blue: 0.2))
                .frame(width: 44, height: 19).rotationEffect(.degrees(28)).position(x: 105, y: 165)
                .shadow(color: .red, radius: 14)
            Ellipse().fill(Color(red: 0.9, green: 0.1, blue: 0.2))
                .frame(width: 44, height: 19).rotationEffect(.degrees(-28)).position(x: 195, y: 165)
                .shadow(color: .red, radius: 14)
            Circle().fill(Color.yellow).frame(width: 7, height: 7).position(x: 108, y: 163)
            Circle().fill(Color.yellow).frame(width: 7, height: 7).position(x: 192, y: 163)
            Path { p in
                p.move(to: CGPoint(x: 65, y: 180))
                p.addQuadCurve(to: CGPoint(x: 95, y: 200), control: CGPoint(x: 80, y: 170))
                p.move(to: CGPoint(x: 235, y: 180))
                p.addQuadCurve(to: CGPoint(x: 205, y: 200), control: CGPoint(x: 220, y: 170))
            }.stroke(Color.red, lineWidth: 5)
            Path { p in
                p.move(to: CGPoint(x: 80, y: 250))
                p.addQuadCurve(to: CGPoint(x: 220, y: 250), control: CGPoint(x: 150, y: 290))
            }.stroke(Color(red: 0.8, green: 0.0, blue: 0.1), lineWidth: 16)
            Circle().fill(Color.yellow).frame(width: 22, height: 22).position(x: 150, y: 272)
                .shadow(color: .orange, radius: 8)
        }
        .frame(width: 300, height: 320)
        .drawingGroup()
    }
}

// MARK: - ★ 骷髏開場粒子（iOS 14 相容）
private struct SkullBootParticles: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<48, id: \.self) { i in
                    let angle = Double(i) * (Double.pi * 2.0 / 48.0)
                    let baseR = 50.0 + Double(i % 5) * 30.0
                    let r = CGFloat(baseR) + progress * CGFloat(130 + (i % 4) * 50)
                    let x = geo.size.width / 2 + CGFloat(cos(angle)) * r
                    let y = geo.size.height / 2 + CGFloat(sin(angle)) * r
                    let fade = max(0.0, 1.0 - Double(progress) * 1.4)
                    let sz = CGFloat(2.0 + Double(i % 4))
                    Circle()
                        .fill(i % 3 == 0 ? Color.white : Color.red)
                        .frame(width: sz * 2, height: sz * 2)
                        .position(x: x, y: y)
                        .opacity(fade * 0.9)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ★ 賽伯全息掃描框（iOS 15+ Canvas，iOS 14 fallback）
private struct CyberHoloScanFrame: View {
    let progress: CGFloat
    let color: Color
    var body: some View {
        if #available(iOS 15.0, *) {
            CyberHoloScanFrameCanvas(progress: progress, color: color)
        } else {
            CyberHoloScanFrameFallback(progress: progress, color: color)
        }
    }
}

@available(iOS 15.0, *)
private struct CyberHoloScanFrameCanvas: View {
    let progress: CGFloat; let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            Canvas { ctx, size in
                let corners: [(CGPoint, CGPoint, CGPoint)] = [
                    (CGPoint(x:0,y:0),    CGPoint(x:60,y:0),   CGPoint(x:0,y:60)),
                    (CGPoint(x:w,y:0),    CGPoint(x:w-60,y:0), CGPoint(x:w,y:60)),
                    (CGPoint(x:0,y:h),    CGPoint(x:60,y:h),   CGPoint(x:0,y:h-60)),
                    (CGPoint(x:w,y:h),    CGPoint(x:w-60,y:h), CGPoint(x:w,y:h-60))
                ]
                for (pivot, e1, e2) in corners {
                    var p = Path(); p.move(to: e1); p.addLine(to: pivot); p.addLine(to: e2)
                    ctx.opacity = 0.9
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
                }
                let scanY = h * CGFloat(progress)
                var scanPath = Path()
                scanPath.move(to: CGPoint(x: 0, y: scanY))
                scanPath.addLine(to: CGPoint(x: w, y: scanY))
                ctx.opacity = 0.7 * Double(1.0 - abs(progress - 0.5) * 2)
                ctx.stroke(scanPath, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
                ctx.opacity = 0.15
                ctx.fill(Path(CGRect(x: 0, y: scanY - 30, width: w, height: 30)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CyberHoloScanFrameFallback: View {
    let progress: CGFloat; let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 四角框
                ForEach(0..<4, id: \.self) { i in
                    let isRight = i % 2 == 1
                    let isBottom = i >= 2
                    VStack(spacing: 0) {
                        if isBottom { Spacer() }
                        HStack(spacing: 0) {
                            if isRight { Spacer() }
                            ZStack(alignment: isBottom ? (isRight ? .bottomTrailing : .bottomLeading) : (isRight ? .topTrailing : .topLeading)) {
                                Path { p in
                                    p.move(to: CGPoint(x: 0, y: 0))
                                    p.addLine(to: CGPoint(x: isRight ? -55 : 55, y: 0))
                                    p.move(to: CGPoint(x: 0, y: 0))
                                    p.addLine(to: CGPoint(x: 0, y: isBottom ? -55 : 55))
                                }
                                .stroke(color, lineWidth: 2.5)
                                .frame(width: 60, height: 60)
                            }
                            if !isRight { Spacer() }
                        }
                        if !isBottom { Spacer() }
                    }
                }
                // 掃描線
                Rectangle()
                    .fill(color.opacity(0.5))
                    .frame(height: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height * progress)
                    .opacity(0.7 * Double(1.0 - abs(progress - 0.5) * 2))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ★ 掃描線（iOS 15+ Canvas，iOS 14 ForEach 版）
private struct ScanlineOverlay: View {
    let color: Color
    let offset: CGFloat
    var body: some View {
        if #available(iOS 15.0, *) {
            ScanlineCanvas(color: color, offset: offset)
        } else {
            ScanlineFallback(color: color, offset: offset)
        }
    }
}

@available(iOS 15.0, *)
private struct ScanlineCanvas: View {
    let color: Color; let offset: CGFloat
    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let spacing: CGFloat = 8
                var y = (offset * size.height).truncatingRemainder(dividingBy: spacing)
                while y < size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.opacity = 0.04
                    ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1))
                    y += spacing
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct ScanlineFallback: View {
    let color: Color; let offset: CGFloat
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<60, id: \.self) { _ in
                    Rectangle()
                        .fill(color.opacity(0.035))
                        .frame(height: 1)
                    Spacer(minLength: 7)
                }
            }
            .offset(y: offset * geo.size.height)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - ★ 賽車速度線（iOS 15+ Canvas，iOS 14 ForEach 版）
private struct RacingSpeedLines: View {
    let color: Color
    let progress: CGFloat
    let intensity: CGFloat

    struct SpeedLine: Identifiable {
        let id: Int
        let x: CGFloat; let y: CGFloat
        let length: CGFloat; let thickness: CGFloat; let delay: CGFloat
    }

    // ★ 修正：改用靜態方法避免型別推斷超時
    static func makeLines() -> [SpeedLine] {
        (0..<28).map { i in
            SpeedLine(
                id: i,
                x: CGFloat((i * 37) % 100) / 100,
                y: CGFloat((i * 61) % 100) / 100,
                length: CGFloat(60 + (i * 29) % 130),
                thickness: CGFloat(1 + i % 3),
                delay: CGFloat((i * 17) % 100) / 100
            )
        }
    }
    private let lines = RacingSpeedLines.makeLines()

    var body: some View {
        if #available(iOS 15.0, *) {
            RacingSpeedLinesCanvas(color: color, progress: progress, intensity: intensity, lines: lines)
        } else {
            RacingSpeedLinesFallback(color: color, progress: progress, intensity: intensity, lines: lines)
        }
    }
}

@available(iOS 15.0, *)
private struct RacingSpeedLinesCanvas: View {
    let color: Color; let progress: CGFloat; let intensity: CGFloat
    let lines: [RacingSpeedLines.SpeedLine]
    var body: some View {
        Canvas { ctx, size in
            for line in lines {
                let x = size.width * line.x
                let y = size.height * (line.y + progress * (0.25 + line.delay * 0.35))
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + line.length, y: y + line.length * 0.14))
                ctx.opacity = Double(0.55 * intensity)
                ctx.stroke(path, with: .linearGradient(
                    Gradient(colors: [.clear, color.opacity(0.85), .clear]),
                    startPoint: CGPoint(x: x, y: y),
                    endPoint: CGPoint(x: x + line.length, y: y)
                ), style: StrokeStyle(lineWidth: line.thickness))
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct RacingSpeedLinesFallback: View {
    let color: Color; let progress: CGFloat; let intensity: CGFloat
    let lines: [RacingSpeedLines.SpeedLine]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(lines) { line in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, color.opacity(0.85 * Double(intensity)), .clear],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: line.length, height: line.thickness)
                        .position(
                            x: geo.size.width * line.x,
                            y: geo.size.height * (line.y + progress * (0.25 + line.delay * 0.35))
                        )
                        .rotationEffect(.degrees(-8))
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - ★ 開場動畫主體
struct MultiThemeBootLoadingView: View {
    @Binding var isFinished: Bool
    @Binding var selectedTheme: DashboardTheme

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
    @State private var holoScanProgress: CGFloat = 0
    @State private var crackProgress: CGFloat = 0
    @State private var glitchOffset: CGFloat = 0
    @State private var matrixOpacity: Double = 0
    @State private var goldFlareScale: CGFloat = 0.1
    @State private var goldFlareOpacity: Double = 0

    private var themeColor: Color {
        switch selectedTheme {
        case .skull:     return .red
        case .cyberpunk: return .safeCyan
        case .sakura:    return Color(red: 1.0, green: 0.3, blue: 0.4)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                switch selectedTheme {
                case .skull:    skullBoot(in: geo.size)
                case .cyberpunk: cyberBoot(in: geo.size)
                case .sakura:   sakuraBoot(in: geo.size)
                }
                ScanlineOverlay(color: themeColor, offset: scanOffset)
                    .allowsHitTesting(false)
                if flashOpacity > 0 {
                    Rectangle().fill(Color.white).opacity(flashOpacity).ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                if showParticles {
                    BootParticlesView(color: themeColor, progress: particleProgress)
                        .allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button("SKIP") { finishBoot() }
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.78))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.black.opacity(0.55))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(themeColor.opacity(0.5), lineWidth: 1))
                            .padding(.top, 18).padding(.trailing, 18)
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

    // MARK: Skull Boot
    @ViewBuilder
    private func skullBoot(in size: CGSize) -> some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.22), Color(red:0.4,green:0,blue:0).opacity(0.15), .clear]),
                center: .center, startRadius: 20, endRadius: 260)
            .ignoresSafeArea()
            .scaleEffect(pulse ? 1.12 : 0.95)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

            if crackProgress > 0 {
                SkullBootParticles(progress: crackProgress)
            }

            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.clear, .red, .white, .red, .clear]),
                            center: .center),
                        lineWidth: CGFloat(4 - i))
                    .frame(width: CGFloat(290 + i * 24), height: CGFloat(290 + i * 24))
                    .rotationEffect(.degrees(rotation * (i % 2 == 0 ? 1 : -1) + Double(i) * 40))
                    .opacity(0.55 - Double(i) * 0.12)
            }

            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                .frame(width: min(size.width, size.height) * 0.88)
                .scaleEffect(ringScale).opacity(ringOpacity)

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 140, height: 140)
                    .blur(radius: 18)
                Image(systemName: "skull.fill")
                    .font(.system(size: min(size.width, size.height) * 0.21, weight: .black))
                    .foregroundColor(.white)
                    .shadow(color: .red, radius: 20)
                    .shadow(color: .red.opacity(0.5), radius: 40)
            }
            .scaleEffect(logoScale).opacity(logoOpacity).blur(radius: logoBlur)
            .offset(x: glitchOffset)

            VStack(spacing: 6) {
                Spacer().frame(height: min(size.width, size.height) * 0.43)
                Text("CHEN")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .kerning(9)        // ★ iOS 14 相容（替代 .tracking）
                    .foregroundColor(.white)
                    .shadow(color: .red, radius: 8)
                HStack(spacing: 4) {
                    Rectangle().fill(Color.red).frame(width: 22, height: 1.5)
                    Text("SYSTEM ONLINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(4).foregroundColor(.red)
                    Rectangle().fill(Color.red).frame(width: 22, height: 1.5)
                }
            }
            .opacity(logoOpacity)
        }
    }

    // MARK: Cyberpunk Boot
    @ViewBuilder
    private func cyberBoot(in size: CGSize) -> some View {
        ZStack {
            CyberpunkNeonGridView(tick: Double(speed) * 3.0).opacity(0.6)
            CyberpunkMatrixRainView(tick: Double(speed) * 2.5).opacity(matrixOpacity)
            CyberHoloScanFrame(progress: holoScanProgress, color: .safeCyan).opacity(logoOpacity)

            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, .safeCyan, .white, .safeCyan, .clear]),
                        center: .center),
                    lineWidth: 2)
                .frame(width: min(size.width * 0.82, 430), height: min(size.height * 0.52, 400))
                .rotationEffect(.degrees(rotation * 0.4))
                .opacity(0.85)

            RoundedRectangle(cornerRadius: 22)
                .fill(Color.safeCyan.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.safeCyan.opacity(0.2), lineWidth: 1))
                .frame(width: min(size.width * 0.76, 400), height: min(size.height * 0.46, 370))

            VStack(spacing: 14) {
                Text("CHEN // DRIVE")
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .kerning(3)        // ★ iOS 14 相容
                    .foregroundColor(.safeCyan)
                    .shadow(color: .safeCyan, radius: 12)
                    .shadow(color: .safeCyan.opacity(0.4), radius: 24)
                    .offset(x: glitchOffset * 0.3)

                Text("NEURAL VEHICLE INTERFACE v2.0")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .kerning(3).foregroundColor(.white.opacity(0.55))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: min(size.width * 0.58, 280), height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.safeCyan, .white], startPoint: .leading, endPoint: .trailing))
                        .frame(width: min(size.width * 0.58, 280) * speed, height: 3)
                        .shadow(color: .safeCyan, radius: 6)
                }
                HStack(spacing: 24) {
                    cyberMetric("BOOST", "MAX")
                    cyberMetric("RADAR", "ONLINE")
                    cyberMetric("GPS", "LOCK")
                    cyberMetric("AI", "ACTIVE")
                }
            }
            .scaleEffect(logoScale).opacity(logoOpacity).blur(radius: logoBlur)
        }
    }

    private func cyberMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Text(value).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.safeCyan)
                .shadow(color: .safeCyan, radius: 4)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.safeCyan.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.safeCyan.opacity(0.25), lineWidth: 1))
        .cornerRadius(6)
    }

    // MARK: Sakura Boot
    @ViewBuilder
    private func sakuraBoot(in size: CGSize) -> some View {
        ZStack {
            RacingSpeedLines(color: .red, progress: speed, intensity: bootStep >= 2 ? 1 : 0.45)

            if goldFlareScale > 0.1 {
                ZStack {
                    ForEach(0..<12, id: \.self) { i in
                        let angle = Double(i) * 30.0
                        let dist = CGFloat(80 + i * 15) * goldFlareScale
                        Circle()
                            .fill(Color(red: 1.0, green: 0.85, blue: 0.2))
                            .frame(width: CGFloat(3 + i % 3), height: CGFloat(3 + i % 3))
                            .offset(x: dist * CGFloat(cos(angle * .pi / 180)),
                                    y: dist * CGFloat(sin(angle * .pi / 180)))
                            .opacity(Double(goldFlareOpacity))
                    }
                    Circle()
                        .fill(Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.25))
                        .frame(width: 180 * goldFlareScale, height: 180 * goldFlareScale)
                        .blur(radius: 20)
                        .opacity(Double(goldFlareOpacity))
                }
            }

            if bootStep <= 1 {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.red).frame(width: 3, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠ WARNING")
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                                .foregroundColor(.red)
                            Text("極速領域")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .kerning(5)   // ★ iOS 14 相容
                                .shadow(color: .red.opacity(0.7), radius: 10)
                        }
                        Rectangle().fill(Color.red).frame(width: 3, height: 40)
                    }
                    Text("超速走行禁止")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .kerning(4).foregroundColor(.red)
                    HStack(spacing: 16) {
                        ForEach(["RADAR","ACTIVE","GPS","ON"], id: \.self) { txt in
                            Text(txt)
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                }
                .padding(.horizontal, 30).padding(.vertical, 28)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.92))
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(pulse ? 1.0 : 0.35), lineWidth: pulse ? 3 : 1)
                        LinearGradient(colors: [Color.white.opacity(0.04), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                )
                .scaleEffect(logoScale).opacity(logoOpacity).blur(radius: logoBlur)
            }

            if bootStep == 2 {
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.clear,
                                                                Color(red:1,green:0.85,blue:0.3),
                                                                .white,
                                                                Color(red:1,green:0.85,blue:0.3),
                                                                .clear]),
                                    center: .center),
                                lineWidth: CGFloat(3 - i))
                            .frame(width: CGFloat(min(size.width * 0.68, 360)) + CGFloat(i) * 20)
                            .rotationEffect(.degrees(rotation * (i == 0 ? 1 : -0.7)))
                            .opacity(0.7 - Double(i) * 0.2)
                    }
                    Circle()
                        .stroke(Color.red.opacity(0.7), lineWidth: 2)
                        .frame(width: min(size.width * 0.66, 360))
                        .scaleEffect(ringScale).opacity(ringOpacity)
                    MajesticWhiteFoxFaceView()
                        .frame(width: min(size.width * 0.64, 330), height: min(size.width * 0.64, 330))
                        .scaleEffect(1.0 + speed * 0.03)
                        .opacity(logoOpacity).blur(radius: logoBlur)
                        .shadow(color: .red.opacity(0.8), radius: 24)
                        .shadow(color: Color(red:1,green:0.85,blue:0.3).opacity(0.35), radius: 40)
                }
                VStack {
                    Spacer()
                    Text("CHEN")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .kerning(10).foregroundColor(.white).shadow(color: .red, radius: 8)
                    Text("EXTREME MODE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(5).foregroundColor(.red)
                        .padding(.top, 3).padding(.bottom, 55)
                }
                .opacity(logoOpacity)
            }

            if bootStep >= 3 {
                VStack(spacing: 10) {
                    Text("SYSTEM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .kerning(5).foregroundColor(.red.opacity(0.8))
                    Text("全系統啟動")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white).shadow(color: .red, radius: 10)
                    HStack(spacing: 8) {
                        Capsule().fill(Color.red).frame(width: 36, height: 3)
                        Capsule().fill(Color.white).frame(width: 36, height: 3)
                        Capsule().fill(Color.red).frame(width: 36, height: 3)
                    }
                    Text("DRIVE • RADAR • GPS • PERFORMANCE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5)).kerning(2)
                }
                .scaleEffect(logoScale).opacity(logoOpacity).blur(radius: logoBlur)
            }
        }
    }

    private func finishBoot() {
        withAnimation(.easeOut(duration: 0.32)) { isFinished = true }
    }

    private func startBoot() {
        bootStep = 0; speed = 0; logoScale = 0.72; logoOpacity = 0; logoBlur = 12
        flashOpacity = 0; shake = 0; ringScale = 0.25; ringOpacity = 0
        scanOffset = 0; pulse = false; particleProgress = 0; showParticles = false
        holoScanProgress = 0; crackProgress = 0; glitchOffset = 0
        matrixOpacity = 0; goldFlareScale = 0.1; goldFlareOpacity = 0

        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { rotation = 360 }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: true)) { scanOffset = 1 }
        withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) { pulse = true }
        withAnimation(.easeOut(duration: 0.38)) { logoOpacity = 1; logoScale = 1.0; logoBlur = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.28)) { speed = 1 }
        }

        switch selectedTheme {
        case .skull:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.8)) { crackProgress = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.06)) { glitchOffset = -8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    withAnimation(.easeOut(duration: 0.06)) { glitchOffset = 6 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeOut(duration: 0.08)) { glitchOffset = 0 }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeIn(duration: 0.22)) { flashOpacity = 0.9; logoOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { finishBoot() }

        case .cyberpunk:
            withAnimation(.easeIn(duration: 0.6).delay(0.3)) { matrixOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.linear(duration: 0.9)) { holoScanProgress = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.05)) { glitchOffset = -12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.05)) { glitchOffset = 10 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.07)) { glitchOffset = 0 }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                withAnimation(.easeIn(duration: 0.24)) { flashOpacity = 0.85; logoOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { finishBoot() }

        case .sakura:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                bootStep = 2; ringScale = 1.0; ringOpacity = 1
                logoScale = 1.0; logoOpacity = 0; logoBlur = 18
                withAnimation(.easeOut(duration: 0.24)) {
                    logoOpacity = 1; logoBlur = 0; ringScale = 1.2; ringOpacity = 0
                }
                withAnimation(.easeOut(duration: 0.06)) { shake = -8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.06)) { shake = 7 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.1)) { shake = 0 }
                }
                withAnimation(.easeOut(duration: 0.18)) { flashOpacity = 0.8 }
                withAnimation(.easeIn(duration: 0.28).delay(0.05)) { flashOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    goldFlareScale = 1.0; goldFlareOpacity = 1
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                    goldFlareOpacity = 0; goldFlareScale = 1.5
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    bootStep = 3; logoScale = 0.92; logoOpacity = 1; logoBlur = 0; speed = 0.25
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) {
                showParticles = true; particleProgress = 0
                withAnimation(.easeOut(duration: 0.12)) { flashOpacity = 1; shake = 4 }
                withAnimation(.easeIn(duration: 0.34).delay(0.02)) { flashOpacity = 0; shake = 0 }
                withAnimation(.easeOut(duration: 0.55)) { particleProgress = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.15) {
                withAnimation(.easeIn(duration: 0.32)) { logoOpacity = 0; logoBlur = 8 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.48) { finishBoot() }
        }
    }
}

// MARK: - 爆閃粒子（iOS 14 ForEach 版）
private struct BootParticlesView: View {
    let color: Color; let progress: CGFloat

    struct Particle: Identifiable {
        let id: Int
        let angle: Double; let radius: CGFloat; let size: CGFloat
    }

    // ★ 改用靜態方法，避免型別推斷超時
    static func makeParticles() -> [Particle] {
        (0..<40).map { i in
            Particle(
                id: i,
                angle: Double(i) * (Double.pi * 2.0 / 40.0),
                radius: CGFloat(80 + (i * 31) % 190),
                size: CGFloat(1.5 + Double(i % 4))
            )
        }
    }
    private let particles = BootParticlesView.makeParticles()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    let x = geo.size.width / 2 + CGFloat(cos(p.angle)) * p.radius * progress
                    let y = geo.size.height / 2 + CGFloat(sin(p.angle)) * p.radius * progress
                    let fade = max(0.0, 1.0 - Double(progress) * 1.1)
                    Circle()
                        .fill(color)
                        .frame(width: p.size * 2, height: p.size * 2)
                        .position(x: x, y: y)
                        .opacity(fade)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 櫻花飄落（iOS 15+ Canvas，iOS 14 ForEach 版）
struct SakuraFallingView: View {
    var density: Double
    var body: some View {
        if #available(iOS 15.0, *) {
            SakuraFallingContentView(density: density)
        } else {
            SakuraFallingFallback(density: density)
        }
    }
}

@available(iOS 15.0, *)
private struct SakuraFallingContentView: View {
    var density: Double
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let count = Int(density)
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 99.0
                    let time = t + seed
                    let x = (sin(time * 0.5 + seed) * 0.5 + 0.5) * size.width
                    let y = fmod(time * 28.0 + seed * 50.0, size.height + 60) - 30
                    let scale = CGFloat(0.4 + sin(seed) * 0.4)
                    let rot = sin(time * 1.5 + seed) * 0.8
                    ctx.opacity = 0.7
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: Angle(radians: rot))
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: -6*scale, y: -4*scale, width: 12*scale, height: 8*scale)),
                        with: .color(Color(red: 1.0, green: 0.4, blue: 0.5))
                    )
                    ctx.translateBy(x: -x, y: -y)
                    ctx.rotate(by: Angle(radians: -rot))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct SakuraFallingFallback: View {
    var density: Double
    @State private var phase: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Int(min(density, 20)), id: \.self) { i in
                    let seed = Double(i) * 99.0
                    let x = CGFloat(sin(seed * 0.5) * 0.5 + 0.5) * geo.size.width
                    let y = (phase * geo.size.height + CGFloat(seed * 50).truncatingRemainder(dividingBy: geo.size.height + 60)) - 30
                    Ellipse()
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.5))
                        .frame(width: 12, height: 8)
                        .position(x: x, y: y)
                        .opacity(0.6)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - ★ 升級版霓虹流光邊框（iOS 14 State 動畫版）
struct BackgroundNeonFlowView: View {
    var primaryColor: Color
    var borderWidth: Double
    var animSpeed: Double
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: primaryColor.opacity(0.15), location: 0),
                        .init(color: primaryColor, location: 0.3),
                        .init(color: .white, location: 0.5),
                        .init(color: primaryColor, location: 0.7),
                        .init(color: primaryColor.opacity(0.15), location: 1)
                    ]),
                    center: .center,
                    angle: .degrees(isAnimating ? 360 : 0)
                ),
                lineWidth: CGFloat(borderWidth)
            )
            .shadow(color: primaryColor, radius: CGFloat(borderWidth) * 2)
            .shadow(color: primaryColor.opacity(0.4), radius: CGFloat(borderWidth) * 4)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onAppear {
                let duration = max(0.5, 6.0 - animSpeed)
                withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - 互動導航地圖
struct InteractiveNavigationMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?
    var destinationCoordinate: CLLocationCoordinate2D?
    var historyPath: [CLLocationCoordinate2D]?
    var isInteractive: Bool = true
    var onMapTap: (CLLocationCoordinate2D) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.userTrackingMode = isInteractive ? .followWithHeading : .none
        map.isZoomEnabled = isInteractive; map.isScrollEnabled = isInteractive
        map.isRotateEnabled = isInteractive
        map.showsCompass = false; map.showsTraffic = false
        map.delegate = context.coordinator
        if isInteractive {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        return map
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if isInteractive && uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
        }
        uiView.removeOverlays(uiView.overlays); uiView.removeAnnotations(uiView.annotations)
        if let p = routePolyline { uiView.addOverlay(p) }
        if let path = historyPath, !path.isEmpty {
            uiView.addOverlay(MKPolyline(coordinates: path, count: path.count))
        }
        if let dest = destinationCoordinate {
            let ann = MKPointAnnotation(); ann.coordinate = dest; ann.title = "目的地"
            uiView.addAnnotation(ann)
        }
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveNavigationMapView
        init(_ p: InteractiveNavigationMapView) { self.parent = p }
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            let map = g.view as! MKMapView
            parent.onMapTap(map.convert(g.location(in: map), toCoordinateFrom: map))
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let p = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: p)
                r.strokeColor = parent.historyPath != nil ? .systemOrange : .safeSystemCyan
                r.lineWidth = 6; return r
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - ★ 升級版速度儀表環（iOS 14 相容）
struct NeonSpeedGaugeRing: View {
    var speed: Double
    var maxDisplaySpeed: Double = 220.0
    var color: Color
    var outerBorderWidth: Double
    var animSpeed: Double
    @State private var isOuterRotating = false

    var progress: Double { min(max(speed / maxDisplaySpeed, 0), 1) }

    var body: some View {
        ZStack {
            // 最外旋轉環
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.08), location: 0),
                            .init(color: color.opacity(0.6), location: 0.25),
                            .init(color: .white, location: 0.5),
                            .init(color: color.opacity(0.6), location: 0.75),
                            .init(color: color.opacity(0.08), location: 1)
                        ]),
                        center: .center,
                        angle: .degrees(isOuterRotating ? 360 : 0)
                    ),
                    lineWidth: CGFloat(outerBorderWidth)
                )
                .frame(width: 299, height: 299)
                .shadow(color: color, radius: 8)
                .shadow(color: color.opacity(0.3), radius: 18)

            // 金屬反射底環
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), color.opacity(0.05),
                                 Color.white.opacity(0.12), color.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 10)
                .frame(width: 259, height: 259)

            // 背景軌道
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 12)
                .frame(width: 257, height: 257)

            // 外光暈層
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .frame(width: 257, height: 257)
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)

            // 主進度弧
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.4), color, .white]),
                        center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 257, height: 257)
                .rotationEffect(.degrees(-90))
                .shadow(color: color, radius: 10)
                .shadow(color: color.opacity(0.4), radius: 20)

            // 弧頭光點
            if progress > 0.01 {
                let angle = (progress * 360 - 90) * .pi / 180
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: CGFloat(cos(angle)) * 128.5,
                            y: CGFloat(sin(angle)) * 128.5)
                    .shadow(color: .white, radius: 6)
                    .shadow(color: color, radius: 10)
            }

            // 刻度燈
            ForEach(0..<12, id: \.self) { i in
                let lit = i < Int(progress * 12)
                Rectangle()
                    .fill(lit ? color : Color.white.opacity(0.15))
                    .frame(width: lit ? 4 : 2.5, height: lit ? 12 : 8)
                    .offset(y: -124)
                    .rotationEffect(.degrees(Double(i) * 30))
                    .shadow(color: lit ? color : .clear, radius: lit ? 6 : 0)
            }
        }
        .drawingGroup()
        .onAppear {
            let duration = max(0.5, 6.0 - animSpeed)
            withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                isOuterRotating = true
            }
        }
    }
}

// MARK: - 轉速燈
struct ShiftLightsView: View {
    let speed: Double
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let lit = speed >= Double(i + 1) * 25.0
                RoundedRectangle(cornerRadius: 3)
                    .fill(lightColor(for: i, lit: lit))
                    .frame(width: 16, height: 7)
                    .shadow(color: lit ? lightColor(for: i, lit: true) : .clear, radius: lit ? 6 : 0)
            }
        }
    }
    private func lightColor(for i: Int, lit: Bool) -> Color {
        guard lit else { return Color.gray.opacity(0.2) }
        if i < 4 { return .green }
        if i < 6 { return .yellow }
        return .red
    }
}

// MARK: - ★ 玻璃態 HUD 資訊卡
struct GlassInfoCard: View {
    let title: String; let value: String
    let valueColor: Color; let icon: String
    var isActive: Bool = false
    @State private var breathe = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(valueColor.opacity(0.8))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(valueColor)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                LinearGradient(colors: [Color.white.opacity(0.12), .clear],
                               startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), valueColor.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
        )
        .scaleEffect(isActive && breathe ? 1.02 : 1.0)
        .onAppear {
            if isActive {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
        }
    }
}

// MARK: - 小地圖
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
                    coordinate: coordinate, routePolyline: routePolyline,
                    destinationCoordinate: destinationCoordinate,
                    isInteractive: false, onMapTap: { _ in })
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(LinearGradient(
                        colors: [primaryColor, primaryColor.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    .padding(6).background(Color.black.opacity(0.75)).clipShape(Circle()).padding(7)
            }
        }
        .frame(width: 110, height: 110)
        .shadow(color: primaryColor.opacity(0.5), radius: 10)
    }
}

// MARK: - 效能測試
struct PerformanceTestDashboardView: View {
    @ObservedObject var vehicleManager: VehicleManager
    var primaryColor: Color
    var body: some View {
        TabView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("0 - 100 KM/H 加速測試")
                        .font(.system(size: 20, weight: .black, design: .monospaced)).foregroundColor(.white)
                    ZStack {
                        Circle().stroke(primaryColor.opacity(0.3), lineWidth: 12).frame(width: 200, height: 200)
                        VStack(spacing: 4) {
                            Text(String(format: "%.2f", vehicleManager.zeroToOneHundredTime))
                                .font(.system(size: 48, weight: .black, design: .monospaced)).foregroundColor(.white)
                            Text("秒 (SEC)").font(.system(size: 12, weight: .bold)).foregroundColor(primaryColor)
                        }
                    }
                    Text(vehicleManager.isTesting0_100 ? "測試中...全油門加速！" : "靜止後自動重置")
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                }
            }
            .tabItem { Label("0-100加速", systemImage: "timer") }
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("0 - 100 公尺短距加速")
                        .font(.system(size: 20, weight: .black, design: .monospaced)).foregroundColor(.white)
                    ZStack {
                        Circle().stroke(Color.orange.opacity(0.3), lineWidth: 12).frame(width: 200, height: 200)
                        VStack(spacing: 4) {
                            Text(String(format: "%.2f", vehicleManager.zeroTo100mTime))
                                .font(.system(size: 48, weight: .black, design: .monospaced)).foregroundColor(.orange)
                            Text("秒 / 100M").font(.system(size: 12, weight: .bold)).foregroundColor(.orange)
                        }
                    }
                    Text(vehicleManager.isTesting0_100m ? "0-100公尺計測中..." : "起步自動開始")
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                }
            }
            .tabItem { Label("100公尺測試", systemImage: "flag.checkered") }
        }
        .accentColor(primaryColor)
        .navigationTitle("車輛效能測試")
        .ignoresSafeArea()
    }
}

// MARK: - 歷史紀錄
struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(records) { rec in
                    NavigationLink(destination: HistoryDetailMapView(record: rec)) {
                        VStack(alignment: .leading) {
                            Text(rec.date, formatter: dateFormatter).font(.system(size: 12)).foregroundColor(.gray)
                            Text(String(format: "極速: %.0f km/h | 0-100: %.2fs | %.2f km",
                                        rec.maxSpeed, rec.zeroToOneHundredTime, rec.tripDistance))
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        }
                    }.listRowBackground(Color.black)
                }
                .onDelete { records.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("行車歷史封存")
    }
    private var dateFormatter: DateFormatter {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium; return df
    }
}
struct HistoryDetailMapView: View {
    let record: HistoryRecord
    var body: some View {
        InteractiveNavigationMapView(
            coordinate: record.routeCoordinates.first?.coordinate ?? CLLocationCoordinate2D(latitude: 25.033, longitude: 121.5654),
            historyPath: record.routeCoordinates.map { $0.coordinate },
            isInteractive: true, onMapTap: { _ in })
        .ignoresSafeArea()
        .navigationTitle("軌跡回放")
    }
}

// MARK: - 設定頁面
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
            Section(header: Text("語音播報")) {
                Picker("語音語言", selection: $vehicleManager.speechManager.currentLanguage) {
                    Text("繁體中文").tag("zh-TW")
                    Text("English").tag("en-US")
                    Text("日本語").tag("ja-JP")
                }
                .pickerStyle(SegmentedPickerStyle())
                Button("測試語音播報") {
                    vehicleManager.speechManager.announceWarning(speedLimit: 60, isOverspeed: true)
                }.foregroundColor(.blue)
            }
            Section(header: Text("測速點位管理")) {
                Button("新增目前位置為測速點") {
                    vehicleManager.addCurrentLocationAsCamera(speedLimit: speedLimit, description: "手動回報")
                }
                Button("移除最近測速點 (150m內)") {
                    vehicleManager.removeNearestCamera()
                }.foregroundColor(.red)
            }
            Section(header: Text("視覺主題")) {
                Picker("佈景主題", selection: $selectedTheme) {
                    ForEach(DashboardTheme.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(SegmentedPickerStyle())
                Toggle("啟用自定義霓虹色", isOn: $useCustomColor)
                if useCustomColor { ColorPicker("自定義主色調", selection: $customColor) }
            }
            if selectedTheme == .sakura {
                Section(header: Text("日本櫻花背景")) {
                    Toggle("啟用櫻花飄落背景", isOn: $enableSakuraBackground)
                    if enableSakuraBackground {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("密度: \(Int(sakuraDensity)) 片").font(.system(size: 13, weight: .bold))
                            Slider(value: $sakuraDensity, in: 5...50, step: 5)
                        }
                    }
                }
            }
            Section(header: Text("模擬速度測試")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("模擬車速: \(Int(simulatedSpeed)) km/h")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $simulatedSpeed, in: 0...220, step: 5)
                }
            }
            Section(header: Text("速限與警告")) {
                VStack(alignment: .leading) {
                    Text("超速閾值: \(Int(speedLimit)) km/h")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $speedLimit, in: 10...180, step: 5)
                }
            }
            Section(header: Text("導航與定位")) {
                Toggle("網路定位增強", isOn: $isNetworkBoostEnabled)
            }
            Section(header: Text("顯示模式")) {
                Toggle("HUD 投影模式 (鏡像)", isOn: $isHudMode)
            }
        }
        .navigationTitle("儀表板設定")
    }
}

// MARK: - ★ 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @StateObject private var animClock = AnimationClock()
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
    var effectiveSpeed: Double { simulatedSpeed > 0 ? simulatedSpeed : vehicleManager.speed }
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
                    primaryColor: currentPrimaryColor,
                    theme: selectedTheme,
                    clock: animClock
                )

                if selectedTheme == .sakura && enableSakuraBackground {
                    SakuraFallingView(density: sakuraDensity).ignoresSafeArea().zIndex(1)
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
                        BackgroundNeonFlowView(
                            primaryColor: currentPrimaryColor,
                            borderWidth: borderWidth,
                            animSpeed: animSpeed
                        )
                        .ignoresSafeArea().zIndex(0)

                        if flashWarning {
                            Color.red.opacity(0.3).ignoresSafeArea().zIndex(10)
                        }

                        if showJapaneseOverspeedAlert {
                            VStack {
                                Spacer()
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow).font(.system(size: 22))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("オービス警報発動")
                                            .font(.system(size: 15, weight: .black, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text("速度超過！減速してください！")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.horizontal, 22).padding(.vertical, 13)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.93))
                                        LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                                       startPoint: .top, endPoint: .bottom)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                )
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red, lineWidth: 2))
                                .shadow(color: .red.opacity(0.85), radius: 16)
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
                                        onMapTap: { vehicleManager.setDestination($0) }
                                    )
                                    .ignoresSafeArea()
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
                                        .padding(.horizontal, 14).frame(height: 44)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(22)
                                        .overlay(RoundedRectangle(cornerRadius: 22)
                                            .stroke(currentPrimaryColor, lineWidth: 1))
                                        if vehicleManager.isNavigating {
                                            Button(action: { vehicleManager.cancelNavigation() }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .frame(width: 44, height: 44)
                                                    .background(Color.red.opacity(0.85))
                                                    .foregroundColor(.white).cornerRadius(22)
                                            }
                                        }
                                    }
                                    .padding(.top, 24).padding(.leading, 24)
                                }
                                .ignoresSafeArea()
                            } else {
                                HStack(spacing: 12) {
                                    // 左側按鈕
                                    VStack(spacing: 10) {
                                        sideButton(icon: "map.fill", label: "地圖",
                                                   bg: Color.white.opacity(0.12), fg: .white) { showMap.toggle() }
                                        sideButton(icon: "gearshape.fill", label: "設定",
                                                   bg: currentPrimaryColor.opacity(0.15),
                                                   fg: currentPrimaryColor,
                                                   border: currentPrimaryColor.opacity(0.5)) { showSettings = true }
                                        sideButton(icon: "timer", label: "測試",
                                                   bg: Color.orange.opacity(0.2), fg: .orange) { showPerformanceView = true }
                                        sideButton(icon: "list.bullet.rectangle.portrait.fill", label: "紀錄",
                                                   bg: Color.white.opacity(0.12), fg: .white) { showHistoryRecords = true }
                                        Spacer()
                                        sideButton(icon: "arrow.counterclockwise.circle.fill", label: "重置",
                                                   bg: Color.red.opacity(0.2), fg: .red) {
                                            let h = HistoryRecord(
                                                id: UUID(), date: Date(),
                                                maxSpeed: vehicleManager.maxSpeed,
                                                zeroToOneHundredTime: vehicleManager.zeroToOneHundredTime,
                                                maxGForce: vehicleManager.maxGForce,
                                                tripDistance: vehicleManager.tripDistance,
                                                routeCoordinates: vehicleManager.recordedPath.map { CodableCoordinate($0) }
                                            )
                                            historyRecords.append(h)
                                            vehicleManager.resetData()
                                            simulatedSpeed = 0
                                        }
                                    }
                                    .frame(width: 54)

                                    // 中央儀表
                                    ZStack {
                                        NeonSpeedGaugeRing(
                                            speed: effectiveSpeed,
                                            color: currentPrimaryColor,
                                            outerBorderWidth: borderWidth,
                                            animSpeed: animSpeed
                                        )
                                        VStack(spacing: 4) {
                                            Text(simulatedSpeed > 0 ? "SIMULATED" : "GPS SPEED")
                                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                                .foregroundColor(simulatedSpeed > 0 ? .orange : .gray)
                                                .kerning(2)
                                            Text(String(format: "%.0f", effectiveSpeed))
                                                .font(.system(size: 80, weight: .black, design: .monospaced))
                                                .foregroundColor(.white)
                                                .shadow(color: currentPrimaryColor, radius: 14)
                                                .shadow(color: currentPrimaryColor.opacity(0.4), radius: 28)
                                            Text("KM/H")
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(currentPrimaryColor)
                                                .shadow(color: currentPrimaryColor, radius: 6)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    // 右側 HUD
                                    VStack(spacing: 8) {
                                        MiniMapView(
                                            coordinate: vehicleManager.currentLocation,
                                            routePolyline: vehicleManager.routePolyline,
                                            destinationCoordinate: vehicleManager.destinationCoordinate,
                                            primaryColor: currentPrimaryColor
                                        ) { showMap = true }
                                        VStack(spacing: 3) {
                                            ShiftLightsView(speed: effectiveSpeed)
                                            Text("RPM SHIFT")
                                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                                .foregroundColor(.gray)
                                        }
                                        VStack(spacing: 5) {
                                            GlassInfoCard(
                                                title: "0-100加速",
                                                value: String(format: "%.2fs", vehicleManager.zeroToOneHundredTime),
                                                valueColor: vehicleManager.isTesting0_100 ? .yellow : currentPrimaryColor,
                                                icon: "speedometer",
                                                isActive: vehicleManager.isTesting0_100
                                            )
                                            GlassInfoCard(
                                                title: "0-100m距",
                                                value: String(format: "%.2fs", vehicleManager.zeroTo100mTime),
                                                valueColor: vehicleManager.isTesting0_100m ? .yellow : .orange,
                                                icon: "flag.checkered",
                                                isActive: vehicleManager.isTesting0_100m
                                            )
                                            GlassInfoCard(
                                                title: "行車里程",
                                                value: String(format: "%.2fkm", vehicleManager.tripDistance),
                                                valueColor: .green,
                                                icon: "road.lanes"
                                            )
                                            GlassInfoCard(
                                                title: "最高極速",
                                                value: String(format: "%.0fkm/h", max(vehicleManager.maxSpeed, simulatedSpeed)),
                                                valueColor: .white,
                                                icon: "flame.fill"
                                            )
                                        }
                                        Spacer()
                                    }
                                    .frame(width: 135)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }

                            if let alert = vehicleManager.nearestCameraAlert {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill").foregroundColor(.yellow)
                                    Text(alert)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(
                                    ZStack {
                                        Capsule().fill(Color.red.opacity(0.93))
                                        LinearGradient(colors: [Color.white.opacity(0.12), .clear],
                                                       startPoint: .top, endPoint: .bottom)
                                        .clipShape(Capsule())
                                    }
                                )
                                .shadow(color: .red, radius: 12)
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
            .ignoresSafeArea()
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
                    withAnimation { showJapaneseOverspeedAlert = true }
                    overspeedTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { _ in
                        withAnimation { showJapaneseOverspeedAlert = false }
                    }
                } else {
                    flashWarning = false
                }
            }
            .background(
                Group {
                    NavigationLink(destination: SettingsView(
                        vehicleManager: vehicleManager,
                        selectedTheme: Binding(get: { selectedTheme }, set: { storedThemeRaw = $0.rawValue }),
                        speedLimit: $speedLimit,
                        isHudMode: $isHudMode,
                        useCustomColor: $useCustomColor,
                        customColor: Binding(
                            get: { Color(rawValue: customColorRaw) ?? Color(red: 1.0, green: 0.3, blue: 0.4) },
                            set: { customColorRaw = $0.rawValue }
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
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func sideButton(icon: String, label: String, bg: Color, fg: Color, border: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text
