import SwiftUI
import WidgetKit

@main
struct TuneAVWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TuneAVMyRadioWidget()
        TuneAVNowPlayingFavoritesWidget()
        TuneAVLockScreenRadioWidget()
        TuneAVNowPlayingLiveActivity()
        TuneAVMyRadioControl()
    }
}
