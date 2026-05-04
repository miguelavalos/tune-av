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
            title: "Discovery",
            value: preferredTag.isEmpty ? "Default" : preferredTag.capitalized,
            detail: "Launch genre"
        )
        LibraryMetricCard(
            title: "Appearance",
            value: appearanceMode,
            detail: "Current mode"
        )
        LibraryMetricCard(
            title: "Start",
            value: launchToSearch ? "Search" : "Home",
            detail: "Launch destination"
        )
        LibraryMetricCard(
            title: "Access",
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
        LibraryMetricCard(title: "Favorites", value: countText(favoritesCount, limit: favoriteLimit), detail: "Pinned stations")
        LibraryMetricCard(title: "Recents", value: countText(recentsCount, limit: recentsLimit), detail: "Playback history")
        LibraryMetricCard(title: "Latest", value: latestStationName ?? "None", detail: "Most recent station")
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.highlight)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .avCardSurface(cornerRadius: 18)
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
                Button("Not now", action: dismissAction)
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

enum HomeFeedContext {
    case popularWorldwide
    case popularInCountry(String)
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

                    Text("Country")
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
                    Text("Clear")
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
                    TextField("Search countries", text: $query)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        selectedCountryCode = nil
                        dismiss()
                    } label: {
                        CountryRow(
                            title: "All countries",
                            subtitle: "Use global discovery",
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
            .navigationTitle("Choose country")
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
