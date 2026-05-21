import AVAppShellFoundation
import SwiftUI

struct RadioStationListSnapshot {
    let baseStations: [Station]
    let filteredStations: [Station]
    let visibleStations: [Station]

    var canShowMore: Bool {
        visibleStations.count < filteredStations.count
    }
}

enum RadioSavedSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case alphabetical
    case lastListened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded:
            return L10n.string("shell.library.sort.recentlyAdded")
        case .alphabetical:
            return L10n.string("shell.library.sort.alphabetical")
        case .lastListened:
            return L10n.string("shell.library.sort.lastListened")
        }
    }
}

struct RadioDetailHeader: View {
    let title: String
    let subtitle: String
    let goBack: () -> Void

    var body: some View {
        DetailTopHeader(
            title: title,
            subtitle: subtitle,
            status: L10n.string("shell.common.radio"),
            accessibilityIdentifier: "library.detail.header",
            goBack: goBack
        )
    }
}

struct ShowMoreButton: View {
    let title: String
    let remainingCount: Int
    let action: () -> Void

    var body: some View {
        AVAppShellShowMoreButton(
            title: L10n.string("common.showMoreCount", title, remainingCount),
            action: action
        )
    }
}

struct RadioOverviewCarouselSection<Content: View>: View {
    let title: String
    let subtitle: String
    var accessibilityIdentifier: String?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if let accessibilityIdentifier {
            section
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            section
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(L10n.string("common.view"))
                            .font(.system(size: 13, weight: .black))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .black))
                    }
                    .foregroundStyle(TuneAVTheme.highlight)
                }
                .buttonStyle(.plain)
            }

            content()
        }
    }
}

struct RadioOverviewMetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            content
        }
    }
}

enum AccountSummaryStatusKind {
    case radios
    case music

    var title: String {
        switch self {
        case .radios:
            return L10n.string("shell.summary.radios.title")
        case .music:
            return L10n.string("shell.summary.music.title")
        }
    }

    var systemImage: String {
        switch self {
        case .radios:
            return "antenna.radiowaves.left.and.right"
        case .music:
            return "music.note.list"
        }
    }
}

struct AccountSummaryStatusCard: View {
    let kind: AccountSummaryStatusKind
    let state: TuneAVUserSummaryRefreshState
    let summary: TuneAVUserSummary?
    let isSignedIn: Bool
    let hasProAccess: Bool
    let localRadioTunedCount: Int?
    let localMusicDetectedCount: Int?
    let localMusicArtistCount: Int?
    let openAccountAction: () -> Void
    let startSignInAction: () -> Void
    let refreshAction: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(statusTint)
                .frame(width: 34, height: 34)
                .background(statusTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(kind.title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingAction
        }
        .padding(14)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusTint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summary.\(kind == .radios ? "radios" : "music")")
    }

    @ViewBuilder
    private var trailingAction: some View {
        if !isSignedIn {
            Button(action: startSignInAction) {
                Text(L10n.string("profile.account.connect"))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if !hasProAccess {
            Button(action: openAccountAction) {
                Text(L10n.string("profile.summary.plan.detail.pro"))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task {
                    isRefreshing = true
                    await refreshAction()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: isRefreshing || state == .loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.highlight.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || state == .loading)
            .accessibilityLabel(L10n.string("shell.summary.refresh"))
        }
    }

    private var statusImage: String {
        switch state {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .loaded:
            return kind.systemImage
        case .empty:
            return "tray"
        case .idle, .unavailable:
            return isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
        }
    }

    private var statusTint: Color {
        switch state {
        case .failed:
            return Color(red: 1.0, green: 0.17, blue: 0.38)
        case .loaded:
            return TuneAVTheme.highlight
        case .empty:
            return Color(red: 0.95, green: 0.48, blue: 0.18)
        case .loading:
            return Color(red: 0.17, green: 0.52, blue: 0.96)
        case .idle, .unavailable:
            return TuneAVTheme.textSecondary
        }
    }

    private var detail: String {
        guard isSignedIn else {
            return L10n.string("shell.summary.signIn")
        }

        guard hasProAccess else {
            return L10n.string("shell.summary.free")
        }

        switch state {
        case .loading:
            return L10n.string("shell.summary.loading")
        case .failed:
            return L10n.string("shell.summary.failed")
        case .loaded:
            return loadedDetail
        case .empty:
            return L10n.string("shell.summary.empty")
        case .idle, .unavailable:
            return L10n.string("shell.summary.ready")
        }
    }

    private var loadedDetail: String {
        guard let summary else {
            return L10n.string("shell.summary.ready")
        }

        switch kind {
        case .radios:
            let topWeekText = L10n.plural(singular: "shell.count.topWeekStation.one", plural: "shell.count.topWeekStation.other", count: summary.radio.cards.topWeek.count, summary.radio.cards.topWeek.count)
            let tunedCount = localRadioTunedCount ?? summary.radio.cards.tuned.count
            let tunedText = L10n.plural(singular: "shell.count.tunedSignal.one", plural: "shell.count.tunedSignal.other", count: tunedCount, tunedCount)
            return L10n.string(
                "shell.summary.radios.loaded",
                topWeekText,
                tunedText
            )
        case .music:
            let detectedCount = localMusicDetectedCount ?? summary.music.cards.history.count
            let artistCount = localMusicArtistCount ?? summary.music.cards.artists.count
            let detectedText = L10n.plural(singular: "shell.count.detectedSong.one", plural: "shell.count.detectedSong.other", count: detectedCount, detectedCount)
            let artistText = L10n.plural(singular: "shell.count.artist.one", plural: "shell.count.artist.other", count: artistCount, artistCount)
            return L10n.string(
                "shell.summary.music.loaded",
                detectedText,
                artistText
            )
        }
    }
}

struct RadioOverviewMetricCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        value: Int,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                Text("\(value)")
                    .font(.system(size: 17, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(TuneAVTheme.textPrimary)
            }
            .padding(10)
            .frame(minHeight: 48)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .modifyIfLet(accessibilityIdentifier) { view, identifier in
            view.accessibilityIdentifier(identifier)
        }
    }
}

private extension View {
    @ViewBuilder
    func modifyIfLet<Value, Modified: View>(
        _ value: Value?,
        transform: (Self, Value) -> Modified
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
