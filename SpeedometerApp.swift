import SwiftUI

@main
struct SpeedometerApp: App {
    init() {
        // 在 App 啟動時即刻接管 window，隱藏狀態列並讓畫面滿版
        UIApplication.shared.isStatusBarHidden = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden) // iOS 16+ 隱藏底部 Home Indicator 橫條 (達到手遊級沉浸感)
        }
    }
}
