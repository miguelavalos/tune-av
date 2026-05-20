import SwiftUI

struct AviActionsPanelView: View {
    let state: ShellAviActionsPanelState
    let showsStationDetailAction: Bool
    let showsCloseSignalAction: Bool
    let previousPage: () -> Void
    let nextPage: () -> Void
    let close: () -> Void
    let searchLyrics: () -> Void
    let searchYouTube: () -> Void
    let searchAppleMusic: () -> Void
    let searchArtist: () -> Void
    let searchPublicInfo: () -> Void
    let showRadioDetails: () -> Void
    let showHistory: () -> Void
    let openWebsite: () -> Void
    let findRelatedRadios: () -> Void
    let closeSignal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            VStack(spacing: 5) {
                if state.showsSongActions {
                    songActions
                } else {
                    stationActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            if showsCloseSignalAction {
                AviCloseSignalPanelButton(action: closeSignal)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 356, alignment: .top)
        .background(TuneAVTheme.elevatedSurface.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(state.pageLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                pagingButton(
                    systemImage: "chevron.left",
                    isEnabled: state.canGoPrevious,
                    accessibilityLabel: L10n.string("shell.avi.actions.previousOptions"),
                    action: previousPage
                )
                pagingButton(
                    systemImage: "chevron.right",
                    isEnabled: state.canGoNext,
                    accessibilityLabel: L10n.string("shell.avi.actions.moreOptions"),
                    action: nextPage
                )
            }
            .foregroundStyle(TuneAVTheme.textSecondary)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.cardSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.avi.actions.closeOptions"))
            .accessibilityIdentifier("avi.actions.close")
        }
    }

    private var songActions: some View {
        Group {
            AviCommandButton(title: L10n.string("shell.avi.actions.searchLyrics"), systemImage: "text.quote", accessibilityIdentifier: "avi.actions.lyrics", action: searchLyrics)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchYouTube"), systemImage: "play.rectangle", accessibilityIdentifier: "avi.actions.youtube", action: searchYouTube)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchAppleMusic"), systemImage: "music.note", accessibilityIdentifier: "avi.actions.appleMusic", action: searchAppleMusic)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchArtist"), systemImage: "person.crop.circle", accessibilityIdentifier: "avi.actions.artist", action: searchArtist)
        }
    }

    private var stationActions: some View {
        Group {
            AviCommandButton(title: L10n.string("shell.avi.actions.searchPublicInfo"), systemImage: "info.circle", accessibilityIdentifier: "avi.actions.publicInfo", action: searchPublicInfo)
            if showsStationDetailAction {
                AviCommandButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioDetails", action: showRadioDetails)
            }
            AviCommandButton(title: L10n.string("shell.avi.actions.history"), systemImage: "clock.arrow.circlepath", accessibilityIdentifier: "avi.actions.history", action: showHistory)
            AviCommandButton(title: L10n.string("shell.avi.actions.openWebsite"), systemImage: "safari", accessibilityIdentifier: "avi.actions.web", action: openWebsite)
            AviCommandButton(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles", accessibilityIdentifier: "avi.actions.relatedRadios", action: findRelatedRadios)
        }
    }

    private func pagingButton(
        systemImage: String,
        isEnabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .black))
                .frame(width: 28, height: 28)
                .background(TuneAVTheme.cardSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AviCommandButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 28, height: 28)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 36)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.46), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }
}

struct AviCloseSignalPanelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(TuneAVTheme.textSecondary.opacity(0.1), in: Circle())

                Text(L10n.string("shell.accessibility.closeSignal"))
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .background(TuneAVTheme.cardSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.closeSignal"))
        .accessibilityIdentifier("avi.actions.closeSignal")
    }
}
