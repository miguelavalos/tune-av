import XCTest
@testable import TuneAV

final class AviReturnContextTests: XCTestCase {
    func testCapturedLibraryContextBuildsRadioReturnRequest() throws {
        let context = try XCTUnwrap(AviReturnContext.captured(
            selectedTab: .library,
            existingContext: nil,
            radioMode: .recent,
            radioOverview: false,
            musicMode: .artists,
            musicOverview: true
        ))

        XCTAssertEqual(context.tab, .library)

        let request = try XCTUnwrap(context.radioReturnRequest)
        XCTAssertEqual(request.mode, .recent)
        XCTAssertEqual(request.overview, false)
        XCTAssertNil(context.musicReturnRequest)
    }

    func testCapturedMusicContextBuildsMusicReturnRequest() throws {
        let context = try XCTUnwrap(AviReturnContext.captured(
            selectedTab: .music,
            existingContext: nil,
            radioMode: .saved,
            radioOverview: true,
            musicMode: .history,
            musicOverview: false
        ))

        XCTAssertEqual(context.tab, .music)

        let request = try XCTUnwrap(context.musicReturnRequest)
        XCTAssertEqual(request.mode, .history)
        XCTAssertEqual(request.overview, false)
        XCTAssertNil(context.radioReturnRequest)
    }

    func testCapturedAviContextReusesExistingReturnTab() throws {
        let existingContext = try XCTUnwrap(AviReturnContext.captured(
            selectedTab: .library,
            existingContext: nil,
            radioMode: .tuned,
            radioOverview: true,
            musicMode: nil,
            musicOverview: nil
        ))

        let context = try XCTUnwrap(AviReturnContext.captured(
            selectedTab: .avi,
            existingContext: existingContext,
            radioMode: .saved,
            radioOverview: false,
            musicMode: .songs,
            musicOverview: false
        ))

        XCTAssertEqual(context.tab, .library)

        let request = try XCTUnwrap(context.radioReturnRequest)
        XCTAssertEqual(request.mode, .tuned)
        XCTAssertEqual(request.overview, true)
        XCTAssertNil(context.musicReturnRequest)
    }

    func testCapturedAviContextWithoutExistingReturnContextIsNil() {
        XCTAssertNil(AviReturnContext.captured(
            selectedTab: .avi,
            existingContext: nil,
            radioMode: .saved,
            radioOverview: true,
            musicMode: .songs,
            musicOverview: true
        ))
    }

    func testCoordinatorConsumesAndClearsRadioRestoreRequest() throws {
        var coordinator = AviReturnCoordinator()
        coordinator.capture(
            selectedTab: .library,
            radioMode: .tuned,
            radioOverview: true,
            musicMode: .songs,
            musicOverview: false
        )

        let restoreRequest = try XCTUnwrap(coordinator.consumeRestoreRequest())
        XCTAssertEqual(restoreRequest.tab, .library)

        let radioRequest = try XCTUnwrap(restoreRequest.radioReturnRequest)
        XCTAssertEqual(radioRequest.mode, .tuned)
        XCTAssertEqual(radioRequest.overview, true)
        XCTAssertNil(restoreRequest.musicReturnRequest)
        XCTAssertNil(coordinator.context)
        XCTAssertNil(coordinator.consumeRestoreRequest())
    }

    func testCoordinatorKeepsOriginalReturnContextWhenCapturingFromAvi() throws {
        var coordinator = AviReturnCoordinator()
        coordinator.capture(
            selectedTab: .music,
            radioMode: nil,
            radioOverview: nil,
            musicMode: .top,
            musicOverview: false
        )

        coordinator.capture(
            selectedTab: .avi,
            radioMode: .saved,
            radioOverview: true,
            musicMode: .songs,
            musicOverview: true
        )

        let restoreRequest = try XCTUnwrap(coordinator.consumeRestoreRequest())
        XCTAssertEqual(restoreRequest.tab, .music)

        let musicRequest = try XCTUnwrap(restoreRequest.musicReturnRequest)
        XCTAssertEqual(musicRequest.mode, .top)
        XCTAssertEqual(musicRequest.overview, false)
        XCTAssertNil(restoreRequest.radioReturnRequest)
    }
}
