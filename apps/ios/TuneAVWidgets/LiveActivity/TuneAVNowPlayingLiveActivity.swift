import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct TuneAVNowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TuneAVNowPlayingAttributes.self) { context in
            TuneAVNowPlayingLockScreenView(state: context.state)
                .activityBackgroundTint(TuneAVWidgetBrand.ink)
                .activitySystemActionForegroundColor(TuneAVWidgetBrand.paper)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TuneAVActivityArtwork(fileName: state.artworkFileName, size: 58, cornerRadius: 14)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TuneAVMark()
                        .frame(height: 12)
                        .padding(.trailing, 6)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    TuneAVActivityTitleBlock(state: state, titleSize: 16, showsStation: false)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        TuneAVActivityStationLabel(state: state)
                        Spacer(minLength: 8)
                        TuneAVActivityControls(state: state, size: 40)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
            } compactLeading: {
                TuneAVActivityArtwork(fileName: state.artworkFileName, size: 24, cornerRadius: 6)
            } compactTrailing: {
                TuneAVLiveBars(isLive: state.isLive)
                    .frame(width: 13, height: 13)
            } minimal: {
                TuneAVMark()
                    .frame(width: 18)
            }
            .keylineTint(TuneAVWidgetBrand.green)
        }
    }
}

struct TuneAVNowPlayingLockScreenView: View {
    let state: TuneAVNowPlayingContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TuneAVLiveBars(isLive: state.isLive)
                    .frame(width: 13, height: 12)
                Text(state.statusText.uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(state.isLive ? TuneAVWidgetBrand.green : TuneAVWidgetBrand.paper.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 8)
                TuneAVMark()
                    .frame(height: 11)
            }

            HStack(alignment: .center, spacing: 14) {
                TuneAVActivityArtwork(fileName: state.artworkFileName, size: 66, cornerRadius: 16)

                TuneAVActivityTitleBlock(state: state, titleSize: 17, showsStation: true)

                Spacer(minLength: 0)

                TuneAVActivityControls(state: state, size: 44)
            }
        }
        .padding(16)
    }
}

struct TuneAVActivityTitleBlock: View {
    let state: TuneAVNowPlayingContentState
    let titleSize: CGFloat
    let showsStation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.primaryText)
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVWidgetBrand.paper)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            if state.hasSong {
                if let artist = state.songArtist {
                    Text(artist)
                        .font(.system(size: titleSize - 3, weight: .semibold))
                        .foregroundStyle(TuneAVWidgetBrand.paper.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if showsStation || state.songArtist == nil {
                    Text(state.stationName)
                        .font(.system(size: titleSize - 5, weight: .bold, design: .rounded))
                        .foregroundStyle(TuneAVWidgetBrand.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else if !showsStation {
                Text(state.statusText)
                    .font(.system(size: titleSize - 3, weight: .semibold))
                    .foregroundStyle(TuneAVWidgetBrand.paper.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TuneAVActivityStationLabel: View {
    let state: TuneAVNowPlayingContentState

    var body: some View {
        HStack(spacing: 6) {
            TuneAVLiveBars(isLive: state.isLive)
                .frame(width: 12, height: 11)
            Text(state.hasSong ? state.stationName : state.statusText)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVWidgetBrand.paper.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TuneAVActivityControls: View {
    let state: TuneAVNowPlayingContentState
    let size: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: TuneAVToggleHeartIntent()) {
                Image(systemName: state.isSaved ? "heart.fill" : "heart")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(state.isSaved ? TuneAVWidgetBrand.green : TuneAVWidgetBrand.paper)
                    .frame(width: size, height: size)
                    .background(Circle().fill(TuneAVWidgetBrand.paper.opacity(state.isSaved ? 0.16 : 0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.heartActionLabel)

            Button(intent: TuneAVTogglePlaybackIntent()) {
                Image(systemName: state.playback == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundStyle(TuneAVWidgetBrand.ink)
                    .frame(width: size, height: size)
                    .background(Circle().fill(TuneAVWidgetBrand.paper))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.playbackActionLabel)
        }
    }
}

struct TuneAVActivityArtwork: View {
    let fileName: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                TuneAVWidgetBrand.inkRaised
                TuneAVMark()
                    .frame(width: size * 0.56)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(TuneAVWidgetBrand.paper.opacity(0.14), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        guard let fileName,
              let url = TuneAVSharedContainer.liveActivityArtworkURL(fileName: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
