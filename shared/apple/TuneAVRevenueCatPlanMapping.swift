import Foundation

#if canImport(RevenueCat)
import RevenueCat

/// Maps RevenueCat product metadata onto Tune AV's offer model.
enum TuneAVRevenueCatPlanMapping {
    static func introductoryOffer(for product: StoreProduct) -> TuneAVSubscriptionIntroductoryOffer? {
        guard let discount = product.introductoryDiscount else { return nil }
        let unit: TuneAVSubscriptionIntroductoryOffer.PeriodUnit
        switch discount.subscriptionPeriod.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        }
        return TuneAVSubscriptionIntroductoryOffer(
            isFreeTrial: discount.paymentMode == .freeTrial,
            periodValue: discount.subscriptionPeriod.value,
            periodUnit: unit
        )
    }
}
#endif
