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
                MusicFeedbackBadge(feedback: feedback, size: badgeSize, fontSize: badgeFontSize)
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
            withAnimation(.snappy(duration: 0.18)) {
                if isShowingAviActions {
                    openAviActionsID = nil
                } else {
                    aviActionsPage = 0
                    openAviActionsID = aviActionsID
                }
            }
        } label: {
            Image("AviV2HeadNeutral")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.mutedSurface, in: Circle())
            .overlay {
                Circle()
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
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
        AviListActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AviListActionButton(
                    title: discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark",
                    accessibilityIdentifier: "discoveryTrack.save.\(discovery.discoveryID)"
                ) {
                    toggleSaved()
                    closeAviActions()
                }
                AviListActionButton(title: L10n.string("shell.music.discovery.openTrackInfo.action"), systemImage: "info.circle") {
                    openTrackInfo()
                    closeAviActions()
                }
                AviListActionButton(title: L10n.string("player.artist.view"), systemImage: "person.crop.circle") {
                    openArtistInfo()
                    closeAviActions()
                }
                AviListActionButton(title: L10n.string("shell.music.discovery.openStation.action"), systemImage: "dot.radiowaves.left.and.right") {
                    openStationInfo()
                    closeAviActions()
                }
            } else {
                AviListActionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AviListActionButton(title: L10n.string("player.discovery.lyrics"), systemImage: "text.quote", action: runAndClose(openLyrics))
                AviListActionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AviListActionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
            }
        }
    }

    private func closeAviActions() {
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
        TuneAVRemoteArtworkImage(url: url, size: 54, scale: displayScale) {
            fallback()
        }
        .frame(width: 54, height: 54)
        .clipShape(artworkShape(size: 54))
        .overlay {
            artworkShape(size: 54)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var fallbackArtwork: some View {
        artworkShape(size: 54)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                artworkShape(size: 54)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private func artworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
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
                MusicFeedbackBadge(feedback: feedback, size: 22, fontSize: 9)
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
        TuneAVRemoteArtworkImage(url: url, size: 68, scale: displayScale) {
            fallbackArtwork
        }
        .frame(width: 68, height: 68)
        .clipShape(artworkShape(size: 68))
        .overlay {
            artworkShape(size: 68)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var fallbackArtwork: some View {
        artworkShape(size: 68)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: 68, height: 68)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                artworkShape(size: 68)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private func artworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
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

private struct MusicFeedbackBadge: View {
    let feedback: TuneAVStationFeedback
    var size: CGFloat = 18
    var fontSize: CGFloat = 8
    var borderWidth: CGFloat = 1

    var body: some View {
        TuneAVFeedbackBadge(feedback: feedback, size: size, fontSize: fontSize)
    }
}

private struct AviListActionsPanel<Content: View>: View {
    let page: Int
    let pageCount: Int
    let previous: () -> Void
    let next: () -> Void
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("shell.avi.actions.ask"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)

                    Text(L10n.string("shell.avi.actions.page", page + 1, pageCount))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer(minLength: 0)

                if pageCount > 1 {
                    HStack(spacing: 6) {
                        Button(action: previous) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .black))
                                .frame(width: 28, height: 28)
                                .background(TuneAVTheme.cardSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(page == 0)
                        .opacity(page == 0 ? 0.34 : 1)
                        .accessibilityLabel(L10n.string("shell.avi.actions.previousOptions"))

                        Button(action: next) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .black))
                                .frame(width: 28, height: 28)
                                .background(TuneAVTheme.cardSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(page >= pageCount - 1)
                        .opacity(page >= pageCount - 1 ? 0.34 : 1)
                        .accessibilityLabel(L10n.string("shell.avi.actions.moreOptions"))
                    }
                    .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.closeOptions"))
            }

            VStack(spacing: 7) {
                content()
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(TuneAVTheme.elevatedSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.glassShadow, radius: 24, y: 12)
    }
}

private struct AviListActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(role == .destructive ? Color.red : TuneAVTheme.highlight)
                    .frame(width: 30, height: 30)
                    .background((role == .destructive ? Color.red : TuneAVTheme.highlight).opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.46), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .modifier(OptionalMusicDiscoveryAccessibilityIdentifier(accessibilityIdentifier))
    }
}

private struct OptionalMusicDiscoveryAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
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
            TuneAVRemoteArtworkImage(url: artworkURL, size: artworkSize, scale: displayScale) {
                fallbackArtwork
            }
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(artworkShape)
            .overlay {
                artworkShape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        artworkShape
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: artworkSize, height: artworkSize)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                artworkShape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: artworkSize), style: .continuous)
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
                withAnimation(.snappy(duration: 0.18)) {
                    if isShowingAviActions {
                        openAviActionsID = nil
                    } else {
                        aviActionsPage = 0
                        openAviActionsID = aviActionsID
                    }
                }
            } label: {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.mutedSurface.opacity(0.85), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
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
        AviListActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AviListActionButton(title: L10n.string("shell.music.artist.openDetails"), systemImage: "info.circle") {
                    openArtist()
                    closeAviActions()
                }
                AviListActionButton(title: L10n.string("shell.music.artist.viewSavedSongs"), systemImage: "music.note.list") {
                    openArtistSongs()
                    closeAviActions()
                }
                AviListActionButton(title: L10n.string("shell.avi.music.artist.radios"), systemImage: "dot.radiowaves.left.and.right") {
                    openArtistRadios()
                    closeAviActions()
                }
            } else {
                AviListActionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AviListActionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AviListActionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = summary.displayArtworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: artworkSize, scale: displayScale) {
                fallbackArtwork
            }
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(artworkShape)
            .overlay {
                artworkShape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        artworkShape
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: artworkSize, height: artworkSize)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                artworkShape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: artworkSize), style: .continuous)
    }
}
