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
                    .padding(.top, proxy.safeAreaInsets.top - 30)
                    .frame(maxHeight: .infinity, alignment: .top)
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
        let termsURL = AppConfig.termsURL?.absoluteString ?? "https://www.avalsys.com/account-av/tune-av/terms"
        let privacyURL = AppConfig.privacyURL?.absoluteString ?? "https://www.avalsys.com/account-av/tune-av/privacy"
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

private struct OnboardingPaperScene: View {
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            Color(red: 0.96, green: 0.91, blue: 0.78).opacity(0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: compact ? 8 : 10) {
                Image("AviV2TuneHeadphones")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 132 : 156, height: compact ? 132 : 156)
                    .shadow(color: TuneAVTheme.brandGraphite.opacity(0.12), radius: 14, y: 8)

                HStack(spacing: 7) {
                    ForEach(Array([18.0, 30.0, 24.0, 38.0, 20.0].enumerated()), id: \.offset) { index, height in
                        Capsule(style: .continuous)
                            .fill(index == 3 ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.2))
                            .frame(width: 7, height: compact ? height * 0.76 : height)
                    }
                }
                .padding(.bottom, compact ? 12 : 16)
            }
            .padding(.top, compact ? 14 : 20)

            Image("OnboardingWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 76 : 88, height: compact ? 43 : 50)
                .opacity(0.9)
                .padding(.top, 18)
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: compact ? 246 : 292)
        .frame(height: compact ? 214 : 252)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.38))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.brandGraphite.opacity(0.08), radius: 18, y: 10)
        .accessibilityLabel(L10n.string("auth.avi.accessibilityLabel"))
    }
}

private struct BrandHeaderBadge: View {
    var body: some View {
        HStack {
            Image("OnboardingWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 146, height: 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tune AV")
    }
}

private struct RadioNotebookGlyph: View {
    let compact: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.brandGraphite)
                .frame(width: compact ? 110 : 126, height: compact ? 92 : 106)
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.24), radius: 12, y: 8)

            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: compact ? 20 : 24, weight: .bold))
                        .foregroundStyle(TuneAVTheme.highlight)

                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white.opacity(0.75)).frame(width: 36, height: 4)
                        Capsule().fill(Color.white.opacity(0.36)).frame(width: 26, height: 4)
                    }
                }

                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(Array([18.0, 34.0, 24.0, 42.0].enumerated()), id: \.offset) { index, height in
                        Capsule(style: .continuous)
                            .fill(index == 3 ? TuneAVTheme.highlight : Color.white.opacity(0.32))
                            .frame(width: 7, height: compact ? height * 0.78 : height)
                    }
                }
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .padding(8)
        }
    }
}

private struct AviGuideBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 68, height: 68)

            Circle()
                .fill(Color(red: 0.97, green: 0.94, blue: 0.84))
                .frame(width: 52, height: 52)

            HStack(spacing: 8) {
                Circle().fill(TuneAVTheme.brandGraphite).frame(width: 6, height: 6)
                Circle().fill(TuneAVTheme.brandGraphite).frame(width: 6, height: 6)
            }
            .offset(y: -4)

            Capsule(style: .continuous)
                .fill(TuneAVTheme.brandGraphite.opacity(0.72))
                .frame(width: 22, height: 5)
                .offset(y: 10)
        }
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
                AuthIconButton(
                    title: L10n.string("auth.provider.apple"),
                    isLoading: activeProvider == .apple,
                    style: .dark,
                    action: onAppleTap
                ) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 17, weight: .bold))
                }

                AuthIconButton(
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

private struct AuthPanelArtwork: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    TuneAVTheme.highlight.opacity(0.24),
                    Color(red: 0.99, green: 0.97, blue: 0.91).opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("AviV2Thinking")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .padding(.trailing, 18)
                .padding(.bottom, 4)
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.12), radius: 10, y: 6)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color(red: 0.99, green: 0.97, blue: 0.91).opacity(0.44)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 144)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.brandGraphite.opacity(0.1), lineWidth: 1)
        }
        .accessibilityLabel(L10n.string("auth.avi.accessibilityLabel"))
    }
}

private struct CompactNotebookHeader: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(TuneAVTheme.brandGraphite)
                .frame(width: 62, height: 62)

            Image(systemName: "book.closed.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TuneAVTheme.highlight)

            AviGuideBadge()
                .scaleEffect(0.46)
                .offset(x: 30, y: -18)
        }
        .accessibilityHidden(true)
    }
}

private struct AuthIconButton<Content: View>: View {
    enum Style {
        case dark
        case light
    }

    let title: String
    let isLoading: Bool
    let style: Style
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .tint(progressTint)
                    } else {
                        content
                            .foregroundStyle(iconTint)
                    }
                }
                .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(titleTint)
            }
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderStyle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var backgroundStyle: Color {
        switch style {
        case .dark:
            TuneAVTheme.brandGraphite
        case .light:
            Color.white.opacity(0.72)
        }
    }

    private var borderStyle: Color {
        switch style {
        case .dark:
            TuneAVTheme.brandGraphite.opacity(0.2)
        case .light:
            TuneAVTheme.brandGraphite.opacity(0.18)
        }
    }

    private var titleTint: Color {
        switch style {
        case .dark:
            .white
        case .light:
            TuneAVTheme.brandGraphite
        }
    }

    private var iconTint: Color {
        switch style {
        case .dark:
            .white
        case .light:
            TuneAVTheme.brandGraphite
        }
    }

    private var progressTint: Color {
        switch style {
        case .dark:
            .white
        case .light:
            TuneAVTheme.brandGraphite
        }
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

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
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
