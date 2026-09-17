=import SwiftUI
import CoreLocation

class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentSpeed: Double = 0.0 // km/h
    @Published var maxSpeed: Double = 0.0
    @Published var gpsStatus: String = "SEARCHING"
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // m/s 轉 km/h
        let speedKmH = max(0, location.speed * 3.6)
        DispatchQueue.main.async {
            self.currentSpeed = speedKmH
            if speedKmH > self.maxSpeed {
                self.maxSpeed = speedKmH
            }
            self.gpsStatus = "LOCK"
        }
    }
}

struct ContentView: View {
    @StateObject private var speedManager = SpeedometerManager()
    
    // 設定儀表板最大顯示速度 (例如微型電動車設為 60)
    let maxGaugeSpeed: Double = 60.0
    
    var body: some View {
        ZStack {
            // 1. 純黑背景 (節能且高對比)
            Color.black.ignoresSafeArea()
            
            // 背景微弱網格紋理感
            VStack {
                Spacer()
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .blur(radius: 90)
            }
            
            VStack(spacing: 30) {
                // 顶部 科技感狀態列
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speedManager.gpsStatus == "LOCK" ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: speedManager.gpsStatus == "LOCK" ? .green : .red, radius: 4)
                        Text("GPS: \(speedManager.gpsStatus)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    
                    Spacer()
                    
                    Text("CYBER-HUD v1.0")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(Color.cyan.opacity(0.6))
                }
                .padding(.horizontal, 25)
                .padding(.top, 10)
                
                Spacer()
                
                // 2. 中央霓虹速限色環儀表
                ZStack {
                    // 底環
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 15)
                        .frame(width: 250, height: 250)
                    
                    // 動態進度環
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(speedManager.currentSpeed / maxGaugeSpeed, 1.0)))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple, .pink]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 15, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 250, height: 250)
                        .shadow(color: .cyan, radius: 10) // 霓虹發光效果
                        .animation(.linear(duration: 0.2), value: speedManager.currentSpeed)
                    
                    // 速度數字與單位
                    VStack(spacing: -5) {
                        Text(String(format: "%.0f", speedManager.currentSpeed))
                            .font(.system(size: 85, weight: .heavy, design: .rounded))
                            .italic()
                            .foregroundColor(.white)
                            .shadow(color: .cyan, radius: 15) // 文字霓虹 Glow
                        
                        Text("KM/H")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                            .tracking(4)
                    }
                }
                
                Spacer()
                
                // 3. 底部駕駛數據方塊
                HStack(spacing: 20) {
                    MetricBox(title: "MAX SPEED", value: String(format: "%.1f", speedManager.maxSpeed), unit: "KM/H", color: .purple)
                    MetricBox(title: "LIMIT", value: "25.0", unit: "KM/H", color: .orange)
                }
                .padding(.horizontal, 25)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true // 保持螢幕常亮
        }
    }
}

// 數據方塊模組
struct MetricBox: View {
    var title: String
    var value: String
    var unit: String
    var color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.bottom, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
