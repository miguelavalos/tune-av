enum HomeAviPickStationSelector {
    static func select(from stations: [Station], limit: Int) -> [Station] {
        Array(stations.prefix(limit))
    }
}
