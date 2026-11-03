import XCTest

@MainActor
final class LaunchPerformanceUITests: TuneAVUITestCase {
    private static let warmUpTimeout: TimeInterval = 60
    private static let settleAfterHome: TimeInterval = 2
    private static let timedLaunchCount = 2

    private struct LaunchReadiness {
        let milliseconds: TimeInterval
        let reachedHome: Bool
        let appState: XCUIApplication.State
    }

    func testLaunchReachesHomeWithinBudget() {
        let budgetMilliseconds = Self.launchReadyBudgetMilliseconds

        let warmUp = measureLaunchReadiness(timeout: Self.warmUpTimeout)
        print("Tune AV launch ready: warm-up \(Self.describe(warmUp)) (untimed)")
        guard warmUp.reachedHome, warmUp.appState == .runningForeground else {
            XCTFail(
                "Tune AV did not reach and stay on the home shell on the warm-up launch within "
                    + "\(Int(Self.warmUpTimeout))s (reachedHome \(warmUp.reachedHome), app state \(warmUp.appState.rawValue))."
            )
            return
        }

        var timedLaunches: [LaunchReadiness] = []
        for run in 1...Self.timedLaunchCount {
            let result = measureLaunchReadiness(timeout: budgetMilliseconds / 1_000)
            print("Tune AV launch ready: run \(run) \(Self.describe(result))")
            XCTAssertEqual(
                result.appState,
                .runningForeground,
                "Tune AV stopped running in the foreground during timed launch \(run)."
            )
            timedLaunches.append(result)
        }

        let bestMilliseconds = timedLaunches.filter(\.reachedHome).map(\.milliseconds).min() ?? .infinity
        let runs = timedLaunches.map { Self.describe($0) }.joined(separator: ",")
        print(
            "Tune AV launch ready: \(Self.format(bestMilliseconds)) budget=\(Int(budgetMilliseconds))ms "
                + "best-of=\(Self.timedLaunchCount) runs=[\(runs)] warm-up=\(Self.describe(warmUp))"
        )
        XCTAssertLessThanOrEqual(
            bestMilliseconds,
            budgetMilliseconds,
            "Tune AV did not reach the home shell within \(Int(budgetMilliseconds))ms on any timed launch (runs \(runs))."
        )
    }

    private func measureLaunchReadiness(timeout: TimeInterval) -> LaunchReadiness {
        XCUIApplication().terminate()

        let startedAt = Date()
        let app = launchApp()
        let homeShell = shellElement("explore", in: app)
        let deadline = startedAt.addingTimeInterval(timeout)

        var reachedHome = false
        while Date() < deadline, app.state == .runningForeground {
            if homeShell.exists {
                reachedHome = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        if reachedHome {
            RunLoop.current.run(until: Date().addingTimeInterval(Self.settleAfterHome))
        }
        let state = app.state
        app.terminate()
        return LaunchReadiness(milliseconds: elapsedMilliseconds, reachedHome: reachedHome, appState: state)
    }

    private static func format(_ milliseconds: TimeInterval) -> String {
        milliseconds.isFinite ? "\(Int(milliseconds.rounded()))ms" : "none"
    }

    private static func describe(_ launch: LaunchReadiness) -> String {
        format(launch.milliseconds) + (launch.reachedHome ? "" : " (home not reached)")
    }

    private static var launchReadyBudgetMilliseconds: TimeInterval {
        let value = ProcessInfo.processInfo.environment["TUNEAV_UI_TEST_MAX_LAUNCH_READY_MS"] ?? "10000"
        return Double(value) ?? 10_000
    }
}
