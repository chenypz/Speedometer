import SwiftUI
import CoreLocation
import MapKit
import UIKit

// 相容 iOS 14+ 顏色定義
extension Color {
    static let cyberCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
}

// UIKit MapView 封裝（實現暗黑模式地圖與跟隨位置）
struct MiniMapView: UIViewRepresentable {
    @ObservedObject var speedManager: SpeedometerManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.overrideUserInterfaceStyle = .dark // 強制暗黑模式地圖
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading // 跟隨位置與方向
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = speedManager.lastCLLocation {
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500, // 地圖縮放範圍 (500m)
                longitudinalMeters: 500
            )
            uiView.setRegion(region, animated: true)
        }
    }
}

class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var currentSpeed: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var totalDistance: Double = 0.0 // 公里
    @Published var gpsStatus: String = "SEARCHING"
    @Published var lastCLLocation: CLLocation?
    
    private var startTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    private var timer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = self.startTime {
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 20 { return }
        
        let speedKmH = max(0, location.speed * 3.6)
        
        DispatchQueue.main.async {
            self.currentSpeed = speedKmH
            if speedKmH > self.maxSpeed {
                self.maxSpeed = speedKmH
            }
            
            if let last = self.lastCLLocation {
                let delta = location.distance(from: last)
                if delta > 1.0 && speedKmH > 1.0 {
                    self.totalDistance += (delta / 1000.0)
                }
            }
            self.lastCLLocation = location
            self.gpsStatus = "LOCK"
        }
    }
    
    var formattedTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: elapsedTime) ?? "00:00:00"
    }
}

struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    @State private var isHudMirrored = false
    @State private var speedLimit: Double = 25.0
    @State private var batteryLevel: Float = 1.0
    @State private var currentTimeString: String = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var isOverspeed: Bool {
        return speedManager.currentSpeed > speedLimit
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 背景動態光暈（超速變紅）
            HStack {
                Spacer()
                Circle()
                    .fill((isOverspeed ? Color.red : Color.cyberCyan).opacity(0.15))
                    .blur(radius: 80)
            }
            
            VStack(spacing: 0) {
                // 頂部狀態列
                HStack {
                    // GPS 狀態
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speedManager.gpsStatus == "LOCK" ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: speedManager.gpsStatus == "LOCK" ? .green : .red, radius: 4)
                        Text("GPS: \(speedManager.gpsStatus)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(15)
                    
                    // 電量 & 時間
                    HStack(spacing: 12) {
                        Text("⚡️ \(Int(batteryLevel * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(currentTimeString)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(15)
                    
                    Spacer()
                    
                    // HUD 鏡像切換按鈕
                    Button(action: {
                        isHudMirrored.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.2.swap")
                            Text(isHudMirrored ? "MIRROR ON" : "HUD MODE")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isHudMirrored ? .black : .cyberCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isHudMirrored ? Color.cyberCyan : Color.cyberCyan.opacity(0.15))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer()
                
                // 主要區域：左側時速與數據，右側即時小地圖
                HStack(spacing: 15) {
                    // 左側：極大車速 + 簡化騎乘數據
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: -15) {
                            Text(String(format: "%.0f", speedManager.currentSpeed))
                                .font(.system(size: 105, weight: .heavy, design: .rounded))
                                .italic()
                                .foregroundColor(isOverspeed ? .red : .white)
                                .shadow(color: isOverspeed ? .red : .cyberCyan, radius: 25)
                            
                            HStack {
                                Text("KM/H")
                                    .font(.system(size: 20, weight: .black, design: .monospaced))
                                    .foregroundColor(isOverspeed ? .red : .cyberCyan)
                                    .tracking(4)
                                
                                if isOverspeed {
                                    Text("⚠️ OVER SPEED")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        // 底部數據列
                        HStack(spacing: 8) {
                            MetricBox(title: "TRIP", value: String(format: "%.2f", speedManager.totalDistance), unit: "KM", color: .cyberCyan)
                            MetricBox(title: "MAX", value: String(format: "%.1f", speedManager.maxSpeed), unit: "KM/H", color: .purple)
                            MetricBox(title: "TIME", value: speedManager.formattedTime, unit: "", color: .orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 右側：暗黑模式即時地圖視窗
                    ZStack(alignment: .topTrailing) {
                        MiniMapView(speedManager: speedManager)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.cyberCyan.opacity(0.4), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 10)
                        
                        // 地圖上的科技感標籤
                        Text("LIVE MAP")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyberCyan)
                            .cornerRadius(8)
                            .padding(8)
                    }
                    .frame(width: 240, height: 210)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .scaleEffect(x: isHudMirrored ? -1 : 1, y: 1)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
            updateTime()
        }
        .onReceive(timer) { _ in
            updateTime()
            batteryLevel = UIDevice.current.batteryLevel
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        currentTimeString = formatter.string(from: Date())
    }
}

struct MetricBox: View {
    var title: String
    var value: String
    var unit: String
    var color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .padding(.bottom, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
