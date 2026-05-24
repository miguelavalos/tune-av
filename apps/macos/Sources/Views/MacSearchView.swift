import SwiftUI

struct MacSearchView: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @State private var isCountryPickerPresented = false
    @State private var countryQuery = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: queryText.isEmpty ? 20 : 14) {
                header
                searchControls
                if queryText.isEmpty {
                    genreTags
                }
                resultsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(isPresented: $isCountryPickerPresented) {
            MacSearchCountryPickerSheet(query: $countryQuery)
                .environmentObject(model)
        }
        .task {
            if model.searchResults.isEmpty {
                await model.search()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("shell.search.title"))
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(searchAviDetail)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()

            if hasActiveFilters {
                Button {
                    Task { await model.clearSearchFilters() }
                } label: {
                    Label(L10n.string("shell.search.country.clear"), systemImage: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(TuneAVTheme.textPrimary)
            }
            ProgressView()
                .opacity(model.isSearching ? 1 : 0)
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)

                    TextField(L10n.string("shell.search.field.defaultPrompt"), text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit {
                            Task { await model.search() }
                        }

                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                            Task { await model.search() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TuneAVTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSearchFocused ? TuneAVTheme.highlight.opacity(0.45) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }

                Button {
                    Task { await model.search() }
                } label: {
                    Label(L10n.string("shell.search.status.search"), systemImage: "magnifyingglass")
                        .font(.system(size: 13, weight: .black))
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TuneAVTheme.brandBlack)
                .keyboardShortcut(.return, modifiers: .command)
                .help(L10n.string("shell.search.status.search"))
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    countryQuery = ""
                    isCountryPickerPresented = true
                } label: {
                    MacSearchFilterPill(
                        title: selectedCountryTitle,
                        flag: selectedCountryFlag,
                        isActive: model.selectedSearchCountryCode != nil
                    )
                }
                .buttonStyle(.plain)

                Picker(L10n.string("shell.search.discoveryMode"), selection: discoveryModeBinding) {
                    Text(L10n.string("shell.search.discoveryMode.music")).tag(TuneAVStationDiscoveryMode.music)
                    Text(L10n.string("shell.search.discoveryMode.allRadio")).tag(TuneAVStationDiscoveryMode.allRadio)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                if model.selectedSearchCountryCode != nil {
                    Button {
                        Task { await model.setSearchCountryCode(nil) }
                    } label: {
                        Label(L10n.string("shell.search.country.clear"), systemImage: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TuneAVTheme.textPrimary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 860, alignment: .leading)
        .background(TuneAVTheme.mutedSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var genreTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visibleTags, id: \.self) { tag in
                    Button {
                        Task { await model.toggleSearchTag(tag) }
                    } label: {
                        Label(L10n.genreLabel(for: tag), systemImage: "sparkle")
                            .font(.system(size: 12, weight: .black))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(model.activeSearchTag == tag ? TuneAVTheme.highlight.opacity(0.16) : TuneAVTheme.cardSurface)
                            )
                            .overlay {
                                Capsule()
                                    .stroke(model.activeSearchTag == tag ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.activeSearchTag == tag ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.searchSectionTitle)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(model.searchSectionSubtitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            if model.searchResults.isEmpty, model.isSearching {
                MacSearchLoadingCard(title: L10n.string("shell.search.loading.title"))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let errorMessage = model.errorMessage, model.searchResults.isEmpty {
                ContentUnavailableView(
                    L10n.string("shell.search.error.title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else if model.searchResults.isEmpty {
                ContentUnavailableView(
                    L10n.string("shell.search.empty.title"),
                    systemImage: "radio",
                    description: Text(emptyDetail)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 8) {
                    if model.isSearching {
                        MacSearchUpdatingCard()
                    }

                    ForEach(model.searchResults) { station in
                        MacCompactStationCard(station: station)
                    }

                    if model.hasMoreSearchResults {
                        MacSearchLoadingCard(title: L10n.string("common.showMore"))
                            .opacity(model.isLoadingMoreSearchResults ? 1 : 0.01)
                            .onAppear {
                                Task { await model.loadMoreSearchResults() }
                            }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .environment(\.macStationPlaybackQueue, model.searchResults)
                .opacity(model.isSearching ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.16), value: model.isSearching)
            }
        }
    }

    private var discoveryModeBinding: Binding<TuneAVStationDiscoveryMode> {
        Binding(
            get: { model.searchDiscoveryMode },
            set: { mode in
                Task { await model.setSearchDiscoveryMode(mode) }
            }
        )
    }

    private var selectedCountryTitle: String {
        guard let code = TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) else {
            return L10n.string("shell.search.country.all")
        }

        return L10n.countryName(for: code)
    }

    private var selectedCountryFlag: String? {
        guard let code = TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) else { return nil }
        return TuneAVCountry(code: code, name: L10n.countryName(for: code)).flag
    }

    private var queryText: String {
        model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleTags: [String] {
        switch model.searchDiscoveryMode {
        case .music:
            return TuneAVMusicGenreCatalog.visibleTags
        case .allRadio:
            return TuneAVMusicGenreCatalog.visibleTags + ["news", "sports", "talk", "culture", "local", "public", "religion"]
        }
    }

    private var searchAviDetail: String {
        if model.searchDiscoveryMode == .allRadio {
            return L10n.string("shell.search.avi.detail.allRadio")
        }
        if let activeTag = model.activeSearchTag {
            return L10n.string("shell.search.avi.detail.genre", L10n.genreLabel(for: activeTag))
        }
        return L10n.string("shell.search.avi.detail.music")
    }

    private var emptyDetail: String {
        hasActiveFilters ? L10n.string("shell.search.empty.detail.retry") : L10n.string("shell.search.empty.detail.initial")
    }

    private var hasActiveFilters: Bool {
        !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            model.activeSearchTag != nil ||
            model.selectedSearchCountryCode != nil
    }
}

private struct MacSearchFilterPill: View {
    let title: String
    let flag: String?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 13, weight: .bold))

            Text(L10n.string("shell.search.country.label"))
                .font(.system(size: 13, weight: .bold))

            if let flag {
                Text(flag)
                    .font(.system(size: 15))
            }

            Text(title)
                .font(.system(size: 13, weight: .black))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .black))
        }
        .foregroundStyle(isActive ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(isActive ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(isActive ? TuneAVTheme.highlight.opacity(0.3) : TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }
}

private struct MacSearchUpdatingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.string("shell.search.updating.title"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MacSearchLoadingCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
            Spacer()
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }
}

private struct MacSearchCountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: TuneAVMacModel
    @Binding var query: String

    private var countries: [TuneAVCountry] {
        TuneAVCountry.filtered(TuneAVCountry.all(localizedName: L10n.countryName(for:)), query: query)
    }

    private var suggestedCountries: [TuneAVCountry] {
        let codes =
            [model.selectedSearchCountryCode, model.currentStation?.countryCode] +
            model.recentStations.compactMap(\.countryCode) +
            model.favoriteStations.compactMap(\.countryCode) +
            ["ES", "US", "GB", "FR", "DE", "IT", "MX", "AR"]
        let allCountries = TuneAVCountry.all(localizedName: L10n.countryName(for:))
        let lookup = Dictionary(uniqueKeysWithValues: allCountries.map { ($0.code, $0) })
        var seen = Set<String>()

        return codes
            .compactMap(TuneAVCountry.sanitizedCode)
            .filter { seen.insert($0).inserted }
            .compactMap { lookup[$0] }
            .prefix(8)
            .map { $0 }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MacSearchSheetSearchField(query: $query)

                    Button {
                        Task {
                            await model.setSearchCountryCode(nil)
                            dismiss()
                        }
                    } label: {
                        MacSearchCountryRow(
                            title: L10n.string("shell.search.country.all"),
                            subtitle: L10n.string("shell.search.country.allSubtitle"),
                            flag: nil,
                            isSelected: model.selectedSearchCountryCode == nil
                        )
                    }
                    .buttonStyle(.plain)

                    if trimmedQuery.isEmpty {
                        suggestedSection
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(countries) { country in
                            Button {
                                Task {
                                    await model.setSearchCountryCode(country.code)
                                    dismiss()
                                }
                            } label: {
                                MacSearchCountryRow(
                                    title: country.name,
                                    subtitle: country.code,
                                    flag: country.flag,
                                    isSelected: TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) == country.code
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 620, height: 680)
        .background(TuneAVTheme.shellBackground)
    }

    private var sheetHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(TuneAVTheme.highlight.opacity(0.14))
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("shell.search.country.pickerTitle"))
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.search.country.allSubtitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .frame(width: 32, height: 32)
                    .background(TuneAVTheme.cardSurface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(TuneAVTheme.textPrimary)
            .keyboardShortcut(.cancelAction)
            .help(L10n.string("shell.search.country.done"))
        }
        .padding(20)
    }

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("shell.search.country.suggested"))
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(suggestedCountries) { country in
                    Button {
                        Task {
                            await model.setSearchCountryCode(country.code)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if let flag = country.flag {
                                Text(flag)
                            }

                            Text(country.name)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            if TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) == country.code {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) == country.code ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                        .background(
                            TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) == country.code ? TuneAVTheme.highlight.opacity(0.11) : TuneAVTheme.cardSurface,
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(TuneAVCountry.sanitizedCode(model.selectedSearchCountryCode) == country.code ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct MacSearchSheetSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            TextField(L10n.string("shell.search.country.searchPrompt"), text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TuneAVTheme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isFocused ? TuneAVTheme.highlight.opacity(0.45) : TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct MacSearchCountryRow: View {
    let title: String
    let subtitle: String
    let flag: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.mutedSurface)

                if let flag {
                    Text(flag)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.highlight)
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(TuneAVTheme.highlight)
            }
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }
}
