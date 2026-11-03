import SwiftUI
import WidgetKit

@main
struct TuneAVWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TuneAVMyRadioWidget()
        TuneAVNowPlayingFavoritesWidget()
        TuneAVLockScreenRadioWidget()
        // The Live Activity is off (`TuneAVLiveActivityFeature.isEnabled`): the lock screen shows
        // only the system Now Playing player. Register `TuneAVNowPlayingLiveActivity()` here again
        // when the switch is turned back on.
        TuneAVMyRadioControl()
    }
}
