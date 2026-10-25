import CoreGraphics
import XCTest
@testable import typer

final class KeyboardInputTests: XCTestCase {
    func testEveryPrintableASCIICharacterHasAPhysicalKey() {
        for value in UInt32(32)...126 {
            let scalar = Unicode.Scalar(value)!
            XCTAssertNotNil(USKeyStroke.mapping[scalar], "Missing physical key for \(scalar)")
        }
        XCTAssertEqual(USKeyStroke.mapping["\n"]?.keyCode, 36)
        XCTAssertEqual(USKeyStroke.mapping["\t"]?.keyCode, 48)
    }

    func testReportedCharactersUseCorrectKeysAndShift() {
        let expected: [(Unicode.Scalar, CGKeyCode, Bool)] = [
            ("-", 27, false), ("D", 2, true), ("d", 2, false),
            ("|", 42, true), ("\\", 42, false),
            ("{", 33, true), ("[", 33, false),
            ("}", 30, true), ("]", 30, false)
        ]
        for (scalar, code, shift) in expected {
            XCTAssertEqual(USKeyStroke.mapping[scalar], USKeyStroke(keyCode: code, needsShift: shift))
        }
    }

    func testShiftWrapsThePhysicalKeyPress() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let input = try XCTUnwrap(KeyboardInput(scalar: "D", source: source))
        var events: [CGEvent] = []
        XCTAssertTrue(input.send(shouldContinue: { true }, post: { events.append($0) }, pause: {}))
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [56, 2, 2, 56])
        XCTAssertEqual(events.map { $0.flags.contains(.maskShift) }, [true, true, true, false])
    }

    func testFocusLossAfterShiftPressReleasesShiftWithoutTyping() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let input = try XCTUnwrap(KeyboardInput(scalar: "|", source: source))
        var events: [CGEvent] = []
        XCTAssertFalse(input.send(shouldContinue: { events.isEmpty }, post: { events.append($0) }, pause: {}))
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .flagsChanged])
        XCTAssertEqual(events.map { $0.flags.contains(.maskShift) }, [true, false])
    }

    func testFocusLossAfterKeyDownStillReleasesKeyAndShift() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let input = try XCTUnwrap(KeyboardInput(scalar: "{", source: source))
        var active = true
        var events: [CGEvent] = []
        XCTAssertFalse(input.send(shouldContinue: { active }, post: {
            events.append($0)
            if $0.type == .keyDown { active = false }
        }, pause: {}))
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertFalse(events.last!.flags.contains(.maskShift))
    }

    func testInactiveTargetReceivesNoEvents() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let input = try XCTUnwrap(KeyboardInput(scalar: "D", source: source))
        XCTAssertFalse(input.send(shouldContinue: { false }, post: { _ in XCTFail("Unexpected event") }, pause: {}))
    }

    func testUnshiftedKeysDoNotSendShiftEvents() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let input = try XCTUnwrap(KeyboardInput(scalar: "d", source: source))
        var events: [CGEvent] = []
        XCTAssertTrue(input.send(shouldContinue: { true }, post: { events.append($0) }, pause: {}))
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertTrue(events.allSatisfy { $0.flags.isEmpty })
    }
}
