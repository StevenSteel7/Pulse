import WidgetKit
import SwiftUI

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PulseWidget()
        PulseClassicLargeWidget()
    }
}
