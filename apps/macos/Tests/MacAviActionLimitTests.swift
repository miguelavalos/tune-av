import XCTest
@testable import TuneAVMac

@MainActor
final class MacAviActionLimitTests: XCTestCase {
    private let lastKnownAccountUserKey = "tuneav.mac.account.lastKnownUser"

    func testGuestGetsFiveAviLookupsBeforeTheUpgradePrompt() {
        let originalUser = UserDefaults.standard.data(forKey: lastKnownAccountUserKey)
        UserDefaults.standard.removeObject(forKey: lastKnownAccountUserKey)
        defer { restoreLastKnownUser(originalUser) }

        let model = makeModel()
        XCTAssertEqual(model.accessMode, .guest)

        for index in 0..<5 {
            XCTAssertTrue(
                model.canPerformPremiumAviSearch(destination: .web, suffix: "lyrics", usageKey: "song \(index)"),
                "Lookup \(index + 1) of 5 must be allowed for a guest"
            )
            XCTAssertNil(model.upgradePrompt)
        }

        XCTAssertFalse(model.canPerformPremiumAviSearch(destination: .youtube, usageKey: "song 5"))
        XCTAssertEqual(model.upgradePrompt?.feature, .youtubeSearch)
        XCTAssertTrue(
            model.canPerformPremiumAviSearch(destination: .web, suffix: "lyrics", usageKey: "song 0"),
            "A lookup already counted today stays available"
        )
    }

    func testFreeAccountGetsFifteenAviLookupsBeforeTheUpgradePrompt() {
        let originalUser = UserDefaults.standard.data(forKey: lastKnownAccountUserKey)
        defer { restoreLastKnownUser(originalUser) }
        UserDefaults.standard.set(
            Data(#"{"id":"user_123","displayName":"Tune Listener","emailAddress":"listener@example.com"}"#.utf8),
            forKey: lastKnownAccountUserKey
        )

        let model = makeModel()
        XCTAssertEqual(model.accessMode, .signedInFree)

        for index in 0..<15 {
            XCTAssertTrue(
                model.canPerformPremiumAviSearch(destination: .spotify, usageKey: "song \(index)"),
                "Lookup \(index + 1) of 15 must be allowed for a Free account"
            )
            XCTAssertNil(model.upgradePrompt)
        }

        XCTAssertFalse(model.canPerformPremiumAviSearch(destination: .appleMusic, usageKey: "song 15"))
        XCTAssertEqual(model.upgradePrompt?.feature, .appleMusicSearch)
    }

    private func makeModel() -> TuneAVMacModel {
        TuneAVMacModel(
            subscriptionPurchasing: MacUITestTuneAVSubscriptionPurchasing(),
            subscriptionReconciliationRetryDelaysNanoseconds: [],
            dailyUsageDefaults: UserDefaults(suiteName: "MacAviActionLimitTests.\(UUID().uuidString)")!,
            nowProvider: { Date(timeIntervalSince1970: 1_780_000_000) },
            sleepNanoseconds: { _ in }
        )
    }

    private func restoreLastKnownUser(_ data: Data?) {
        if let data {
            UserDefaults.standard.set(data, forKey: lastKnownAccountUserKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastKnownAccountUserKey)
        }
    }
}
