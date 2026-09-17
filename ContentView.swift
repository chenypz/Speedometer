import SwiftUI
import MapKit
import CoreLocation
import CoreMotion
import Combine
import AudioToolbox

// MARK: - 1. 主題風格
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

// MARK: - 2. GPS + G-Force + 0-400m 行車數據核心
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
    
    // G-Force 重力感應
    @Published var gForceX: Double = 0.0
    @Published var gForceY: Double = 0.0
    @Published var maxGForce: Double = 0.0
    
    // 0-100 km/h 測速
    @Published var zeroToHundredTime: Double? = nil
    @Published var isTimingZeroToHundred: Bool = false
    private var zeroToHundredStartTime: Date?
    
    // 0-400m 直線加速測速
    @Published var quarterMileTime: Double? = nil
    @Published var quarterMileTrapSpeed: Double = 0.0
    @Published var isTimingQuarterMile: Bool = false
    private var quarterMileStartDistance: Double = 0.0
    private var quarterMileStartTime: Date?
    
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
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func setupGForce() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.03
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let userAccel = motion?.userAcceleration else { return }
                
                self.gForceX = userAccel.x
                self.gForceY = userAccel.y
                
                let currentG = sqrt(pow(userAccel.x, 2) + pow(userAccel.y, 2))
                if currentG > self.maxGForce {
                    self.maxGForce = currentG
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        self.isGpsReady = true
        self.userLocation = location.coordinate
        self.altitudeMeters = max(0, location.altitude)
        
        let speed = max(0, location.speed * 3.6)
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
        
        // 0-100 km/h 與 0-400m 測速邏輯
        if speed == 0 {
            isTimingZeroToHundred = false
            zeroToHundredStartTime = nil
            
            isTimingQuarterMile = false
            quarterMileStartTime = nil
        } else if speed > 2.0 && zeroToHundredStartTime == nil {
            isTimingZeroToHundred = true
            zeroToHundredStartTime = Date()
            
            isTimingQuarterMile = true
            quarterMileStartTime = Date()
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
    
    func resetData() {
        maxSpeed = 0.0
        avgSpeed = 0.0
        totalDistanceMeters = 0.0
        maxGForce = 0.0
        speedRecords.removeAll()
        zeroToHundredTime = nil
        quarterMileTime = nil
        quarterMileTrapSpeed = 0.0
        isTimingZeroToHundred = false
        isTimingQuarterMile = false
        zeroToHundredStartTime = nil
        quarterMileStartTime = nil
    }
    
    var headingDirectionText: String {
        let degrees = headingDegree
        switch degrees {
        case 22.5..<67.5: return "NE \(Int(degrees))°"
        case 67.5..<112.5: return "E \(Int(degrees))°"
        case 112.5..<157.5: return "SE \(Int(degrees))°"
        case 157.5..<202.5: return "S \(Int(degrees))°"
        case 202.5..<247.5: return "SW \(Int(degrees))°"
        case 247.5..<292.5: return "W \(Int(degrees))°"
        case 292.5..<337.5: return "NW \(Int(degrees))°"
        default: return "N \(Int(degrees))°"
        }
    }
}

// MARK: - 3. G-Force 動態雷達圖
struct GForceView: View {
    var gx: Double
    var gy: Double
    var maxG: Double
    var themeColor: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
            Circle()
                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))
                .scaleEffect(0.5)
            
            Path { path in
                path.move(to: CGPoint(x: 35, y: 0))
                path.addLine(to: CGPoint(x: 35, y: 70))
                path.move(to: CGPoint(x: 0, y: 35))
                path.addLine(to: CGPoint(x: 70, y: 35))
            }
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
            
            let posX = CGFloat(min(max(gx, -1.0), 1.0)) * 30
            let posY = CGFloat(min(max(-gy, -1.0), 1.0)) * 30
            
            Circle()
                .fill(themeColor)
                .frame(width: 8, height: 8)
                .shadow(color: themeColor, radius: 4)
                .offset(x: posX, y: posY)
            
            VStack {
                Spacer()
                Text(String(format: "MAX %.2fG", maxG))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 70, height: 70)
        .background(Color.black.opacity(0.4))
        .cornerRadius(35)
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - 4. 地圖包裝器
struct MapTrackingView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.overrideUserInterfaceStyle = .dark
        mapView.isUserInteractionEnabled = false
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = userLocation {
            let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))
            uiView.setRegion(region, animated: true)
        }
    }
}

// MARK: - 5. 主畫面 (全功能整合 + 夜間 HUD 模式)
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHUDMode = false
    @State private var showMap = false
    @State private var showSettings = false
    @State private var currentTime = Date()
    
    @State private var speedLimit: Double = 110.0
    @State private var selectedTheme: DashboardTheme = .porsche
    @State private var flashWarning = false
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var isOverspeed: Bool { speedManager.speedKMH > speedLimit }
    var activePrimaryColor: Color { isOverspeed ? .red : selectedTheme.primaryColor }
    
    // 相容舊版 iOS 的青色定義
    let customCyan = Color(red: 0.0, green: 0.8, blue: 1.0)
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isLandscape = screenWidth > screenHeight
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if showMap && !isHUDMode, let location = speedManager.userLocation {
                    MapTrackingView(userLocation: location)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(Color.black.opacity(0.55))
                }
                
                if isOverspeed && flashWarning {
                    Color.red.opacity(0.25).edgesIgnoringSafeArea(.all)
                }
                
                VStack(spacing: 0) {
                    
                    // 頂部導覽列
                    HStack(alignment: .center, spacing: 8) {
                        Text(currentTime, style: .time)
                            .font(.system(size: isLandscape ? screenHeight * 0.045 : screenWidth * 0.038, weight: .bold, design: .monospaced))
                            .foregroundColor(activePrimaryColor)
                        
                        Spacer()
                        
                        if !isHUDMode {
                            HStack(spacing: 8) {
                                Text("⛰️ \(Int(speedManager.altitudeMeters))m")
                                Text("🧭 \(speedManager.headingDirectionText)")
                            }
                            .font(.system(size: isLandscape ? screenHeight * 0.032 : screenWidth * 0.028, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            
                            Spacer()
                        }
                        
                        if !isHUDMode {
                            Button(action: { withAnimation { showMap.toggle() } }) {
                                Image(systemName: "map.fill")
                                    .padding(6)
                                    .background(showMap ? activePrimaryColor : Color.gray.opacity(0.3))
                                    .foregroundColor(showMap ? .black : .white)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Button(action: { isHUDMode.toggle() }) {
                            Text("HUD")
                                .font(.caption.bold())
                                .padding(6)
                                .background(isHUDMode ? Color.orange : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        if !isHUDMode {
                            Button(action: { showSettings.toggle() }) {
                                Image(systemName: "gearshape.fill")
                                    .padding(6)
                                    .background(Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geometry.safeAreaInsets.top + 5)
                    
                    Spacer()
                    
                    // 中央區域
                    let gaugeSize = isLandscape ? min(screenWidth, screenHeight) * 0.72 : screenWidth * 0.78
                    let progress = min(speedManager.speedKMH / 160.0, 1.0)
                    
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .trim(from: 0.125, to: 0.875)
                                .stroke(Color.gray.opacity(isHUDMode ? 0.05 : 0.2), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .rotationEffect(.degrees(90))
                                .frame(width: gaugeSize, height: gaugeSize)
                            
                            Circle()
                                .trim(from: 0.125, to: 0.125 + (0.75 * CGFloat(progress)))
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [selectedTheme.secondaryColor, activePrimaryColor]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                                )
                                .rotationEffect(.degrees(90))
                                .frame(width: gaugeSize, height: gaugeSize)
                                .shadow(color: activePrimaryColor.opacity(0.85), radius: 12)
                            
                            VStack(spacing: 0) {
                                Text("\(Int(round(speedManager.speedKMH)))")
                                    .font(.system(size: gaugeSize * 0.38, weight: .black, design: .rounded))
                                    .foregroundColor(activePrimaryColor)
                                    .shadow(color: activePrimaryColor.opacity(0.8), radius: 12)
                                
                                Text("KM/H")
                                    .font(.system(size: gaugeSize * 0.08, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .tracking(4)
                                
                                if isOverspeed {
                                    Text("⚠️ OVER SPEED")
                                        .font(.system(size: gaugeSize * 0.06, weight: .bold))
                                        .foregroundColor(.red)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        
                        if !isHUDMode {
                            GForceView(gx: speedManager.gForceX, gy: speedManager.gForceY, maxG: speedManager.maxGForce, themeColor: activePrimaryColor)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Spacer()
                    
                    // 📊 底部行車電腦
                    if !isHUDMode {
                        HStack(spacing: 8) {
                            // 0-100 km/h
                            VStack(alignment: .leading, spacing: 2) {
                                Text("0-100 KM/H").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                if let t = speedManager.zeroToHundredTime {
                                    Text(String(format: "%.2fs", t)).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundColor(.green)
                                } else {
                                    Text(speedManager.isTimingZeroToHundred ? "TIMING" : "READY").font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
                                }
                            }.frame(maxWidth: .infinity)
                            
                            Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                            
                            // 0-400m (已修正青色相容性)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("0-400M").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                if let t = speedManager.quarterMileTime {
                                    Text(String(format: "%.1fs@%.0f", t, speedManager.quarterMileTrapSpeed)).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(customCyan)
                                } else {
                                    Text(speedManager.isTimingQuarterMile ? "TIMING" : "READY").font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
                                }
                            }.frame(maxWidth: .infinity)
                            
                            Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                            
                            // TRIP
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TRIP").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                Text(String(format: "%.2fkm", speedManager.totalDistanceMeters / 1000.0)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white)
                            }.frame(maxWidth: .infinity)
                            
                            Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                            
                            // MAX SPEED
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MAX SPEED").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                Text(String(format: "%.0fkm/h", speedManager.maxSpeed)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                            }.frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                }
                .scaleEffect(x: isHUDMode ? -1 : 1, y: 1)
            }
            
            // ⚙️ 設定 Sheet
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    Form {
                        Section(header: Text("視覺主題")) {
                            Picker("風格主題", selection: $selectedTheme) {
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
                        
                        Section(header: Text("重置數據")) {
                            Button(action: { speedManager.resetData() }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("重置行車電腦 (0-100 / 0-400m / G-Force)")
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .navigationTitle("⚙️ 儀表板設定")
                    .navigationBarItems(trailing: Button("完成") { showSettings = false })
                }
            }
        }
        .onReceive(timer) { _ in
            self.currentTime = Date()
            if isOverspeed {
                flashWarning.toggle()
                AudioServicesPlaySystemSound(1005)
            } else {
                flashWarning = false
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
