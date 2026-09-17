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

// MARK: - 3. 主儀表板畫面
struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHUDMode = false
    @State private var showMap = false // 控制地圖開關
    @State private var currentTime = Date()
    
    // 自訂顏色 (相容舊版 iOS)
    private let cyanColor = Color(red: 0.0, green: 0.8, blue: 1.0)
    private let maxSpeedThreshold: Double = 120.0 // 加速條的最大參考車速 (120 km/h)
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isLandscape = screenWidth > screenHeight
            
            ZStack {
                // 純黑底色
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 背景地圖（只有在按下按鈕時才顯示）
                if showMap, let location = speedManager.userLocation {
                    MapTrackingView(userLocation: location)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(Color.black.opacity(0.45))
                        .transition(.opacity)
                }
                
                // 主要儀表板內容
                VStack(spacing: 0) {
                    
                    // 頂部列：時間、GPS狀態、地圖按鈕、HUD按鈕
                    HStack(alignment: .center, spacing: 8) {
                        // 時間
                        Text(currentTime, style: .time)
                            .font(.system(size: isLandscape ? screenHeight * 0.05 : screenWidth * 0.04, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanColor)
                        
                        Spacer()
                        
                        // 定位狀態
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
                        
                        // 地圖開關按鈕
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
                        
                        // HUD 切換按鈕
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
                    
                    // 中間核心區域：時速 + 油車風加速條
                    VStack(spacing: isLandscape ? 5 : 12) {
                        
                        // 超大時速數字
                        Text("\(Int(round(speedManager.speedKMH)))")
                            .font(.system(size: isLandscape ? screenHeight * 0.55 : screenWidth * 0.45, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.3)
                            .foregroundColor(speedColor(speed: speedManager.speedKMH))
                            .shadow(color: speedColor(speed: speedManager.speedKMH).opacity(0.85), radius: 20, x: 0, y: 0)
                        
                        // 單位 KM/H
                        Text("KM / H")
                            .font(.system(size: isLandscape ? screenHeight * 0.07 : screenWidth * 0.06, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .tracking(4)
                        
                        // 🔥 油車 / 跑車風格 加速進度條 (Power Bar)
                        VStack(spacing: 4) {
                            GeometryReader { barGeo in
                                let barWidth = barGeo.size.width
                                let currentSpeed = min(speedManager.speedKMH, maxSpeedThreshold)
                                let fillProgress = CGFloat(currentSpeed / maxSpeedThreshold)
                                
                                ZStack(alignment: .leading) {
                                    // 背景軌道
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.25))
                                        .frame(height: isLandscape ? 12 : 16)
                                    
                                    // 動態充能進度條
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [cyanColor, speedColor(speed: speedManager.speedKMH)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, barWidth * fillProgress), height: isLandscape ? 12 : 16)
                                        .shadow(color: speedColor(speed: speedManager.speedKMH).opacity(0.7), radius: 8, x: 0, y: 0)
                                        .animation(.easeOut(duration: 0.2), value: speedManager.speedKMH)
                                }
                            }
                            .frame(height: isLandscape ? 12 : 16)
                            
                            // 進度條底部的刻度數字 (0 ~ 120)
                            HStack {
                                Text("0").font(.caption2).foregroundColor(.gray)
                                Spacer()
                                Text("40").font(.caption2).foregroundColor(.gray)
                                Spacer()
                                Text("80").font(.caption2).foregroundColor(.gray)
                                Spacer()
                                Text("120+").font(.caption2).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 2)
                        }
                        .frame(width: isLandscape ? screenWidth * 0.6 : screenWidth * 0.8)
                        .padding(.top, isLandscape ? 5 : 10)
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
    
    // 根據車速動態切換顏色
    private func speedColor(speed: Double) -> Color {
        switch speed {
        case 0..<40:
            return Color(red: 0.0, green: 1.0, blue: 0.8) // 青綠
        case 40..<80:
            return Color(red: 0.2, green: 0.9, blue: 0.3) // 螢光綠
        case 80..<110:
            return Color(red: 1.0, green: 0.7, blue: 0.0) // 警告黃
        default:
            return Color(red: 1.0, green: 0.2, blue: 0.3) // 爆紅
        }
    }
}
