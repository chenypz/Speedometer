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

// MARK: - 3. GPS、感應器與導航管理器
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
    
    // 導航與路向相關屬性
    @Published var isNavigating: Bool = false
    @Published var routePolyline: MKPolyline? = nil
    @Published var currentInstruction: String = "目的地を検索するか、地図をタップしてください"
    @Published var distanceToNextStep: Double = 0.0
    @Published var destinationCoordinate: CLLocationCoordinate2D? = nil
    
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
    }
    
    // 關鍵字搜尋地點並導航
    func searchAndNavigate(query: String) {
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: currentLocation, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self, let item = response?.mapItems.first else {
                self?.currentInstruction = "指定の場所が見つかりませんでした"
                return
            }
            self.setDestination(item.placemark.coordinate)
            self.currentInstruction = "目的地: \(item.name ?? query)"
        }
    }
    
    // 計算導航路線
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
                self?.currentInstruction = "ルートの計算に失敗しました"
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
        currentInstruction = "ナビゲーションが終了しました"
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

// MARK: - 4. 炫彩科技感開場動畫 (日文警告)
struct BootLoadingView: View {
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0.0
    @State private var textStep = 0
    @State private var showWarningScreen: Bool = false
    @State private var warningOpacity: Double = 0.0
    @State private var pulseEffect: Bool = false
    @State private var matrixRotation: Double = 0.0
    
    let steps = [
        "INITIALIZING VORTEX CORE MATRIX...",
        "CONNECTING TO HIGH-PRECISION GNSS SATELLITES...",
        "CALIBRATING 6-AXIS GYRO & G-FORCE SENSORS...",
        "SYSTEM ONLINE. READY FOR LAUNCH."
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.0, blue: 0.15), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
            
            if !showWarningScreen {
                VStack(spacing: 30) {
                    ZStack {
                        Circle()
                            .stroke(
                                AngularGradient(gradient: Gradient(colors: [Color(red: 0.0, green: 0.8, blue: 1.0), .purple, .pink, Color(red: 0.0, green: 0.8, blue: 1.0)]), center: .center, angle: .degrees(matrixRotation)),
                                lineWidth: 2
                            )
                            .frame(width: 140, height: 140)
                            .scaleEffect(pulseEffect ? 1.05 : 0.95)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 8)
                            .frame(width: 110, height: 110)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(colors: [Color(red: 0.0, green: 0.8, blue: 1.0), .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 110, height: 110)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .purple, radius: 10)
                        
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 38))
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 1.0))
                            .shadow(color: Color(red: 0.0, green: 0.8, blue: 1.0), radius: 8)
                    }
                    
                    Text("VORTEX RACING HUD")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .tracking(6)
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0.0, green: 0.8, blue: 1.0), .white, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: Color(red: 0.0, green: 0.8, blue: 1.0).opacity(0.8), radius: 6)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 300, height: 8)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(LinearGradient(colors: [Color(red: 0.0, green: 0.8, blue: 1.0), .purple, .pink], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 300 * progress, height: 8)
                                .cornerRadius(4)
                                .shadow(color: .pink, radius: 4)
                        }
                        
                        Text(steps[min(textStep, steps.count - 1)])
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 1.0).opacity(0.8))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("警告")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                            .tracking(6)
                        Spacer()
                        Text("警告 / 法律遵守事項")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("道路交通法規の遵守および極速安全に関するお知らせ")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.red)
                        
                        Text("本システムが提供する高精度GPS速度、Gフォース、サーキット計測およびナビゲーションデータは、あくまで運転の参考用です。公道では必ず現地の制限速度および交通法規を厳守し、危険な運転は絶対に避けてください。万が一の事故や違反について、開発者は一切の責任を負いません。")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(5)
                        
                        Text("SEC. 501 / 508 - VORTEX RACING SYSTEM AUTHENTICATED")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.top, 6)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)
                }
                .frame(width: min(UIScreen.main.bounds.width - 40, 520))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 3))
                .cornerRadius(10)
                .shadow(color: .red.opacity(0.5), radius: 15)
                .opacity(warningOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2)) {
                progress = 1.0
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                matrixRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseEffect = true
            }
            Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { timer in
                if textStep < steps.count - 1 {
                    textStep += 1
                } else {
                    timer.invalidate()
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWarningScreen = true
                    }
                    withAnimation(.easeIn(duration: 0.5)) {
                        warningOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            warningOpacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                isFinished = true
                            }
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

// MARK: - 6. 具備導航路徑與點擊設終點功能的 Apple Maps 檢視
struct InteractiveNavigationMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?
    var destinationCoordinate: CLLocationCoordinate2D?
    var isInteractive: Bool = true
    var onMapTap: (CLLocationCoordinate2D) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.isZoomEnabled = isInteractive
        mapView.isScrollEnabled = isInteractive
        mapView.isRotateEnabled = isInteractive
        mapView.showsCompass = false
        mapView.showsTraffic = false
        mapView.delegate = context.coordinator
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if isInteractive && uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
        }
        
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)
        
        if let polyline = routePolyline {
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
        
        init(_ parent: InteractiveNavigationMapView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap(coord)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.9)
                renderer.lineWidth = 6
                return renderer
            }
            return MKOverlayRenderer()
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

// MARK: - 9. 內嵌小地圖元件
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(primaryColor.opacity(0.6), lineWidth: 2)
                )
                
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .frame(width: 120, height: 120)
        .shadow(color: primaryColor.opacity(0.3), radius: 4)
    }
}

// MARK: - 10. 科幻粒子凝聚特效外框
struct SciFiParticleAssembleView<Content: View>: View {
    let content: Content
    @State private var assembleProgress: CGFloat = 0.0
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
                .opacity(Double(assembleProgress))
                .scaleEffect(0.8 + (assembleProgress * 0.2))
            
            if assembleProgress < 1.0 {
                ZStack {
                    ForEach(0..<30, id: \.self) { i in
                        let angle = Double(i) * (Double.pi * 2 / 30.0)
                        let distance = (1.0 - assembleProgress) * 300.0
                        let x = cos(angle) * distance
                        let y = sin(angle) * distance
                        
                        Circle()
                            .fill(i % 2 == 0 ? Color(red: 0.0, green: 0.8, blue: 1.0) : Color.white)
                            .frame(width: CGFloat(2 + (i % 4)), height: CGFloat(2 + (i % 4)))
                            .offset(x: x, y: y)
                            .shadow(color: Color(red: 0.0, green: 0.8, blue: 1.0), radius: 4)
                    }
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2)) {
                assembleProgress = 1.0
            }
        }
    }
}

// MARK: - 11. 超速違規清單頁面
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
                            Text(String(format: "制限: %.0f", log.speedLimit))
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
        .navigationTitle("スピード違反記録")
        .navigationBarItems(trailing: Button("すべて削除") {
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

// MARK: - 12. 行程歷史封存紀錄頁面
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
                                Text("最高速度").font(.system(size: 10)).foregroundColor(.gray)
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
        .navigationTitle("走行履歴アーカイブ")
        .navigationBarItems(trailing: Button("すべて削除") {
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

// MARK: - 13. 設定選單
struct SettingsView: View {
    @Binding var selectedTheme: DashboardTheme
    @Binding var speedLimit: Double
    @Binding var isHudMode: Bool
    @Binding var useCustomColor: Bool
    @Binding var customColor: Color
    @Binding var isNetworkBoostEnabled: Bool
    
    var body: some View {
        Form {
            Section(header: Text("ビジュアルテーマ")) {
                Picker("テーマ", selection: $selectedTheme) {
                    ForEach(DashboardTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("カスタムネオンカラーを有効化", isOn: $useCustomColor)
                if useCustomColor {
                    ColorPicker("メインカラー", selection: $customColor)
                }
            }
            
            Section(header: Text("安全アラート")) {
                VStack(alignment: .leading) {
                    Text("制限速度警告: \(Int(speedLimit)) km/h")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Slider(value: $speedLimit, in: 40...180, step: 5)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("ナビゲーション & 位置情報")) {
                Toggle("ネットワーク位置情報ブースト", isOn: $isNetworkBoostEnabled)
                Text("基地局とGPSを組み合わせて都市部の測位精度を向上させます。")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("表示モード")) {
                Toggle("HUD投影モード (ミラー反転)", isOn: $isHudMode)
            }
        }
        .navigationTitle("サーキット設定")
    }
}

// MARK: - 14. 主畫面 ContentView
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
    
    // 搜尋與伸縮按鈕狀態
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    
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
                    SciFiParticleAssembleView {
                        ZStack {
                            selectedTheme.backgroundColor.edgesIgnoringSafeArea(.all)
                            
                            BackgroundNeonFlowView(primaryColor: currentPrimaryColor)
                                .zIndex(0)
                            
                            if flashWarning {
                                Color.red.opacity(0.3)
                                    .edgesIgnoringSafeArea(.all)
                                    .animation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: flashWarning)
                                    .zIndex(10)
                            }
                            
                            VStack(spacing: 0) {
                                // === 賽道頂部導航路向指引橫幅 (HUD Direction Banner) ===
                                HStack(spacing: 12) {
                                    Image(systemName: "location.north.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(currentPrimaryColor)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vehicleManager.currentInstruction)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        Text(vehicleManager.isNavigating ? "ナビゲーション中" : "ヒント: マップで場所を検索またはタップ")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if vehicleManager.isNavigating {
                                        Button(action: {
                                            vehicleManager.cancelNavigation()
                                        }) {
                                            Text("終了")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.red.opacity(0.8))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.85))
                                .overlay(Rectangle().frame(height: 1).foregroundColor(currentPrimaryColor.opacity(0.3)), alignment: .bottom)
                                .zIndex(15)
                                
                                ZStack {
                                    if showMap {
                                        // === 全螢幕地圖模式 (支援伸縮搜尋列與點擊) ===
                                        ZStack(alignment: .topLeading) {
                                            InteractiveNavigationMapView(
                                                coordinate: vehicleManager.currentLocation,
                                                routePolyline: vehicleManager.routePolyline,
                                                destinationCoordinate: vehicleManager.destinationCoordinate,
                                                isInteractive: true,
                                                onMapTap: { clickedCoord in
                                                    vehicleManager.setDestination(clickedCoord)
                                                }
                                            )
                                            .edgesIgnoringSafeArea(.all)
                                            
                                            HStack(alignment: .top, spacing: 12) {
                                                // 伸縮式返回儀表按鈕
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
                                                
                                                // 伸縮式地點搜尋與導航放大鏡列
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
                                                            .background(Color.black.opacity(0.75))
                                                            .clipShape(Circle())
                                                            .overlay(Circle().stroke(currentPrimaryColor.opacity(0.8), lineWidth: 2))
                                                    }
                                                    
                                                    if isSearchExpanded {
                                                        HStack {
                                                            TextField("目的地を検索 (例: 東京タワー)", text: $searchText, onCommit: {
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
                                                                Text("移動")
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
                                                        .background(Color.black.opacity(0.85))
                                                        .cornerRadius(22)
                                                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(currentPrimaryColor.opacity(0.6), lineWidth: 1))
                                                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                                                    }
                                                }
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
                                                        Text("マップ")
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
                                                        Text("リセット")
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
                                                            Text(vehicleManager.isTesting0_100 ? "0-100 計測中..." : "0-100 記録:")
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
                                                MiniMapView(
                                                    coordinate: vehicleManager.currentLocation,
                                                    routePolyline: vehicleManager.routePolyline,
                                                    destinationCoordinate: vehicleManager.destinationCoordinate,
                                                    primaryColor: currentPrimaryColor
                                                ) {
                                                    showMap = true
                                                }
                                                
                                                VStack(spacing: 4) {
                                                    ShiftLightsView(speed: vehicleManager.speed)
                                                    Text("RPM LIGHTS")
                                                        .font(.system(size: 8, design: .monospaced))
                                                        .foregroundColor(.gray)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack {
                                                        Text("距離:").foregroundColor(.gray)
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
                        }
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
