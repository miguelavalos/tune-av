import SwiftUI

final class AppShellChromeActions: ObservableObject {
    var openSettings: () -> Void = {}
    var openAccount: () -> Void = {}
}

enum ShellBrandHeaderActiveItem {
    case settings
    case account
}

struct ShellBrandHeader: View {
    @EnvironmentObject private var chromeActions: AppShellChromeActions

    let statusTitle: String
    var activeItem: ShellBrandHeaderActiveItem?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                chromeActions.openSettings()
            } label: {
                headerIcon(
                    systemName: "gearshape.fill",
                    isSelected: activeItem == .settings,
                    fontSize: 15
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.header.settings"))
            .accessibilityValue(activeItem == .settings ? L10n.string("common.selected") : "")
            .accessibilityIdentifier("header.settings")

            Spacer(minLength: 8)

            Image("OnboardingWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 54)

            Spacer(minLength: 8)

            Button {
                chromeActions.openAccount()
            } label: {
                headerIcon(
                    systemName: "person.crop.circle.fill",
                    isSelected: activeItem == .account,
                    fontSize: 16
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.header.account"))
            .accessibilityValue(activeItem == .account ? L10n.string("common.selected") : "")
            .accessibilityIdentifier("header.account")
        }
    }

    private func headerIcon(systemName: String, isSelected: Bool, fontSize: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
            .frame(width: 36, height: 36)
            .background(isSelected ? TuneAVTheme.footerGlassSelected : TuneAVTheme.elevatedSurface, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        isSelected ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle.opacity(0.52),
                        lineWidth: 1
                    )
            }
            .shadow(color: TuneAVTheme.highlight.opacity(isSelected ? 0.12 : 0), radius: 8, y: 3)
    }
}

struct LiveNowPanel: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let currentStation: Station?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("shell.liveNow.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(TuneAVTheme.highlight)

                Spacer()

                ShellStatusPill(title: status)
            }

            HStack(spacing: 12) {
                Group {
                    if let currentStation {
                        StationThumbnailView(
                            station: currentStation,
                            size: 64,
                            surfaceStyle: .dark,
                            animationOverlay: .none,
                            isAnimationActive: false
                        )
                    } else {
                        EmptyLiveArtwork(size: 64)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(audioPlayer.currentTrackTitle ?? currentStation?.name ?? L10n.string("shell.liveNow.ready"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .lineLimit(2)

                    if let currentTrackArtist = audioPlayer.currentTrackArtist, !currentTrackArtist.isEmpty {
                        Text(currentTrackArtist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.highlight)
                    }

                    Text(audioPlayer.currentTrackAlbumTitle ?? currentStation?.shortMeta ?? L10n.string("shell.liveNow.subtitle.empty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.darkSurface)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight.opacity(0.18))
                        .padding(.top, 18)
                        .padding(.trailing, 16)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.48), lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.72), radius: 16, y: 8)
    }
}

struct EmptyLiveArtwork: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TuneAVTheme.darkSurface,
                        TuneAVTheme.highlight.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                ZStack {
                    Circle()
                        .fill(TuneAVTheme.highlight.opacity(0.08))
                        .frame(width: size * 0.62, height: size * 0.62)

                    HStack(alignment: .bottom, spacing: size * 0.05) {
                        ForEach(Array([0.28, 0.46, 0.74, 0.46, 0.28].enumerated()), id: \.offset) { _, scale in
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            TuneAVTheme.textInverse.opacity(0.45),
                                            TuneAVTheme.highlight.opacity(0.92)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: size * 0.07, height: size * CGFloat(scale))
                        }
                    }
                    .frame(height: size * 0.24)
                }
            }
            .shadow(color: TuneAVTheme.highlight.opacity(0.07), radius: 10, y: 5)
    }
}

struct StationThumbnailView: View {
    let station: Station
    let size: CGFloat
    var surfaceStyle: StationArtworkView.SurfaceStyle = .light
    var textMode: StationArtworkView.TextMode = .initials
    var animationOverlay: StationArtworkView.AnimationOverlay = .none
    var isAnimationActive: Bool = false

    private var cornerRadius: CGFloat {
        StationArtworkView.ArtworkStyle.cornerRadius(for: size)
    }

    var body: some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: surfaceStyle,
            textMode: textMode,
            animationOverlay: animationOverlay,
            isAnimationActive: isAnimationActive
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            thumbnailBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(thumbnailBorder, lineWidth: 1)
        }
        .shadow(color: thumbnailShadow, radius: size * 0.08, y: size * 0.03)
    }

    private var thumbnailBackground: Color {
        switch surfaceStyle {
        case .light:
            return Color.white
        case .dark:
            return TuneAVTheme.darkSurface
        }
    }

    private var thumbnailBorder: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.borderSubtle
        case .dark:
            return Color.white.opacity(0.08)
        }
    }

    private var thumbnailShadow: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.softShadow.opacity(0.08)
        case .dark:
            return TuneAVTheme.softShadow.opacity(0.18)
        }
    }
}
