import WidgetKit
import SwiftUI

@main
struct TonneWatchWidgetBundle: WidgetBundle {
    init() { SnapshotStore.applyHomeTimeZone() }

    var body: some Widget {
        WatchPickupWidget()
    }
}
