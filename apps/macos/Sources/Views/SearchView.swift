import SwiftUI

struct SearchView: View {
    @Binding var query: String
    @Binding var activeTag: String?
    @Binding var selectedCountryCode: String?
    let results: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let genreTags: [String]
    let playAction: (Station) -> Void
    let toggleFavorite: (Station) -> Void
    let isFavorite: (Station) -> Bool
    let showDetails: (Station) -> Void
    let searchAction: () -> Void
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isShowingCountryPicker = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let compact = width < 820

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("shell.search.title"))
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                            Text(sectionSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        HeaderStatusPill(status: isLoading ? L10n.string("shell.search.status.searching") : L10n.plural(singular: "shell.search.results.count.one", plural: "shell.search.results.count.other", count: results.count, results.count, queryText.isEmpty ? L10n.string("shell.search.status.search") : queryText))
                    }

                    if compact {
                        VStack(spacing: 12) {
                            searchBar
                            searchFilters
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            searchBar
                            searchFilters
                        }
                    }

                    StationSection(title: sectionTitle, subtitle: sectionSubtitle) {
                        if !results.isEmpty {
                            LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                ForEach(results) { station in
                                    StationRowCard(
                                        station: station,
                                        isFavorite: isFavorite(station),
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playAction(station) },
                                        detailsAction: { showDetails(station) }
                                    )
                                }
                            }
                        } else if isLoading {
                            EmptyStateCard(title: L10n.string("shell.search.loading.title"), detail: L10n.string("shell.search.loading.detail"))
                        } else if let errorMessage {
                            EmptyStateCard(title: L10n.string("shell.search.error.title"), detail: errorMessage)
                        } else {
                            EmptyStateCard(
                                title: L10n.string("shell.search.empty.title"),
                                detail: queryText.isEmpty && activeTag == nil
                                    ? L10n.string("shell.search.empty.detail.initial")
                                    : L10n.string("shell.search.empty.detail.retry")
                            )
                        }
                    }
                }
                .frame(maxWidth: compact ? 760 : 1040, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.top, compact ? 18 : 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isShowingCountryPicker) {
            SearchCountryPickerSheet(selectedCountryCode: $selectedCountryCode)
                .environmentObject(libraryStore)
        }
        .onChange(of: selectedCountryCode) { _, newValue in
            libraryStore.updatePreferredCountryCode(newValue)
            searchAction()
        }
    }

    private var queryText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 124, maximum: 150), spacing: 12)
        ]
    }

    private var sectionTitle: String {
        if queryText.isEmpty && activeTag == nil && selectedCountryCode != nil {
            return L10n.string("shell.search.section.country.title", selectedCountryTitle)
        }
        if queryText.isEmpty && activeTag == nil {
            return L10n.string("shell.search.section.popularWorldwide.title")
        }
        if queryText.isEmpty {
            return L10n.string("shell.search.section.browse.title")
        }
        return L10n.string("shell.search.section.results.title")
    }

    private var sectionSubtitle: String {
        if let errorMessage {
            return errorMessage
        }
        if isLoading {
            return L10n.string("shell.search.loading.detail")
        }
        if queryText.isEmpty {
            if let selectedCountryCode {
                return L10n.string("shell.search.section.country.subtitle", CountryOption(code: selectedCountryCode, name: selectedCountryTitle).name)
            }
            if let activeTag {
                return L10n.string("shell.home.section.topGenre.title", L10n.genreLabel(for: activeTag))
            }
            return L10n.string("shell.search.section.browse.subtitle")
        }
        return L10n.plural(singular: "shell.search.results.count.one", plural: "shell.search.results.count.other", count: results.count, results.count, queryText)
    }

    private var selectedCountryTitle: String {
        guard let selectedCountryCode else { return L10n.string("shell.search.country.all") }
        return L10n.countryName(for: selectedCountryCode)
    }

    private var selectedCountryFlag: String? {
        guard let selectedCountryCode else { return nil }
        return CountryOption(code: selectedCountryCode, name: selectedCountryTitle).flag
    }

    private func clearCountryFilter() {
        selectedCountryCode = nil
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            MacSearchField(
                prompt: L10n.string("shell.search.field.defaultPrompt"),
                text: $query,
                submitAction: searchAction
            )

            MacIconButton(
                systemImage: "arrow.right",
                title: L10n.string("shell.search.status.search"),
                isProminent: true,
                action: searchAction
            )
        }
    }

    private var searchFilters: some View {
            VStack(alignment: .leading, spacing: 10) {
            SearchCountryFilterButton(
                title: selectedCountryTitle,
                flag: selectedCountryFlag,
                isActive: selectedCountryCode != nil,
                clearAction: clearCountryFilter,
                openAction: { isShowingCountryPicker = true }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(genreTags, id: \.self) { tag in
                        Button {
                            toggleGenre(tag)
                        } label: {
                            Text(L10n.genreLabel(for: tag))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(activeTag == tag ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(activeTag == tag ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface)
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(activeTag == tag ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggleGenre(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
        searchAction()
    }
}
