import WidgetKit
import SwiftUI

@main
struct TonneWidgetBundle: WidgetBundle {
    init() { SnapshotStore.applyHomeTimeZone() }

    var body: some Widget {
        PickupWidget()
        BirthdayWidget()
        PickupLiveActivity()
    }
}
