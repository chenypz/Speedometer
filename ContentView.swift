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

// MARK: - 2. 主題風格
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

// MARK: - 3. GPS + G-Force 核心 (行車電腦數據)
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
    
    @Published var historyRecords: [SpeedHistoryRecord] = []
    @Published var overspeedLogs: [OverspeedLog] = []
    
    private var speedRecords: [Double] = []
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
        
        if speed == 0 {
            isTimingZeroToHundred = false; zeroToHundredStartTime = nil
        } else if speed > 2.0 && zeroToHundredStartTime == nil {
            isTimingZeroToHundred = true; zeroToHundredStartTime = Date()
        } else {
            if speed >= 100.0 && isTimingZeroToHundred {
                if let start = zeroToHundredStartTime {
                    zeroToHundredTime = Date().timeIntervalSince(start)
                    isTimingZeroToHundred = false
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
            quarterMile: nil,
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
        maxSpeed = 0.0; totalDistanceMeters = 0.0; maxGForce = 0.0
        speedRecords.removeAll(); zeroToHundredTime = nil; isTimingZeroToHundred = false
        zeroToHundredStartTime = nil
    }
}

// MARK: - 4. 長亮流水燈動畫背景
struct CyberpunkAnimatedBackground: View {
    var activeColor: Color
    @State private var phase: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.01, blue: 0.02).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 35) {
                ForEach(0..<14, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, activeColor.opacity(0.18), .clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1.5)
                        .offset(x: sin(phase + CGFloat(i)) * 120)
                }
            }
            .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - 5. 開機動畫
struct BootLoadingView: View {
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0.0
    @State private var currentStepIndex = 0
    let bootSteps = [
        "INITIALIZING iPHONE 11 TELEMETRY...",
        "CONNECTING TO SATELLITE...",
        "CALIBRATING G-FORCE SENSORS...",
        "SYSTEM READY..."
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Text("🏎️ PORSCHE // HUD SYSTEM")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(Color.cyan)
                    .tracking(4)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<bootSteps.count, id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: index <= currentStepIndex ? "checkmark.square.fill" : "square")
                                .foregroundColor(index <= currentStepIndex ? .cyan : .gray)
                            Text(bootSteps[index])
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(index <= currentStepIndex ? .white : .gray)
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 280, height: 8).cornerRadius(4)
                    Rectangle().fill(Color.cyan).frame(width: 280 * progress, height: 8).cornerRadius(4)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5)) { progress = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { currentStepIndex = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { currentStepIndex = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { currentStepIndex = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
                withAnimation { isFinished = true }
            }
        }
    }
}

// MARK: - 6. 專業賽道與裝飾元件
struct NeonArcFlowView: View {
    var activeColor: Color
    @State private var phase: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [activeColor.opacity(0.1), activeColor, .white, activeColor, activeColor.opacity(0.1)]),
                        center: .center,
                        angle: .degrees(phase)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(180))
                .shadow(color: activeColor, radius: 12)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 360 }
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
        HStack(spacing: 4) {
            ForEach(0..<totalLights, id: \.self) { index in
                let isActive = index < activeCount
                let isRedZone = index >= 11
                Rectangle()
                    .fill(isActive ? (isRedZone ? Color.red : (index >= 8 ? Color.yellow : Color.green)) : Color.white.opacity(0.1))
                    .frame(height: 5).cornerRadius(2.5)
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
            Path { path in
                path.move(to: CGPoint(x: 35, y: 0)); path.addLine(to: CGPoint(x: 35, y: 70))
                path.move(to: CGPoint(x: 0, y: 35)); path.addLine(to: CGPoint(x: 70, y: 35))
            }.stroke(Color.white.opacity(0.15), lineWidth: 1)
            let posX = CGFloat(min(max(gx, -1.0), 1.0)) * 30
            let posY = CGFloat(min(max(-gy, -1.0), 1.0)) * 30
            Circle().fill(themeColor).frame(width: 8, height: 8).offset(x: posX, y: posY)
            VStack {
                Spacer()
                Text(String(format: "MAX %.2fG", maxG)).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 70, height: 70).background(Color.black.opacity(0.6)).cornerRadius(35)
        .overlay(Circle().stroke(themeColor.opacity(0.4), lineWidth: 1))
    }
}

struct MapTrackingView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = userLocation {
            let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
            uiView.setRegion(region, animated: true)
        }
    }
}

// MARK: - 7. 主畫面 (完整保留所有功能並完美整合方向切換與版面縮放)
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isBootCompleted = false
    @State private var isHUDMode = false
    @State private var showMap = false
    @State private var showSettings = false
    @State private var currentTime = Date()
    @State private var isPortraitMode = false // 預設橫向，點擊按鈕可隨時切換為直向
    
    @AppStorage("savedSpeedLimit") private var speedLimit: Double = 110.0
    @AppStorage("savedThemeRaw") private var savedThemeRaw: String = DashboardTheme.porsche.rawValue
    @AppStorage("customColorRed") private var customRed: Double = 0.0
    @AppStorage("customColorGreen") private var customGreen: Double = 0.9
    @AppStorage("customColorBlue") private var customBlue: Double = 1.0
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    
    @State private var flashWarning = false
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
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
        let theme = DashboardTheme(rawValue: savedThemeRaw) ?? .porsche
        return theme.primaryColor
    }
    
    var body: some View {
        ZStack {
            if !isBootCompleted {
                BootLoadingView(isFinished: $isBootCompleted)
            } else {
                GeometryReader { geometry in
                    let screenWidth = geometry.size.width
                    let screenHeight = geometry.size.height
                    let isReallyPortrait = isPortraitMode
                    
                    ZStack {
                        if showMap, let location = speedManager.userLocation {
                            MapTrackingView(userLocation: location)
                                .edgesIgnoringSafeArea(.all)
                                .overlay(Color.black.opacity(0.3))
                        } else {
                            CyberpunkAnimatedBackground(activeColor: activePrimaryColor)
                                .edgesIgnoringSafeArea(.all)
                        }
                        
                        if speedManager.speedKMH > speedLimit && flashWarning {
                            Color.red.opacity(0.3).edgesIgnoringSafeArea(.all)
                        }
                        
                        VStack(spacing: 0) {
                            // 頂端工具列（包含時間、方向切換、地圖、HUD、設定）
                            HStack(spacing: 8) {
                                Text(currentTime, style: .time)
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(activePrimaryColor)
                                    .padding(5)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(6)
                                
                                Spacer()
                                
                                // 直向/橫向切換按鈕
                                Button(action: {
                                    withAnimation { isPortraitMode.toggle() }
                                    AudioServicesPlaySystemSound(1105)
                                }) {
                                    Text(isPortraitMode ? "切換:橫向" : "切換:直向")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.5))
                                        .foregroundColor(.white)
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
                                
                                // HUD 模式開關按鈕
                                Button(action: { isHUDMode.toggle() }) {
                                    Text("HUD")
                                        .font(.caption.bold())
                                        .padding(5)
                                        .background(isHUDMode ? Color.orange : Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                                
                                // 設定選單按鈕
                                Button(action: { showSettings.toggle() }) {
                                    Image(systemName: "gearshape.fill")
                                        .padding(6)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, max(geometry.safeAreaInsets.top, 10))
                            
                            // 專業賽道轉速燈
                            if !isHUDMode {
                                ShiftLightsView(speed: speedManager.speedKMH)
                                    .padding(.top, 4)
                            }
                            
                            Spacer()
                            
                            // 速度計主體與 G力感應器
                            let gaugeSize = isReallyPortrait ? screenWidth * 0.70 : min(screenWidth, screenHeight) * 0.60
                            let progress = min(speedManager.speedKMH / 160.0, 1.0)
                            
                            VStack(spacing: 10) {
                                ZStack {
                                    if !isHUDMode {
                                        NeonArcFlowView(activeColor: activePrimaryColor)
                                            .frame(width: gaugeSize, height: gaugeSize)
                                    }
                                    
                                    Circle()
                                        .trim(from: 0.125, to: 0.875)
                                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                                        .rotationEffect(.degrees(90))
                                        .frame(width: gaugeSize, height: gaugeSize)
                                    
                                    Circle()
                                        .trim(from: 0.125, to: 0.125 + (0.75 * CGFloat(progress)))
                                        .stroke(activePrimaryColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                        .rotationEffect(.degrees(90))
                                        .frame(width: gaugeSize, height: gaugeSize)
                                        .shadow(color: activePrimaryColor, radius: 10)
                                    
                                    VStack(spacing: 2) {
                                        Text("\(Int(round(speedManager.speedKMH)))")
                                            .font(.system(size: gaugeSize * 0.35, weight: .black, design: .monospaced))
                                            .foregroundColor(activePrimaryColor)
                                            .shadow(color: activePrimaryColor.opacity(0.8), radius: 10)
                                        
                                        Text("KM/H")
                                            .font(.system(size: gaugeSize * 0.07, weight: .heavy, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.8))
                                            .tracking(4)
                                    }
                                }
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                                
                                // G力感應器
                                if !isHUDMode && !isReallyPortrait {
                                    GForceView(gx: speedManager.gForceX, gy: speedManager.gForceY, maxG: speedManager.maxGForce, themeColor: activePrimaryColor)
                                }
                            }
                            
                            Spacer()
                            
                            // 完美保留您重視的核心數據列（0-100加速計時、TRIP DIST 總里程、MAX SPEED 歷史極速）
                            if !isHUDMode {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("0-100").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        if let t = speedManager.zeroToHundredTime {
                                            Text(String(format: "%.2fs", t)).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.green)
                                        } else {
                                            Text(speedManager.isTimingZeroToHundred ? "TIMING" : "READY").font(.system(size: 9, weight: .bold)).foregroundColor(.yellow)
                                        }
                                    }.frame(maxWidth: .infinity)
                                    
                                    Divider().background(Color.white.opacity(0.2)).frame(height: 22)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TRIP DIST").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        Text(String(format: "%.2fkm", speedManager.totalDistanceMeters / 1000.0)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white)
                                    }.frame(maxWidth: .infinity)
                                    
                                    Divider().background(Color.white.opacity(0.2)).frame(height: 22)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("MAX SPEED").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        Text(String(format: "%.0fkm/h", speedManager.maxSpeed)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                                    }.frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.black.opacity(0.85))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(activePrimaryColor.opacity(0.4), lineWidth: 1))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 10))
                            }
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section(header: Text("視覺主題與自訂調色盤")) {
                        Picker("風格主題", selection: bindingTheme) {
                            ForEach(DashboardTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Toggle("啟用自訂調色", isOn: $useCustomColor)
                        if useCustomColor {
                            ColorPicker("自訂流水燈與主色", selection: Binding(
                                get: { Color(red: customRed, green: customGreen, blue: customBlue) },
                                set: { newColor in
                                    if let components = UIColor(newColor).cgColor.components, components.count >= 3 {
                                        customRed = Double(components[0])
                                        customGreen = Double(components[1])
                                        customBlue = Double(components[2])
                                    }
                                }
                            ))
                        }
                    }
                    
                    Section(header: Text("安全速限警報")) {
                        Slider(value: $speedLimit, in: 30...200, step: 5) {
                            Text("速限: \(Int(speedLimit)) km/h")
                        }
                    }
                    
                    Section(header: Text("行車電腦與歷史紀錄")) {
                        Button(action: { speedManager.resetData() }) {
                            Text("重置目前數據並封存至歷史紀錄").foregroundColor(.red)
                        }
                        
                        // 歷史紀錄檢視清單
                        NavigationLink(destination: HistoryRecordsView(speedManager: speedManager)) {
                            Text("檢視歷史行程封存紀錄 (\(speedManager.historyRecords.count) 筆)")
                        }
                        
                        // 超速違規清單
                        NavigationLink(destination: OverspeedLogsView(speedManager: speedManager)) {
                            Text("檢視超速違規紀錄 (\(speedManager.overspeedLogs.count) 筆)")
                        }
                    }
                }
                .navigationTitle("⚙️ 設定與行車電腦")
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

// MARK: - 8. 歷史紀錄與超速清單檢視頁面
struct HistoryRecordsView: View {
    @ObservedObject var speedManager: SpeedometerManager
    
    var body: some View {
        List {
            ForEach(speedManager.historyRecords) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.date, style: .date) + Text(" ") + Text(record.date, style: .time)
                        .font(.caption).foregroundColor(.gray)
                    HStack {
                        Text("極速: \(Int(record.maxSpeed)) km/h")
                        Spacer()
                        Text("里程: \(String(format: "%.2f km", record.totalDistance / 1000.0))")
                    }
                    .font(.subheadline.bold())
                    
                    if let t = record.zeroToHundred {
                        Text(String(format: "0-100加速: %.2f 秒", t))
                            .font(.footnote).foregroundColor(.green)
                    }
                    Text(String(format: "最大G力: %.2f G", record.maxGForce))
                        .font(.footnote).foregroundColor(.orange)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("🏁 行程歷史封存紀錄")
    }
}

struct OverspeedLogsView: View {
    @ObservedObject var speedManager: SpeedometerManager
    
    var body: some View {
        List {
            ForEach(speedManager.overspeedLogs) { log in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.date, style: .date) + Text(" ") + Text(log.date, style: .time)
                            .font(.caption).foregroundColor(.gray)
                        Text(String(format: "違規車速: %.1f km/h", log.speed))
                            .font(.subheadline.bold()).foregroundColor(.red)
                    }
                    Spacer()
                    Text(String(format: "限速 %.0f", log.limit))
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("⚠️ 超速違規清單")
    }
}
