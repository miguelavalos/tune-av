import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    func focusedSignalInfo(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("shell.stationInfo.title"))
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer()

                Text(stationInfoBadgeTitle(for: station))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule(style: .continuous))
            }

            stationInfoContent(for: station)
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    func stationInfoContent(for station: Station) -> some View {
        if let editorial = station.editorial, let summary = stationInfoSummary(for: editorial) {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                let badges = stationInfoBadges(for: editorial)
                if !badges.isEmpty {
                    WrapTagsRow(tags: badges, highlighted: true)
                }

                if let profile = editorial.discoveryProfile {
                    StationInfoDiscoverySnapshot(profile: profile)
                }

                let contextTags = stationInfoContextTags(for: editorial)
                if !contextTags.isEmpty {
                    WrapTagsRow(tags: contextTags)
                }
            }
        } else {
            Text(L10n.string("shell.stationInfo.notProcessed"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func focusedRadioQuickActions(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AVAviPrimaryActionButton(
                    title: isFocusedStationActive ? L10n.string("player.header.nowPlaying") : L10n.string("shell.avi.actions.playRadio"),
                    systemImage: isFocusedStationActive ? "waveform" : "play.fill",
                    accessibilityIdentifier: "avi.detail.radio.play",
                    action: openPlayer
                )

                AVAviIconActionButton(
                    systemImage: stationSaveActionSystemImage(for: station),
                    isSelected: libraryStore.isFavorite(station),
                    accessibilityLabel: stationSaveActionTitle(for: station),
                    accessibilityIdentifier: "avi.detail.radio.save"
                ) {
                    toggleFavorite(station)
                }
            }

            StationFeedbackControl(
                feedbackIdentity: "station:\(station.id)",
                selectedFeedback: stationFeedback[station.id],
                selectFeedback: { feedback in
                    let nextFeedback = stationFeedback[station.id] == feedback ? nil : feedback
                    setStationFeedback(station, nextFeedback)
                },
                clearFeedback: {
                    setStationFeedback(station, nil)
                }
            )
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }

    func fullPlayerRadioDetailLink(for station: Station) -> some View {
        Button {
            showStationDetails(station, [station], .about)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 38, height: 38)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("shell.avi.recommendation.details"))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(station.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.75))
            }
            .padding(14)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.fullPlayer.radioDetail")
    }

    var aviStatusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            aviHeroImage(width: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text(aviEmotionLabel)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviMoodLine)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Text(aviDetailLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(TuneAVTheme.elevatedSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.38), radius: 18, y: 10)
    }

    func aviHeroImage(width: CGFloat) -> some View {
        AviStableEmotionImage(emotion: aviEmotion, assetVariant: .head, width: width)
            .accessibilityLabel(L10n.string("shell.avi.title"))
    }

    @ViewBuilder
    var focusedSignalPanel: some View {
        if let focusedStation {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(signalEyebrow)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(isFocusedStationActive ? (currentTrackTitle ?? focusedStation.name) : focusedStation.name)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)

                    Text(focusedSignalDetail(for: focusedStation))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    listeningControlButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)

                    Button(action: openPlayer) {
                        Label(primaryFocusedActionTitle, systemImage: primaryFocusedActionIcon)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(TuneAVTheme.brandBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    listeningControlButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)
                }

                StationFeedbackControl(
                    feedbackIdentity: "station:\(focusedStation.id)",
                    selectedFeedback: stationFeedback[focusedStation.id],
                    selectFeedback: { feedback in
                        let nextFeedback = stationFeedback[focusedStation.id] == feedback ? nil : feedback
                        setStationFeedback(focusedStation, nextFeedback)
                    },
                    clearFeedback: {
                        setStationFeedback(focusedStation, nil)
                    }
                )

                focusedSignalActions(for: focusedStation)
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
        }
    }

    func focusedSignalDetail(for station: Station) -> String {
        if isFocusedStationActive, let currentTrackArtist {
            return "\(currentTrackArtist) · \(station.name)"
        }
        return station.primaryDetailLine.isEmpty ? L10n.string("shell.avi.radioPublicFallback") : station.primaryDetailLine
    }

    func signalInfoTitle(for station: Station) -> String {
        let tags = stationTagList(for: station)
        if tags.isEmpty {
            return L10n.string("shell.stationInfo.publicSignal")
        }
        return tags.prefix(2).map { L10n.genreLabel(for: $0) }.joined(separator: " · ")
    }

    func defaultPublicSignalInfo(for station: Station) -> String {
        var details: [String] = []
        if let countryCode = station.countryCode {
            details.append(L10n.countryName(for: countryCode))
        }
        if !station.language.isEmpty {
            details.append(station.language)
        }
        let tags = stationTagList(for: station)
        if !tags.isEmpty {
            details.append(tags.prefix(4).map { L10n.genreLabel(for: $0) }.joined(separator: ", "))
        }
        return details.isEmpty
            ? L10n.string("shell.stationInfo.publicFallback")
            : details.joined(separator: " · ")
    }

    func stationInfoBadgeTitle(for station: Station) -> String {
        station.editorial.flatMap(stationInfoSummary(for:)) != nil
            ? L10n.string("shell.stationInfo.summary")
            : L10n.string("shell.stationInfo.pending")
    }

    func stationInfoSummary(for editorial: StationEditorial) -> String? {
        let summary = editorial.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    func stationInfoBadges(for editorial: StationEditorial) -> [String] {
        var badges = [
            stationInfoLocalizedPrimaryFormat(editorial.primaryFormat),
            stationInfoLocalizedIntensity("music", value: editorial.musicIntensity),
            stationInfoLocalizedIntensity("speech", value: editorial.speechIntensity)
        ].compactMap { $0 }

        for format in editorial.secondaryFormats.prefix(2) {
            let label = L10n.genreLabel(for: format)
            guard !label.isEmpty, !badges.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) else {
                continue
            }
            badges.append(label)
        }

        return badges
    }

    func stationInfoContextTags(for editorial: StationEditorial) -> [String] {
        let profileTags = editorial.discoveryProfile.map { $0.genres + $0.moods } ?? []
        return (profileTags + editorial.programming + editorial.languages)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, tag in
                guard result.count < 6 else { return }
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else { return }
                result.append(L10n.genreLabel(for: tag))
            }
    }

    func stationInfoLocalizedPrimaryFormat(_ format: String) -> String? {
        switch format {
        case "music": return L10n.string("shell.stationDetail.editorial.format.music")
        case "newsTalk": return L10n.string("shell.stationDetail.editorial.format.newsTalk")
        case "sports": return L10n.string("shell.stationDetail.editorial.format.sports")
        case "mixed": return L10n.string("shell.stationDetail.editorial.format.mixed")
        case "community": return L10n.string("shell.stationDetail.editorial.format.community")
        case "religious": return L10n.string("shell.stationDetail.editorial.format.religious")
        default: return nil
        }
    }

    func stationInfoLocalizedIntensity(_ kind: String, value: String) -> String? {
        switch (kind, value) {
        case ("music", "low"): return L10n.string("shell.stationDetail.editorial.music.low")
        case ("music", "medium"): return L10n.string("shell.stationDetail.editorial.music.medium")
        case ("music", "high"): return L10n.string("shell.stationDetail.editorial.music.high")
        case ("speech", "low"): return L10n.string("shell.stationDetail.editorial.speech.low")
        case ("speech", "medium"): return L10n.string("shell.stationDetail.editorial.speech.medium")
        case ("speech", "high"): return L10n.string("shell.stationDetail.editorial.speech.high")
        default: return nil
        }
    }

    func stationTagList(for station: Station) -> [String] {
        station.tags
            .split(separator: ",")
            .compactMap { TuneAVMusicGenreCatalog.canonicalTag(for: String($0)) }
            .reduce(into: [String]()) { result, tag in
                guard !result.contains(tag) else { return }
                result.append(tag)
            }
    }

    var signalEyebrow: String {
        isFocusedStationActive ? L10n.string("shell.stationDetail.signal.liveFound") : L10n.string("shell.stationInfo.title")
    }
}
