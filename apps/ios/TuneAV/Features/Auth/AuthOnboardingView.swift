import AuthenticationServices
import AVSettingsFoundation
import SwiftUI
import os

struct AuthOnboardingView: View {
    @Binding var authOptionsArePresented: Bool
    let accountIsAvailable: Bool
    let onContinueWithApple: () async throws -> Void
    let onContinueWithGoogle: () async throws -> Void
    let onSkip: () -> Void

    @State private var activeProvider: AuthProvider?
    @State private var errorMessage = ""
    @State private var isShowingError = false
    @State private var signInTask: Task<Void, Never>?
    @GestureState private var authOptionsDragOffset: CGFloat = 0

    private let authLogger = Logger(subsystem: "com.avalsys.tuneav", category: "auth")

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TuneAVTheme.onboardingBackground.ignoresSafeArea()

                OnboardingBackdrop()
                    .overlay {
                        LinearGradient(
                            colors: [
                                TuneAVTheme.neutral50.opacity(0.16),
                                TuneAVTheme.neutral50.opacity(authOptionsArePresented ? 0.54 : 0.28),
                                TuneAVTheme.neutral50.opacity(authOptionsArePresented ? 0.94 : 0.86)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .blur(radius: authOptionsArePresented ? 6 : 0)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: max(proxy.safeAreaInsets.top + 44, 62))

                    DiscoveryHero(compact: authOptionsArePresented)

                    Spacer(minLength: authOptionsArePresented ? 18 : 246)

                    if authOptionsArePresented {
                        AuthOptionsPanel(
                            accountIsAvailable: accountIsAvailable,
                            legalConsentText: legalConsentText,
                            activeProvider: activeProvider,
                            onAppleTap: startAppleSignIn,
                            onGoogleTap: startGoogleSignIn,
                            onSkip: onSkip
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, max(4, proxy.safeAreaInsets.bottom - 10))
                        .offset(y: authOptionsDragOffset)
                        .gesture(authOptionsDismissGesture)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        CallToActionSection(
                            accountIsAvailable: accountIsAvailable,
                            accountAction: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                    authOptionsArePresented = true
                                }
                            },
                            skipAction: onSkip
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(16, proxy.safeAreaInsets.bottom + 6))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BrandHeaderBadge()
                    .padding(.top, 24)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: authOptionsArePresented)
        .alert(L10n.string("auth.alert.continueFailed.title"), isPresented: $isShowingError) {
            Button(L10n.string("auth.alert.close"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            signInTask?.cancel()
            signInTask = nil
        }
    }

    private func startAppleSignIn() {
        guard accountIsAvailable else {
            errorMessage = AVAccountServiceError.unavailable.localizedDescription
            isShowingError = true
            return
        }
        guard activeProvider == nil else { return }
        activeProvider = .apple
        signInTask?.cancel()

        signInTask = Task {
            do {
                try await onContinueWithApple()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    authOptionsArePresented = false
                    activeProvider = nil
                    signInTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard !error.isAuthenticationCancellation else {
                    await MainActor.run {
                        activeProvider = nil
                        signInTask = nil
                    }
                    return
                }
                logAuthError(error, provider: "apple")
                await MainActor.run {
                    activeProvider = nil
                    signInTask = nil
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
        }
    }

    private func startGoogleSignIn() {
        guard accountIsAvailable else {
            errorMessage = AVAccountServiceError.unavailable.localizedDescription
            isShowingError = true
            return
        }
        guard activeProvider == nil else { return }
        activeProvider = .google
        signInTask?.cancel()

        signInTask = Task {
            do {
                try await onContinueWithGoogle()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    authOptionsArePresented = false
                    activeProvider = nil
                    signInTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard !error.isAuthenticationCancellation else {
                    await MainActor.run {
                        activeProvider = nil
                        signInTask = nil
                    }
                    return
                }
                logAuthError(error, provider: "google")
                await MainActor.run {
                    activeProvider = nil
                    signInTask = nil
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
        }
    }

    private var authOptionsDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($authOptionsDragOffset) { value, state, _ in
                state = max(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss =
                    value.translation.height > 120 ||
                    value.predictedEndTranslation.height > 180

                guard shouldDismiss else { return }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    authOptionsArePresented = false
                }
            }
    }

    private var legalConsentText: AttributedString {
        let termsURL = AppConfig.termsURL?.absoluteString ?? "https://www.avalsys.com/account-av/tune-av/terms"
        let privacyURL = AppConfig.privacyURL?.absoluteString ?? "https://www.avalsys.com/account-av/tune-av/privacy"
        return L10n.markdown("auth.legalConsent", termsURL, privacyURL)
    }

    private func logAuthError(_ error: Error, provider: String) {
        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let underlyingDomain = underlyingError?.domain ?? "none"
        let underlyingCode = underlyingError?.code ?? 0
        authLogger.error(
            "Account AV \(provider, privacy: .public) failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) underlying_domain=\(underlyingDomain, privacy: .public) underlying_code=\(underlyingCode, privacy: .public)"
        )
    }
}

private extension Error {
    var isAuthenticationCancellation: Bool {
        let nsError = self as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            return true
        }

        if nsError.domain.contains("AuthenticationServices"),
           nsError.code == ASAuthorizationError.Code.unknown.rawValue {
            return true
        }

        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
            return true
        }

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        if description.contains("cancel") || description.contains("cancelad") {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying.isAuthenticationCancellation
        }

        return false
    }
}

private enum AuthProvider {
    case apple
    case google
}

private struct DiscoveryHero: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(L10n.string("auth.feature.title"))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(TuneAVTheme.brandGraphite)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.86)

            Text(L10n.string("auth.feature.subtitle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.76))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 316)
        }
        .padding(.horizontal, 24)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .contain)
    }
}

private struct BrandHeaderBadge: View {
    var body: some View {
        HStack {
            Image("AuthWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tune AV")
    }
}

private struct CallToActionSection: View {
    let accountIsAvailable: Bool
    let accountAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: accountIsAvailable ? accountAction : skipAction) {
                Text(L10n.string("auth.cta.continue"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }
            .overlay(alignment: .topTrailing) {
                AviOnboardingCompanion()
                    .offset(x: -2, y: -112)
                    .allowsHitTesting(false)
            }

            Button(L10n.string("auth.cta.skip"), action: skipAction)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.84))
        }
        .background(alignment: .top) {
            RadialGradient(
                colors: [
                    TuneAVTheme.highlight.opacity(0.18),
                    .clear
                ],
                center: .top,
                startRadius: 24,
                endRadius: 220
            )
            .frame(height: 220)
            .offset(y: -18)
        }
    }
}

private struct AviOnboardingCompanion: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(TuneAVTheme.brandGraphite.opacity(0.1))
                .frame(width: 82, height: 11)
                .blur(radius: 5)
                .offset(x: 4, y: 2)

            Image("AviV2OnboardingCTA")
                .resizable()
                .scaledToFit()
                .frame(width: 146, height: 146)
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.12), radius: 10, y: 7)
        }
        .frame(width: 146, height: 150)
        .accessibilityHidden(true)
    }
}

private struct AuthOptionsPanel: View {
    let accountIsAvailable: Bool
    let legalConsentText: AttributedString
    let activeProvider: AuthProvider?
    let onAppleTap: () -> Void
    let onGoogleTap: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(TuneAVTheme.brandGraphite.opacity(0.22))
                .frame(width: 46, height: 4)
                .padding(.top, 12)

            VStack(spacing: 7) {
                Text(L10n.string("auth.options.title"))
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(TuneAVTheme.brandGraphite)
                    .multilineTextAlignment(.center)

                Text(L10n.string("auth.options.subtitle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.neutral600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)

            VStack(spacing: 10) {
                AVAuthProviderButton(
                    title: L10n.string("auth.provider.apple"),
                    isLoading: activeProvider == .apple,
                    style: .dark,
                    action: onAppleTap
                ) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 17, weight: .bold))
                }

                AVAuthProviderButton(
                    title: L10n.string("auth.provider.google"),
                    isLoading: activeProvider == .google,
                    style: .light,
                    action: onGoogleTap
                ) {
                    GoogleBadge()
                }
            }
            .padding(.top, 20)
            .disabled(!accountIsAvailable)

            if !accountIsAvailable {
                Text(L10n.string("auth.options.unavailable"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            Button(L10n.string("auth.options.skip"), action: onSkip)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.82))
                .padding(.top, 16)

            Text(legalConsentText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.66))
                .tint(TuneAVTheme.brandGraphite.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.99, green: 0.97, blue: 0.91).opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(TuneAVTheme.brandGraphite.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
        )
        .overlay(alignment: .topTrailing) {
            AviSheetPeekCompanion()
                .offset(x: -44, y: -91)
                .allowsHitTesting(false)
        }
    }
}

private struct AviSheetPeekCompanion: View {
    var body: some View {
        Image("AviV2LoginSheetPeek")
            .resizable()
            .scaledToFit()
            .frame(width: 126, height: 126)
            .shadow(color: TuneAVTheme.brandGraphite.opacity(0.1), radius: 8, y: 5)
            .offset(y: -5)
        .frame(width: 140, height: 110)
        .accessibilityHidden(true)
    }
}

private struct GoogleBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)

            Text("G")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.22, green: 0.74, blue: 0.35),
                            Color(red: 0.99, green: 0.84, blue: 0.21),
                            Color(red: 0.92, green: 0.31, blue: 0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 20, height: 20)
    }
}

private struct OnboardingBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.94, blue: 0.86),
                        TuneAVTheme.neutral50,
                        Color(red: 0.9, green: 0.93, blue: 0.89)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image("AviOnboardingHeroStatic")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: 50)
                    .clipped()
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.18), location: 0.1),
                                .init(color: .black, location: 0.23),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .opacity(0.82)
                    .saturation(0.92)

                VStack {
                    Spacer()

                    CurvedWave()
                        .stroke(TuneAVTheme.highlight.opacity(0.1), lineWidth: 2)
                        .frame(height: 180)

                    CurvedWave(offset: 50)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                        .frame(height: 210)
                        .offset(y: -24)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct CurvedWave: Shape {
    var offset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -40, y: rect.height * 0.72 - offset))
        path.addCurve(
            to: CGPoint(x: rect.width + 40, y: rect.height * 0.86 - offset),
            control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.12 - offset),
            control2: CGPoint(x: rect.width * 0.75, y: rect.height * 0.18 - offset)
        )
        return path
    }
}

#Preview("Collapsed") {
    AuthOnboardingView(
        authOptionsArePresented: .constant(false),
        accountIsAvailable: true,
        onContinueWithApple: { },
        onContinueWithGoogle: { },
        onSkip: {}
    )
}

#Preview("Expanded") {
    AuthOnboardingView(
        authOptionsArePresented: .constant(true),
        accountIsAvailable: true,
        onContinueWithApple: { },
        onContinueWithGoogle: { },
        onSkip: {}
    )
}
