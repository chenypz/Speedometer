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
        
        // 標記已成功接收到 GPS 訊號
        self.isGpsReady = true
        self.userLocation = location.coordinate
        
        // 計算速度 (m/s 轉 km/h)
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

// MARK: - 2. 隨位置自動跟隨的 MKMapView 包裝器
struct MapTrackingView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow // 自動跟隨使用者移動 (類似導航)
        mapView.overrideUserInterfaceStyle = .dark // 強制暗黑模式
        mapView.isUserInteractionEnabled = false // 避免滑動干擾自動追蹤
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = userLocation {
            // 當位置更新時，保持視角跟隨並調整地圖縮放範圍 (0.003 約為近距離導航視角)
            let region = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
            uiView.setRegion(region, animated: true)
        }
    }
}

// MARK: - 3. 主儀表板畫面
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHUDMode = false
    @State private var currentTime = Date()
    
    // 青色 (相容所有 iOS 版本)
    private let cyanColor = Color(red: 0.0, green: 0.8, blue: 1.0)
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isLandscape = screenWidth > screenHeight
            
            ZStack {
                // 背景：自動跟隨的暗黑地圖
                if speedManager.userLocation != nil {
                    MapTrackingView(userLocation: speedManager.userLocation)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(Color.black.opacity(0.4)) // 黑色半透明遮罩，突出數字
                } else {
                    Color.black.edgesIgnoringSafeArea(.all)
                }
                
                // 畫面內容配置
                VStack(spacing: 0) {
                    
                    // 頂部狀態列：時間、GPS定位狀態、HUD切換按鈕
                    HStack(alignment: .center) {
                        // 時間
                        Text(currentTime, style: .time)
                            .font(.system(size: isLandscape ? screenHeight * 0.05 : screenWidth * 0.045, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanColor)
                        
                        Spacer()
                        
                        // 定位與衛星偵測狀態提示
                        HStack(spacing: 6) {
                            Circle()
                                .fill(speedManager.isGpsReady ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            
                            Text(speedManager.isGpsReady ? "📍 定位完成" : "📡 偵測衛星中...")
                                .font(.system(size: isLandscape ? screenHeight * 0.04 : screenWidth * 0.035, weight: .medium))
                                .foregroundColor(speedManager.isGpsReady ? .green : .orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        // HUD 切換按鈕
                        Button(action: {
                            isHUDMode.toggle()
                        }) {
                            Text(isHUDMode ? "HUD: 開" : "HUD 鏡像")
                                .font(.system(size: isLandscape ? screenHeight * 0.04 : screenWidth * 0.035, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isHUDMode ? cyanColor : Color.gray.opacity(0.4))
                                .foregroundColor(isHUDMode ? .black : .white)
                                .cornerRadius(15)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geometry.safeAreaInsets.top + 5)
                    
                    // 正中央：超大時速表
                    Spacer()
                    
                    VStack(spacing: isLandscape ? -10 : -5) {
                        // 時速數字（自動適應螢幕最大化居中）
                        Text("\(Int(round(speedManager.speedKMH)))")
                            .font(.system(size: isLandscape ? screenHeight * 0.65 : screenWidth * 0.48, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.3)
                            .foregroundColor(speedColor(speed: speedManager.speedKMH))
                            .shadow(color: speedColor(speed: speedManager.speedKMH).opacity(0.85), radius: 20, x: 0, y: 0)
                        
                        // 單位 KM/H
                        Text("KM/H")
                            .font(.system(size: isLandscape ? screenHeight * 0.09 : screenWidth * 0.075, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .tracking(6)
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
                .scaleEffect(x: isHUDMode ? -1 : 1, y: 1) // HUD 擋風玻璃鏡像翻轉
            }
        }
        .onReceive(timer) { _ in
            self.currentTime = Date()
        }
        .onAppear {
            // 保持螢幕常亮不休眠
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // 根據車速動態切換霓虹顏色
    private func speedColor(speed: Double) -> Color {
        switch speed {
        case 0..<40:
            return Color(red: 0.0, green: 1.0, blue: 0.8) // 霓虹青綠
        case 40..<80:
            return Color(red: 0.2, green: 0.9, blue: 0.3) // 螢光綠
        case 80..<110:
            return Color(red: 1.0, green: 0.7, blue: 0.0) // 警告黃
        default:
            return Color(red: 1.0, green: 0.2, blue: 0.3) // 超速亮紅
        }
    }
}
