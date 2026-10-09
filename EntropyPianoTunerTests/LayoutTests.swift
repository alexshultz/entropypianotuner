import XCTest
@testable import EntropyPianoTuner

final class LayoutTests: XCTestCase {
    func testKeyZeroIsA0AndA4IsKey48() {
        XCTAssertEqual(PianoLayout.keyCount, 88)
        XCTAssertEqual(PianoLayout.a4, 48)
        XCTAssertEqual(PianoLayout.label(0), "A0")
        XCTAssertEqual(PianoLayout.label(48), "A4")
        XCTAssertEqual(PianoLayout.label(87), "C8")
    }
}
