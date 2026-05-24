import XCTest
@testable import TuneAVMac

final class TuneAVMacSmokeTests: XCTestCase {
    func testStationSamplesAreAvailable() {
        XCTAssertFalse(Station.samples.isEmpty)
    }
}
