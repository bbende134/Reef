import Testing
import CoreGraphics
@testable import Reef

struct ScreenGeometryTests {

    private let primaryMaxY: CGFloat = 1080

    // MARK: - The flip

    @Test func flipIsSelfInverse() {
        let rects = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: -1920, y: -180, width: 1920, height: 1080),
            CGRect(x: 37.5, y: 12.25, width: 800.75, height: 600.5),
            CGRect(x: 0, y: 0, width: 0, height: 0)
        ]

        for rect in rects {
            let there = ScreenGeometry.flipped(rect, primaryMaxY: primaryMaxY)
            let back = ScreenGeometry.flipped(there, primaryMaxY: primaryMaxY)
            #expect(back == rect)
        }
    }

    @Test func flipMovesTheOriginToTheTopLeft() {
        // A 100 pt tall strip sitting on the bottom of a 1080 pt primary display.
        let cocoa = CGRect(x: 0, y: 0, width: 1920, height: 100)
        let ax = ScreenGeometry.flipped(cocoa, primaryMaxY: primaryMaxY)
        #expect(ax == CGRect(x: 0, y: 980, width: 1920, height: 100))
    }

    @Test func aDisplayBelowThePrimaryFlipsToPositiveY() {
        // Cocoa: a 900 pt display directly under the primary sits at y = -900.
        let cocoa = CGRect(x: 0, y: -900, width: 1440, height: 900)
        let ax = ScreenGeometry.flipped(cocoa, primaryMaxY: primaryMaxY)
        #expect(ax.minY == primaryMaxY)
    }

    @Test func flippingAPointMatchesFlippingARect() {
        let point = CGPoint(x: 42, y: 300)
        let flipped = ScreenGeometry.flipped(point, primaryMaxY: primaryMaxY)
        #expect(flipped == CGPoint(x: 42, y: 780))
        #expect(ScreenGeometry.flipped(flipped, primaryMaxY: primaryMaxY) == point)
    }

    // MARK: - Screen selection

    private let screens = [
        CGRect(x: 0, y: 0, width: 1000, height: 1000),
        CGRect(x: 1000, y: 0, width: 1000, height: 1000)
    ]

    @Test func fullyContainedWindowPicksItsScreen() {
        let rect = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(ScreenGeometry.indexOfScreen(containing: rect, screenFrames: screens) == 0)
    }

    @Test func straddlingWindowPicksTheLargerOverlap() {
        // 150 pt on screen 0, 50 pt on screen 1.
        let rect = CGRect(x: 850, y: 0, width: 200, height: 100)
        #expect(ScreenGeometry.indexOfScreen(containing: rect, screenFrames: screens) == 0)

        // And the other way around.
        let other = CGRect(x: 950, y: 0, width: 200, height: 100)
        #expect(ScreenGeometry.indexOfScreen(containing: other, screenFrames: screens) == 1)
    }

    @Test func degenerateRectFallsBackToItsCentre() {
        // Zero area, so no intersection to measure — the centre still lands on screen 1.
        let rect = CGRect(x: 1500, y: 500, width: 0, height: 0)
        #expect(ScreenGeometry.indexOfScreen(containing: rect, screenFrames: screens) == 1)
    }

    @Test func fullyOffscreenWindowMatchesNothing() {
        let rect = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        #expect(ScreenGeometry.indexOfScreen(containing: rect, screenFrames: screens) == nil)
    }

    @Test func noScreensMatchesNothing() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ScreenGeometry.indexOfScreen(containing: rect, screenFrames: []) == nil)
    }

    // MARK: - The notch

    @Test func menuBarShownNeedsNoSafeAreaCorrection() {
        // visibleFrame already stops below the notch band.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)
        let clamped = ScreenGeometry.clampedForSafeArea(visible, screenFrame: screen, safeAreaTop: 37)
        #expect(clamped == visible)
    }

    @Test func autoHiddenMenuBarIsPulledBelowTheNotch() {
        // visibleFrame runs to the physical top, so a maximised window would sit behind
        // the camera housing.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let clamped = ScreenGeometry.clampedForSafeArea(visible, screenFrame: screen, safeAreaTop: 37)
        #expect(clamped.maxY == 945)
        #expect(clamped.minY == visible.minY)   // bottom edge stays pinned
    }

    @Test func nonNotchedDisplayIsUntouched() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let clamped = ScreenGeometry.clampedForSafeArea(visible, screenFrame: screen, safeAreaTop: 0)
        #expect(clamped == visible)
    }
}
