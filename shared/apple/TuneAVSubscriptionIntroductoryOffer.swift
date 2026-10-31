import Foundation

/// StoreKit introductory offer attached to the monthly Pro product, reduced to what the paywall says.
struct TuneAVSubscriptionIntroductoryOffer: Equatable, Sendable {
    enum PeriodUnit: String, Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    let isFreeTrial: Bool
    let periodValue: Int
    let periodUnit: PeriodUnit
}

/// Localized copy shared by the iOS and macOS paywalls for the single monthly plan.
enum TuneAVSubscriptionOfferCopy {
    /// "€4.99 / month".
    static func priceLine(localizedPrice: String) -> String {
        L10n.string("paywall.plan.monthly.price", localizedPrice)
    }

    /// "7 days free, then €4.99 / month" when the monthly product carries a free-trial introductory offer.
    static func trialLine(localizedPrice: String, introductoryOffer: TuneAVSubscriptionIntroductoryOffer?) -> String? {
        guard let offer = introductoryOffer, offer.isFreeTrial else { return nil }
        let periodText: String
        switch offer.periodUnit {
        case .day: periodText = L10n.string("paywall.plan.trial.days", offer.periodValue)
        case .week: periodText = L10n.string("paywall.plan.trial.weeks", offer.periodValue)
        case .month: periodText = L10n.string("paywall.plan.trial.months", offer.periodValue)
        case .year: periodText = L10n.string("paywall.plan.trial.years", offer.periodValue)
        }
        return L10n.string("paywall.plan.trial", periodText, priceLine(localizedPrice: localizedPrice))
    }

    /// Monthly subscription terms, plus the trial clause when a free trial is offered.
    static func terms(localizedPrice: String, introductoryOffer: TuneAVSubscriptionIntroductoryOffer?) -> String {
        var sentences = [L10n.string("paywall.subscriptionTerms", localizedPrice)]
        if introductoryOffer?.isFreeTrial == true {
            sentences.append(L10n.string("paywall.terms.trial"))
        }
        return sentences.joined(separator: " ")
    }
}
