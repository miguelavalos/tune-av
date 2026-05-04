import AuthenticationServices
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
                                TuneAVTheme.brandBlack.opacity(0.04),
                                TuneAVTheme.brandBlack.opacity(authOptionsArePresented ? 0.42 : 0.24),
                                TuneAVTheme.brandBlack.opacity(0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .blur(radius: authOptionsArePresented ? 6 : 0)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: max(proxy.safeAreaInsets.top + 96, authOptionsArePresented ? 128 : 148))

                    FeatureCallout(compact: authOptionsArePresented)

                    Spacer(minLength: authOptionsArePresented ? 24 : 94)

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
                        .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
                        .offset(y: authOptionsDragOffset)
                        .gesture(authOptionsDismissGesture)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        CallToActionSection(
                            accountIsAvailable: accountIsAvailable,
                            listenAction: onSkip,
                            accountAction: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                    authOptionsArePresented = true
                                }
                            },
                            skipAction: onSkip
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 12))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .top) {
                    BrandHeaderBadge()
                        .padding(.top, proxy.safeAreaInsets.top + 8)
                }
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: authOptionsArePresented)
        .alert(L10n.string("auth.alert.continueFailed.title"), isPresented: $isShowingError) {
            Button(L10n.string("auth.alert.close"), role: .cancel) {}
        } message: {
            Text(errorMessage)
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

        Task {
            do {
                try await onContinueWithApple()
                await MainActor.run {
                    authOptionsArePresented = false
                    activeProvider = nil
                }
            } catch {
                guard !error.isAuthenticationCancellation else {
                    await MainActor.run {
                        activeProvider = nil
                    }
                    return
                }
                logAuthError(error, provider: "apple")
                await MainActor.run {
                    activeProvider = nil
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

        Task {
            do {
                try await onContinueWithGoogle()
                await MainActor.run {
                    authOptionsArePresented = false
                    activeProvider = nil
                }
            } catch {
                guard !error.isAuthenticationCancellation else {
                    await MainActor.run {
                        activeProvider = nil
                    }
                    return
                }
                logAuthError(error, provider: "google")
                await MainActor.run {
                    activeProvider = nil
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
        let termsURL = AppConfig.termsURL?.absoluteString ?? "https://www.avalsys.com/av-account/tune-av/terms"
        let privacyURL = AppConfig.privacyURL?.absoluteString ?? "https://www.avalsys.com/av-account/tune-av/privacy"
        return L10n.markdown("auth.legalConsent", termsURL, privacyURL)
    }

    private func logAuthError(_ error: Error, provider: String) {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey].map { "\($0)" } ?? "none"
        authLogger.error(
            "Account AV \(provider, privacy: .public) failed: type=\(String(describing: type(of: error)), privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(error.localizedDescription, privacy: .public) underlying=\(underlying, privacy: .public)"
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

private struct FeatureCallout: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 14 : 18) {
            HeroBadge(size: compact ? 104 : 124)

            VStack(spacing: compact ? 10 : 12) {
                Text(L10n.string("auth.feature.title"))
                    .font(.system(size: compact ? 26 : 30, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textInverse)
                    .multilineTextAlignment(.center)

                Text(L10n.string("auth.feature.subtitle"))
                    .font(.system(size: compact ? 15 : 16, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textInverse.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, compact ? 18 : 14)
                    .frame(maxWidth: 320)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, compact ? 16 : 18)
            .frame(maxWidth: 350)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(TuneAVTheme.brandBlack.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            )
        }
        .padding(.horizontal, 24)
    }
}

private struct BrandHeaderBadge: View {
    var body: some View {
        HStack {
            Image("OnboardingWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 174)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tune AV")
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.46), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

private struct HeroBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(TuneAVTheme.brandBlack.opacity(0.8))
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.44), radius: 34, y: 22)

            Circle()
                .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                .frame(width: size + 18, height: size + 18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            TuneAVTheme.highlight.opacity(0.16),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: size / 1.5
                    )
                )
                .frame(width: size * 0.86, height: size * 0.86)

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: size * 0.58, height: size * 0.58)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
                .overlay {
                    VStack(spacing: size * 0.035) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: size * 0.18, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.highlight)

                        HStack(spacing: size * 0.04) {
                            ForEach(Array([0.16, 0.34, 0.18].enumerated()), id: \.offset) { index, height in
                                Capsule(style: .continuous)
                                    .fill(index == 1 ? TuneAVTheme.highlight : Color.white.opacity(0.24))
                                    .frame(width: size * 0.035, height: size * height)
                            }
                        }
                    }
                }
        }
    }
}

private struct CallToActionSection: View {
    let accountIsAvailable: Bool
    let listenAction: () -> Void
    let accountAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: listenAction) {
                Text(L10n.string("auth.cta.localMode"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }

            Text(accountIsAvailable ? L10n.string("auth.cta.subtitle.available") : L10n.string("auth.cta.subtitle.unavailable"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.76))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            Button(accountIsAvailable ? L10n.string("auth.cta.continue") : L10n.string("auth.cta.skip"), action: accountIsAvailable ? accountAction : skipAction)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.88))
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

private struct AuthOptionsPanel: View {
    let accountIsAvailable: Bool
    let legalConsentText: AttributedString
    let activeProvider: AuthProvider?
    let onAppleTap: () -> Void
    let onGoogleTap: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.white.opacity(0.18))
                .frame(width: 46, height: 4)
                .padding(.top, 10)

            Text(L10n.string("auth.options.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse)

            HStack(spacing: 18) {
                AuthIconButton(
                    title: "Apple",
                    isLoading: activeProvider == .apple,
                    action: onAppleTap
                ) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.black)
                }

                AuthIconButton(
                    title: "Google",
                    isLoading: activeProvider == .google,
                    action: onGoogleTap
                ) {
                    GoogleBadge()
                }
            }
            .disabled(!accountIsAvailable)

            if !accountIsAvailable {
                Text(L10n.string("auth.options.unavailable"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Text(legalConsentText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .tint(.white.opacity(0.82))
                .multilineTextAlignment(.center)

            Button(L10n.string("auth.options.skip"), action: onSkip)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(TuneAVTheme.darkSurfaceAlt.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        )
    }
}

private struct AuthIconButton<Content: View>: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)

                    if isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        content
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
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
        .frame(width: 64, height: 64)
    }
}

private struct OnboardingBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        TuneAVTheme.brandBlack,
                        TuneAVTheme.darkSurfaceAlt,
                        TuneAVTheme.brandBlack
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        TuneAVTheme.highlight.opacity(0.18),
                        .clear
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: proxy.size.width * 0.9
                )

                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(TuneAVTheme.brandBlack.opacity(0.18))
                    .frame(width: min(proxy.size.width - 76, 300), height: 360)
                    .blur(radius: 10)
                    .offset(y: 12)

                VStack(spacing: 32) {
                    Spacer()

                    SignalRings(size: min(proxy.size.width * 0.72, 280))
                        .offset(y: -118)

                    Spacer()
                }

                VStack {
                    Spacer()
                }

                EqualizerRails()
                    .opacity(0.18)

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

private struct SignalRings: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach([0.56, 0.82, 1.06], id: \.self) { scale in
                Circle()
                    .stroke(TuneAVTheme.highlight.opacity(scale == 0.82 ? 0.12 : 0.06), lineWidth: 1.5)
                    .frame(width: size * scale, height: size * scale)
            }

            ForEach([-1.0, 1.0], id: \.self) { direction in
                VStack(spacing: 10) {
                    ForEach([68.0, 96.0], id: \.self) { bar in
                        Capsule(style: .continuous)
                            .fill(TuneAVTheme.highlight.opacity(0.1))
                            .frame(width: 2, height: bar)
                    }
                }
                .offset(x: direction * size * 0.43)
            }

            VStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(TuneAVTheme.highlight)

                HStack(spacing: 12) {
                    ForEach(Array([0.18, 0.34, 0.22].enumerated()), id: \.offset) { index, height in
                        Capsule(style: .continuous)
                            .fill(index == 2 ? TuneAVTheme.highlight : Color.white.opacity(0.28))
                            .frame(width: 8, height: size * height)
                    }
                }
                .frame(height: size * 0.42)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(TuneAVTheme.brandBlack.opacity(0.56))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            )
        }
    }
}

private struct EqualizerRails: View {
    var body: some View {
        HStack {
            EqualizerColumn()
            Spacer()
            EqualizerColumn()
        }
        .padding(.horizontal, 112)
    }
}

private struct EqualizerColumn: View {
    private let heights: [CGFloat] = [54, 110, 72]

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule(style: .continuous)
                    .fill(index == 1 ? TuneAVTheme.highlight.opacity(0.08) : Color.white.opacity(0.04))
                    .frame(width: 2, height: height)
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
