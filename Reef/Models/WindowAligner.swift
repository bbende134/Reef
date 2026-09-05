//
//  WindowAligner.swift
//  Reef
//
//  Applies a WindowLayout to a real window through the Accessibility API.
//
//  The frame-writing strategy here — the size/position/size ordering, the
//  AXEnhancedUserInterface dance, and the assistive-technology carve-out — is ported
//  from Rectangle, and the hard-won knowledge is entirely theirs:
//
//      Rectangle — https://github.com/rxhanson/Rectangle
//      Copyright (c) 2019-2026 Ryan Hanson. MIT licensed.
//      Based on the Spectacle app, Copyright (c) 2017 Eric Czarny.
//

import Foundation
import Cocoa

/// Owns the cycling state and the pre-alignment frame history for one cycle panel.
@MainActor
final class WindowAligner {

    enum Outcome: Equatable {
        /// The window moved. Carries the layout actually applied, for the panel badge.
        case applied(WindowLayout)
        /// The window was put back where it started.
        case restored
        case refused(WindowAlignmentRefusal)
    }

    private var cycle = AlignmentCycleState()
    private var history = WindowFrameHistory()

    /// Breaks the repeat-press cycle. Called when the selection changes or the panel closes.
    func resetCycle() {
        cycle.reset()
    }

    /// Forgets remembered pre-alignment frames. Not called during normal operation —
    /// history intentionally outlives a single panel session so `R` still works after
    /// reopening the switcher.
    func resetHistory() {
        history.removeAll()
    }

    func perform(_ command: AlignmentCommand, on window: Window) -> Outcome {
        if let refusal = window.alignmentRefusal {
            return .refused(refusal)
        }

        guard let currentFrame = window.axFrame else {
            return .refused(.noFrame)
        }

        guard let screen = ScreenGeometry.screen(containingAXFrame: currentFrame) else {
            return .refused(.noScreen)
        }

        let bounds = ScreenGeometry.usableBoundsAX(of: screen)

        if case .restore = command {
            cycle.reset()
            guard let original = history.take(for: window.id) else {
                return .refused(.noHistory)
            }
            WindowFrameWriter.setFrame(original, on: window, within: bounds)
            return .restored
        }

        let layout: WindowLayout
        switch command {
        case .edge(let edge):
            layout = cycle.layout(for: .edge(edge))
        case .corner(let edge):
            layout = cycle.layout(for: .corner(edge))
        case .maximize:
            cycle.reset()
            layout = .maximize
        case .center:
            cycle.reset()
            layout = .center
        case .restore:
            // Handled above, before the layout is resolved.
            return .refused(.noHistory)
        }

        // Record-once, so a later restore returns to where the window was before the
        // *first* alignment rather than to the previous one.
        history.record(currentFrame, for: window.id)

        let target = layout.frame(in: bounds, current: currentFrame)
        WindowFrameWriter.setFrame(target, on: window, within: bounds)

        return .applied(layout)
    }
}

/// The Accessibility write itself, and the workarounds that make it land.
@MainActor
enum WindowFrameWriter {

    /// How aggressively to fight `AXEnhancedUserInterface`.
    enum EnhancedUIMode: String {
        case never, whenNeeded, always

        static var current: EnhancedUIMode {
            let raw = UserDefaults.standard.string(forKey: "alignmentEnhancedUIMode") ?? ""
            return EnhancedUIMode(rawValue: raw) ?? .whenNeeded
        }
    }

    /// Frames that differ by less than this are treated as equal — apps routinely land a
    /// fraction of a point off.
    private static let tolerance: CGFloat = 1.0

    /// Writes `target`, then verifies. Returns the frame the window actually ended up
    /// with, or nil if it could not be read back.
    @discardableResult
    static func setFrame(_ target: CGRect,
                         on window: Window,
                         within bounds: CGRect,
                         adjustSizeFirst: Bool = true) -> CGRect? {
        let element = window.element
        let appElement = window.applicationElement

        // Every Accessibility call here is synchronous on the main thread, and the
        // default timeout is seconds long. Scope a short one to just these elements so a
        // wedged app degrades to "nothing moved" rather than a beachball with Ctrl held.
        // (Set per-element deliberately: passing the system-wide element would change
        // timeouts for Reef's existing window-listing path too.)
        element.setMessagingTimeout(1.0)
        appElement?.setMessagingTimeout(1.0)

        withEnhancedUIDisabled(appElement: appElement) {
            // Shrink first so the destination screen's bounds cannot clamp the position
            // write; set size again afterwards for apps that resnap when the position
            // crosses a display boundary.
            if adjustSizeFirst {
                try? element.setAttributeValue(.size, target.size)
            }
            try? element.setAttributeValue(.position, target.origin)
            try? element.setAttributeValue(.size, target.size)
        }

        guard var achieved = element.axFrame else { return nil }

        // The app may have refused to shrink — Terminal snaps to its character grid,
        // Electron and Java apps enforce minimums. Keep the size it insisted on, but
        // slide it back inside the usable area so it is not hanging off an edge.
        let missedSize = achieved.width > target.width + tolerance
            || achieved.height > target.height + tolerance
        let missedOrigin = abs(achieved.minX - target.minX) > tolerance
            || abs(achieved.minY - target.minY) > tolerance

        if missedSize || missedOrigin {
            var origin = achieved.origin
            // min-then-max: a window wider than the bounds ends up flush against the
            // leading edge and overflowing trailing, rather than hanging off the far side.
            origin.x = min(origin.x, bounds.maxX - achieved.width)
            origin.y = min(origin.y, bounds.maxY - achieved.height)
            origin.x = max(origin.x, bounds.minX)
            origin.y = max(origin.y, bounds.minY)

            if origin != achieved.origin {
                withEnhancedUIDisabled(appElement: appElement) {
                    try? element.setAttributeValue(.position, origin)
                }
                achieved = element.axFrame ?? CGRect(origin: origin, size: achieved.size)
            }
        }

        // Exactly one corrective pass, never a loop: some apps apply frame changes
        // asynchronously, so the read-back can legitimately show the old frame and a
        // retry would fight itself while blocking the main thread with Ctrl held.
        return achieved
    }

    /// Runs `body` with `AXEnhancedUserInterface` forced off, restoring it afterwards.
    ///
    /// While that attribute is set, Chromium and Electron apps animate or ignore frame
    /// writes. It is also how AppKit signals that a screen reader is listening, so when
    /// VoiceOver or Switch Control is actually running we leave it strictly alone —
    /// a cosmetic animation is not worth degrading a real assistive-technology session.
    private static func withEnhancedUIDisabled(appElement: AXUIElement?, _ body: () -> Void) {
        let mode = EnhancedUIMode.current
        let assistiveTechActive = NSWorkspace.shared.isVoiceOverEnabled
            || NSWorkspace.shared.isSwitchControlEnabled

        var mustRestore = false

        if mode != .never, !assistiveTechActive, let appElement {
            let isEnabled: Bool? = appElement.getAttributeValue(.enhancedUserInterface)
            if mode == .always || isEnabled == true {
                try? appElement.setAttributeValue(.enhancedUserInterface, false)
                mustRestore = (isEnabled == true)
            }
        }

        body()

        if mustRestore, let appElement {
            try? appElement.setAttributeValue(.enhancedUserInterface, true)
        }
    }
}
