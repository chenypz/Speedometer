import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - 1. GPS 定位與時速管理器
class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var speedKMH: Double = 0.0
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isGpsReady: Bool = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        self.isGpsReady = true
        self.userLocation = location.coordinate
        
        let speed = location.speed
        if speed > 0 {
            self.speedKMH = speed * 3.6
        } else {
            self.speedKMH = 0.0
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.isGpsReady = false
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - 2. 自動跟隨地圖包裝器
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
            let region = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
            uiView.setRegion(region, animated: true)
        }
    }
}

// MARK: - 3. 主儀表板畫面 (包含圓弧跑車轉速表)
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHUDMode = false
    @State private var showMap = false
    @State private var currentTime = Date()
    
    // 自訂顏色
    private let cyanColor = Color(red: 0.0, green: 0.8, blue: 1.0)
    private let maxSpeedThreshold: Double = 140.0 // 轉速表表底上限 (140 km/h)
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isLandscape = screenWidth > screenHeight
            
            ZStack {
                // 純黑底色
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 背景地圖按鈕開啟時顯示
                if showMap, let location = speedManager.userLocation {
                    MapTrackingView(userLocation: location)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(Color.black.opacity(0.5))
                        .transition(.opacity)
                }
                
                // 主要介面佈局
                VStack(spacing: 0) {
                    
                    // 頂部狀態列
                    HStack(alignment: .center, spacing: 8) {
                        Text(currentTime, style: .time)
                            .font(.system(size: isLandscape ? screenHeight * 0.05 : screenWidth * 0.04, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanColor)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(speedManager.isGpsReady ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            
                            Text(speedManager.isGpsReady ? "📍 定位" : "📡 搜尋中")
                                .font(.system(size: isLandscape ? screenHeight * 0.035 : screenWidth * 0.03, weight: .medium))
                                .foregroundColor(speedManager.isGpsReady ? .green : .orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        
                        // 地圖按鈕
                        Button(action: {
                            withAnimation {
                                showMap.toggle()
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "map.fill")
                                Text(showMap ? "關閉" : "地圖")
                            }
                            .font(.system(size: isLandscape ? screenHeight * 0.035 : screenWidth * 0.03, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(showMap ? cyanColor : Color.gray.opacity(0.3))
                            .foregroundColor(showMap ? .black : .white)
                            .cornerRadius(12)
                        }
                        
                        // HUD 按鈕
                        Button(action: {
                            isHUDMode.toggle()
                        }) {
                            Text(isHUDMode ? "HUD:開" : "HUD")
                                .font(.system(size: isLandscape ? screenHeight * 0.035 : screenWidth * 0.03, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isHUDMode ? Color.yellow : Color.gray.opacity(0.3))
                                .foregroundColor(isHUDMode ? .black : .white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geometry.safeAreaInsets.top + 5)
                    
                    Spacer()
                    
                    // 🏎️ 中央核心：跑車風圓弧轉速儀表板
                    let gaugeSize = isLandscape ? min(screenWidth, screenHeight) * 0.8 : screenWidth * 0.85
                    let progress = min(speedManager.speedKMH / maxSpeedThreshold, 1.0)
                    let activeColor = speedColor(speed: speedManager.speedKMH)
                    
                    ZStack {
                        // 1. 底層灰色圓弧軌道 (角度 135° ~ 405°，即底部的 270 度環形)
                        Circle()
                            .trim(from: 0.125, to: 0.875)
                            .stroke(
                                Color.gray.opacity(0.2),
                                style: StrokeStyle(lineWidth: isLandscape ? 16 : 20, lineCap: .round)
                            )
                            .rotationEffect(.degrees(90))
                            .frame(width: gaugeSize, height: gaugeSize)
                        
                        // 2. 彩色發光加速圓弧
                        Circle()
                            .trim(from: 0.125, to: 0.125 + (0.75 * CGFloat(progress)))
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [cyanColor, activeColor]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: isLandscape ? 16 : 20, lineCap: .round)
                            )
                            .rotationEffect(.degrees(90))
                            .frame(width: gaugeSize, height: gaugeSize)
                            .shadow(color: activeColor.opacity(0.8), radius: 12, x: 0, y: 0)
                            .animation(.easeOut(duration: 0.25), value: speedManager.speedKMH)
                        
                        // 3. 中央數字與單位
                        VStack(spacing: isLandscape ? -5 : 0) {
                            Text("\(Int(round(speedManager.speedKMH)))")
                                .font(.system(size: gaugeSize * 0.38, weight: .black, design: .rounded))
                                .minimumScaleFactor(0.3)
                                .foregroundColor(activeColor)
                                .shadow(color: activeColor.opacity(0.8), radius: 15, x: 0, y: 0)
                            
                            Text("KM/H")
                                .font(.system(size: gaugeSize * 0.08, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .tracking(4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Spacer()
                    
                    // 底部：GPS 權限提醒
                    if speedManager.authorizationStatus == .denied {
                        Text("⚠️ 請至 iPhone 設定中開啟定位權限")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.bottom, 10)
                    }
                }
                .scaleEffect(x: isHUDMode ? -1 : 1, y: 1) // HUD 鏡像
            }
        }
        .onReceive(timer) { _ in
            self.currentTime = Date()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // 車速顏色切換
    private func speedColor(speed: Double) -> Color {
        switch speed {
        case 0..<40:
            return Color(red: 0.0, green: 1.0, blue: 0.8) // 霓虹青色
        case 40..<80:
            return Color(red: 0.2, green: 0.9, blue: 0.3) // 螢光綠
        case 80..<110:
            return Color(red: 1.0, green: 0.7, blue: 0.0) // 跑車黃
        default:
            return Color(red: 1.0, green: 0.2, blue: 0.3) // 極速爆紅
        }
    }
}
