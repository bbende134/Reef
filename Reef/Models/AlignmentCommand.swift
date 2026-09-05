//
//  AlignmentCommand.swift
//  Reef
//
//  What a keypress asks for, and the repeat-press cycling state machine.
//  Pure: no AppKit, no Accessibility.
//

import Foundation

/// A user request, before it is resolved into a concrete `WindowLayout`.
///
/// `edge` and `corner` are deliberately *not* layouts: pressing `H` twice means two
/// different things, so the resolution needs `AlignmentCycleState`.
enum AlignmentCommand: Equatable {
    /// Half the screen on this edge; repeat presses cycle ½ → ⅓ → ⅔.
    case edge(LayoutEdge)
    /// A quarter on this edge; repeat presses cycle the two corners it touches.
    case corner(LayoutEdge)
    case maximize
    case center
    /// Put the window back where it was before Reef first moved it.
    case restore
}

/// Tracks what the previous alignment press asked for, so a repeat can advance.
///
/// Deliberately does **not** track window identity. The selected window can only change
/// via `CyclePanelController.showSwitcher(for:startIndex:)` or `cycleNext()`, and the
/// controller calls `reset()` at both — which keeps this a handful of pure lines instead
/// of a cache that has to be invalidated correctly.
struct AlignmentCycleState: Equatable {
    /// What is being cycled. A change of group restarts at step 0.
    enum Group: Equatable {
        case edge(LayoutEdge)
        case corner(LayoutEdge)
    }

    private var group: Group?
    private var step: Int = 0

    init() {}

    /// Advances the cycle if `group` matches the last call, otherwise restarts it.
    mutating func layout(for group: Group) -> WindowLayout {
        if group == self.group {
            step += 1
        } else {
            self.group = group
            step = 0
        }
        return AlignmentCycleState.layout(for: group, step: step)
    }

    /// Breaks the cycle, so the next edge press starts at ½ again.
    ///
    /// Called when the selection changes, the panel closes, or a non-cycling command
    /// (maximise / centre / restore) runs.
    mutating func reset() {
        group = nil
        step = 0
    }

    /// Pure resolution — testable without driving the mutating interface.
    static func layout(for group: Group, step: Int) -> WindowLayout {
        switch group {
        case .edge(let edge):
            let fractions = LayoutFraction.cycle
            return .edge(edge, fractions[wrapped(step, count: fractions.count)])
        case .corner(let edge):
            let corners = AlignmentCycleState.corners(on: edge)
            return .corner(corners[wrapped(step, count: corners.count)])
        }
    }

    /// The two quarters that touch a given edge, in the order repeat presses walk them.
    static func corners(on edge: LayoutEdge) -> [LayoutCorner] {
        switch edge {
        case .left:   return [.topLeft, .bottomLeft]
        case .right:  return [.topRight, .bottomRight]
        case .top:    return [.topLeft, .topRight]
        case .bottom: return [.bottomLeft, .bottomRight]
        }
    }

    /// `%` on a negative Int is negative in Swift; step is never negative here, but this
    /// keeps the subscript total regardless.
    private static func wrapped(_ step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let r = step % count
        return r < 0 ? r + count : r
    }
}
