enum HomeAroundYouStationSelector {
    static func select(
        from stations: [Station],
        aviPickStations: [Station],
        preferredCountryCode: String?,
        currentCountryCode: String?,
        fallbackStartOffset: Int,
        limit: Int
    ) -> [Station] {
        let preferredCountry = TuneAVCountry.sanitizedCode(preferredCountryCode)
        let currentCountry = TuneAVCountry.sanitizedCode(currentCountryCode)
        let country = preferredCountry ?? currentCountry

        guard let country else {
            return Array(stations.dropFirst(fallbackStartOffset).prefix(limit))
        }

        return select(
            from: stations,
            excluding: Set(aviPickStations.map(\.id)),
            countryCode: country,
            limit: limit
        )
    }

    static func select(
        from stations: [Station],
        excluding excludedIDs: Set<String>,
        countryCode: String,
        limit: Int
    ) -> [Station] {
        let remainingStations = stations.filter { !excludedIDs.contains($0.id) }
        let countryStations = remainingStations.filter { station in
            TuneAVCountry.sanitizedCode(station.countryCode) == countryCode
        }

        return Array((countryStations.isEmpty ? remainingStations : countryStations).prefix(limit))
    }
}
