import SwiftUI

@main
struct SpeedometerApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                if #available(iOS 16.0, *) {
                    ContentView()
                        .persistentSystemOverlays(.hidden)
                } else {
                    ContentView()
                }
            }
        }
    }
}
