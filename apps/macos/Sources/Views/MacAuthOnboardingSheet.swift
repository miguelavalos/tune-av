import SwiftUI

struct MacAuthOnboardingSheet: View {
    let accountIsAvailable: Bool
    let isAuthenticating: Bool
    let errorMessage: String?
    let onContinueWithApple: () -> Void
    let onContinueWithGoogle: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .padding(10)
                    .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("auth.feature.title"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("auth.feature.subtitle"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(accountIsAvailable ? L10n.string("auth.cta.subtitle.available") : L10n.string("auth.cta.subtitle.unavailable"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onContinueWithApple) {
                    Label("Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accountIsAvailable || isAuthenticating)

                Button(action: onContinueWithGoogle) {
                    Label("Google", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!accountIsAvailable || isAuthenticating)
            }

            Button(accountIsAvailable ? L10n.string("auth.cta.localMode") : L10n.string("auth.cta.skip"), action: onSkip)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 460)
        .background(TuneAVTheme.shellBackground)
    }
}
