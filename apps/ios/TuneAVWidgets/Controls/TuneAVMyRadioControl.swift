import AppIntents
import SwiftUI
import WidgetKit

struct TuneAVMyRadioControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: TuneAVControlKind.myRadio, provider: TuneAVMyRadioControlProvider()) { value in
            ControlWidgetToggle(isOn: value.isPlaying, action: TuneAVMyRadioControlIntent()) {
                Text(value.title)
            } valueLabel: { isOn in
                Label(value.subtitle, systemImage: isOn ? "pause.fill" : "play.fill")
                    .controlWidgetActionHint(isOn ? value.pauseHint : value.playHint)
            }
            .tint(TuneAVWidgetBrand.green)
        }
        .displayName(LocalizedStringResource(stringLiteral: TuneAVWidgetText.string("widget.myRadio.title", fallback: "My radio")))
        .description(LocalizedStringResource(stringLiteral: TuneAVWidgetText.string(
            "control.myRadio.description",
            fallback: "Play or pause your radio."
        )))
    }
}

struct TuneAVMyRadioControlValue: Hashable, Sendable {
    var isPlaying: Bool
    var title: String
    var subtitle: String
    var playHint: String
    var pauseHint: String

    init(snapshot: TuneAVWidgetSnapshot?, fallbackStrings: TuneAVWidgetStrings) {
        let strings = snapshot?.strings ?? fallbackStrings
        isPlaying = snapshot?.isPlaybackActive ?? false
        title = strings.myRadio
        subtitle = snapshot?.myRadio?.name ?? strings.emptyTitle
        playHint = strings.play
        pauseHint = strings.pause
    }
}

struct TuneAVMyRadioControlProvider: ControlValueProvider {
    var previewValue: TuneAVMyRadioControlValue {
        TuneAVMyRadioControlValue(snapshot: TuneAVWidgetText.previewSnapshot, fallbackStrings: TuneAVWidgetText.fallbackStrings)
    }

    func currentValue() async throws -> TuneAVMyRadioControlValue {
        TuneAVMyRadioControlValue(
            snapshot: TuneAVWidgetSnapshotStore.readShared(),
            fallbackStrings: TuneAVWidgetText.fallbackStrings
        )
    }
}
