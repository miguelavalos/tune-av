import AVLaunchFoundation
import SwiftUI

struct TuneAVSplashView: View {
    var body: some View {
        AVSplashScreen(
            tagline: L10n.string("splash.tagline"),
            status: L10n.string("splash.status"),
            logo: {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
            },
            hero: {
                SplashTuningScene()
            }
        )
    }
}

private struct SplashTuningScene: View {
    var body: some View {
        ZStack {
            Image("AviSplashListeningBackground")
                .resizable()
                .scaledToFill()
                .frame(width: 330, height: 386)
                .clipped()
                .opacity(0.96)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .shadow(color: TuneAVTheme.brandGraphite.opacity(0.08), radius: 16, y: 8)

            ForEach(Array([136.0, 184.0, 232.0].enumerated()), id: \.offset) { index, size in
                Circle()
                    .trim(from: 0.04, to: 0.24)
                    .stroke(TuneAVTheme.highlight.opacity(0.16 - Double(index) * 0.032), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-22))
                    .offset(x: 94, y: 28)
            }

            HStack(spacing: 5) {
                ForEach(Array([12.0, 22.0, 16.0, 30.0, 14.0].enumerated()), id: \.offset) { index, height in
                    Capsule(style: .continuous)
                        .fill(index == 3 ? TuneAVTheme.highlight.opacity(0.86) : TuneAVTheme.brandGraphite.opacity(0.16))
                        .frame(width: 4, height: height)
                }
            }
            .offset(x: -86, y: 128)
        }
        .frame(width: 330, height: 386)
    }
}

#Preview {
    TuneAVSplashView()
}
