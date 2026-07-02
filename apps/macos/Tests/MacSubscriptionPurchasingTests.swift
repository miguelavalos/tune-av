import AccountAV
import XCTest
@testable import TuneAVMac

@MainActor
final class MacSubscriptionPurchasingTests: XCTestCase {
    private let lastKnownAccountUserKey = "tuneav.mac.account.lastKnownUser"

    func testUITestPurchasingLoadsMonthlyOfferForSignedInUser() async throws {
        let purchasing = MacUITestTuneAVSubscriptionPurchasing()
        let user = AccountAVUser(id: "user_123", displayName: "Tune Listener", emailAddress: "listener@example.com")

        let offer = try await purchasing.loadMonthlyOffer(for: user)

        XCTAssertEqual(offer.identifier, "$rc_monthly")
        XCTAssertEqual(offer.productIdentifier, "tuneav_pro_monthly")
        XCTAssertFalse(offer.localizedPrice.isEmpty)
    }

    func testUITestPurchasingRequiresSignedInUser() async {
        let purchasing = MacUITestTuneAVSubscriptionPurchasing()

        do {
            _ = try await purchasing.loadMonthlyOffer(for: nil)
            XCTFail("Expected missing account user error")
        } catch let error as MacTuneAVSubscriptionPurchaseError {
            XCTAssertEqual(error, .missingAccountUser)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModelLoadsMonthlyOfferForPersistedSignedInFreeUser() async {
        let userDefaults = UserDefaults.standard
        let originalUser = userDefaults.data(forKey: lastKnownAccountUserKey)
        defer {
            if let originalUser {
                userDefaults.set(originalUser, forKey: lastKnownAccountUserKey)
            } else {
                userDefaults.removeObject(forKey: lastKnownAccountUserKey)
            }
        }

        let userSnapshot = """
        {"id":"user_123","displayName":"Tune Listener","emailAddress":"listener@example.com"}
        """
        userDefaults.set(Data(userSnapshot.utf8), forKey: lastKnownAccountUserKey)

        let model = TuneAVMacModel(
            subscriptionPurchasing: MacUITestTuneAVSubscriptionPurchasing(),
            subscriptionReconciliationRetryDelaysNanoseconds: [],
            sleepNanoseconds: { _ in }
        )

        XCTAssertEqual(model.accessMode, .signedInFree)

        await model.loadMonthlySubscriptionOffer()

        XCTAssertNil(model.subscriptionError)
        XCTAssertEqual(model.subscriptionOffer?.identifier, "$rc_monthly")
        XCTAssertEqual(model.subscriptionOffer?.productIdentifier, "tuneav_pro_monthly")
    }

    func testModelClaimPromotionCodeUsesBackendRedeemerAndStartsReconciliation() async throws {
        let userDefaults = UserDefaults.standard
        let originalUser = userDefaults.data(forKey: lastKnownAccountUserKey)
        defer {
            if let originalUser {
                userDefaults.set(originalUser, forKey: lastKnownAccountUserKey)
            } else {
                userDefaults.removeObject(forKey: lastKnownAccountUserKey)
            }
        }

        let userSnapshot = """
        {"id":"user_123","displayName":"Tune Listener","emailAddress":"listener@example.com"}
        """
        userDefaults.set(Data(userSnapshot.utf8), forKey: lastKnownAccountUserKey)

        let promotionCodeRedeemer = StubPromotionCodeRedeemer()
        let model = TuneAVMacModel(
            subscriptionPurchasing: MacUITestTuneAVSubscriptionPurchasing(),
            promotionCodeRedeemer: promotionCodeRedeemer,
            subscriptionReconciliationRetryDelaysNanoseconds: [],
            sleepNanoseconds: { _ in }
        )

        XCTAssertEqual(model.accessMode, .signedInFree)

        try await model.claimPromotionCode(" tune-pro-2026 ")

        XCTAssertEqual(promotionCodeRedeemer.codes, ["tune-pro-2026"])
        XCTAssertEqual(model.accessMode, .signedInFree)
        XCTAssertTrue(model.isWaitingForSubscriptionReconciliation)
        XCTAssertEqual(model.subscriptionReconciliationSource, .redeemCode)
        XCTAssertNil(model.subscriptionError)
    }
}

@MainActor
private final class StubPromotionCodeRedeemer: TuneAVPromotionCodeRedeeming {
    private(set) var codes: [String] = []

    func redeemPromotionCode(_ code: String) async throws -> TuneAVPromoCodeRedemptionResponse {
        codes.append(code)
        return TuneAVPromoCodeRedemptionResponse(
            appId: "tuneav",
            userId: "user_123",
            code: code,
            campaignId: "campaign-1",
            redemptionId: "redemption-1",
            entitlement: TuneAVPromoCodeEntitlement(
                appId: "tuneav",
                userId: "user_123",
                planTier: "pro",
                accessMode: "signedInPro",
                status: "active",
                source: "promo"
            )
        )
    }
}
