=import SwiftUI
import CoreLocation
import UIKit

class SpeedManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var speedKmH: Double = 0.0
    @Published var gpsStatus: String = "搜尋衛星中 (無網路約需 1 分鐘)..."
    @Published var isGoodSignal: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 25 {
            gpsStatus = "搜尋衛星中..."
            isGoodSignal = false
            return
        }

        gpsStatus = "GPS 定位成功 (無網路可運作)"
        isGoodSignal = true

        let mps = location.speed
        if mps >= 0 {
            let kmh = mps * 3.6
            self.speedKmH = kmh < 1.5 ? 0.0 : kmh
        } else {
            self.speedKmH = 0.0
        }
    }
}

struct ContentView: View {
    @StateObject private var speedManager = SpeedManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Circle()
                        .fill(speedManager.isGoodSignal ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(speedManager.gpsStatus)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 30)

                Spacer()

                Text("\(Int(round(speedManager.speedKmH)))")
                    .font(.system(size: 150, weight: .heavy, design: .rounded))
                    .foregroundColor(speedManager.speedKmH > 25 ? Color.orange : Color(red: 0.0, green: 0.8, blue: 1.0))

                Text("KM/H")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.gray)

                Spacer()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
