//
//  AlignmentKeyMap.swift
//  Reef
//
//  Turns a keystroke arriving at the open cycle panel into an AlignmentCommand.
//
//  Note that Ctrl+arrow never reaches an application on a stock Mac: all four are
//  Mission Control symbolic hot keys (Mission Control, Application Windows, and move
//  left/right a space), which the WindowServer consumes before app delivery. The arrow
//  cases below are therefore wired but dormant, and the letters are the real map. They
//  become live for anyone who turns those four off in System Settings.
//

import Foundation
import AppKit

enum AlignmentKeyMap {

    /// A keystroke, reduced to just what the map cares about.
    ///
    /// Deliberately free of `NSEvent` so `command(for:)` is a pure function that tests
    /// can drive directly.
    struct Chord: Equatable {
        let keyCode: UInt16
        /// `charactersIgnoringModifiers`, lowercased. Nil for keys with no character.
        let character: Character?
        /// Whether the "give me a quarter instead of a half" modifier was held.
        let hasCornerModifier: Bool

        init(keyCode: UInt16, character: Character?, hasCornerModifier: Bool) {
            self.keyCode = keyCode
            self.character = character
            self.hasCornerModifier = hasCornerModifier
        }
    }

    // Virtual key codes, from HIToolbox/Events.h. Physical positions, so layout-invariant
    // — which is what you want for keys that carry no character.
    static let keyCodeLeftArrow: UInt16 = 123
    static let keyCodeRightArrow: UInt16 = 124
    static let keyCodeDownArrow: UInt16 = 125
    static let keyCodeUpArrow: UInt16 = 126
    static let keyCodeEscape: UInt16 = 53

    /// The modifiers worth reasoning about. Arrow events also carry `.numericPad` and
    /// `.function`, so a bare `modifierFlags == [...]` comparison would never match.
    static let interestingModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Which modifier means "quarter", given the chord the user holds to open the panel.
    ///
    /// If the activate chord already contains Option — it does not by default, but it is
    /// user-configurable — then Option is held throughout and every plain `H` would read
    /// as a corner request, making the halves unreachable. Falling through keeps both
    /// available.
    static func cornerModifier(base: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        for candidate in [NSEvent.ModifierFlags.option, .shift, .command] where !base.contains(candidate) {
            return candidate
        }
        return .option
    }

    /// AppKit glue. Returns nil for keystrokes carrying modifiers the map does not
    /// understand, so those fall through to normal handling untouched.
    static func chord(from event: NSEvent, base: NSEvent.ModifierFlags) -> Chord? {
        let flags = event.modifierFlags.intersection(interestingModifiers)
        let extra = flags.subtracting(base)
        let corner = cornerModifier(base: base)

        guard extra.isEmpty || extra == corner else { return nil }

        let character = event.charactersIgnoringModifiers?.lowercased().first

        return Chord(keyCode: event.keyCode,
                     character: character,
                     hasCornerModifier: extra == corner)
    }

    /// Pure. The unit-tested core of the map.
    static func command(for chord: Chord) -> AlignmentCommand? {
        if let edge = edge(for: chord) {
            return chord.hasCornerModifier ? .corner(edge) : .edge(edge)
        }

        // Maximise, centre and restore take no corner modifier.
        guard !chord.hasCornerModifier, let character = chord.character else { return nil }

        switch character {
        case "m": return .maximize
        case "c": return .center
        case "r": return .restore
        default: return nil
        }
    }

    /// Arrows match by key code; letters match by character so they follow the keycap
    /// rather than the physical position — which matters on any non-QWERTY layout.
    private static func edge(for chord: Chord) -> LayoutEdge? {
        switch chord.keyCode {
        case keyCodeLeftArrow: return .left
        case keyCodeRightArrow: return .right
        case keyCodeUpArrow: return .top
        case keyCodeDownArrow: return .bottom
        default: break
        }

        switch chord.character {
        case "h": return .left
        case "l": return .right
        case "k": return .top
        case "j": return .bottom
        default: return nil
        }
    }
}
