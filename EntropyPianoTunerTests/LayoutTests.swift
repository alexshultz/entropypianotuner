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

    func testWhiteKeysMeetTheDefaultHitWidth() {
        XCTAssertGreaterThanOrEqual(PianoLayout.whiteKeyWidth, 44)
        XCTAssertGreaterThan(PianoLayout.whiteKeyHeight, PianoLayout.whiteKeyWidth)
    }

    func testBlackKeysStayNarrowerAndCenteredOnTheGap() {
        XCTAssertGreaterThanOrEqual(PianoLayout.blackKeyWidth, 28)
        XCTAssertLessThan(PianoLayout.blackKeyWidth, PianoLayout.whiteKeyWidth)
        XCTAssertEqual(
            PianoLayout.blackKeyOffset - PianoLayout.blackKeyWidth / 2,
            PianoLayout.keySpacing / 2
        )
    }

    func testPitchVerdictUsesAOneCentBand() {
        XCTAssertEqual(PitchVerdict.from(cents: nil), .listening)
        XCTAssertEqual(PitchVerdict.from(cents: 0), .inTune)
        XCTAssertEqual(PitchVerdict.from(cents: 0.9), .inTune)
        XCTAssertEqual(PitchVerdict.from(cents: -0.9), .inTune)
        XCTAssertEqual(PitchVerdict.from(cents: -1), .flat)
        XCTAssertEqual(PitchVerdict.from(cents: 1), .sharp)
        XCTAssertEqual(PitchVerdict.flat.label, "Flat")
        XCTAssertEqual(PitchVerdict.sharp.label, "Sharp")
        XCTAssertEqual(PitchVerdict.inTune.label, "In tune")
        XCTAssertEqual(PitchVerdict.listening.label, "Listening")
    }
}
