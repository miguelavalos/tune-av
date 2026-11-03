import XCTest
@testable import TuneAV

final class TuneAVSurpriseStationPickerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // Monday 2026-10-26 09:30 UTC, a morning.
    private lazy var now = date(day: 26, hour: 9, minute: 30)

    func testEmptyInputsPickNothing() {
        XCTAssertNil(pick(favorites: [], recentPlays: [], feedback: [:], popular: []))
    }

    func testNeverPicksTheCurrentStationOrNegativeFeedback() {
        let current = station("current")
        let disliked = station("disliked")
        let notForMe = station("notForMe")
        let feedback: [String: TuneAVStationFeedback] = [disliked.id: .disliked, notForMe.id: .notForMe]

        XCTAssertNil(
            pick(favorites: [current, disliked, notForMe], recentPlays: [], feedback: feedback, popular: [current, disliked, notForMe], currentStationID: current.id)
        )

        let fresh = station("fresh")
        let picked = pick(favorites: [current, disliked, notForMe, fresh], recentPlays: [], feedback: feedback, popular: [], currentStationID: current.id)
        XCTAssertEqual(picked?.station.id, fresh.id)
        XCTAssertEqual(picked?.reason, .savedFavorite)
    }

    func testFavoriteWithoutADatedPlayIsOnlyCalledSaved() {
        // Played before the play log existed, more than 14 days ago, or on another device:
        // Avi cannot know it was never played, so the reason must not say so.
        let favorite = station("favorite")

        let picked = pick(favorites: [favorite], recentPlays: [], playedStations: [favorite], feedback: [:], popular: [])

        XCTAssertEqual(picked?.station.id, favorite.id)
        XCTAssertEqual(picked?.reason, .savedFavorite)
        XCTAssertEqual(picked?.reasonKey, "shell.home.surprise.reason.favoriteSaved")
        XCTAssertEqual(picked?.reasonArguments, [favorite.name])
    }

    func testFavoriteMatchesItsPlaysByStreamWhenTheIDsDiffer() {
        let favorite = station("synced-favorite-id", stream: "shared")
        let playedCopy = station("local-recent-id", stream: "shared")
        let popular = station("popular", tags: "news")

        let playedYesterday = pick(
            favorites: [favorite],
            recentPlays: [play(playedCopy, daysAgo: 1, hour: 8)],
            feedback: [:],
            popular: [popular]
        )
        XCTAssertEqual(playedYesterday?.station.id, popular.id, "A favorite played yesterday under another id is not offered again")
        XCTAssertEqual(playedYesterday?.reason, .popular)

        let playedLastWeek = pick(
            favorites: [favorite],
            recentPlays: [play(playedCopy, daysAgo: 6, hour: 8)],
            feedback: [:],
            popular: [popular]
        )
        XCTAssertEqual(playedLastWeek?.station.id, favorite.id)
        XCTAssertEqual(playedLastWeek?.reason, .restedFavorite)
    }

    func testNewForYouSkipsRadiosPlayedWithoutADateOrAlreadySaved() {
        let favorite = station("favorite", tags: "rock")
        let undatedRecent = station("undated-recent", tags: "rock")
        let popularCopyOfFavorite = station("popular-copy", tags: "rock", stream: "favorite")
        let fresh = station("fresh", tags: "rock")

        let picked = pick(
            favorites: [favorite],
            recentPlays: [play(favorite, daysAgo: 0, hour: 8)],
            playedStations: [favorite, undatedRecent],
            feedback: [:],
            popular: [undatedRecent, popularCopyOfFavorite, fresh]
        )

        XCTAssertEqual(picked?.station.id, fresh.id)
        XCTAssertEqual(picked?.reason, .tag("rock"))
    }

    func testRestedFavoriteComesFirstAndTheOldestWins() {
        let restedFourDays = station("rested-4")
        let restedTenDays = station("rested-10")
        let playedYesterday = station("yesterday")
        let liked = station("liked")
        let plays = [
            play(restedFourDays, daysAgo: 4, hour: 9),
            play(restedTenDays, daysAgo: 10, hour: 9),
            play(playedYesterday, daysAgo: 1, hour: 9),
            play(liked, daysAgo: 1, hour: 9)
        ]

        let picked = pick(
            favorites: [playedYesterday, restedFourDays, restedTenDays],
            recentPlays: plays,
            feedback: [liked.id: .liked],
            popular: [station("popular", tags: "jazz")]
        )

        XCTAssertEqual(picked?.station.id, restedTenDays.id)
        XCTAssertEqual(picked?.reason, .restedFavorite)
        XCTAssertEqual(picked?.reasonKey, "shell.home.surprise.reason.favoriteRested")
    }

    func testLikedRecentFromTheSameHourBandComesBeforePopular() {
        let morningLiked = station("morning-liked", tags: "rock")
        let morningNeutral = station("morning-neutral", tags: "rock")
        let eveningLiked = station("evening-liked", tags: "rock")
        let plays = [
            play(morningLiked, daysAgo: 1, hour: 8),
            play(morningNeutral, daysAgo: 1, hour: 8),
            play(eveningLiked, daysAgo: 1, hour: 21)
        ]
        let feedback: [String: TuneAVStationFeedback] = [morningLiked.id: .liked, eveningLiked.id: .liked]

        let picked = pick(favorites: [], recentPlays: plays, feedback: feedback, popular: [station("popular", tags: "rock")])

        XCTAssertEqual(picked?.station.id, morningLiked.id)
        XCTAssertEqual(picked?.reason, .hourBand(.morning))
        XCTAssertEqual(picked?.reasonKey, "shell.home.surprise.reason.band.morning")
    }

    func testHourBandCandidateMustNotHavePlayedToday() {
        let morningLiked = station("morning-liked", tags: "rock")
        let plays = [
            play(morningLiked, daysAgo: 1, hour: 8),
            play(morningLiked, daysAgo: 0, hour: 7)
        ]
        let popular = station("popular", tags: "jazz,rock")

        let picked = pick(favorites: [], recentPlays: plays, feedback: [morningLiked.id: .liked], popular: [popular])

        XCTAssertEqual(picked?.station.id, popular.id)
        XCTAssertEqual(picked?.reason, .tag("rock"))
        XCTAssertEqual(picked?.reasonArguments, [popular.name, "rock"])
    }

    func testPopularStationMatchingTheMostCommonTagBeatsAnyPopularStation() {
        let recentJazz = station("recent-jazz", tags: "Jazz, Smooth")
        let favoriteJazz = station("favorite-jazz", tags: "jazz")
        let favoritePop = station("favorite-pop", tags: "pop")
        let plays = [play(recentJazz, daysAgo: 0, hour: 8), play(favoriteJazz, daysAgo: 0, hour: 8), play(favoritePop, daysAgo: 0, hour: 8)]
        let anyPopular = station("any-popular", tags: "news")
        let jazzPopular = station("jazz-popular", tags: "swing,jazz")

        let picked = pick(favorites: [favoriteJazz, favoritePop], recentPlays: plays, feedback: [:], popular: [anyPopular, jazzPopular])

        XCTAssertEqual(picked?.station.id, jazzPopular.id)
        XCTAssertEqual(picked?.reason, .tag("jazz"))
    }

    func testFallsBackToAnyPopularStationNotInRecents() {
        let recent = station("recent", tags: "rock")
        let popularRecent = station("recent", tags: "rock")
        let popularNew = station("new", tags: "news")

        let picked = pick(favorites: [], recentPlays: [play(recent, daysAgo: 0, hour: 8)], feedback: [:], popular: [popularRecent, popularNew])

        XCTAssertEqual(picked?.station.id, popularNew.id)
        XCTAssertEqual(picked?.reason, .popular)
        XCTAssertEqual(picked?.reasonKey, "shell.home.surprise.reason.popular")
    }

    func testHourBandsFollowTheDayParts() {
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 6), calendar: calendar), .morning)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 10, minute: 59), calendar: calendar), .morning)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 11), calendar: calendar), .midday)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 15), calendar: calendar), .afternoon)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 19), calendar: calendar), .evening)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 23, minute: 59), calendar: calendar), .evening)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 0), calendar: calendar), .night)
        XCTAssertEqual(TuneAVHourBand.band(for: date(day: 26, hour: 5, minute: 59), calendar: calendar), .night)
    }

    func testLocalizedReasonUsesTheGenreLabelForTags() {
        let pick = TuneAVSurprisePick(station: station("radio", tags: "jazz"), reason: .tag("jazz"))

        let reason = pick.localizedReason(genreLabel: { "Jazz label for \($0)" })

        XCTAssertEqual(reason, L10n.string("shell.home.surprise.reason.tag", "Station radio", "Jazz label for jazz"))
        XCTAssertEqual(pick.reasonKey, "shell.home.surprise.reason.tag")
    }

    func testPlayLogRemembersReturnsAndForgetsOldPlays() {
        var log = TuneAVStationPlayLog()
        log = log.recording("old", at: date(day: 1, hour: 8))
        for daysAgo in [3, 2, 1] {
            log = log.recording("habit", at: date(day: 26 - daysAgo, hour: 8))
        }
        log = log.recording("once", at: date(day: 25, hour: 8))

        let pruned = log.pruned(now: now)
        XCTAssertEqual(pruned.plays(for: "old"), [])
        XCTAssertEqual(pruned.plays(for: "habit").count, 3)

        let weekAgo = now.addingTimeInterval(-TuneAVStationPlayLog.returningWindow)
        XCTAssertEqual(pruned.mostPlayedStation(since: weekAgo)?.stationID, "habit")
        XCTAssertEqual(pruned.mostPlayedStation(since: weekAgo)?.count, 3)
        XCTAssertNil(TuneAVStationPlayLog().recording("once", at: now).mostPlayedStation(since: weekAgo))

        let habit = station("habit")
        let unknown = station("unknown")
        let plays = pruned.recentPlays(stations: [habit, unknown], lastPlayedByID: [unknown.id: date(day: 20, hour: 8)])
        XCTAssertEqual(plays.filter { $0.station.id == habit.id }.count, 3)
        XCTAssertEqual(plays.filter { $0.station.id == unknown.id }.map(\.playedAt), [date(day: 20, hour: 8)])
    }

    // MARK: - Helpers

    private func pick(
        favorites: [Station],
        recentPlays: [TuneAVRecentPlay],
        playedStations: [Station] = [],
        feedback: [String: TuneAVStationFeedback],
        popular: [Station],
        currentStationID: String? = nil
    ) -> TuneAVSurprisePick? {
        TuneAVSurpriseStationPicker.pick(
            favorites: favorites,
            recentPlays: recentPlays,
            playedStations: playedStations,
            feedback: feedback,
            popular: popular,
            now: now,
            currentStationID: currentStationID,
            calendar: calendar
        )
    }

    private func play(_ station: Station, daysAgo: Int, hour: Int) -> TuneAVRecentPlay {
        TuneAVRecentPlay(station: station, playedAt: date(day: 26 - daysAgo, hour: hour))
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func station(_ id: String, tags: String = "", stream: String? = nil) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            language: "Spanish",
            tags: tags,
            streamURL: "https://example.com/\(stream ?? id)"
        )
    }
}
