import SwiftUI

@main
struct TonneWatchApp: App {
    init() {
        SnapshotStore.applyHomeTimeZone()
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView().tonneTypography(maxSize: .xxLarge)
        }
    }
}
