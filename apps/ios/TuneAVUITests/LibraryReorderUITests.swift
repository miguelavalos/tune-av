import XCTest

@MainActor
final class LibraryReorderUITests: TuneAVUITestCase {
    /// The seeded library saves SomaFM Groove Salad first and BBC Radio 1 second, so Saved lists
    /// them in that order. Dragging BBC Radio 1 above Groove Salad in the reorder sheet puts it
    /// first in the Saved list.
    func testReorderingSavedRadiosChangesTheSavedListOrder() {
        let app = launchApp(preferredTab: "library")

        let savedCard = app.buttons["library.overview.saved"].firstMatch
        XCTAssertTrue(savedCard.waitForExistence(timeout: 5))
        savedCard.tap()

        let savedSection = app.otherElements["library.section.saved"].firstMatch
        XCTAssertTrue(savedSection.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSavedOrder(["groove-salad", "bbc-radio-1"], in: savedSection))

        let reorderButton = app.buttons["library.saved.reorder"].firstMatch
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 5))
        reorderButton.tap()

        let grooveSaladRow = app.descendants(matching: .any)["library.reorder.row.groove-salad"].firstMatch
        let bbcRow = app.descendants(matching: .any)["library.reorder.row.bbc-radio-1"].firstMatch
        XCTAssertTrue(bbcRow.waitForExistence(timeout: 5))
        XCTAssertTrue(grooveSaladRow.exists)
        XCTAssertLessThan(grooveSaladRow.frame.minY, bbcRow.frame.minY)

        let handle = reorderHandle(for: bbcRow, in: app)
        let destination = grooveSaladRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        handle.press(forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.4)

        let doneButton = app.buttons["library.reorder.done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(savedSection.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSavedOrder(["bbc-radio-1", "groove-salad"], in: savedSection))
    }

    /// The system reorder control of the row when it is exposed as its own button; otherwise the
    /// trailing edge of the row, where the handle is drawn.
    private func reorderHandle(for row: XCUIElement, in app: XCUIApplication) -> XCUICoordinate {
        let rowFrame = row.frame
        let handles = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Reorder' OR label BEGINSWITH[c] 'Reordenar'"))
            .allElementsBoundByIndex
        if let handle = handles.first(where: { abs($0.frame.midY - rowFrame.midY) < rowFrame.height / 2 }) {
            return handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        }
        return row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
    }

    private func waitForSavedOrder(_ expected: [String], in section: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var order = savedStationOrder(in: section)
        while order != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            order = savedStationOrder(in: section)
        }
        if order != expected {
            XCTFail("Saved order is \(order), expected \(expected)")
        }
        return order == expected
    }

    private func savedStationOrder(in section: XCUIElement) -> [String] {
        section.descendants(matching: .other)
            .matching(NSPredicate(format: "identifier MATCHES %@", "stationRow\\.[^.]+"))
            .allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { String($0.identifier.dropFirst("stationRow.".count)) }
    }
}
