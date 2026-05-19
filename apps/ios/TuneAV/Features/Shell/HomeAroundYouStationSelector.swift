enum HomeAroundYouStationSelector {
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
