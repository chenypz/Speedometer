import SwiftUI
import MapKit
import CoreLocation
import Combine
import AudioToolbox

// MARK: - 1. 高階行車電腦 GPS 管理器
class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var speedKMH: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var totalDistanceMeters: Double = 0.0 // 總行程距離
    @Published var altitudeMeters: Double = 0.0 // 海拔
    @Published var headingDegree: Double = 0.0 // 方位角
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isGpsReady: Bool = false
    
    // 0-100 加速計時狀態
    @Published var zeroToHundredTime: Double? = nil
    @Published var isTimingZeroToHundred: Bool = false
    private var zeroToHundredStartTime: Date?
    
    // 平均車速計算
    private var speedRecords: [Double] = []
    @Published var avgSpeed: Double = 0.0
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        self.isGpsReady = true
        self.userLocation = location.coordinate
        self.altitudeMeters = max(0, location.altitude)
        
        let speed = max(0, location.speed * 3.6)
        self.speedKMH = speed
        
        // 更新極速
        if speed > maxSpeed {
            maxSpeed = speed
        }
        
        // 計算累積距離與平均時速
        if let last = lastLocation {
            let delta = location.distance(from: last)
            if delta > 0.5 {
                totalDistanceMeters += delta
            }
        }
        lastLocation = location
        
        if speed > 1.0 {
            speedRecords.append(speed)
            avgSpeed = speedRecords.reduce(0, +) / Double(speedRecords.count)
        }
        
        // 0-100 km/h 加速測速邏輯
        if speed == 0 {
            isTimingZeroToHundred = false
            zeroToHundredStartTime = nil
        } else if speed > 2.0 && speed < 100.0 && zeroToHundredStartTime == nil && zeroToHundredTime == nil {
            isTimingZeroToHundred = true
            zeroToHundredStartTime = Date()
        } else if speed >= 100.0 && isTimingZeroToHundred {
            if let start = zeroToHundredStartTime {
                zeroToHundredTime = Date().timeIntervalSince(start)
                isTimingZeroToHundred = false
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
        speedRecords.removeAll()
        zeroToHundredTime = nil
        isTimingZeroToHundred = false
        zeroToHundredStartTime = nil
    }
    
    // 指南針方位轉文字
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

// MARK: - 2. 地圖元件
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

// MARK: - 3. 主畫面 (保時捷風格 + 警報 + 行車數據)
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHUDMode = false
    @State private var showMap = false
    @State private var showSettings = false // 設定選單開關
    @State private var currentTime = Date()
    
    // 設定參數
    @State private var speedLimit: Double = 110.0 // 超速警報上限 (km/h)
    @State private var isPorscheTheme: Bool = true // 主題切換 (保時捷風 / 賽博朋克)
    @State private var flashWarning = false
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var isOverspeed: Bool {
        return speedManager.speedKMH > speedLimit
    }
    
    // 保時捷經典配色 (高對比賽車黃 + 純白) / 賽博青色
    var primaryThemeColor: Color {
        if isOverspeed { return .red }
        return isPorscheTheme ? Color(red: 1.0, green: 0.8, blue: 0.0) : Color(red: 0.0, green: 0.8, blue: 1.0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isLandscape = screenWidth > screenHeight
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 地圖背景
                if showMap, let location = speedManager.userLocation {
                    MapTrackingView(userLocation: location)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(Color.black.opacity(0.55))
                }
                
                // ⚠️ 超速全螢幕閃爍警示 Overlay
                if isOverspeed && flashWarning {
                    Color.red.opacity(0.25)
                        .edgesIgnoringSafeArea(.all)
                }
                
                VStack(spacing: 0) {
                    
                    // 頂部控制欄
                    HStack(alignment: .center, spacing: 8) {
                        Text(currentTime, style: .time)
                            .font(.system(size: isLandscape ? screenHeight * 0.045 : screenWidth * 0.038, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryThemeColor)
                        
                        Spacer()
                        
                        // 海拔與指南針方位
                        HStack(spacing: 8) {
                            Text("⛰️ \(Int(speedManager.altitudeMeters))m")
                            Text("🧭 \(speedManager.headingDirectionText)")
                        }
                        .font(.system(size: isLandscape ? screenHeight * 0.032 : screenWidth * 0.028, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // 功能按鈕群
                        Button(action: { withAnimation { showMap.toggle() } }) {
                            Image(systemName: "map.fill")
                                .padding(6)
                                .background(showMap ? primaryThemeColor : Color.gray.opacity(0.3))
                                .foregroundColor(showMap ? .black : .white)
                                .cornerRadius(8)
                        }
                        
                        Button(action: { isHUDMode.toggle() }) {
                            Text("HUD")
                                .font(.caption.bold())
                                .padding(6)
                                .background(isHUDMode ? Color.orange : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        // ⚙️ 設定按鈕
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape.fill")
                                .padding(6)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geometry.safeAreaInsets.top + 5)
                    
                    Spacer()
                    
                    // 🏎️ 中央保時捷風圓弧儀表板
                    let gaugeSize = isLandscape ? min(screenWidth, screenHeight) * 0.75 : screenWidth * 0.8
                    let progress = min(speedManager.speedKMH / 160.0, 1.0)
                    
                    ZStack {
                        // 圓弧外軌道
                        Circle()
                            .trim(from: 0.125, to: 0.875)
                            .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(90))
                            .frame(width: gaugeSize, height: gaugeSize)
                        
                        // 動態發光指針
                        Circle()
                            .trim(from: 0.125, to: 0.125 + (0.75 * CGFloat(progress)))
                            .stroke(
                                LinearGradient(gradient: Gradient(colors: [.white, primaryThemeColor]), startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round)
                            )
                            .rotationEffect(.degrees(90))
                            .frame(width: gaugeSize, height: gaugeSize)
                            .shadow(color: primaryThemeColor.opacity(0.8), radius: 10)
                        
                        // 中央數字與單位
                        VStack(spacing: 0) {
                            Text("\(Int(round(speedManager.speedKMH)))")
                                .font(.system(size: gaugeSize * 0.38, weight: .black, design: .rounded))
                                .foregroundColor(primaryThemeColor)
                                .shadow(color: primaryThemeColor.opacity(0.8), radius: 12)
                            
                            Text("KM/H")
                                .font(.system(size: gaugeSize * 0.08, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                                .tracking(4)
                            
                            // 超速警示文字
                            if isOverspeed {
                                Text("⚠️ OVER SPEED")
                                    .font(.system(size: gaugeSize * 0.06, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Spacer()
                    
                    // 📊 底部行車電腦面板 (0-100測速、TRIP、MAX、AVG)
                    HStack(spacing: 12) {
                        // 0-100 計時
                        VStack(alignment: .leading, spacing: 2) {
                            Text("0-100 KM/H")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            if let t = speedManager.zeroToHundredTime {
                                Text(String(format: "%.2fs", t))
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundColor(.green)
                            } else if speedManager.isTimingZeroToHundred {
                                Text("TIMING...")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.yellow)
                            } else {
                                Text("READY")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                        
                        // TRIP 里程
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRIP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.2f km", speedManager.totalDistanceMeters / 1000.0))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                        
                        // MAX 極速
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MAX SPEED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.0f km/h", speedManager.maxSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider().background(Color.gray.opacity(0.5)).frame(height: 25)
                        
                        // AVG 平均車速
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AVG SPEED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.0f km/h", speedManager.avgSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryThemeColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .scaleEffect(x: isHUDMode ? -1 : 1, y: 1)
            }
            
            // ⚙️ 設定選單彈窗 (Sheet)
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    Form {
                        Section(header: Text("安全警報設定")) {
                            HStack {
                                Text("速限警報 (km/h)")
                                Spacer()
                                Text("\(Int(speedLimit)) km/h")
                                    .bold()
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $speedLimit, in: 30...200, step: 5)
                        }
                        
                        Section(header: Text("視覺主題")) {
                            Toggle("保時捷經典黃風格", isOn: $isPorscheTheme)
                        }
                        
                        Section(header: Text("行車數據紀錄")) {
                            Button(action: {
                                speedManager.resetData()
                            }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("重置本次行程數據 (TRIP / MAX / 0-100)")
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
            
            // 超速蜂鳴警報與紅光閃爍
            if isOverspeed {
                flashWarning.toggle()
                AudioServicesPlaySystemSound(1005) // iPhone 蜂鳴警報聲
            } else {
                flashWarning = false
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
