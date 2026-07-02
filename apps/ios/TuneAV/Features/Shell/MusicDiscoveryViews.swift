import AVAviFoundation
import AVAppShellFoundation
import AVHaptics
import SwiftUI

struct DiscoveryTrackCard: View {
    @Environment(\.displayScale) private var displayScale

    let discovery: DiscoveredTrack
    let stationArtworkURL: URL?
    let feedback: TuneAVStationFeedback?
    var showsSaveButton = true
    @Binding var openAviActionsID: String?
    let openTrackInfo: () -> Void
    let openArtistInfo: () -> Void
    let openStationInfo: () -> Void
    let toggleSaved: () -> Void
    let openYouTube: () -> Void
    let openLyrics: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    let hideAction: (() -> Void)?
    let removeAction: (() -> Void)?
    @State private var aviActionsPage = 0

    private var aviActionsID: String {
        "track-\(discovery.discoveryID)"
    }

    private var isShowingAviActions: Bool {
        openAviActionsID == aviActionsID
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openTrackInfo) {
                HStack(spacing: 12) {
                    feedbackArtwork(size: 54, badgeSize: 22, badgeFontSize: 9, badgeOffset: -5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(discovery.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(discovery.artistDisplayText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)

                        Text(discovery.stationName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(discovery.title), \(discovery.artistDisplayText), \(discovery.stationName)")
            .accessibilityHint(L10n.string("shell.music.discovery.openTrackInfo.hint"))
            .accessibilityIdentifier("discoveryTrack.openInfo.\(discovery.discoveryID)")

            if showsSaveButton {
                saveButton
            }
            aviActionsMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discoveryTrack.\(discovery.discoveryID)")
    }

    private func feedbackArtwork(
        size: CGFloat,
        badgeSize: CGFloat,
        badgeFontSize: CGFloat,
        badgeOffset: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            artwork

            if let feedback {
                TuneAVFeedbackBadge(feedback: feedback, size: badgeSize, fontSize: badgeFontSize)
                    .offset(x: badgeOffset, y: badgeOffset)
            }
        }
        .frame(width: size, height: size)
    }

    private var saveButton: some View {
        Button(action: toggleSaved) {
            Image(systemName: discovery.isMarkedInteresting ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.mutedSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.save"))
        .accessibilityIdentifier("discoveryTrack.save.\(discovery.discoveryID)")
    }

    private var aviActionsMenu: some View {
        Button {
            AVHaptics.perform(isShowingAviActions ? .closePanel : .openPanel)
            withAnimation(.snappy(duration: 0.18)) {
                if isShowingAviActions {
                    openAviActionsID = nil
                } else {
                    aviActionsPage = 0
                    openAviActionsID = aviActionsID
                }
            }
        } label: {
            AVAviAvatarBadge(backgroundStyle: .muted) {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
        .accessibilityIdentifier("discoveryTrack.menu.\(discovery.discoveryID)")
        .popover(
            isPresented: Binding(
                get: { isShowingAviActions },
                set: { if !$0 { closeAviActions() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            aviActionsPanel
                .frame(width: 278)
                .presentationCompactAdaptation(.none)
        }
    }

    private var aviActionsPanel: some View {
        TuneAviPopoverActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AVAviPanelOptionButton(
                    title: discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark",
                    accessibilityIdentifier: "discoveryTrack.save.\(discovery.discoveryID)"
                ) {
                    toggleSaved()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openTrackInfo.action"), systemImage: "info.circle") {
                    openTrackInfo()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("player.artist.view"), systemImage: "person.crop.circle") {
                    openArtistInfo()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openStation.action"), systemImage: "dot.radiowaves.left.and.right") {
                    openStationInfo()
                    closeAviActions()
                }
            } else {
                AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.lyrics"), systemImage: "text.quote", action: runAndClose(openLyrics))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
                if let hideAction {
                    AVAviPanelOptionButton(
                        title: L10n.string("player.discovery.hide"),
                        systemImage: "eye.slash",
                        accessibilityIdentifier: "discoveryTrack.hide.\(discovery.discoveryID)",
                        action: runAndClose(hideAction)
                    )
                }
                if let removeAction {
                    AVAviPanelOptionButton(
                        title: L10n.string("player.discovery.remove"),
                        systemImage: "trash",
                        accessibilityIdentifier: "discoveryTrack.remove.\(discovery.discoveryID)",
                        action: runAndClose(removeAction)
                    )
                }
            }
        }
    }

    private func closeAviActions() {
        AVHaptics.perform(.closePanel)
        withAnimation(.snappy(duration: 0.18)) {
            openAviActionsID = nil
            aviActionsPage = 0
        }
    }

    private func runAndClose(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            closeAviActions()
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = discovery.resolvedArtworkURL {
            remoteArtwork(url: artworkURL) {
                fallbackArtwork
            }
        } else if let stationArtworkURL {
            remoteArtwork(url: stationArtworkURL) {
                fallbackArtwork
            }
        } else if let stationArtworkURL = discovery.resolvedStationArtworkURL {
            remoteArtwork(url: stationArtworkURL) {
                fallbackArtwork
            }
        } else {
            fallbackArtwork
        }
    }

    private func remoteArtwork<Fallback: View>(url: URL, @ViewBuilder fallback: @escaping () -> Fallback) -> some View {
        AVFramedArtwork(
            size: 54,
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 54)
        ) {
            TuneAVRemoteArtworkImage(url: url, size: 54, scale: displayScale) {
                fallback()
            }
        }
    }

    private var fallbackArtwork: some View {
        TuneAVMusicArtworkFallback(systemImage: "music.note", size: 54)
    }
}

struct MusicTrackCompactCarousel: View {
    let discoveries: [DiscoveredTrack]
    let stationArtworkURL: (DiscoveredTrack) -> URL?
    let trackFeedback: (DiscoveredTrack) -> TuneAVStationFeedback?
    let openTrackInfo: (DiscoveredTrack) -> Void
    let toggleSaved: (DiscoveredTrack) -> Void
    let openYouTube: (DiscoveredTrack) -> Void
    let openLyrics: (DiscoveredTrack) -> Void
    let openAppleMusic: (DiscoveredTrack) -> Void
    let openSpotify: (DiscoveredTrack) -> Void
    let hideAction: (DiscoveredTrack) -> Void
    let removeAction: (DiscoveredTrack) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(discoveries) { discovery in
                    MusicTrackCompactCard(
                        discovery: discovery,
                        stationArtworkURL: stationArtworkURL(discovery),
                        feedback: trackFeedback(discovery),
                        openTrackInfo: { openTrackInfo(discovery) },
                        toggleSaved: { toggleSaved(discovery) },
                        openYouTube: { openYouTube(discovery) },
                        openLyrics: { openLyrics(discovery) },
                        openAppleMusic: { openAppleMusic(discovery) },
                        openSpotify: { openSpotify(discovery) },
                        hideAction: { hideAction(discovery) },
                        removeAction: { removeAction(discovery) }
                    )
                    .frame(width: 252)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -20)
    }
}

private struct MusicTrackCompactCard: View {
    @Environment(\.displayScale) private var displayScale

    let discovery: DiscoveredTrack
    let stationArtworkURL: URL?
    let feedback: TuneAVStationFeedback?
    let openTrackInfo: () -> Void
    let toggleSaved: () -> Void
    let openYouTube: () -> Void
    let openLyrics: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    let hideAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            feedbackArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(discovery.artistDisplayText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .lineLimit(1)

                Text(discovery.playedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if discovery.isMarkedInteresting {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                    }

                    Text(discovery.isMarkedInteresting ? L10n.string("player.discovery.saved") : discovery.stationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: openTrackInfo)
        .background(TuneAVTheme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    private var feedbackArtwork: some View {
        ZStack(alignment: .topLeading) {
            artwork

            if let feedback {
                TuneAVFeedbackBadge(feedback: feedback, size: 22, fontSize: 9)
                    .offset(x: -5, y: -5)
            }
        }
        .frame(width: 68, height: 68)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = discovery.resolvedArtworkURL {
            remoteArtwork(url: artworkURL)
        } else if let stationArtworkURL {
            remoteArtwork(url: stationArtworkURL)
        } else if let stationArtworkURL = discovery.resolvedStationArtworkURL {
            remoteArtwork(url: stationArtworkURL)
        } else {
            fallbackArtwork
        }
    }

    private func remoteArtwork(url: URL) -> some View {
        AVFramedArtwork(
            size: 68,
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 68)
        ) {
            TuneAVRemoteArtworkImage(url: url, size: 68, scale: displayScale) {
                fallbackArtwork
            }
        }
    }

    private var fallbackArtwork: some View {
        TuneAVMusicArtworkFallback(systemImage: "music.note", size: 68)
    }

    private var discoveryMenu: some View {
        Menu {
            Button(L10n.string("player.discovery.youtube"), action: openYouTube)
            Button(L10n.string("player.discovery.lyrics"), action: openLyrics)
            Button(L10n.string("player.discovery.appleMusic"), action: openAppleMusic)
            Button(L10n.string("player.discovery.spotify"), action: openSpotify)
            Button(L10n.string("player.discovery.hide"), role: .destructive, action: hideAction)
            Button(L10n.string("player.discovery.remove"), role: .destructive, action: removeAction)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .rotationEffect(.degrees(90))
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.mutedSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("common.more"))
    }
}

struct MusicArtistCompactCarousel: View {
    let artists: [DiscoveryArtistSummary]
    let openArtistInfo: (DiscoveryArtistSummary) -> Void
    let openYouTube: (String) -> Void
    let openAppleMusic: (String) -> Void
    let openSpotify: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(artists) { artist in
                    MusicArtistCompactCard(
                        summary: artist,
                        openArtistInfo: { openArtistInfo(artist) },
                        openYouTube: { openYouTube(artist.name) },
                        openAppleMusic: { openAppleMusic(artist.name) },
                        openSpotify: { openSpotify(artist.name) }
                    )
                    .frame(width: 252)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -20)
    }
}

private struct MusicArtistCompactCard: View {
    @Environment(\.displayScale) private var displayScale
    private let artworkSize: CGFloat = 68

    let summary: DiscoveryArtistSummary
    let openArtistInfo: () -> Void
    let openYouTube: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            artwork

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(L10n.plural(
                    singular: "shell.library.discoveries.artistSongs.one",
                    plural: "shell.library.discoveries.artistSongs.other",
                    count: summary.trackCount,
                    summary.trackCount
                ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .lineLimit(1)

                Text(L10n.string("shell.music.artist.viewSongs"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: openArtistInfo)
        .background(TuneAVTheme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = summary.displayArtworkURL {
            AVFramedArtwork(
                size: artworkSize,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: artworkSize)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: artworkSize, scale: displayScale) {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        TuneAVMusicArtworkFallback(systemImage: "person.fill", size: artworkSize)
    }
}

struct DiscoveryArtistRow: View {
    @Environment(\.displayScale) private var displayScale
    private let artworkSize: CGFloat = 54

    let summary: DiscoveryArtistSummary
    @Binding var openAviActionsID: String?
    let openArtist: () -> Void
    let openArtistSongs: () -> Void
    let openArtistRadios: () -> Void
    let openYouTube: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    @State private var aviActionsPage = 0

    private var aviActionsID: String {
        "artist-\(summary.id)"
    }

    private var isShowingAviActions: Bool {
        openAviActionsID == aviActionsID
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openArtist) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(L10n.plural(
                            singular: "shell.library.discoveries.artistSongs.one",
                            plural: "shell.library.discoveries.artistSongs.other",
                            count: summary.trackCount,
                            summary.trackCount
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AVHaptics.perform(isShowingAviActions ? .closePanel : .openPanel)
                withAnimation(.snappy(duration: 0.18)) {
                    if isShowingAviActions {
                        openAviActionsID = nil
                    } else {
                        aviActionsPage = 0
                        openAviActionsID = aviActionsID
                    }
                }
            } label: {
                AVAviAvatarBadge(backgroundStyle: .mutedSoft) {
                    Image("AviV2HeadNeutral")
                        .resizable()
                        .scaledToFit()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
            .accessibilityIdentifier("discoveryArtistRow.aviActions.\(summary.id)")
            .popover(
                isPresented: Binding(
                    get: { isShowingAviActions },
                    set: { if !$0 { closeAviActions() } }
                ),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                aviActionsPanel
                    .frame(width: 278)
                    .presentationCompactAdaptation(.none)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discoveryArtistRow.\(summary.id)")
    }

    private func closeAviActions() {
        AVHaptics.perform(.closePanel)
        withAnimation(.snappy(duration: 0.18)) {
            openAviActionsID = nil
            aviActionsPage = 0
        }
    }

    private func runAndClose(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            closeAviActions()
        }
    }

    private var aviActionsPanel: some View {
        TuneAviPopoverActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AVAviPanelOptionButton(title: L10n.string("shell.music.artist.openDetails"), systemImage: "info.circle") {
                    openArtist()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.artist.viewSavedSongs"), systemImage: "music.note.list") {
                    openArtistSongs()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.avi.music.artist.radios"), systemImage: "dot.radiowaves.left.and.right") {
                    openArtistRadios()
                    closeAviActions()
                }
            } else {
                AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = summary.displayArtworkURL {
            AVFramedArtwork(
                size: artworkSize,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: artworkSize)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: artworkSize, scale: displayScale) {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        TuneAVMusicArtworkFallback(systemImage: "person.fill", size: artworkSize)
    }
}
