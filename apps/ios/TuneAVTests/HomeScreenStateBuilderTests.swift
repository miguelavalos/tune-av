import XCTest
@testable import TuneAV

final class HomeScreenStateBuilderTests: XCTestCase {
    func testBuildsCurrentStationHeroState() {
        let current = makeStation(id: "current", tags: "pop, hits")
        let recent = makeStation(id: "recent", tags: "news")

        let state = HomeScreenStateBuilder.build(
            stations: [recent],
            isLoading: false,
            errorMessage: nil,
            recentStations: [recent],
            favoriteStations: [],
            lastPlayedStation: nil,
            discoveries: [],
            stationFeedback: [current.id: .liked],
            feedContext: .popularWorldwide,
            preferredTag: "",
            preferredCountryCode: "ES",
            favoriteStationIDs: [current.id],
            currentStation: current,
            playbackStatusLabel: "Playing",
            isCurrentStation: { $0.id == current.id },
            isPlaying: true,
            isStationLoading: true,
            currentTrackTitle: "Current Song",
            currentTrackArtist: "Current Artist"
        )

        XCTAssertEqual(state.featuredState.source, .current)
        XCTAssertEqual(state.heroContentState.station?.id, current.id)
        XCTAssertEqual(state.heroContentState.presentation?.title, current.name)
        XCTAssertEqual(state.heroContentState.presentation?.primaryLine, "Current Artist · Current Song")
        XCTAssertTrue(state.heroContentState.isFavorite)
        XCTAssertTrue(state.heroContentState.isCurrentStation)
        XCTAssertTrue(state.heroContentState.isPlaying)
        XCTAssertTrue(state.heroContentState.isStationLoading)
        XCTAssertEqual(state.heroContentState.stationFeedback, .liked)
        XCTAssertEqual(state.headerContentState.statusTitle, "Playing")
        XCTAssertFalse(state.derivedState.displayedRecentStations.map(\.id).contains(current.id))
    }

    func testBuildsLastPlayedHeroWithoutCurrentPlaybackFlags() {
        let lastPlayed = makeStation(id: "last-played", tags: "jazz")
        let favorite = makeStation(id: "favorite", tags: "rock")
        let popular = makeStation(id: "popular", tags: "pop")

        let state = HomeScreenStateBuilder.build(
            stations: [popular],
            isLoading: true,
            errorMessage: "Offline",
            recentStations: [lastPlayed],
            favoriteStations: [favorite],
            lastPlayedStation: lastPlayed,
            discoveries: [],
            stationFeedback: [:],
            feedContext: .popularWorldwide,
            preferredTag: "",
            preferredCountryCode: "ES",
            favoriteStationIDs: [favorite.id],
            currentStation: nil,
            playbackStatusLabel: "Stopped",
            isCurrentStation: { _ in false },
            isPlaying: true,
            isStationLoading: true,
            currentTrackTitle: nil,
            currentTrackArtist: nil
        )

        XCTAssertEqual(state.featuredState.source, .lastPlayed)
        XCTAssertEqual(state.heroContentState.station?.id, lastPlayed.id)
        XCTAssertEqual(state.heroContentState.errorMessage, "Offline")
        XCTAssertFalse(state.heroContentState.isFavorite)
        XCTAssertFalse(state.heroContentState.isCurrentStation)
        XCTAssertFalse(state.heroContentState.isPlaying)
        XCTAssertFalse(state.heroContentState.isStationLoading)
        XCTAssertEqual(state.headerContentState.statusTitle, L10n.string("shell.status.refreshing"))
        XCTAssertEqual(state.derivedState.displayedFavoriteStations.map(\.id), [favorite.id])
    }

    private func makeStation(id: String, tags: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            language: "Spanish",
            tags: tags,
            streamURL: "https://example.com/\(id)"
        )
    }
}
