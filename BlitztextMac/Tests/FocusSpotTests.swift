import ApplicationServices
import XCTest

final class FocusSpotTests: XCTestCase {
    private let field = AXUIElementCreateApplication(1)
    private let otherObject = AXUIElementCreateApplication(2)

    private func spot(_ element: AXUIElement, _ role: String?, _ position: CGPoint?) -> FocusedFieldReader.FocusSpot {
        FocusedFieldReader.FocusSpot(element: element, role: role, position: position)
    }

    func testSameObjectIsTheSameField() {
        XCTAssertTrue(spot(field, "AXTextArea", CGPoint(x: 10, y: 20)).isSameField(as: spot(field, "AXTextArea", CGPoint(x: 10, y: 80))))
    }

    func testRebuiltObjectInTheSamePlaceIsTheSameField() {
        // Some apps replace the field's accessibility object while it keeps the focus.
        XCTAssertTrue(spot(otherObject, "AXTextArea", CGPoint(x: 10, y: 20)).isSameField(as: spot(field, "AXTextArea", CGPoint(x: 10, y: 20))))
    }

    func testClickIntoAnotherFieldIsNoLongerTheSameField() {
        let start = spot(field, "AXTextArea", CGPoint(x: 10, y: 20))
        XCTAssertFalse(spot(otherObject, "AXTextArea", CGPoint(x: 10, y: 300)).isSameField(as: start))
        XCTAssertFalse(spot(otherObject, "AXButton", CGPoint(x: 10, y: 20)).isSameField(as: start))
    }
}
