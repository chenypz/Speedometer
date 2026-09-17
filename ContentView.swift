import SwiftUI
import CoreLocation

// 定義 iOS 14 相容的賽博青色 (Cyan)
extension Color {
    static let cyberCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
}

class SpeedometerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentSpeed: Double = 0.0
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
    let maxGaugeSpeed: Double = 60.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 背景科技藍光
            HStack {
                Spacer()
                Circle()
                    .fill(Color.cyberCyan.opacity(0.15))
                    .blur(radius: 80)
            }
            
            VStack(spacing: 0) {
                // 頂部狀態列
                HStack {
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
                    
                    Spacer()
                    
                    Text("CYBER-HUD LANDSCAPE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(Color.cyberCyan.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // 橫向左右分欄
                HStack(spacing: 30) {
                    // 左側：極大字體車速
                    VStack(alignment: .leading, spacing: -10) {
                        Text(String(format: "%.0f", speedManager.currentSpeed))
                            .font(.system(size: 110, weight: .heavy, design: .rounded))
                            .italic()
                            .foregroundColor(.white)
                            .shadow(color: .cyberCyan, radius: 20)
                        
                        Text("KM/H")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(.cyberCyan)
                            .tracking(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // 右側：動態圓環 + 數據盒
                    VStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 12)
                                .frame(width: 140, height: 140)
                            
                            Circle()
                                .trim(from: 0.0, to: CGFloat(min(speedManager.currentSpeed / maxGaugeSpeed, 1.0)))
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [.cyberCyan, .blue, .purple]),
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 140, height: 140)
                                .shadow(color: .cyberCyan, radius: 8)
                                .animation(.linear(duration: 0.2))
                            
                            VStack(spacing: 2) {
                                Text("LIMIT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                Text("25")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        HStack(spacing: 10) {
                            MetricBox(title: "MAX", value: String(format: "%.1f", speedManager.maxSpeed), unit: "KM/H", color: .purple)
                        }
                        .frame(width: 160)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}

struct MetricBox: View {
    var title: String
    var value: String
    var unit: String
    var color: Color
    
    var body: View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
