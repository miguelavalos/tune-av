import Foundation

@MainActor
final class TuneAVSleepTimerController {
    private var timer: Timer?
    private(set) var endDate: Date?

    func setTimer(
        minutes: Int?,
        setDescription: @MainActor @escaping (String?) -> Void,
        onFire: @MainActor @escaping () -> Void
    ) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        setDescription(nil)

        guard let minutes else { return }

        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        setDescription(L10n.string("audio.sleep.inMinutes", minutes))
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { _ in
            Task { @MainActor in
                onFire()
                setDescription(L10n.string("audio.sleep.ended"))
            }
        }
    }

    func clearNoticeIfIdle(isIdle: Bool, setDescription: (String?) -> Void) {
        guard isIdle else { return }
        setDescription(nil)
    }
}
