import SwiftUI

struct TuneNowPlayingCard<Artwork: View, Backdrop: View, Controls: View>: View {
    static var height: CGFloat { 440 }

    let stationName: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let artworkAccessibilityLabel: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let primaryAction: () -> Void
    let artworkAction: () -> Void
    let metadataAction: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let backdrop: () -> Backdrop
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 0) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    TuneAVLiveSignal(isActive: isLive)
                        .frame(width: 30, height: 11)

                    Text(stationName.uppercased())
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stationName)
            .accessibilityIdentifier("avi.footerPlayer.primaryTitle")
            .frame(height: 22)

            Spacer()
                .frame(height: 12)

            Button(action: artworkAction) {
                artwork()
                    .shadow(color: Color.black.opacity(0.45), radius: 18, y: 10)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(artworkAccessibilityLabel)
            .accessibilityIdentifier("avi.footerPlayer.artworkZoom")
            .frame(height: 200)

            Spacer()
                .frame(height: 16)

            Button(action: metadataAction) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(artworkAccessibilityLabel)
            .accessibilityIdentifier("avi.footerPlayer.textZoom")
            .frame(height: 70)

            Spacer(minLength: 0)

            controls()
                .frame(height: 72)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(height: Self.height)
        .background {
            ZStack {
                Color.black
                GeometryReader { proxy in
                    backdrop()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.25)
                        .blur(radius: 34)
                        .saturation(1.25)
                }
                .clipped()
                LinearGradient(
                    colors: [Color.black.opacity(0.18), Color.black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("avi.footerPlayer.container")
    }
}

struct TuneAVLiveSignal: View {
    let isActive: Bool
    var color: Color = TuneAVTheme.highlight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    private static let cycle: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            TuneAVSignalWave(phase: phase(at: context.date))
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        .clipped()
        .opacity(isActive ? 1 : 0.45)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var isAnimating: Bool {
        isActive && !reduceMotion && scenePhase == .active && !isLowPowerModeEnabled
    }

    private func phase(at date: Date) -> Double {
        guard isAnimating else { return 0 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
    }
}

struct TuneAVSignalWave: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: 0, dy: 1.2)
        guard frame.height > 0 else { return Path() }
        let period = frame.height * (104.0 / 88.0)
        var path = Path()
        var x = frame.minX - period - phase * period
        path.move(to: CGPoint(x: x, y: frame.maxY))
        while x < frame.maxX + period {
            path.addLine(to: CGPoint(x: x + period / 2, y: frame.minY))
            path.addLine(to: CGPoint(x: x + period, y: frame.maxY))
            x += period
        }
        return path
    }
}
