import SwiftUI

@main
struct TonneWatchApp: App {
    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
