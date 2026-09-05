//
//  WindowLayout.swift
//  Reef
//
//  Pure geometry for window alignment. No AppKit, no Accessibility, no state.
//

import Foundation
import CoreGraphics

/// Which edge of the screen a layout is anchored to.
enum LayoutEdge: CaseIterable, Hashable {
    case left, right, top, bottom
}

/// How much of the screen an edge-anchored layout occupies.
enum LayoutFraction: Hashable {
    case oneHalf, oneThird, twoThirds

    var value: CGFloat {
        switch self {
        case .oneHalf: return 1.0 / 2.0
        case .oneThird: return 1.0 / 3.0
        case .twoThirds: return 2.0 / 3.0
        }
    }

    var symbol: String {
        switch self {
        case .oneHalf: return "½"
        case .oneThird: return "⅓"
        case .twoThirds: return "⅔"
        }
    }

    /// The order repeat presses walk through.
    static let cycle: [LayoutFraction] = [.oneHalf, .oneThird, .twoThirds]
}

/// One of the four screen quarters.
enum LayoutCorner: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// A target position for a window.
///
/// - Important: Every rect in this type is in **Accessibility space** — origin at the
///   top-left of the primary display, y increasing *downward*. That is the space the
///   Accessibility API reads and writes, so the single Cocoa/AX flip lives in
///   `ScreenGeometry.usableBoundsAX(of:)` and never leaks into this math.
///   `.top` therefore means *smaller* y.
enum WindowLayout: Hashable {
    /// Anchored to one edge, occupying `fraction` of the perpendicular axis.
    case edge(LayoutEdge, LayoutFraction)
    /// One screen quarter.
    case corner(LayoutCorner)
    /// The whole usable area.
    case maximize
    /// Centred, keeping the window's current size (clamped to the usable area).
    case center

    /// - Parameters:
    ///   - bounds: The usable area of the target screen, in AX space.
    ///   - current: The window's present frame, in AX space. Only `.center` reads it.
    func frame(in bounds: CGRect, current: CGRect) -> CGRect {
        let raw: CGRect

        switch self {
        case .edge(let edge, let fraction):
            switch edge {
            case .left:
                let w = bounds.width * fraction.value
                raw = CGRect(x: bounds.minX, y: bounds.minY, width: w, height: bounds.height)
            case .right:
                let w = bounds.width * fraction.value
                // Anchor from maxX so the edge lands flush, rather than accumulating from minX.
                raw = CGRect(x: bounds.maxX - w, y: bounds.minY, width: w, height: bounds.height)
            case .top:
                let h = bounds.height * fraction.value
                raw = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: h)
            case .bottom:
                let h = bounds.height * fraction.value
                raw = CGRect(x: bounds.minX, y: bounds.maxY - h, width: bounds.width, height: h)
            }

        case .corner(let corner):
            let w = bounds.width / 2.0
            let h = bounds.height / 2.0
            let x: CGFloat
            let y: CGFloat
            switch corner {
            case .topLeft:     x = bounds.minX;     y = bounds.minY
            case .topRight:    x = bounds.maxX - w; y = bounds.minY
            case .bottomLeft:  x = bounds.minX;     y = bounds.maxY - h
            case .bottomRight: x = bounds.maxX - w; y = bounds.maxY - h
            }
            raw = CGRect(x: x, y: y, width: w, height: h)

        case .maximize:
            raw = bounds

        case .center:
            let w = min(current.width, bounds.width)
            let h = min(current.height, bounds.height)
            raw = CGRect(x: bounds.midX - w / 2.0, y: bounds.midY - h / 2.0, width: w, height: h)
        }

        return WindowLayout.snapped(raw, to: bounds)
    }

    /// Rounds each edge independently and rebuilds the rect from the rounded edges.
    ///
    /// Rounding origin and size separately would let `left(⅔)` and `right(⅓)` drift apart
    /// by a point; rounding the *edges* guarantees they abut exactly. Edges that coincide
    /// with the bounds are pinned rather than rounded, so a layout stays flush against the
    /// screen even when the usable area is non-integral.
    static func snapped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let x0 = rect.minX == bounds.minX ? bounds.minX : rect.minX.rounded()
        let x1 = rect.maxX == bounds.maxX ? bounds.maxX : rect.maxX.rounded()
        let y0 = rect.minY == bounds.minY ? bounds.minY : rect.minY.rounded()
        let y1 = rect.maxY == bounds.maxY ? bounds.maxY : rect.maxY.rounded()

        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

extension WindowLayout {
    /// Short label for the panel hint / badge accessibility description.
    var shortDescription: String {
        switch self {
        case .edge(let edge, let fraction):
            let name: String
            switch edge {
            case .left: name = "Left"
            case .right: name = "Right"
            case .top: name = "Top"
            case .bottom: name = "Bottom"
            }
            return "\(name) \(fraction.symbol)"
        case .corner(let corner):
            switch corner {
            case .topLeft: return "Top-left ¼"
            case .topRight: return "Top-right ¼"
            case .bottomLeft: return "Bottom-left ¼"
            case .bottomRight: return "Bottom-right ¼"
            }
        case .maximize: return "Maximised"
        case .center: return "Centred"
        }
    }
}
