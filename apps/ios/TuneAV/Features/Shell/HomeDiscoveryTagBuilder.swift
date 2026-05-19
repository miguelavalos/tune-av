enum HomeDiscoveryTagBuilder {
    static func build(from stations: [Station], stationLimit: Int) -> [String] {
        stations
            .prefix(stationLimit)
            .flatMap(\.normalizedTags)
            .map { $0.lowercased() }
    }
}
