import XCTest

@MainActor
final class LaunchPerformanceUITests: TuneAVUITestCase {
    func testLaunchReachesHomeWithinBudget() {
        let budgetMilliseconds = Self.launchReadyBudgetMilliseconds
        let startedAt = Date()

        let app = launchApp()
        let timeout = budgetMilliseconds / 1_000

        XCTAssertTrue(
            shellButton("search", in: app, timeout: timeout).exists,
            "Tune AV did not reach the home shell within \(Int(budgetMilliseconds))ms."
        )

        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        print("Tune AV launch ready: \(Int(elapsedMilliseconds.rounded()))ms budget=\(Int(budgetMilliseconds))ms")
        XCTAssertLessThanOrEqual(elapsedMilliseconds, budgetMilliseconds)
    }

    private static var launchReadyBudgetMilliseconds: TimeInterval {
        let value = ProcessInfo.processInfo.environment["TUNEAV_UI_TEST_MAX_LAUNCH_READY_MS"] ?? "10000"
        return Double(value) ?? 10_000
    }
}
