import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

struct AviHeaderCopy {
    let label: String
    let title: String
    let summary: String
}


enum ArtistDetailSection: Equatable {
    case info
    case songs

    var accessibilityID: String {
        switch self {
        case .info:
            return "info"
        case .songs:
            return "songs"
        }
    }
}

struct AviScreen: View {
    static let artistDetailPageSize = 12

    @Environment(\.displayScale) var displayScale
    @EnvironmentObject var accessController: AccessController
    @EnvironmentObject var libraryStore: LibraryStore
    @EnvironmentObject var songIdentification: ShellSongIdentificationController

    let currentStation: Station?
    let focusedStation: Station?
    let isFocusedStationActive: Bool
    let currentTrackTitle: String?
    let currentTrackArtist: String?
    let currentTrackArtworkURL: URL?
    let isPlaying: Bool
    let isLoading: Bool
    let activeSleepTimerMinutes: Int?
    let activeSleepTimerRemainingMinutes: Int?
    let canCyclePlaybackQueue: Bool
    let playbackQueueSource: AudioPlayerService.PlaybackQueue.Source
    let playbackQueueStations: [Station]
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let focusedMusicDetail: SelectedMusicAviDetail?
    let isNowPlayingFullPlayer: Bool
    let focusedStationDetailSection: StationDetailSection
    @Binding var isActionPanelOpen: Bool
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let preferredCountryCode: String
    let bottomContentPadding: CGFloat
    let openSearch: () -> Void
    let openLibrary: () -> Void
    let openPlayer: () -> Void
    let stopPlayback: () -> Void
    let setSleepTimer: (Int?) -> Void
    let playPrevious: () -> Void
    let playNext: () -> Void
    let playStation: (Station, [Station]) -> Void
    let playStationFromQueue: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void
    let toggleFavorite: (Station) -> Void
    let setStationFeedback: (Station, TuneAVStationFeedback?) -> Void
    let showStationDetails: (Station, [Station], StationDetailSection) -> Void
    let openDiscoveryInfo: (DiscoveredTrack) -> Void
    let openDiscoveryStation: (DiscoveredTrack) -> Void
    let openAccount: () -> Void
    let startSignIn: () -> Void
    let openProPaywall: () -> Void
    let closeFocusedDetail: () -> Void
    /// Shows a song recognised from the stream as the current track (player, heart, history).
    let applyIdentifiedTrack: (Station, TuneAVIdentifiedTrack) -> Void
    @State var isShowingAviActions = false
    @State var isShowingMoreAviActions = false
    @State var isShowingFeedbackPicker = false
    @State var aviActionsPage = 0
    @State var isEditingRadioFeedback = false
    @State var isShowingArtworkZoom = false
    @State var isShowingQueueSwitcher = false
    @State var browserDestination: BrowserDestination?
    @State var nestedMusicDetail: SelectedMusicAviDetail?
    @State var aviReaction: AviScreenReaction?
    @State var relatedStationContext: RelatedStationContext?
    @State var relatedStationResults: [(station: Station, reason: String)] = []
    @State var isLoadingRelatedStations = false
    @State var aviReactionStartedAt = Date.distantPast
    @State var aviReactionToken = UUID()
    @State var lastAutomaticAviReactionIdentity = ""
    @State var lastAutomaticAviReactionAt = Date.distantPast
    @State var visibleArtistSongLimit = artistDetailPageSize
    @State var visibleArtistStationLimit = artistDetailPageSize
    @State var visibleFocusedRadioHistoryLimit = artistDetailPageSize
    @State var selectedStationDetailSection: StationDetailSection = .about
    @State var selectedArtistDetailSection: ArtistDetailSection = .info
    @State var openArtistDetailAviActionsID: String?
    @State var isShowingPlanComparison = false
    @ScaledMetric(relativeTo: .caption) var fullPlayerAviActionsButtonHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .callout) var fullPlayerHeartButtonHeight: CGFloat = 52

    var browserRouter: ShellBrowserRouter {
        ShellBrowserRouter(
            openDestination: { browserDestination = $0 },
            openSystemURL: { UIApplication.shared.open($0) },
            closeAviActions: closeAviActions,
            searchEngine: AVExternalSearchEngine.resolved(from: libraryStore.settings.externalSearchEngine),
            webOpenMode: AVExternalWebOpenMode.resolved(from: libraryStore.settings.externalWebOpenMode),
            allowLookup: { feature, url in
                accessController.useDailyFeatureIfAllowed(feature, usageKey: url.absoluteString)
            }
        )
    }

    var body: some View {
        TuneAdaptiveLayoutReader { layout in
            ZStack(alignment: .bottom) {
                if isNowPlayingFullPlayer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: aviContentSpacing(for: layout)) {
                            if focusedDetailIsEmpty || activeMusicDetail != nil {
                                aviContextHeader
                            }

                            if focusedDetailIsEmpty {
                                aviLandingContent
                            } else if let activeMusicDetail {
                                focusedMusicExperience(activeMusicDetail)
                            } else {
                                focusedSignalExperience
                            }
                        }
                        .shellScreenContentPadding(layout: layout, bottom: aviScrollBottomPadding)
                    }
                    .shellScreenScrollBehavior()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: aviContentSpacing(for: layout)) {
                                Color.clear
                                    .frame(height: 0)
                                    .id("avi.detail.top")

                                aviContextHeader

                                if focusedDetailIsEmpty {
                                    aviLandingContent
                                } else if let activeMusicDetail {
                                    focusedMusicExperience(activeMusicDetail)
                                } else {
                                    focusedSignalExperience
                                }
                            }
                            .shellScreenContentPadding(layout: layout, bottom: aviScrollBottomPadding)
                        }
                        .shellScreenScrollBehavior()
                        .onChange(of: activeDetailScrollID) { _, _ in
                            scrollToDetailTop(proxy)
                        }
                    }
                }
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .sheet(item: $browserDestination) { destination in
                InAppBrowserView(destination: destination)
            }
            .sheet(isPresented: $isShowingQueueSwitcher) {
                AviQueueSwitcherSheet(
                    currentSource: playbackQueueSource,
                    options: queueSwitchOptions,
                    selectOption: selectQueueOption(_:),
                    onDismiss: { isShowingQueueSwitcher = false }
                )
            }
            .sheet(isPresented: $isShowingPlanComparison) {
                AviPlanComparisonSheet(
                    accessMode: accessController.accessMode,
                    onPrimaryAction: primaryAviPreviewAction,
                    onDismiss: { isShowingPlanComparison = false }
                )
            }
            .overlay {
                if isShowingArtworkZoom, let focusedStation {
                    artworkZoomOverlay(for: focusedStation)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(30)
                }
            }
            .onChange(of: currentSongIdentity) { _, nextIdentity in
                resetTransientAviUI()
                showAviReactionForCurrentSongChange(identity: nextIdentity)
            }
            .onChange(of: isShowingAviActions) { _, isShowing in
                isActionPanelOpen = isShowing && isNowPlayingFullPlayer
            }
            .onChange(of: isNowPlayingFullPlayer) { _, isFullPlayer in
                isActionPanelOpen = isFullPlayer && isShowingAviActions
                if isFullPlayer {
                    resetNestedMusicNavigation()
                }
            }
            .onChange(of: focusedMusicDetail?.id) { _, _ in
                resetNestedMusicNavigation()
            }
            .onChange(of: focusedStation?.id) { _, _ in
                resetNestedMusicNavigation()
                visibleFocusedRadioHistoryLimit = Self.artistDetailPageSize
                selectedStationDetailSection = focusedStationDetailSection
            }
            .onChange(of: focusedStationDetailSection) { _, section in
                selectedStationDetailSection = section
            }
            .onAppear {
                selectedStationDetailSection = focusedStationDetailSection
            }
            .onDisappear {
                isActionPanelOpen = false
            }
            .accessibilityIdentifier("avi.screen")
        }
    }

    func aviContentSpacing(for layout: TuneLayoutContext) -> CGFloat {
        layout.isTabletLike ? 20 : 16
    }

    var activeMusicDetail: SelectedMusicAviDetail? {
        guard !isNowPlayingFullPlayer else { return nil }
        return nestedMusicDetail ?? focusedMusicDetail
    }

    var activeDetailScrollID: String {
        if let activeMusicDetail {
            return "music:\(activeMusicDetail.id)"
        }
        if let focusedStation {
            return "radio:\(focusedStation.id)"
        }
        return "landing"
    }

    func scrollToDetailTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.22)) {
                proxy.scrollTo("avi.detail.top", anchor: .top)
            }
        }
    }

    func closeActiveDetail() {
        if nestedMusicDetail != nil {
            nestedMusicDetail = nil
        } else {
            closeFocusedDetail()
        }
    }

    func resetArtistDetailLimits() {
        visibleArtistSongLimit = Self.artistDetailPageSize
        visibleArtistStationLimit = Self.artistDetailPageSize
        openArtistDetailAviActionsID = nil
    }

    func resetNestedMusicNavigation() {
        nestedMusicDetail = nil
        resetArtistDetailLimits()
        selectedArtistDetailSection = .info
    }

    var focusedDetailIsEmpty: Bool {
        focusedStation == nil && activeMusicDetail == nil
    }

    var aviScrollBottomPadding: CGFloat {
        bottomContentPadding
    }

    @ViewBuilder
    var aviLandingContent: some View {
        if currentStation != nil {
            aviCommandCenter
            aviCurrentSignalCard
            if topRecommendation != nil {
                recommendationPanel
            }
            aviListeningSignals
            aviFreeAccessSupport
        } else {
            aviCommandCenter
            if topRecommendation != nil {
                recommendationPanel
            } else {
                aviCurrentSignalCard
                quickActions
            }
            localSignals
            aviFreeAccessSupport
        }
    }

    @ViewBuilder
    var aviFreeAccessSupport: some View {
        if !accessController.capabilities.canAccessPremiumFeatures {
            VStack(alignment: .leading, spacing: 12) {
                aviPreviewActions
                aviPreviewCapabilities
            }
            .accessibilityIdentifier("avi.freeAccess.support")
        }
    }

    @ViewBuilder
    var focusedSignalExperience: some View {
        if let focusedStation {
            if !isNowPlayingFullPlayer {
                VStack(alignment: .leading, spacing: 12) {
                    focusedRadioSectionPicker(for: focusedStation)

                    switch selectedStationDetailSection {
                    case .about:
                        focusedRadioAboutContent(for: focusedStation)
                    case .history:
                        focusedRadioHistoryBlock(for: focusedStation, showsTitle: false)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    fullPlayerAviFeedbackBlock(for: focusedStation)
                }
            }
        }
    }

    func focusedRadioAboutContent(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            focusedRadioSummaryCard(for: station)
            focusedRadioStats(for: station)
            focusedRadioQuickActions(for: station)
            focusedAviServices(for: station)
            relatedStationsPanel
            focusedSignalInfo(for: station)
        }
    }
}
