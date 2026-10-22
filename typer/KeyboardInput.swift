import CoreGraphics
import Foundation

struct USKeyStroke: Equatable {
    let keyCode: CGKeyCode
    let needsShift: Bool

    static let mapping: [Unicode.Scalar: USKeyStroke] = {
        // Physical macOS ANSI keycodes, independent of the local input source.
        let rows: [(String, String, [CGKeyCode])] = [
            ("`1234567890-=", "~!@#$%^&*()_+", [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]),
            ("qwertyuiop[]\\", "QWERTYUIOP{}|", [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42]),
            ("asdfghjkl;'", "ASDFGHJKL:\"", [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39]),
            ("zxcvbnm,./", "ZXCVBNM<>?", [6, 7, 8, 9, 11, 45, 46, 43, 47, 44])
        ]
        var result: [Unicode.Scalar: USKeyStroke] = [:]
        for (plain, shifted, codes) in rows {
            for (scalar, code) in zip(plain.unicodeScalars, codes) {
                result[scalar] = USKeyStroke(keyCode: code, needsShift: false)
            }
            for (scalar, code) in zip(shifted.unicodeScalars, codes) {
                result[scalar] = USKeyStroke(keyCode: code, needsShift: true)
            }
        }
        result[" "] = USKeyStroke(keyCode: 49, needsShift: false)
        result["\n"] = USKeyStroke(keyCode: 36, needsShift: false)
        result["\t"] = USKeyStroke(keyCode: 48, needsShift: false)
        return result
    }()
}

struct KeyboardInput {
    let keyDown: CGEvent
    let keyUp: CGEvent
    let shiftDown: CGEvent?
    let shiftUp: CGEvent?

    init?(scalar: Unicode.Scalar, source: CGEventSource) {
        let stroke = USKeyStroke.mapping[scalar]
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: stroke?.keyCode ?? 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: stroke?.keyCode ?? 0, keyDown: false) else {
            return nil
        }
        let shifted = stroke?.needsShift == true
        down.flags = shifted ? .maskShift : []
        up.flags = shifted ? .maskShift : []

        if stroke == nil {
            // Keep Unicode support for local apps. Send complete scalars so that
            // supplementary characters are not split into unrelated surrogates.
            let units = Array(String(scalar).utf16)
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
        }

        if shifted {
            guard let press = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: true),
                  let release = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: false) else {
                return nil
            }
            press.type = .flagsChanged
            release.type = .flagsChanged
            press.flags = .maskShift
            release.flags = []
            shiftDown = press
            shiftUp = release
        } else {
            shiftDown = nil
            shiftUp = nil
        }
        keyDown = down
        keyUp = up
    }

    // Injectable delivery lets tests verify cancellation without typing into apps.
    func send(
        shouldContinue: () -> Bool,
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.01) }
    ) -> Bool {
        guard shouldContinue() else { return false }
        if let shiftDown {
            post(shiftDown)
            pause()
        }
        defer {
            if let shiftUp {
                post(shiftUp)
                pause()
            }
        }
        guard shouldContinue() else { return false }
        post(keyDown)
        pause()
        // Always release a key already sent, even if focus changed while held.
        post(keyUp)
        pause()
        return shouldContinue()
    }
}
