enum HomePersonalStationSelector {
    static func select(from stations: [Station], excludingFeaturedID featuredStationID: String?, limit: Int) -> [Station] {
        let visibleStations: [Station]
        if let featuredStationID {
            visibleStations = stations.filter { $0.id != featuredStationID }
        } else {
            visibleStations = stations
        }

        return Array(visibleStations.prefix(limit))
    }
}
