import WidgetKit
import SwiftUI

@main
struct TonneWidgetBundle: WidgetBundle {
    var body: some Widget {
        PickupWidget()
        PickupLiveActivity()
    }
}
