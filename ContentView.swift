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
        case .arcade: return .green
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .porsche: return .black
        case .cyberpunk: return Color(red: 0.02, green: 0.02, blue: 0.06)
        case .arcade: return Color(red: 0.03, green: 0.0, blue: 0.08)
        }
    }
}

// MARK: - Color 擴充：支援存入 UserDefaults (加上 @retroactive 消除警告)
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

// MARK: - 3. GPS 與感應器管理器
class VehicleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    
    @Published var speed: Double = 0.0 // km/h
    @Published var maxSpeed: Double = 0.0
    @Published var tripDistance: Double = 0.0 // km
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
            locationManager.distanceFilter = kCLLocationDistanceNone
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

// MARK: - 4. 開機動畫
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

// MARK: - 5. 背景流水長亮霓虹燈條特效
struct BackgroundNeonFlowView: View {
    @State private var isAnimating = false
    var primaryColor: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [primaryColor.opacity(0.1), primaryColor, primaryColor.opacity(0.1), Color.clear]),
                        center: .center,
                        angle: .degrees(isAnimating ? 360 : 0)
                    ),
                    lineWidth: 3
                )
                .padding(4)
                .shadow(color: primaryColor.opacity(0.6), radius: 8)
            
            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    for i in 0..<6 {
                        let xOffset = CGFloat(i) * 150 + (isAnimating ? width : -100)
                        path.move(to: CGPoint(x: xOffset, y: 0))
                        path.addLine(to: CGPoint(x: xOffset - 100, y: height))
                    }
                }
                .stroke(
                    LinearGradient(gradient: Gradient(colors: [.clear, primaryColor.opacity(0.08), .clear]), startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
            }
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 6).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 6. 具備原生搜尋與導航功能的 Apple Maps 檢視
struct InteractiveNavigationMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.showsCompass = true
        mapView.showsTraffic = true
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
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
                .stroke(color.opacity(0.15), lineWidth: 2)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0.0, to: 0.3)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.clear, color]), center: .center),
                    style: StrokeStyle(lineWidth: size > 200 ? 4 : 3, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .animation(Animation.linear(duration: 4).repeatForever(autoreverses: false), value: animate)
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
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(lightColor(for: index))
                    .frame(width: 16, height: 5)
                    .cornerRadius(2)
                    .shadow(color: lightColor(for: index).opacity(0.8), radius: isLit(index) ? 3 : 0)
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
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1).frame(width: 60, height: 60)
            
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 120)
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 120, height: 1)
            
            Circle()
                .fill(primaryColor)
                .frame(width: 10, height: 10)
                .offset(x: CGFloat(x * 45), y: CGFloat(y * 45))
                .shadow(color: primaryColor, radius: 4)
            
            VStack {
                Text("G-FORCE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(String(format: "MAX: %.2fG", maxG))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .offset(y: 42)
        }
        .frame(width: 120, height: 120)
        .background(Color.black.opacity(0.4))
        .cornerRadius(60)
        .overlay(Circle().stroke(primaryColor.opacity(0.5), lineWidth: 2))
    }
}

// MARK: - 10. 超速違規清單頁面
struct OverspeedLogsView: View {
    @Binding var logs: [OverspeedRecord]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
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
                    .listRowBackground(Color.black)
                }
                .onDelete { indexSet in
                    logs.remove(atOffsets: indexSet)
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("超速違規紀錄")
        .navigationBarItems(trailing: Button("清除全部") {
            logs.removeAll()
        }.foregroundColor(.red))
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
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
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
                    .listRowBackground(Color.black)
                }
                .onDelete { indexSet in
                    records.remove(atOffsets: indexSet)
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("行程歷史封存")
        .navigationBarItems(trailing: Button("清除全部") {
            records.removeAll()
        }.foregroundColor(.red))
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
    @Binding var isNetworkBoostEnabled: Bool
    
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
            
            Section(header: Text("導航與定位")) {
                Toggle("網路加速定位模式", isOn: $isNetworkBoostEnabled)
                Text("結合行動網路基地台與 GPS 進行混合式快速定位，提升城市高樓區定位反應。")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("顯示模式")) {
                Toggle("HUD 投影模式 (鏡像翻轉)", isOn: $isHudMode)
            }
        }
        .navigationTitle("賽道儀表設定")
    }
}

// MARK: - 13. 主畫面 ContentView
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
                if !isBootLoaded {
                    BootLoadingView(isFinished: $isBootLoaded)
                        .transition(.opacity)
                        .zIndex(20)
                } else {
                    selectedTheme.backgroundColor.edgesIgnoringSafeArea(.all)
                    
                    BackgroundNeonFlowView(primaryColor: currentPrimaryColor)
                        .zIndex(0)
                    
                    if flashWarning {
                        Color.red.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                            .animation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: flashWarning)
                            .zIndex(10)
                    }
                    
                    if showMap {
                        // === 極簡地圖模式：全螢幕 Apple 地圖 + 浮動時速表與返回按鈕 ===
                        ZStack(alignment: .topLeading) {
                            InteractiveNavigationMapView(coordinate: vehicleManager.currentLocation)
                                .edgesIgnoringSafeArea(.all)
                            
                            // 左上角浮動控制按鈕與精簡時速表
                            HStack(alignment: .top, spacing: 12) {
                                Button(action: { showMap.toggle() }) {
                                    Image(systemName: "gauge.with.needle")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(width: 44, height: 44)
                                        .background(Color.black.opacity(0.75))
                                        .foregroundColor(currentPrimaryColor)
                                        .cornerRadius(22)
                                        .overlay(Circle().stroke(currentPrimaryColor.opacity(0.8), lineWidth: 2))
                                        .shadow(radius: 4)
                                }
                                
                                // 浮動高對比時速表
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.0f", vehicleManager.speed))
                                        .font(.system(size: 32, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("KM/H")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(currentPrimaryColor)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(22)
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(currentPrimaryColor.opacity(0.5), lineWidth: 1))
                                .shadow(radius: 4)
                            }
                            .padding(.top, 12)
                            .padding(.leading, 12)
                        }
                        .transition(.opacity)
                        
                    } else {
                        // === 預設賽道儀表模式 ===
                        HStack(spacing: 15) {
                            VStack(spacing: 12) {
                                Button(action: { showMap.toggle() }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "map.fill")
                                            .font(.system(size: 14))
                                        Text("地圖")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    }
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                Button(action: { showSettings = true }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 14))
                                        Text("設定")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    }
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    let history = HistoryRecord(id: UUID(), date: Date(), maxSpeed: vehicleManager.maxSpeed, zeroToOneHundredTime: vehicleManager.zeroToOneHundredTime, maxGForce: vehicleManager.maxGForce, tripDistance: vehicleManager.tripDistance)
                                    historyRecords.append(history)
                                    saveHistoryRecords()
                                    vehicleManager.resetData()
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                            .font(.system(size: 14))
                                        Text("重置")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                                        .tracking(2)
                                    
                                    Text(String(format: "%.0f", vehicleManager.speed))
                                        .font(.system(size: 78, weight: .black, design: .monospaced))
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
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            VStack(spacing: 12) {
                                GForceView(x: vehicleManager.currentGForceX, y: vehicleManager.currentGForceY, maxG: vehicleManager.maxGForce, primaryColor: currentPrimaryColor)
                                
                                VStack(spacing: 4) {
                                    ShiftLightsView(speed: vehicleManager.speed)
                                    Text("RPM LIGHTS")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("里程:").foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.2f km", vehicleManager.tripDistance)).foregroundColor(.green)
                                    }
                                    HStack {
                                        Text("極速:").foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f km/h", vehicleManager.maxSpeed)).foregroundColor(currentPrimaryColor)
                                    }
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
                        .transition(.opacity)
                    }
                }
            }
            .navigationBarHidden(true)
            .scaleEffect(x: isHudMode ? -1.0 : 1.0, y: 1.0)
            .onAppear {
                loadOverspeedLogs()
                loadHistoryRecords()
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled: isNetworkBoostEnabled)
            }
            .onChange(of: isNetworkBoostEnabled) { newValue in
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled: newValue)
            }
            .onChange(of: vehicleManager.speed) { newSpeed in
                if newSpeed > speedLimit {
                    if !flashWarning {
                        flashWarning = true
                        AudioServicesPlaySystemSound(1005)
                        let record = OverspeedRecord(id: UUID(), date: Date(), speed: newSpeed, speedLimit: speedLimit)
                        overspeedLogs.append(record)
                        saveOverspeedLogs()
                    }
                } else {
                    flashWarning = false
                }
            }
            .onChange(of: overspeedLogs.count) { _ in saveOverspeedLogs() }
            .onChange(of: historyRecords.count) { _ in saveHistoryRecords() }
            .background(
                Group {
                    // 修正：改用區域 Binding 變數，避免直接存取不可變的 self
                    NavigationLink(
                        destination: SettingsView(
                            selectedTheme: Binding(
                                get: { self.selectedTheme },
                                set: { newTheme in self.storedThemeRaw = newTheme.rawValue }
                            ),
                            speedLimit: $speedLimit,
                            isHudMode: $isHudMode,
                            useCustomColor: $useCustomColor,
                            customColor: $customColor,
                            isNetworkBoostEnabled: $isNetworkBoostEnabled
                        ),
                        isActive: $showSettings
                    ) { EmptyView() }
                    
                    NavigationLink(destination: OverspeedLogsView(logs: $overspeedLogs), isActive: $showOverspeedLogs) { EmptyView() }
                    NavigationLink(destination: HistoryRecordsView(records: $historyRecords), isActive: $showHistoryRecords) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func saveOverspeedLogs() {
        if let encoded = try? JSONEncoder().encode(overspeedLogs) {
            overspeedLogsData = encoded
        }
    }
    
    private func loadOverspeedLogs() {
        if let decoded = try? JSONDecoder().decode([OverspeedRecord].self, from: overspeedLogsData) {
            overspeedLogs = decoded
        }
    }
    
    private func saveHistoryRecords() {
        if let encoded = try? JSONEncoder().encode(historyRecords) {
            historyRecordsData = encoded
        }
    }
    
    private func loadHistoryRecords() {
        if let decoded = try? JSONDecoder().decode([HistoryRecord].self, from: historyRecordsData) {
            historyRecords = decoded
        }
    }
}
