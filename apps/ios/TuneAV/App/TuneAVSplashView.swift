import SwiftUI

struct TuneAVSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var signalExpanded = false
    @State private var contentVisible = false
    @State private var statusVisible = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.86),
                    Color(red: 0.99, green: 0.97, blue: 0.91),
                    TuneAVTheme.neutral50
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            PaperSignalBackdrop(expanded: signalExpanded)

            VStack(spacing: 34) {
                Image("OnboardingWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 174, height: 98)
                    .opacity(contentVisible ? 1 : 0)

                SplashTuningScene()
                    .scaleEffect(contentVisible ? 1 : 0.94)
                    .opacity(contentVisible ? 1 : 0.68)

                VStack(spacing: 10) {
                    Text(L10n.string("splash.tagline"))
                        .font(.system(size: 28, weight: .black, design: .serif))
                        .foregroundStyle(TuneAVTheme.brandGraphite)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(TuneAVTheme.highlight)
                            .frame(width: 7, height: 7)

                        Text(L10n.string("splash.status"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.72))
                    }
                    .opacity(statusVisible ? 1 : 0)
                    .offset(y: statusVisible ? 0 : 8)
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 10)
            }
            .padding(.horizontal, 24)
        }
        .onAppear(perform: startAnimations)
        .accessibilityHidden(true)
    }

    private func startAnimations() {
        guard !reduceMotion else {
            signalExpanded = true
            contentVisible = true
            statusVisible = true
            return
        }

        withAnimation(.easeOut(duration: 0.7)) {
            signalExpanded = true
        }

        withAnimation(.spring(response: 0.76, dampingFraction: 0.82).delay(0.1)) {
            contentVisible = true
        }

        withAnimation(.easeOut(duration: 0.45).delay(0.28)) {
            statusVisible = true
        }
    }
}

private struct SplashTuningScene: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .frame(width: 286, height: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.08), radius: 24, y: 14)

            ForEach(Array([82.0, 124.0, 166.0].enumerated()), id: \.offset) { index, size in
                Circle()
                    .trim(from: 0.02, to: 0.18)
                    .stroke(TuneAVTheme.highlight.opacity(0.2 - Double(index) * 0.04), lineWidth: 1.6)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-22))
                    .offset(x: -12, y: -42)
            }

            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .offset(x: -70, y: -34)
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.16), radius: 12, y: 7)

            Image("AviV2TuneListening")
                .resizable()
                .scaledToFit()
                .frame(width: 166, height: 166)
                .offset(x: 58, y: -6)
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.14), radius: 14, y: 8)

            HStack(spacing: 5) {
                ForEach(Array([14.0, 24.0, 18.0, 32.0, 16.0].enumerated()), id: \.offset) { index, height in
                    Capsule(style: .continuous)
                        .fill(index == 3 ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.18))
                        .frame(width: 5, height: height)
                }
            }
            .offset(x: -71, y: -8)
        }
        .frame(width: 316, height: 238)
    }
}

private struct PaperSignalBackdrop: View {
    let expanded: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    TuneAVTheme.highlight.opacity(0.18),
                    TuneAVTheme.highlight.opacity(0.06),
                    .clear
                ],
                center: .center,
                startRadius: 12,
                endRadius: 260
            )
            .frame(width: 420, height: 420)
            .blur(radius: 10)
            .scaleEffect(expanded ? 1 : 0.82)

            ForEach(Array([110.0, 166.0, 224.0].enumerated()), id: \.offset) { index, size in
                Circle()
                    .trim(from: 0.05, to: 0.35)
                    .stroke(TuneAVTheme.highlight.opacity(0.13 - Double(index) * 0.025), lineWidth: 1.4)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-32))
                    .offset(x: 92, y: -18)
                    .scaleEffect(expanded ? 1 : 0.76)
            }

            ForEach(Array([0.0, 1.0, 2.0, 3.0].enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(index == 1 ? TuneAVTheme.highlight.opacity(0.24) : TuneAVTheme.brandGraphite.opacity(0.08))
                    .frame(width: index == 1 ? 7 : 4, height: index == 1 ? 7 : 4)
                    .offset(x: CGFloat(index * 52 - 92), y: CGFloat(index % 2 == 0 ? 132 : -138))
                    .opacity(expanded ? 1 : 0.2)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    TuneAVSplashView()
}
