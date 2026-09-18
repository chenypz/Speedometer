import SwiftUI
import CoreLocation
import MapKit
import AVFoundation

// MARK: - 1. 主程式進入點
@main
struct RacingDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 2. 資料模型與歷史紀錄
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
}

// MARK: - 3. 佈景主題設定
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
        case .arcade: return .green
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .porsche: return .black
        case .cyberpunk: return Color(red: 0.05, green: 0.05, blue: 0.1)
        case .arcade: return Color(red: 0.05, green: 0.0, blue: 0.15)
        }
    }
}

// MARK: - 4. GPS 與感應器管理器
class VehicleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    
    @Published var speed: Double = 0.0 // km/h
    @Published var maxSpeed: Double = 0.0
    @Published var tripDistance: Double = 0.0 // km
    @Published var heading: Double = 0.0
    
    // G 力數據
    @Published var currentGForceX: Double = 0.0
    @Published var currentGForceY: Double = 0.0
    @Published var maxGForce: Double = 0.0
    
    // 0-100 加速計時
    @Published var zeroToOneHundredTime: Double = 0.0
    @Published var isTesting0_100: Bool = false
    private var accelStartTime: Date? = nil
    private var hasReached100: Bool = false
    
    // 導航座標
    @Published var currentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
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
    
    func resetData() {
        tripDistance = 0.0
        maxSpeed = 0.0
        maxGForce = 0.0
        zeroToOneHundredTime = 0.0
        isTesting0_100 = false
        hasReached100 = false
        accelStartTime = nil
        lastLocation = nil
    }
    
    private func startMotionUpdates() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
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
        
        let speedKmh = max(0, newLocation.speed * 3.6)
        self.speed = speedKmh
        
        if speedKmh > maxSpeed {
            maxSpeed = speedKmh
        }
        
        if let last = lastLocation {
            let distanceInMeters = newLocation.distance(from: last)
            if distanceInMeters > 0 {
                tripDistance += distanceInMeters / 1000.0
            }
        }
        lastLocation = newLocation
        
        // 0-100 加速測試邏輯
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.trueHeading >= 0 {
            heading = newHeading.trueHeading
        } else {
            heading = newHeading.magneticHeading
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - 5. 開機動畫
struct BootLoadingView: View {
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0.0
    @State private var textStep = 0
    
    let steps = [
        "初始化賽道核心系統...",
        "載入 GPS 高精度衛星定位...",
        "校準陀螺儀與 G 力感應器...",
        "系統就緒，準備出發！"
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color(red: 0.0, green: 0.8, blue: 1.0), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                
                Text("VORTEX RACING HUD")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 280, height: 8).cornerRadius(4)
                        Rectangle().fill(Color(red: 0.0, green: 0.8, blue: 1.0)).frame(width: 280 * progress, height: 8).cornerRadius(4)
                    }
                    Text(steps[min(textStep, steps.count - 1)])
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2)) {
                progress = 1.0
            }
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { timer in
                if textStep < steps.count - 1 {
                    textStep += 1
                } else {
                    timer.invalidate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation {
                            isFinished = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 6. 地圖導航檢視
struct MapTrackingView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
        }
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))
        uiView.setRegion(region, animated: true)
    }
}

// MARK: - 7. 炫光流光線條背景
struct NeonArcFlowView: View {
    @State private var animate = false
    var color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 2)
                .frame(width: 320, height: 320)
            
            Circle()
                .trim(from: 0.0, to: 0.3)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.clear, color]), center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 320, height: 320)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .animation(Animation.linear(duration: 4).repeatForever(autoreverses: false), value: animate)
            
            Circle()
                .trim(from: 0.5, to: 0.8)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.clear, color.opacity(0.8)]), center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 290, height: 290)
                .rotationEffect(.degrees(animate ? -360 : 0))
                .animation(Animation.linear(duration: 6).repeatForever(autoreverses: false), value: animate)
        }
        .onAppear {
            animate = true
        }
    }
}

// MARK: - 8. 專業轉速提示燈
struct ShiftLightsView: View {
    let speed: Double
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(lightColor(for: index))
                    .frame(width: 22, height: 8)
                    .cornerRadius(2)
                    .shadow(color: lightColor(for: index).opacity(0.8), radius: isLit(index) ? 6 : 0)
            }
        }
    }
    
    private func isLit(_ index: Int) -> Bool {
        let threshold = Double(index + 1) * 25.0
        return speed >= threshold
    }
    
    private func lightColor(for index: Int) -> Color {
        guard isLit(index) else { return Color.gray.opacity(0.3) }
        if index < 4 { return .green }
        if index < 6 { return .yellow }
        return .red
    }
}

// MARK: - 9. G 力感應器圖表
struct GForceView: View {
    let x: Double
    let y: Double
    let maxG: Double
    var primaryColor: Color
    
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1).frame(width: 80, height: 80)
            
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 160)
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 160, height: 1)
            
            Circle()
                .fill(primaryColor)
                .frame(width: 12, height: 12)
                .offset(x: CGFloat(x * 60), y: CGFloat(y * 60))
                .shadow(color: primaryColor, radius: 6)
            
            VStack {
                Text("G-FORCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(String(format: "MAX: %.2fG", maxG))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .offset(y: 55)
        }
        .frame(width: 160, height: 160)
        .background(Color.black.opacity(0.4))
        .cornerRadius(80)
        .overlay(Circle().stroke(primaryColor.opacity(0.5), lineWidth: 2))
    }
}

// MARK: - 10. 超速違規清單頁面
struct OverspeedLogsView: View {
    @Binding var logs: [OverspeedRecord]
    
    var body: some View {
        List {
            ForEach(logs) { log in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.date, formatter: dateFormatter)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(log.date, formatter: timeFormatter)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.0f km/h", log.speed))
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.red)
                        Text(String(format: "速限: %.0f", log.speedLimit))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                logs.remove(atOffsets: indexSet)
            }
        }
        .navigationTitle("超速違規紀錄")
        .navigationBarItems(trailing: Button("清除全部") {
            logs.removeAll()
        }.foregroundColor(.red))
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .scrollContentBackground(.hidden)
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
    
    private var timeFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .medium
        return df
    }
}

// MARK: - 11. 行程歷史封存紀錄頁面
struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    
    var body: some View {
        List {
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.date, formatter: dateFormatter)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(record.date, formatter: timeFormatter)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.2f km", record.tripDistance))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("極速").font(.system(size: 10)).foregroundColor(.gray)
                            Text(String(format: "%.0f", record.maxSpeed)).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading) {
                            Text("0-100加速").font(.system(size: 10)).foregroundColor(.gray)
                            Text(record.zeroToOneHundredTime > 0 ? String(format: "%.1fs", record.zeroToOneHundredTime) : "---").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.orange)
                        }
                        VStack(alignment: .leading) {
                            Text("最大G力").font(.system(size: 10)).foregroundColor(.gray)
                            Text(String(format: "%.2fG", record.maxGForce)).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(Color(red: 0.0, green: 0.8, blue: 1.0))
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onDelete { indexSet in
                records.remove(atOffsets: indexSet)
            }
        }
        .navigationTitle("行程歷史封存")
        .navigationBarItems(trailing: Button("清除全部") {
            records.removeAll()
        }.foregroundColor(.red))
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .scrollContentBackground(.hidden)
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
    
    private var timeFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .medium
        return df
    }
}

// MARK: - 12. 設定選單
struct SettingsView: View {
    @Binding var selectedTheme: DashboardTheme
    @Binding var speedLimit: Double
    @Binding var isHudMode: Bool
    @Binding var useCustomColor: Bool
    @Binding var customColor: Color
    
    var body: some View {
        Form {
            Section(header: Text("視覺佈景主題")) {
                Picker("佈景主題", selection: $selectedTheme) {
                    ForEach(DashboardTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("啟用自訂霓虹燈光色彩", isOn: $useCustomColor)
                if useCustomColor {
                    ColorPicker("主色調", selection: $customColor)
                }
            }
            
            Section(header: Text("行車安全警報")) {
                VStack(alignment: .leading) {
                    Text("安全速限警報: \(Int(speedLimit)) km/h")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $speedLimit, in: 40...180, step: 5)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("顯示模式")) {
                Toggle("HUD 投影模式 (鏡像翻轉)", isOn: $isHudMode)
            }
            
            Section(header: Text("賽道數據紀錄管理")) {
                NavigationLink(destination: OverspeedLogsView(logs: .constant([]))) {
                    Text("查看超速違規紀錄")
                }
                NavigationLink(destination: HistoryRecordsView(records: .constant([]))) {
                    Text("查看歷史行程封存")
                }
            }
        }
        .navigationTitle("賽道儀表設定")
    }
}

// MARK: - 13. 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    
    @State private var isBootLoaded: Bool = false
    
    @State private var selectedTheme: DashboardTheme = .cyberpunk
    @State private var speedLimit: Double = 120.0
    @State private var isHudMode: Bool = false
    @State private var showMap: Bool = false
    @State private var useCustomColor: Bool = false
    @State private var customColor: Color = Color(red: 0.0, green: 0.8, blue: 1.0)
    
    @State private var overspeedLogs: [OverspeedRecord] = []
    @State private var historyRecords: [HistoryRecord] = []
    
    @State private var showSettings: Bool = false
    @State private var showOverspeedLogs: Bool = false
    @State private var showHistoryRecords: Bool = false
    
    @State private var flashWarning: Bool = false
    @State private var isLandscapeMode: Bool = false
    
    var currentPrimaryColor: Color {
        selectedTheme.primaryColor(custom: useCustomColor ? customColor : nil)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if !isBootLoaded {
                    BootLoadingView(isFinished: $isBootLoaded)
                        .transition(.opacity)
                        .zIndex(20)
                } else {
                    selectedTheme.backgroundColor.edgesIgnoringSafeArea(.all)
                    
                    if flashWarning {
                        Color.red.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                            .animation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: flashWarning)
                            .zIndex(10)
                    }
                    
                    if isLandscapeMode {
                        HStack(spacing: 20) {
                            leftControlPanel
                            centerDashboardView
                            rightTelemetryPanel
                        }
                        .padding()
                        .zIndex(1)
                    } else {
                        VStack(spacing: 12) {
                            topStatusBar
                            
                            ZStack {
                                if showMap {
                                    MapTrackingView(coordinate: vehicleManager.currentLocation, heading: vehicleManager.heading)
                                        .cornerRadius(20)
                                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(currentPrimaryColor, lineWidth: 2))
                                        .transition(.opacity)
                                } else {
                                    centerDashboardView
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxHeight: .infinity)
                            
                            HStack(spacing: 15) {
                                GForceView(x: vehicleManager.currentGForceX, y: vehicleManager.currentGForceY, maxG: vehicleManager.maxGForce, primaryColor: currentPrimaryColor)
                                    .scaleEffect(0.65)
                                    .frame(width: 100, height: 100)
                                
                                VStack(spacing: 6) {
                                    ShiftLightsView(speed: vehicleManager.speed)
                                    Text("RPM SHIFT LIGHTS")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                            .frame(height: 100)
                            
                            bottomStatsRow
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .zIndex(1)
                    }
                }
            }
            .navigationBarHidden(true)
            .scaleEffect(x: isHudMode ? -1.0 : 1.0, y: 1.0)
            .onChange(of: vehicleManager.speed) { newSpeed in
                if newSpeed > speedLimit {
                    if !flashWarning {
                        flashWarning = true
                        AudioServicesPlaySystemSound(1005)
                        let record = OverspeedRecord(id: UUID(), date: Date(), speed: newSpeed, speedLimit: speedLimit)
                        overspeedLogs.append(record)
                    }
                } else {
                    flashWarning = false
                }
            }
            .background(
                Group {
                    NavigationLink(destination: SettingsView(selectedTheme: $selectedTheme, speedLimit: $speedLimit, isHudMode: $isHudMode, useCustomColor: $useCustomColor, customColor: $customColor), isActive: $showSettings) { EmptyView() }
                    NavigationLink(destination: OverspeedLogsView(logs: $overspeedLogs), isActive: $showOverspeedLogs) { EmptyView() }
                    NavigationLink(destination: HistoryRecordsView(records: $historyRecords), isActive: $showHistoryRecords) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    var topStatusBar: some View {
        HStack {
            Button(action: {
                withAnimation { isLandscapeMode.toggle() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isLandscapeMode ? "rectangle.portrait" : "rectangle.landscape")
                    Text(isLandscapeMode ? "直向" : "橫向")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            Spacer()
            
            Button(action: { showMap.toggle() }) {
                Text(showMap ? "地圖: 關" : "地圖: 開")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showMap ? currentPrimaryColor.opacity(0.3) : Color.white.opacity(0.1))
                    .foregroundColor(showMap ? currentPrimaryColor : .white)
                    .cornerRadius(12)
            }
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
        }
    }
    
    var centerDashboardView: some View {
        ZStack {
            NeonArcFlowView(color: currentPrimaryColor)
            
            VStack(spacing: 6) {
                Text("GPS SPEED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .tracking(2)
                
                Text(String(format: "%.0f", vehicleManager.speed))
                    .font(.system(size: 72, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: currentPrimaryColor.opacity(0.8), radius: 10)
                
                Text("KM/H")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(currentPrimaryColor)
                
                if vehicleManager.isTesting0_100 || vehicleManager.zeroToOneHundredTime > 0 {
                    HStack(spacing: 4) {
                        Text(vehicleManager.isTesting0_100 ? "0-100 測速中..." : "0-100 紀錄:")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f s", vehicleManager.zeroToOneHundredTime))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(width: 260, height: 260)
    }
    
    var bottomStatsRow: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("0-100 ACCEL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(vehicleManager.zeroToOneHundredTime > 0 ? String(format: "%.1fs", vehicleManager.zeroToOneHundredTime) : "--.-s")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            VStack(spacing: 4) {
                Text("TRIP DIST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(String(format: "%.2f km", vehicleManager.tripDistance))
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            VStack(spacing: 4) {
                Text("MAX SPEED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(String(format: "%.0f", vehicleManager.maxSpeed))
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(currentPrimaryColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    var leftControlPanel: some View {
        VStack(spacing: 15) {
            Button(action: { withAnimation { isLandscapeMode.toggle() } }) {
                Image(systemName: "rectangle.portrait")
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            Spacer()
            Button(action: {
                let history = HistoryRecord(id: UUID(), date: Date(), maxSpeed: vehicleManager.maxSpeed, zeroToOneHundredTime: vehicleManager.zeroToOneHundredTime, maxGForce: vehicleManager.maxGForce, tripDistance: vehicleManager.tripDistance)
                historyRecords.append(history)
                vehicleManager.resetData()
            }) {
                Text("重置並封存")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(8)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
        }
    }
    
    var rightTelemetryPanel: some View {
        VStack(spacing: 15) {
            GForceView(x: vehicleManager.currentGForceX, y: vehicleManager.currentGForceY, maxG: vehicleManager.maxGForce, primaryColor: currentPrimaryColor)
                .scaleEffect(0.7)
            ShiftLightsView(speed: vehicleManager.speed)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "里程: %.2f km", vehicleManager.tripDistance)).font(.system(size: 12, design: .monospaced)).foregroundColor(.green)
                Text(String(format: "極速: %.0f km/h", vehicleManager.maxSpeed)).font(.system(size: 12, design: .monospaced)).foregroundColor(currentPrimaryColor)
            }
            Spacer()
        }
    }
}
