import SwiftUI

struct ProfileSummaryRow: View {
    let preferredTag: String
    let appearanceMode: String
    let launchToSearch: Bool
    let accessMode: AccessMode
    let accountConnectionState: AccountConnectionState
    let accessDetail: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                summaryCards
            }

            VStack(spacing: 8) {
                summaryCards
            }
        }
    }

    @ViewBuilder
    private var summaryCards: some View {
        LibraryMetricCard(
            title: L10n.string("shell.library.discoveries.title"),
            value: preferredTag.isEmpty ? L10n.string("mac.profile.genre.none") : L10n.genreLabel(for: preferredTag),
            detail: L10n.string("mac.profile.summary.launchGenre")
        )
        LibraryMetricCard(
            title: L10n.string("profile.preferences.theme.title"),
            value: appearanceMode,
            detail: L10n.string("mac.profile.summary.currentMode")
        )
        LibraryMetricCard(
            title: L10n.string("mac.profile.summary.start"),
            value: launchToSearch ? L10n.string("tab.search") : L10n.string("tab.home"),
            detail: L10n.string("mac.profile.summary.launchDestination")
        )
        LibraryMetricCard(
            title: L10n.string("profile.summary.plan.title"),
            value: accountConnectionState.title,
            detail: accessDetail
        )
    }
}

struct LibrarySummaryRow: View {
    let favoritesCount: Int
    let recentsCount: Int
    let latestStationName: String?
    let favoriteLimit: Int?
    let recentsLimit: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                metricCards
            }

            VStack(spacing: 8) {
                metricCards
            }
        }
    }

    @ViewBuilder
    private var metricCards: some View {
        LibraryMetricCard(title: L10n.string("shell.library.favorites.title"), value: countText(favoritesCount, limit: favoriteLimit), detail: L10n.string("mac.library.pinnedStations"))
        LibraryMetricCard(title: L10n.string("shell.library.recents.title"), value: countText(recentsCount, limit: recentsLimit), detail: L10n.string("mac.library.playbackHistory"))
        LibraryMetricCard(title: L10n.string("mac.library.latest"), value: latestStationName ?? L10n.string("mac.profile.genre.none"), detail: L10n.string("mac.library.latestDetail"))
    }

    private func countText(_ count: Int, limit: Int?) -> String {
        guard let limit else { return "\(count)" }
        return "\(count)/\(limit)"
    }
}

struct LibraryMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.highlight)
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(TuneAVTheme.highlight.opacity(0.08))
                        .frame(width: 58, height: 58)
                        .offset(x: 18, y: -22)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
                }
        )
    }
}

struct MacSearchField: View {
    let prompt: String
    @Binding var text: String
    var submitAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .onSubmit {
                    submitAction?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    submitAction?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.72))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.86), lineWidth: 1)
        }
    }
}

struct MacIconButton: View {
    let systemImage: String
    var title: String? = nil
    var isProminent = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 0 : 13)
            .frame(width: title == nil ? 44 : nil, height: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if role == .destructive { return Color(red: 0.88, green: 0.08, blue: 0.22) }
        return isProminent ? .white : TuneAVTheme.textPrimary
    }

    private var background: Color {
        if role == .destructive { return Color(red: 1, green: 0.17, blue: 0.38).opacity(0.09) }
        return isProminent ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface
    }

    private var border: Color {
        if role == .destructive { return Color(red: 1, green: 0.17, blue: 0.38).opacity(0.2) }
        return isProminent ? TuneAVTheme.highlight.opacity(0.35) : TuneAVTheme.borderSubtle
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(18)
        .avCardSurface(cornerRadius: 22)
    }
}

struct SettingsFieldRow<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsLabel(title: title, description: description)
            content
        }
    }
}

struct SettingsLabel: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
    }
}

struct SettingsStatsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

enum SettingsActionButtonStyle {
    case normal
    case prominent
    case destructive
}

struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    var style: SettingsActionButtonStyle = .normal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .normal:
            return TuneAVTheme.textPrimary
        case .prominent:
            return Color.white
        case .destructive:
            return .red
        }
    }

    private var background: Color {
        switch style {
        case .normal:
            return TuneAVTheme.elevatedSurface
        case .prominent:
            return TuneAVTheme.highlight
        case .destructive:
            return Color.red.opacity(0.08)
        }
    }

    private var border: Color {
        switch style {
        case .normal:
            return TuneAVTheme.borderSubtle.opacity(0.8)
        case .prominent:
            return Color.clear
        case .destructive:
            return Color.red.opacity(0.18)
        }
    }
}

struct SettingsOptionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .background(
                isSelected ? TuneAVTheme.highlight.opacity(0.10) : TuneAVTheme.elevatedSurface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.35) : TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsLinkButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMenuButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
        }
    }
}

struct UpgradePromptSheet: View {
    let context: UpgradePromptContext
    let accountConnectionState: AccountConnectionState
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 48, height: 48)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.title)
                        .font(.title2.weight(.bold))
                    Text(accountConnectionState.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(context.message)
                .font(.body)
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(context.benefit)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let progressText = context.progressText {
                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TuneAVTheme.highlight.opacity(0.10), in: Capsule())
            }

            HStack {
                Button(L10n.string("mac.common.notNow"), action: dismissAction)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(TuneAVTheme.highlight)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

typealias CountryOption = TuneAVCountry

extension TuneAVCountry {
    static var all: [TuneAVCountry] {
        all(localizedName: name(for:))
    }

    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

struct ShellHeader: View {
    let status: String

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image("OnboardingWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
            }

            Spacer()

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TuneAVTheme.cardSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
    }
}

struct HeaderStatusPill: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TuneAVTheme.highlight)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TuneAVTheme.cardSurface, in: Capsule())
            .overlay {
                Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }
}

struct SearchCountryFilterButton: View {
    let title: String
    let flag: String?
    let isActive: Bool
    let clearAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openAction) {
                HStack(spacing: 8) {
                    Image(systemName: "globe.europe.africa")
                        .font(.system(size: 14, weight: .semibold))

                    Text(L10n.string("shell.search.country.label"))
                        .font(.system(size: 14, weight: .semibold))

                    if let flag {
                        Text(flag)
                            .font(.system(size: 16))
                    }

                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(isActive ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? TuneAVTheme.highlight.opacity(0.08) : TuneAVTheme.cardSurface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isActive ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: clearAction) {
                    Text(L10n.string("shell.search.country.clear"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .avRoundedControl(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SearchCountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCountryCode: String?
    @State private var query = ""

    private var countryOptions: [CountryOption] {
        CountryOption.filtered(CountryOption.all, query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(L10n.string("shell.search.country.searchPrompt"), text: $query)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        selectedCountryCode = nil
                        dismiss()
                    } label: {
                        CountryRow(
                            title: L10n.string("shell.search.country.all"),
                            subtitle: L10n.string("shell.search.country.allSubtitle"),
                            flag: nil,
                            isSelected: selectedCountryCode == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(countryOptions) { option in
                        Button {
                            selectedCountryCode = option.code
                            dismiss()
                        } label: {
                            CountryRow(
                                title: option.name,
                                subtitle: nil,
                                flag: option.flag,
                                isSelected: selectedCountryCode == option.code
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .navigationTitle(L10n.string("shell.search.country.pickerTitle"))
        }
    }
}

struct CountryRow: View {
    let title: String
    let subtitle: String?
    let flag: String?
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.mutedSurface)

                if let flag {
                    Text(flag)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
        }
        .padding(14)
        .avCardSurface(
            cornerRadius: 20,
            borderColor: isSelected ? TuneAVTheme.highlight.opacity(0.26) :
                (isHovered ? TuneAVTheme.highlight.opacity(0.16) : TuneAVTheme.borderSubtle),
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0
        )
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
