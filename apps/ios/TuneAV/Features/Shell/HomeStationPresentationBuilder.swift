import Foundation

struct HomeStationPresentation: Equatable {
    enum Tier: Equatable {
        case rich
        case fallback
    }

    let tier: Tier
    let label: String
    let title: String
    let primaryLine: String?
    let secondaryLine: String?
    let badges: [String]
}

enum HomeStationPresentationBuilder {
    static func build(
        station: Station,
        source: HomeFeaturedStationSource?,
        isCurrentStation: Bool,
        currentTrackTitle: String?,
        currentTrackArtist: String?,
        feedContext: HomeFeedContext
    ) -> HomeStationPresentation {
        let currentTrack = currentTrackLine(
            station: station,
            isCurrentStation: isCurrentStation,
            currentTrackTitle: currentTrackTitle,
            currentTrackArtist: currentTrackArtist
        )
        let context = stationContextLine(for: station)
        let hasReliableProgramData = currentTrack != nil
        let badges = hasReliableProgramData ? [stationCategoryLabel(for: station)].compactMap { $0 }.prefix(2).map { $0 } : []

        return HomeStationPresentation(
            tier: hasReliableProgramData ? .rich : .fallback,
            label: heroLabel(source: source, station: station, isCurrentStation: isCurrentStation, feedContext: feedContext),
            title: station.name,
            primaryLine: currentTrack ?? context,
            secondaryLine: currentTrack == nil ? nil : context,
            badges: badges
        )
    }

    private static func currentTrackLine(
        station: Station,
        isCurrentStation: Bool,
        currentTrackTitle: String?,
        currentTrackArtist: String?
    ) -> String? {
        guard isCurrentStation else { return nil }
        guard let title = TuneAVDisplayMetadata.normalized(currentTrackTitle) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: station.name) else { return nil }

        if
            let artist = TuneAVDisplayMetadata.normalized(currentTrackArtist),
            !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: station.name)
        {
            return "\(artist) · \(title)"
        }

        return title
    }

    private static func stationContextLine(for station: Station) -> String? {
        let country = localizedCountryName(for: station).map { country in
            if let flag = station.flagEmoji {
                return "\(flag) \(country)"
            }
            return country
        }
        let language = cleanedFeaturedDetail(station.language)
        let values = [country, language]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }

        guard !values.isEmpty else { return nil }
        return values.prefix(2).joined(separator: " · ")
    }

    private static func cleanedFeaturedDetail(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }

    private static func localizedCountryName(for station: Station) -> String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return cleanedFeaturedDetail(station.country)
    }

    private static func stationCategoryLabel(for station: Station) -> String? {
        let tags = station.tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let preferredTags = ["music", "pop", "rock", "jazz", "news", "talk", "sports", "classical", "electronic", "latin", "ambient", "country"]
        if let tag = tags.first(where: { tag in preferredTags.contains { tag.localizedCaseInsensitiveContains($0) } }) {
            return tag.capitalized(with: L10n.locale)
        }

        return nil
    }

    private static func heroLabel(
        source: HomeFeaturedStationSource?,
        station: Station,
        isCurrentStation: Bool,
        feedContext: HomeFeedContext
    ) -> String {
        if isCurrentStation {
            return L10n.string("shell.liveNow.title")
        }

        switch source {
        case .favorite:
            return L10n.string("shell.home.favorites.title")
        case .lastPlayed:
            return L10n.string("shell.home.featured.continueListening")
        case .recent:
            return L10n.string("shell.home.recents.title")
        case .current:
            return L10n.string("shell.liveNow.title")
        case .popular, .none:
            return featuredLabel(source: source, feedContext: feedContext)
        }
    }

    private static func featuredLabel(source: HomeFeaturedStationSource?, feedContext: HomeFeedContext) -> String {
        switch source {
        case .recent:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .favorite:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .current:
            return L10n.string("shell.liveNow.title").uppercased(with: .current)
        case .lastPlayed:
            return L10n.string("shell.home.featured.continueListening").uppercased(with: .current)
        case .popular, .none:
            break
        }

        switch feedContext {
        case .preferredGenre:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .popularInCountry(let countryCode):
            let countryName = L10n.countryName(for: countryCode)
            return countryName.uppercased(with: .current)
        case .popularWorldwide:
            return L10n.string("shell.home.featured.popular").uppercased(with: .current)
        }
    }
}
