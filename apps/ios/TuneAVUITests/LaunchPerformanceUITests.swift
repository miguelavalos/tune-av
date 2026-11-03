import XCTest

private final class LostAutomationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}

@MainActor
final class LaunchPerformanceUITests: TuneAVUITestCase {
    private static let warmUpTimeout: TimeInterval = 60
    private static let warmUpAttempts = 3
    private static let settleAfterHome: TimeInterval = 2
    private static let terminateTimeout: TimeInterval = 10
    private static let timedLaunchCount = 2
    private static let lostAutomationMarker = "Lost connection to the application"

    private struct LaunchReadiness {
        let milliseconds: TimeInterval
        let reachedHome: Bool
        let appState: XCUIApplication.State
        let lostAutomation: Bool
    }

    func testLaunchReachesHomeWithinBudget() {
        let budgetMilliseconds = Self.launchReadyBudgetMilliseconds

        var warmUp = measureWarmUpLaunch()
        var warmUpAttempt = 1
        print("Tune AV launch ready: warm-up \(Self.describe(warmUp)) (untimed)")
        while warmUp.lostAutomation, warmUp.appState == .runningForeground, warmUpAttempt < Self.warmUpAttempts {
            warmUpAttempt += 1
            warmUp = measureWarmUpLaunch()
            print("Tune AV launch ready: warm-up attempt \(warmUpAttempt) \(Self.describe(warmUp)) (untimed)")
        }
        guard warmUp.reachedHome, warmUp.appState == .runningForeground else {
            XCTFail(
                "Tune AV did not reach and stay on the home shell on the warm-up launch within "
                    + "\(Int(Self.warmUpTimeout))s after \(warmUpAttempt) attempt(s) (reachedHome \(warmUp.reachedHome), "
                    + "app state \(warmUp.appState.rawValue), lost automation \(warmUp.lostAutomation))."
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

    private func measureWarmUpLaunch() -> LaunchReadiness {
        let lostAutomation = LostAutomationFlag()
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { issue in
            guard issue.compactDescription.contains(Self.lostAutomationMarker) else { return false }
            lostAutomation.set()
            return true
        }

        var result: LaunchReadiness?
        XCTExpectFailure("The automation connection to the app can drop on a cold simulator.", options: options) {
            result = measureLaunchReadiness(timeout: Self.warmUpTimeout, lostAutomation: lostAutomation)
        }
        return result ?? LaunchReadiness(milliseconds: .infinity, reachedHome: false, appState: .unknown, lostAutomation: true)
    }

    private func measureLaunchReadiness(
        timeout: TimeInterval,
        lostAutomation: LostAutomationFlag = LostAutomationFlag()
    ) -> LaunchReadiness {
        terminateAndWait(XCUIApplication())

        let startedAt = Date()
        let app = launchApp()
        let homeShell = shellElement("explore", in: app)
        let deadline = startedAt.addingTimeInterval(timeout)

        var reachedHome = false
        while Date() < deadline, app.state == .runningForeground, !lostAutomation.isSet {
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
        terminateAndWait(app)
        return LaunchReadiness(
            milliseconds: elapsedMilliseconds,
            reachedHome: reachedHome,
            appState: state,
            lostAutomation: lostAutomation.isSet
        )
    }

    private func terminateAndWait(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: Self.terminateTimeout),
            "Tune AV was still running \(Int(Self.terminateTimeout))s after terminate."
        )
    }

    private static func format(_ milliseconds: TimeInterval) -> String {
        milliseconds.isFinite ? "\(Int(milliseconds.rounded()))ms" : "none"
    }

    private static func describe(_ launch: LaunchReadiness) -> String {
        format(launch.milliseconds) + (launch.reachedHome ? "" : " (home not reached)")
            + (launch.lostAutomation ? " (lost automation connection)" : "")
    }

    private static var launchReadyBudgetMilliseconds: TimeInterval {
        let value = ProcessInfo.processInfo.environment["TUNEAV_UI_TEST_MAX_LAUNCH_READY_MS"] ?? "10000"
        return Double(value) ?? 10_000
    }
}
