import AVAviFoundation
import AVHaptics
import SwiftUI

// "What's playing?": Avi recognises the song from the station's stream audio when the station
// sends no title, or confirms the exact catalog match when it does. The capture never uses the
// microphone and never touches the player; see `TuneAVStreamSongIdentifier`.
extension AviScreen {
    var isAviListeningForSong: Bool {
        songIdentification.isListening(stationID: (focusedStation ?? currentStation)?.id)
    }

    /// The station is the one in the player and its stream is `https`, which the identifier can
    /// read. Paused still counts: the station keeps broadcasting and the question stays valid.
    func canIdentifyCurrentSong(for station: Station) -> Bool {
        isFocusedStationActive
            && TuneAVStreamSongIdentificationPolicy.supports(streamURLString: station.streamURL)
    }

    func identifyCurrentSong(for station: Station) {
        guard canIdentifyCurrentSong(for: station) else { return }

        // One identification is one Avi lookup against the daily budget (Guest 5, Free 15, Pro
        // unlimited). A retry on the same station within the window is free, and only a catalog
        // answer (match or no match) is counted: stream and service failures cost nothing.
        let usageKey = ShellSongIdentificationMetering.usageKey(stationID: station.id)
        guard accessController.canUseDailyFeature(.aviAction, usageKey: usageKey) else {
            accessController.presentUpgradePrompt(for: .aviAction)
            return
        }

        AVHaptics.perform(.selection)
        songIdentification.identify(station: station) { result in
            switch result.outcome {
            case .matched(let track):
                accessController.recordDailyFeatureUse(.aviAction, usageKey: usageKey)
                applyIdentifiedTrack(station, track)
            case .noMatch:
                accessController.recordDailyFeatureUse(.aviAction, usageKey: usageKey)
            case .unsupportedStream, .unavailable, .networkFailure, .cancelled:
                break
            }
        }
    }

    @ViewBuilder
    func fullPlayerSongIdentificationRow(for station: Station) -> some View {
        switch songIdentification.phase(for: station.id) {
        case .idle:
            if canIdentifyCurrentSong(for: station), !hasCurrentSongContext {
                songIdentificationActionButton(for: station)
            }
        case .listening(_, let streamTitle):
            songIdentificationStatusRow(
                message: L10n.string("player.identify.listening.title"),
                detail: streamTitle.flatMap(songIdentificationStreamTitleDetail),
                isListening: true,
                accessibilityIdentifier: "avi.fullPlayer.identifyListening"
            )
        case .matched:
            songIdentificationStatusRow(
                message: L10n.string("player.identify.identifiedBadge"),
                detail: nil,
                isListening: false,
                systemImage: "shazam.logo",
                accessibilityIdentifier: "avi.fullPlayer.identifyMatched"
            )
        case .noMatch:
            songIdentificationStatusRow(
                message: L10n.string("player.identify.noMatch"),
                detail: nil,
                isListening: false,
                accessibilityIdentifier: "avi.fullPlayer.identifyResult"
            )
            if canIdentifyCurrentSong(for: station) {
                songIdentificationActionButton(for: station)
            }
        case .unsupported:
            songIdentificationStatusRow(
                message: L10n.string("player.identify.unsupported"),
                detail: nil,
                isListening: false,
                accessibilityIdentifier: "avi.fullPlayer.identifyResult"
            )
        case .unavailable:
            songIdentificationStatusRow(
                message: L10n.string("player.identify.unavailable"),
                detail: nil,
                isListening: false,
                accessibilityIdentifier: "avi.fullPlayer.identifyResult"
            )
            if canIdentifyCurrentSong(for: station) {
                songIdentificationActionButton(for: station)
            }
        case .networkFailure:
            songIdentificationStatusRow(
                message: L10n.string("player.identify.network"),
                detail: nil,
                isListening: false,
                accessibilityIdentifier: "avi.fullPlayer.identifyResult"
            )
            if canIdentifyCurrentSong(for: station) {
                songIdentificationActionButton(for: station)
            }
        }
    }

    private func songIdentificationStreamTitleDetail(_ streamTitle: TuneAVTrackMetadata) -> String? {
        let parts = [streamTitle.artist, streamTitle.title].compactMap { TuneAVText.normalizedValue($0) }
        guard !parts.isEmpty else { return nil }
        return L10n.string("player.identify.stationSays", parts.joined(separator: " · "))
    }

    func songIdentificationActionButton(for station: Station) -> some View {
        Button {
            identifyCurrentSong(for: station)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "shazam.logo")
                    .tuneScaledFont(size: 20, weight: .black)
                    .foregroundStyle(TuneAVTheme.highlight)
                    .accessibilityHidden(true)

                Text(L10n.string("player.identify.action"))
                    .tuneScaledFont(size: 16, weight: .black, design: .rounded)
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .tuneScaledFont(size: 11, weight: .black)
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: fullPlayerHeartButtonHeight)
            .background(TuneAVTheme.highlight.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.28), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("player.identify.action"))
        .accessibilityIdentifier("avi.fullPlayer.identifySong")
    }

    func songIdentificationStatusRow(
        message: String,
        detail: String?,
        isListening: Bool,
        systemImage: String = "waveform",
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                if isListening {
                    ProgressView()
                        .tint(TuneAVTheme.highlight)
                } else {
                    Image(systemName: systemImage)
                        .tuneScaledFont(size: 13, weight: .black)
                        .foregroundStyle(TuneAVTheme.highlight)
                }
            }
            .frame(width: 28, height: 28)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .tuneScaledFont(size: 13, weight: .bold)
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .tuneScaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([message, detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// How "What's playing?" counts against the daily Avi budget: one key per station and two-minute
/// window, so a retry right after a no match at a song boundary is free.
enum ShellSongIdentificationMetering {
    static let retryWindow: TimeInterval = 120

    static func usageKey(stationID: String, now: Date = Date()) -> String {
        let bucket = Int(now.timeIntervalSince1970 / retryWindow)
        return "identify:\(stationID):\(bucket)"
    }
}
