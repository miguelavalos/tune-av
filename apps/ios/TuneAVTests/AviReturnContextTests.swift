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
        XCTAssertNil(request.mode)
        XCTAssertNil(request.overview)
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
}
