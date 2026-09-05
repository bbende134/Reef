import Testing
import AppKit
@testable import Reef

struct AlignmentKeyMapTests {

    private func chord(_ keyCode: UInt16, _ character: Character?, corner: Bool = false) -> AlignmentKeyMap.Chord {
        AlignmentKeyMap.Chord(keyCode: keyCode, character: character, hasCornerModifier: corner)
    }

    // kVK_ANSI_H / L / K / J / M / C / R
    private let h: UInt16 = 4, l: UInt16 = 37, k: UInt16 = 40, j: UInt16 = 38
    private let m: UInt16 = 46, c: UInt16 = 8, r: UInt16 = 15

    // MARK: - Letters

    @Test func vimLettersMapToHalves() {
        #expect(AlignmentKeyMap.command(for: chord(h, "h")) == .edge(.left))
        #expect(AlignmentKeyMap.command(for: chord(l, "l")) == .edge(.right))
        #expect(AlignmentKeyMap.command(for: chord(k, "k")) == .edge(.top))
        #expect(AlignmentKeyMap.command(for: chord(j, "j")) == .edge(.bottom))
    }

    @Test func cornerModifierTurnsHalvesIntoQuarters() {
        #expect(AlignmentKeyMap.command(for: chord(h, "h", corner: true)) == .corner(.left))
        #expect(AlignmentKeyMap.command(for: chord(j, "j", corner: true)) == .corner(.bottom))
    }

    @Test func standaloneCommands() {
        #expect(AlignmentKeyMap.command(for: chord(m, "m")) == .maximize)
        #expect(AlignmentKeyMap.command(for: chord(c, "c")) == .center)
        #expect(AlignmentKeyMap.command(for: chord(r, "r")) == .restore)
    }

    @Test func standaloneCommandsRejectTheCornerModifier() {
        #expect(AlignmentKeyMap.command(for: chord(m, "m", corner: true)) == nil)
        #expect(AlignmentKeyMap.command(for: chord(c, "c", corner: true)) == nil)
        #expect(AlignmentKeyMap.command(for: chord(r, "r", corner: true)) == nil)
    }

    /// Letters are matched by character, so they follow the keycap rather than the
    /// physical key — which is what keeps the map right across QWERTY and QWERTZ.
    @Test func lettersMatchByCharacterNotKeyCode() {
        // Same character reached from a different physical key still means "left half".
        #expect(AlignmentKeyMap.command(for: chord(99, "h")) == .edge(.left))
        // And the right physical key with a different character does not.
        #expect(AlignmentKeyMap.command(for: chord(h, "ő")) == nil)
    }

    // MARK: - Arrows

    @Test func arrowsMapToTheSameHalves() {
        #expect(AlignmentKeyMap.command(for: chord(AlignmentKeyMap.keyCodeLeftArrow, nil)) == .edge(.left))
        #expect(AlignmentKeyMap.command(for: chord(AlignmentKeyMap.keyCodeRightArrow, nil)) == .edge(.right))
        #expect(AlignmentKeyMap.command(for: chord(AlignmentKeyMap.keyCodeUpArrow, nil)) == .edge(.top))
        #expect(AlignmentKeyMap.command(for: chord(AlignmentKeyMap.keyCodeDownArrow, nil)) == .edge(.bottom))
    }

    @Test func arrowsTakeTheCornerModifierToo() {
        #expect(AlignmentKeyMap.command(for: chord(AlignmentKeyMap.keyCodeUpArrow, nil, corner: true)) == .corner(.top))
    }

    // MARK: - Non-commands

    @Test func digitsAreNotAlignmentKeys() {
        // Reef's own Ctrl+digit bindings must keep cycling the window selection.
        for (code, character) in [(UInt16(18), Character("1")), (UInt16(29), Character("0"))] {
            #expect(AlignmentKeyMap.command(for: chord(code, character)) == nil)
        }
    }

    @Test func unknownKeysFallThrough() {
        #expect(AlignmentKeyMap.command(for: chord(999, nil)) == nil)
        #expect(AlignmentKeyMap.command(for: chord(0, "q")) == nil)
    }

    // MARK: - Corner modifier selection

    @Test func cornerModifierIsOptionByDefault() {
        #expect(AlignmentKeyMap.cornerModifier(base: [.control]) == .option)
    }

    /// If Option is part of the chord that opens the panel it is held throughout, so it
    /// cannot also mean "quarter" — otherwise the halves become unreachable.
    @Test func cornerModifierAvoidsTheActivateChord() {
        #expect(AlignmentKeyMap.cornerModifier(base: [.control, .option]) == .shift)
        #expect(AlignmentKeyMap.cornerModifier(base: [.control, .option, .shift]) == .command)
    }
}
