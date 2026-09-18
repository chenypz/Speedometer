import SwiftUI
import MapKit
import CoreLocation
import CoreMotion
import Combine
import AudioToolbox

// MARK: - 1. 數據模型 (歷史與超速紀錄)
struct SpeedHistoryRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var maxSpeed: Double
    var zeroToHundred: Double?
    var quarterMile: Double?
    var maxGForce: Double
    var totalDistance: Double
}

struct OverspeedLog: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var speed: Double
    var limit: Double
}

// MARK: - 2. 主題風格 (支援背景自定義顏色)
enum DashboardTheme: String, CaseIterable, Identifiable {
    case porsche = "🏎️ 保時捷經典"
    case cyberpunk = "🌌 賽博朋克"
    case gaming = "🎮 極速電玩"
    
    var id: String { self.rawValue }
    
    var primaryColor: Color {
        switch self {
        case .porsche: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .cyberpunk: return Color(red: 0.0, green: 0.9, blue: 1.0)
        case .gaming: return Color(red: 1.0, green: 0.1, blue: 0.3)
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .porsche: return Color.white
        case .cyberpunk: return Color(red: 1.0, green: 0.0, blue: 0.8)
        case .gaming: return Color(red: 1.0, green: 0.5, blue: 0.0)
        }
    }
}

// MARK: - 3. GPS + G-Force 核心
class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    
    @Published var speedKMH: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var totalDistanceMeters: Double = 0.0
    @Published var altitudeMeters: Double = 0.0
    @Published var headingDegree: Double = 0.0
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isGpsReady: Bool = false
    
    @Published var isOfflineMode: Bool = false {
        didSet { updateLocationAccuracy() }
    }
    
    @Published var gForceX: Double = 0.0
    @Published var gForceY: Double = 0.0
    @Published var maxGForce: Double = 0.0
    
    @Published var zeroToHundredTime: Double? = nil
    @Published var isTimingZeroToHundred: Bool = false
    private var zeroToHundredStartTime: Date?
    
    @Published var quarterMileTime: Double? = nil
    @Published var quarterMileTrapSpeed: Double = 0.0
    @Published var isTimingQuarterMile: Bool = false
    private var quarterMileStartDistance: Double = 0.0
    private var quarterMileStartTime: Date?
    
    @Published var historyRecords: [SpeedHistoryRecord] = []
    @Published var overspeedLogs: [OverspeedLog] = []
    
    private var speedRecords: [Double] = []
    @Published var avgSpeed: Double = 0.0
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        setupGPS()
        setupGForce()
    }
    
    private func setupGPS() {
        locationManager.delegate = self
        updateLocationAccuracy()
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func updateLocationAccuracy() {
        if isOfflineMode {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.activityType = .automotiveNavigation
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.activityType = .automotiveNavigation
        }
    }
    
    private func setupGForce() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.03
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let userAccel = motion?.userAcceleration else { return }
                self.gForceX = userAccel.x
                self.gForceY = userAccel.y
                let currentG = sqrt(pow(userAccel.x, 2) + pow(userAccel.y, 2))
                if currentG > self.maxGForce { self.maxGForce = currentG }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 20 { return }
        
        self.isGpsReady = true
        self.userLocation = location.coordinate
        self.altitudeMeters = max(0, location.altitude)
        
        let rawSpeed = location.speed * 3.6
        let speed = rawSpeed > 0.8 ? rawSpeed : 0.0
        
        self.speedKMH = speed
        if speed > maxSpeed { maxSpeed = speed }
        
        if let last = lastLocation {
            let delta = location.distance(from: last)
            if delta > 0.5 { totalDistanceMeters += delta }
        }
        lastLocation = location
        
        if speed > 1.0 {
            speedRecords.append(speed)
            avgSpeed = speedRecords.reduce(0, +) / Double(speedRecords.count)
        }
        
        if speed == 0 {
            isTimingZeroToHundred = false; zeroToHundredStartTime = nil
            isTimingQuarterMile = false; quarterMileStartTime = nil
        } else if speed > 2.0 && zeroToHundredStartTime == nil {
            isTimingZeroToHundred = true; zeroToHundredStartTime = Date()
            isTimingQuarterMile = true; quarterMileStartTime = Date()
            quarterMileStartDistance = totalDistanceMeters
        } else {
            if speed >= 100.0 && isTimingZeroToHundred {
                if let start = zeroToHundredStartTime {
                    zeroToHundredTime = Date().timeIntervalSince(start)
                    isTimingZeroToHundred = false
                }
            }
            if isTimingQuarterMile {
                let currentTraveled = totalDistanceMeters - quarterMileStartDistance
                if currentTraveled >= 400.0 {
                    if let start = quarterMileStartTime {
                        quarterMileTime = Date().timeIntervalSince(start)
                        quarterMileTrapSpeed = speed
                        isTimingQuarterMile = false
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            self.headingDegree = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    func saveCurrentTripToHistory() {
        let record = SpeedHistoryRecord(
            date: Date(),
            maxSpeed: maxSpeed,
            zeroToHundred: zeroToHundredTime,
            quarterMile: quarterMileTime,
            maxGForce: maxGForce,
            totalDistance: totalDistanceMeters
        )
        historyRecords.insert(record, at: 0)
    }
    
    func logOverspeed(currentSpeed: Double, limit: Double) {
        let log = OverspeedLog(date: Date(), speed: currentSpeed, limit: limit)
        overspeedLogs.insert(log, at: 0)
        if overspeedLogs.count > 50 { overspeedLogs.removeLast() }
    }
    
    func resetData() {
        saveCurrentTripToHistory()
        maxSpeed = 0.0; avgSpeed = 0.0; totalDistanceMeters = 0.0; maxGForce = 0.0
        speedRecords.removeAll(); zeroToHundredTime = nil; quarterMileTime = nil
        quarterMileTrapSpeed = 0.0; isTimingZeroToHundred = false; isTimingQuarterMile = false
        zeroToHundredStartTime = nil; quarterMileStartTime = nil
    }
}

// MARK: - 4. 深度升級版開機動畫
struct BootLoadingView: View {
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0.0
    @State private var currentStepIndex = 0
    @State private var glitchEffect = false
    
    let bootSteps = [
        "INITIALIZING QUANTUM CORE...",
        "CONNECTING TO SATELLITE CONSTELLATION...",
        "CALIBRATING HIGH-PRECISION GYROSCOPE...",
        "LOADING TELEMETRY & OVERCLOCK PROFILES...",
        "SYSTEM READY. LAUNCHING INTERFACE..."
    ]
    
    let safeCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Rectangle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.clear, safeCyan.opacity(0.15), .clear]), startPoint: .top, endPoint: .bottom))
                    .frame(height: 150)
                    .offset(y: glitchEffect ? 600 : -600)
                    .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: glitchEffect)
                Spacer()
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("🏎️ PORSCHE // QUANTUM HUD")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(safeCyan)
                        .tracking(8)
                        .shadow(color: safeCyan, radius: 10)
                    
                    Text("SECURE TELEMETRY OS v4.8")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<bootSteps.count, id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: index <= currentStepIndex ? "checkmark.square.fill" : "square")
                                .foregroundColor(index <= currentStepIndex ? safeCyan : .gray)
                            Text(bootSteps[index])
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(index <= currentStepIndex ? .white : .gray.opacity(0.5))
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(safeCyan.opacity(0.3), lineWidth: 1))
                
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 320, height: 10).cornerRadius(5)
                        Rectangle().fill(LinearGradient(gradient: Gradient(colors: [safeCyan, .yellow, .red]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: 320 * progress, height: 10).cornerRadius(5)
                            .shadow(color: safeCyan, radius: 8)
                    }
                    
                    HStack {
                        Text("SYSTEM INTEGRITY CHECK")
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .foregroundColor(safeCyan)
                    }
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .frame(width: 320)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            glitchEffect = true
            withAnimation(.easeInOut(duration: 3.5)) {
                progress = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { currentStepIndex = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { currentStepIndex = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { currentStepIndex = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { currentStepIndex = 4 }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                withAnimation { isFinished = true }
            }
        }
    }
}

// MARK: - 5. 儀表裝飾元件
struct NeonArcFlowView: View {
    var speed: Double
    var maxSpeed: Double = 160.0
    var activeColor: Color
    @State private var phase: CGFloat = 0.0
    @State private var isFlowing: Bool = true
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(activeColor.opacity(0.2), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(180))
            
            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [activeColor.opacity(0.1), activeColor, .white, activeColor, activeColor.opacity(0.1)]),
                        center: .center,
                        angle: .degrees(isFlowing ? phase : 0)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(180))
                .shadow(color: activeColor, radius: 15)
        }
        .frame(width: 320, height: 160)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 360 }
        }
    }
}

struct ShiftLightsView: View {
    var speed: Double
    var maxSpeed: Double = 160.0
    var body: some View {
        let ratio = min(speed / maxSpeed, 1.0)
        let totalLights = 14
        let activeCount = Int(ratio * Double(totalLights))
        HStack(spacing: 5) {
            ForEach(0..<totalLights, id: \.self) { index in
                let isActive = index < activeCount
                let isRedZone = index >= 11
                Rectangle()
                    .fill(isActive ? (isRedZone ? Color.red : (index >= 8 ? Color.yellow : Color.green)) : Color.white.opacity(0.1))
                    .frame(height: 6).cornerRadius(3)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct GForceView: View {
    var gx: Double, gy: Double, maxG: Double, themeColor: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
            Circle().stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2])).scaleEffect(0.5)
            Path { path in
                path.move(to: CGPoint(x: 40, y: 0)); path.addLine(to: CGPoint(x: 40, y: 80))
                path.move(to: CGPoint(x: 0, y: 40)); path.addLine(to: CGPoint(x: 80, y: 40))
            }.stroke(Color.white.opacity(0.15), lineWidth: 1)
            let posX = CGFloat(min(max(gx, -1.0), 1.0)) * 35
            let posY = CGFloat(min(max(-gy, -1.0), 1.0)) * 35
            Circle().fill(themeColor).frame(width: 9, height: 9).offset(x: posX, y: posY)
            VStack {
                Spacer()
                Text(String(format: "MAX %.2fG", maxG)).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 80, height: 80).background(Color.black.opacity(0.6)).cornerRadius(40)
        .overlay(Circle().stroke(themeColor.opacity(0.4), lineWidth: 1.5))
    }
}

struct MapTrackingView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsTraffic = true
        return mapView
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = userLocation {
            let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
            uiView.setRegion(region, animated: true)
        }
    }
}

// MARK: - 6. 主畫面 (支援地圖開關切換、滿屏速度表與直橫向切換)
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isBootCompleted = false
    @State private var isHUDMode = false
    @State private var showMap = false
    @State private var showSettings = false
    @State private var currentTime = Date()
    @State private var isPortraitForced = false
    
    @AppStorage("savedSpeedLimit") private var speedLimit: Double = 110.0
    @AppStorage("savedThemeRaw") private var savedThemeRaw: String = DashboardTheme.porsche.rawValue
    @AppStorage("customNeonColorRed") private var customRed: Double = 0.0
    @AppStorage("customNeonColorGreen") private var customGreen: Double = 0.9
    @AppStorage("customNeonColorBlue") private var customBlue: Double = 1.0
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    
    @State private var flashWarning = false
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var selectedTheme: DashboardTheme {
        get { DashboardTheme(rawValue: savedThemeRaw) ?? .porsche }
        set { savedThemeRaw = newValue.rawValue }
    }
    
    var bindingTheme: Binding<DashboardTheme> {
        Binding(
            get: { DashboardTheme(rawValue: savedThemeRaw) ?? .porsche },
            set: { newValue in savedThemeRaw = newValue.rawValue }
        )
    }
    
    var activePrimaryColor: Color {
        if speedManager.speedKMH > speedLimit { return .red }
        if useCustomColor {
            return Color(red: customRed, green: customGreen, blue: customBlue)
        }
        return selectedTheme.primaryColor
    }
    
    let customCyan = Color(red: 0.0, green: 0.8, blue: 1.0)
    
    var body: some View {
        ZStack {
            if !isBootCompleted {
                BootLoadingView(isFinished: $isBootCompleted)
            } else {
                GeometryReader { geometry in
                    let screenWidth = geometry.size.width
                    let screenHeight = geometry.size.height
                    let isPortrait = isPortraitForced || (screenWidth < screenHeight)
                    
                    ZStack {
                        // 修正：只有當開啟地圖且有定位時顯示地圖；關閉時維持原本暗色背景
                        if showMap, let location = speedManager.userLocation {
                            MapTrackingView(userLocation: location)
                                .edgesIgnoringSafeArea(.all)
                                .overlay(Color.black.opacity(0.3))
                        } else {
                            Color(red: 0.02, green: 0.02, blue: 0.04).edgesIgnoringSafeArea(.all)
                        }
                        
                        if speedManager.speedKMH > speedLimit && flashWarning {
                            Color.red.opacity(0.3).edgesIgnoringSafeArea(.all)
                        }
                        
                        VStack(spacing: 0) {
                            // 頂端工具列
                            HStack(alignment: .center, spacing: 6) {
                                Text(currentTime, style: .time)
                                    .font(.system(size: isPortrait ? 14 : 16, weight: .black, design: .monospaced))
                                    .foregroundColor(activePrimaryColor)
                                    .padding(6)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(6)
                                
                                Spacer()
                                
                                // 直向/橫向切換按鈕
                                Button(action: {
                                    withAnimation { isPortraitForced.toggle() }
                                    AudioServicesPlaySystemSound(1105)
                                }) {
                                    Text(isPortraitForced ? "直向" : "橫向")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.4))
                                        .foregroundColor(customCyan)
                                        .cornerRadius(6)
                                }
                                
                                // 地圖開關按鈕
                                Button(action: {
                                    withAnimation { showMap.toggle() }
                                    AudioServicesPlaySystemSound(1105)
                                }) {
                                    Text(showMap ? "地圖:開" : "地圖:關")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(showMap ? activePrimaryColor : Color.black.opacity(0.6))
                                        .foregroundColor(showMap ? .black : .white)
                                        .cornerRadius(6)
                                }
                                
                                Button(action: { isHUDMode.toggle() }) {
                                    Text("HUD")
                                        .font(.caption.bold())
                                        .padding(6)
                                        .background(isHUDMode ? Color.orange : Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                
                                Button(action: { showSettings.toggle() }) {
                                    Image(systemName: "gearshape.fill")
                                        .padding(6)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, geometry.safeAreaInsets.top + 5)
                            
                            if !isHUDMode {
                                ShiftLightsView(speed: speedManager.speedKMH)
                                    .padding(.top, 6)
                            }
                            
                            Spacer()
                            
                            // 滿屏幕放大版速度計
                            let gaugeSize = isPortrait ? screenWidth * 0.85 : min(screenWidth, screenHeight) * 0.75
                            let progress = min(speedManager.speedKMH / 160.0, 1.0)
                            
                            VStack(spacing: 15) {
                                ZStack {
                                    if !isHUDMode {
                                        NeonArcFlowView(speed: speedManager.speedKMH, activeColor: activePrimaryColor)
                                            .scaleEffect(isPortrait ? 1.1 : 1.25)
                                    }
                                    
                                    Circle()
                                        .trim(from: 0.125, to: 0.875)
                                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                                        .rotationEffect(.degrees(90))
                                        .frame(width: gaugeSize, height: gaugeSize)
                                    
                                    Circle()
                                        .trim(from: 0.125, to: 0.125 + (0.75 * CGFloat(progress)))
                                        .stroke(
                                            LinearGradient(gradient: Gradient(colors: [selectedTheme.secondaryColor, activePrimaryColor]), startPoint: .leading, endPoint: .trailing),
                                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(90))
                                        .frame(width: gaugeSize, height: gaugeSize)
                                        .shadow(color: activePrimaryColor.opacity(0.9), radius: 20)
                                    
                                    VStack(spacing: 4) {
                                        Text("\(Int(round(speedManager.speedKMH)))")
                                            .font(.system(size: gaugeSize * 0.36, weight: .black, design: .monospaced))
                                            .foregroundColor(activePrimaryColor)
                                            .shadow(color: activePrimaryColor.opacity(0.8), radius: 12)
                                        
                                        Text("KM/H // 滿屏速度表")
                                            .font(.system(size: gaugeSize * 0.065, weight: .heavy, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.9))
                                            .tracking(6)
                                        
                                        if speedManager.speedKMH > speedLimit {
                                            Text("⚠️ 速度制限オーバー")
                                                .font(.system(size: gaugeSize * 0.045, weight: .black, design: .monospaced))
                                                .foregroundColor(.red)
                                                .padding(.top, 2)
                                        }
                                    }
                                }
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(activePrimaryColor.opacity(0.4), lineWidth: 2))
                                
                                if !isHUDMode && !isPortrait {
                                    GForceView(gx: speedManager.gForceX, gy: speedManager.gForceY, maxG: speedManager.maxGForce, themeColor: activePrimaryColor)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Spacer()
                            
                            // 底部行車數據列
                            if !isHUDMode {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("0-100").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        if let t = speedManager.zeroToHundredTime {
                                            Text(String(format: "%.2fs", t)).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.green)
                                        } else {
                                            Text(speedManager.isTimingZeroToHundred ? "TIMING" : "READY").font(.system(size: 10, weight: .bold)).foregroundColor(.yellow)
                                        }
                                    }.frame(maxWidth: .infinity)
                                    
                                    Divider().background(Color.white.opacity(0.2)).frame(height: 25)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TRIP DIST").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        Text(String(format: "%.2fkm", speedManager.totalDistanceMeters / 1000.0)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white)
                                    }.frame(maxWidth: .infinity)
                                    
                                    Divider().background(Color.white.opacity(0.2)).frame(height: 25)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("MAX SPEED").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        Text(String(format: "%.0fkm/h", speedManager.maxSpeed)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                                    }.frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.black.opacity(0.85))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(activePrimaryColor.opacity(0.4), lineWidth: 1))
                                .cornerRadius(12)
                                .padding(.horizontal, 20).padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section(header: Text("定位設定")) {
                        Toggle("離線精準模式 (停用網路輔助)", isOn: $speedManager.isOfflineMode)
                    }
                    
                    Section(header: Text("視覺主題")) {
                        Picker("風格主題", selection: bindingTheme) {
                            ForEach(DashboardTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    Section(header: Text("安全警報")) {
                        HStack {
                            Text("速限警報")
                            Spacer()
                            Text("\(Int(speedLimit)) km/h").bold().foregroundColor(.orange)
                        }
                        Slider(value: $speedLimit, in: 30...200, step: 5)
                    }
                    
                    Section(header: Text("歷史行程與超速紀錄")) {
                        NavigationLink(destination: HistoryView(speedManager: speedManager)) {
                            Label("查看歷史操作紀錄 (\(speedManager.historyRecords.count))", systemImage: "clock.arrow.circlepath")
                        }
                        NavigationLink(destination: OverspeedLogView(speedManager: speedManager)) {
                            Label("查看超速違規紀錄 (\(speedManager.overspeedLogs.count))", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(speedManager.overspeedLogs.isEmpty ? .primary : .red)
                        }
                    }
                    
                    Section(header: Text("行車電腦")) {
                        Button(action: { speedManager.resetData() }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("重置目前數據並封存至歷史紀錄")
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle("⚙️ 儀表板設定")
                .navigationBarItems(trailing: Button("完成") { showSettings = false })
            }
        }
        .onReceive(timer) { _ in
            if isBootCompleted {
                self.currentTime = Date()
                if speedManager.speedKMH > speedLimit {
                    flashWarning.toggle()
                    AudioServicesPlaySystemSound(1005)
                    speedManager.logOverspeed(currentSpeed: speedManager.speedKMH, limit: speedLimit)
                } else {
                    flashWarning = false
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// MARK: - 7. 歷史紀錄列表頁面
struct HistoryView: View {
    @ObservedObject var speedManager: SpeedometerManager
    var body: some View {
        List {
            if speedManager.historyRecords.isEmpty {
                Text("尚無歷史紀錄，點擊重置行車電腦可封存當次行程。").foregroundColor(.gray)
            } else {
                ForEach(speedManager.historyRecords) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.date, style: .date) + Text(" ") + Text(record.date, style: .time)
                            .font(.caption).bold().foregroundColor(.gray)
                        
                        HStack {
                            Text("極速: \(Int(record.maxSpeed)) km/h").bold().foregroundColor(.orange)
                            Spacer()
                            Text(String(format: "里程: %.2fkm", record.totalDistance / 1000.0)).bold()
                        }
                        HStack {
                            if let t100 = record.zeroToHundred {
                                Text("0-100: \(String(format: "%.2fs", t100))").foregroundColor(.green)
                            }
                            Spacer()
                            Text(String(format: "最大G力: %.2fG", record.maxGForce)).foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("📜 歷史操作紀錄")
    }
}

// MARK: - 8. 超速紀錄列表頁面
struct OverspeedLogView: View {
    @ObservedObject var speedManager: SpeedometerManager
    var body: some View {
        List {
            if speedManager.overspeedLogs.isEmpty {
                Text("太棒了！目前沒有任何超速紀錄。").foregroundColor(.gray)
            } else {
                ForEach(speedManager.overspeedLogs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.date, style: .date) + Text(" ") + Text(log.date, style: .time)
                                .font(.caption).bold().foregroundColor(.gray)
                            Text("当前速限: \(Int(log.limit)) km/h")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(log.speed)) km/h")
                                .font(.headline).bold()
                                .foregroundColor(.red)
                            Text("⚠️ 速度制限オーバー")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("⚠️ 超速紀錄表")
    }
}
