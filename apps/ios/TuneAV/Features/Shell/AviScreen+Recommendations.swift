import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var quickActions: some View {
        VStack(spacing: 12) {
            if focusedStation == nil {
                Button(action: openSearch) {
                    Label(L10n.string("shell.avi.action.findStation"), systemImage: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.primaryAction")
            }

            HStack(spacing: 12) {
                AVAviActionButton(title: L10n.string("tab.explore"), systemImage: "safari", action: openSearch)
                AVAviActionButton(title: L10n.string("shell.avi.action.saved"), systemImage: "bookmark.fill", action: openLibrary)
            }
        }
    }

    var localSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.avi.signals.title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.recent.title"),
                detail: recentStations.isEmpty ? L10n.string("shell.avi.signals.recent.empty") : L10n.plural(singular: "shell.avi.signals.recent.count.one", plural: "shell.avi.signals.recent.count.other", count: recentStations.count, recentStations.count),
                systemImage: "clock.arrow.circlepath",
                accessibilityIdentifier: "avi.signals.recent"
            )

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.saved.title"),
                detail: favoriteStations.isEmpty ? L10n.string("shell.avi.signals.saved.empty") : L10n.plural(singular: "shell.avi.signals.saved.count.one", plural: "shell.avi.signals.saved.count.other", count: favoriteStations.count, favoriteStations.count),
                systemImage: "dot.radiowaves.left.and.right",
                accessibilityIdentifier: "avi.signals.saved"
            )

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.discoveries.title"),
                detail: recentDiscoveryCount == 0 ? L10n.string("shell.avi.signals.discoveries.empty") : L10n.plural(singular: "shell.avi.signals.discoveries.count.one", plural: "shell.avi.signals.discoveries.count.other", count: recentDiscoveryCount, recentDiscoveryCount),
                systemImage: "sparkles",
                accessibilityIdentifier: "avi.signals.discoveries"
            )

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.feedback.title"),
                detail: feedbackSignalCount == 0 ? L10n.string("shell.avi.signals.feedback.empty") : L10n.plural(singular: "shell.avi.signals.feedback.count.one", plural: "shell.avi.signals.feedback.count.other", count: feedbackSignalCount, feedbackSignalCount),
                systemImage: "hand.thumbsup",
                accessibilityIdentifier: "avi.signals.feedback"
            )
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    var aviStateTitle: String {
        focusedStation == nil ? L10n.string("shell.avi.state.curious") : L10n.string("shell.avi.state.listening")
    }

    var aviSubtitle: String {
        L10n.string("shell.avi.subtitle")
    }

    var aviEmotion: TuneAVAviEmotion {
        if isAviListeningForSong {
            return .thinking
        }
        return TuneAVAviEmotionResolver.focusedSignalEmotion(
            focusedStation: focusedStation,
            isFocusedStationActive: isFocusedStationActive,
            isPlaying: isPlaying,
            isLoading: isLoading,
            currentTrackTitle: currentTrackTitle,
            currentTrackArtist: currentTrackArtist,
            feedback: isNowPlayingFullPlayer && hasCurrentSongContext
                ? currentTrackFeedback
                : focusedStation.flatMap { stationFeedback[$0.id] }
        )
    }

    var aviMoodLine: String {
        if focusedStation != nil {
            return isFocusedStationActive ? L10n.string("shell.avi.mood.vibing") : L10n.string("shell.avi.mood.curiousRadio")
        }
        return recentStations.isEmpty ? L10n.string("shell.avi.mood.ready") : L10n.string("shell.avi.mood.thinking")
    }

    var aviDetailLine: String {
        if focusedStation != nil {
            return isFocusedStationActive
                ? L10n.string("shell.avi.detail.detecting")
                : L10n.string("shell.avi.detail.scanning")
        }
        return L10n.string("shell.avi.detail.ready")
    }

    var aviEmotionLabel: String {
        if focusedStation == nil { return L10n.string("shell.avi.state.thinking") }
        return isFocusedStationActive ? L10n.string("shell.avi.state.attentive") : L10n.string("shell.avi.state.exploring")
    }

    var recommendationScorer: TuneAVLocalRecommendationScorer {
        TuneAVLocalRecommendationScorer(
            currentStation: currentStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            currentCountryCode: preferredCountryCode
        )
    }

    func showRelatedStations(for station: Station) {
        relatedStationContext = RelatedStationContext(baseStation: station)
        let localResults = relatedStationResults(for: station, candidates: relatedCandidateStations)
        relatedStationResults = localResults
        isLoadingRelatedStations = true

        Task {
            let remoteStations = await remoteRelatedStations(for: station)
            let merged = relatedStationResults(
                for: station,
                candidates: relatedCandidateStations + remoteStations
            )
            await MainActor.run {
                guard relatedStationContext?.baseStation.id == station.id else { return }
                relatedStationResults = merged
                isLoadingRelatedStations = false
            }
        }
    }

    var relatedCandidateStations: [Station] {
        AviRelatedStationsCoordinator.candidateStations(
            stations: stations,
            playbackQueueStations: playbackQueueStations,
            recentStations: recentStations,
            favoriteStations: favoriteStations
        )
    }

    func relatedStationResults(
        for station: Station,
        candidates: [Station]
    ) -> [(station: Station, reason: String)] {
        AviRelatedStationsCoordinator.results(
            for: station,
            candidates: candidates,
            scorer: recommendationScorer
        )
    }

    func remoteRelatedStations(for station: Station) async -> [Station] {
        guard let filters = AviRelatedStationsCoordinator.remoteFilters(for: station) else { return [] }
        do {
            return try await TuneAVStationService().searchStations(filters: filters)
        } catch {
            return []
        }
    }

    var rankedRecommendationCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)] {
        AviRecommendationsCoordinator.rankedCandidates(
            stations: stations,
            currentStation: currentStation,
            scorer: recommendationScorer
        )
    }

    var topRecommendation: (station: Station, reason: String)? {
        AviRecommendationsCoordinator.topRecommendation(from: rankedRecommendationCandidates)
    }

    var secondaryRecommendations: [(station: Station, reason: String)] {
        AviRecommendationsCoordinator.secondaryRecommendations(from: rankedRecommendationCandidates)
    }

    var recommendationQueue: [Station] {
        AviRecommendationsCoordinator.queue(from: rankedRecommendationCandidates)
    }

    var feedbackSignalCount: Int {
        stationFeedback.values.filter { feedback in
            switch feedback {
            case .liked, .disliked, .notForMe:
                return true
            }
        }.count
    }

    var recentDiscoveryCount: Int {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        return discoveries.filter { discovery in
            !discovery.isHidden && discovery.playedAt >= cutoff
        }.count
    }
}
