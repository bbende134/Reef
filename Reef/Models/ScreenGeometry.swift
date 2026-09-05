//
//  ScreenGeometry.swift
//  Reef
//
//  The one place Cocoa screen coordinates become Accessibility coordinates.
//
//  Cocoa/NSScreen: origin at the bottom-left of the primary display, y increases upward.
//  Accessibility:  origin at the top-left of that same display, y increases downward.
//
//  The pure half takes `primaryMaxY` as a parameter rather than reading NSScreen, which
//  is what makes the conversion testable without a display attached.
//

import Foundation
import CoreGraphics
import AppKit

enum ScreenGeometry {

    // MARK: - Pure

    /// Converts a rect between Cocoa and Accessibility space.
    ///
    /// Self-inverse: `flipped(flipped(r, m), m) == r`.
    static func flipped(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return rect }
        return CGRect(x: rect.origin.x,
                      y: primaryMaxY - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }

    /// Converts a point between Cocoa and Accessibility space. Self-inverse.
    static func flipped(_ point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    /// Picks the screen a window belongs to. All rects in the *same* space (Cocoa).
    ///
    /// Order matters: full containment wins outright, then largest overlap, then the
    /// screen under the rect's centre — the last case catches windows reported with a
    /// degenerate (zero-area) frame, which some apps do transiently.
    static func indexOfScreen(containing rect: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        if let index = screenFrames.firstIndex(where: { $0.contains(rect) }) {
            return index
        }

        var best: (index: Int, area: CGFloat)?
        for (index, frame) in screenFrames.enumerated() {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        if let best, best.area > 0 { return best.index }

        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let index = screenFrames.firstIndex(where: { $0.contains(centre) }) {
            return index
        }

        return nil
    }

    /// Shrinks a Cocoa-space rect so it clears a notch, given the screen's top safe inset.
    ///
    /// Lowers `maxY` and leaves the bottom edge pinned.
    static func clampedForSafeArea(_ visible: CGRect, screenFrame: CGRect, safeAreaTop: CGFloat) -> CGRect {
        guard safeAreaTop > 0 else { return visible }
        let safeMaxY = screenFrame.maxY - safeAreaTop
        guard visible.maxY > safeMaxY else { return visible }
        var clamped = visible
        clamped.size.height -= (visible.maxY - safeMaxY)
        return clamped
    }

    // MARK: - AppKit readers

    /// The reference for every flip: the top of the "zero" screen.
    @MainActor
    static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// The screen a window is on, given its AX-space frame.
    ///
    /// Falls back to the screen the user is looking at — while the cycle panel is key,
    /// `NSScreen.main` is the panel's screen, which is a good default.
    @MainActor
    static func screen(containingAXFrame axFrame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let cocoa = flipped(axFrame, primaryMaxY: primaryMaxY)
        if let index = indexOfScreen(containing: cocoa, screenFrames: screens.map(\.frame)) {
            return screens[index]
        }
        return NSScreen.main ?? screens.first
    }

    /// The area a window should be laid out within, in AX space.
    ///
    /// `visibleFrame` already excludes the menu bar and the Dock. Two known residual
    /// inaccuracies are handled or acknowledged here:
    ///   - The notch, when the menu bar is set to auto-hide (`safeAreaInsets`).
    ///   - The Stage Manager strip, whose width macOS does not publish. Rectangle
    ///     measures it by scraping the Dock's accessibility tree; rather than ship that,
    ///     Reef exposes `alignmentStageManagerInset` for anyone who runs Stage Manager
    ///     with the strip pinned.
    @MainActor
    static func usableBoundsAX(of screen: NSScreen) -> CGRect {
        var visible = clampedForSafeArea(screen.visibleFrame,
                                         screenFrame: screen.frame,
                                         safeAreaTop: screen.safeAreaInsets.top)

        let inset = StageManager.effectiveLeadingInset
        if inset > 0, visible.width > inset {
            visible.origin.x += inset
            visible.size.width -= inset
        }

        return flipped(visible, primaryMaxY: primaryMaxY)
    }
}

/// Stage Manager detection. The strip's width is not published anywhere, so Reef asks
/// the user for it once rather than scraping the Dock's accessibility tree.
enum StageManager {
    static var isEnabled: Bool {
        CFPreferencesCopyAppValue("GloballyEnabled" as CFString,
                                  "com.apple.WindowManager" as CFString) as? Bool ?? false
    }

    /// When the strip auto-hides it does not steal layout space.
    static var stripAutoHides: Bool {
        CFPreferencesCopyAppValue("AutoHide" as CFString,
                                  "com.apple.WindowManager" as CFString) as? Bool ?? false
    }

    /// Hidden preference, in points. 0 disables the correction entirely.
    static var effectiveLeadingInset: CGFloat {
        guard isEnabled, !stripAutoHides else { return 0 }
        let stored = UserDefaults.standard.double(forKey: "alignmentStageManagerInset")
        return stored > 0 ? CGFloat(stored) : 0
    }
}
