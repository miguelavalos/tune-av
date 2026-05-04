import SwiftUI

struct TuneAVSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowExpanded = false
    @State private var contentVisible = false
    @State private var statusVisible = false

    var body: some View {
        ZStack {
            TuneAVTheme.onboardingBackground
                .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [TuneAVTheme.highlight.opacity(0.24), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 12)
                .scaleEffect(glowExpanded ? 1.18 : 0.76)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 16)
                .offset(x: 28, y: 42)
                .scaleEffect(glowExpanded ? 1.12 : 0.84)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 168, height: 168)
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.highlight.opacity(0.16), lineWidth: 1)
                        }

                    Image("OnboardingWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 246)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.9))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                }
                        }
                        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                        .scaleEffect(contentVisible ? 1 : 0.88)
                }
                .scaleEffect(contentVisible ? 1 : 0.92)
                .opacity(contentVisible ? 1 : 0.72)

                VStack(spacing: 10) {

                    Text(L10n.string("splash.tagline"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.74))
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)

                HStack(spacing: 8) {
                    Circle()
                        .fill(TuneAVTheme.highlight)
                        .frame(width: 8, height: 8)

                    Text(L10n.string("splash.status"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.66))
                }
                .opacity(statusVisible ? 1 : 0)
                .offset(y: statusVisible ? 0 : 10)
            }
            .padding(.horizontal, 28)
        }
        .onAppear(perform: startAnimations)
        .accessibilityHidden(true)
    }

    private func startAnimations() {
        guard !reduceMotion else {
            glowExpanded = true
            contentVisible = true
            statusVisible = true
            return
        }

        withAnimation(.easeOut(duration: 0.7)) {
            glowExpanded = true
        }

        withAnimation(.spring(response: 0.76, dampingFraction: 0.82).delay(0.1)) {
            contentVisible = true
        }

        withAnimation(.easeOut(duration: 0.45).delay(0.28)) {
            statusVisible = true
        }
    }
}

#Preview {
    TuneAVSplashView()
}
