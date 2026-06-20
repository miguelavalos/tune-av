import AVBrandFoundation
import AVSettingsFoundation

enum TuneAppExperience {
    private static let appIdentity = AVAppIdentity(
        displayName: "Tune AV",
        assistantName: "Avi",
        accountName: "Account AV"
    )

    @MainActor
    static var experience: AVCommonAppExperience {
        AVCommonAppExperience(
            identity: appIdentity,
            legalLinks: legalLinks,
            brandPalette: TuneAVTheme.brandPalette,
            visualAssets: visualAssets,
            splashTagline: L10n.string("splash.tagline"),
            splashStatus: L10n.string("splash.status"),
            onboardingTitle: L10n.string("auth.feature.title"),
            onboardingSubtitle: L10n.string("auth.feature.subtitle"),
            onboardingPrimaryTitle: L10n.string("auth.cta.continue"),
            onboardingSecondaryTitle: L10n.string("auth.cta.skip"),
            onboardingBackgroundStart: .init(red: 0.97, green: 0.94, blue: 0.86),
            onboardingBackgroundMid: TuneAVTheme.neutral50,
            onboardingBackgroundEnd: .init(red: 0.9, green: 0.93, blue: 0.89)
        )
    }

    static var identity: AVAppIdentity {
        appIdentity
    }

    static var visualAssets: AVCommonAppVisualAssets {
        AVCommonAppVisualAssets(
            headerLogoName: "HeaderWordmark",
            splashLogoName: "SplashLogo",
            splashHeroName: "AviSplashListeningBackground",
            onboardingBrandName: "AuthOnboardingWordmark",
            onboardingHeroName: "AviOnboardingHeroStatic",
            onboardingCTACompanionName: "AviV2OnboardingCTA",
            onboardingAuthPanelCompanionName: "AviV2LoginSheetPeek",
            footerAssistantName: "AviFooterIcon"
        )
    }

    @MainActor
    static var legalLinks: AVAppLegalLinks {
        AVAppLegalLinks(
            supportURL: AppConfig.supportURL,
            privacyURL: AppConfig.privacyURL,
            termsURL: AppConfig.termsURL
        )
    }
}
