import Testing
import CoreGraphics
@testable import Reef

/// All bounds here are in Accessibility space: top-left origin, y increasing downward.
/// `(0, 25, 1512, 920)` reads as "a 1512×945 display with a 25 pt menu bar".
struct WindowLayoutTests {

    private let bounds = CGRect(x: 0, y: 25, width: 1512, height: 920)
    private let window = CGRect(x: 300, y: 300, width: 400, height: 300)

    // MARK: - Halves and fractions

    @Test func leftHalf() {
        let f = WindowLayout.edge(.left, .oneHalf).frame(in: bounds, current: window)
        #expect(f == CGRect(x: 0, y: 25, width: 756, height: 920))
    }

    @Test func rightThirdIsFlushWithTheScreenEdge() {
        let f = WindowLayout.edge(.right, .oneThird).frame(in: bounds, current: window)
        #expect(f.maxX == bounds.maxX)
        #expect(f == CGRect(x: 1008, y: 25, width: 504, height: 920))
    }

    /// Guards against a whole-file sign inversion: in AX space, "top" is *smaller* y.
    @Test func topMeansSmallerY() {
        let top = WindowLayout.edge(.top, .oneHalf).frame(in: bounds, current: window)
        #expect(top.minY == bounds.minY)
        #expect(top == CGRect(x: 0, y: 25, width: 1512, height: 460))
    }

    @Test func bottomTwoThirdsIsFlushWithTheBottom() {
        let f = WindowLayout.edge(.bottom, .twoThirds).frame(in: bounds, current: window)
        #expect(f.maxY == bounds.maxY)
        #expect(f.minX == bounds.minX)
        #expect(f.width == bounds.width)
    }

    /// The reason `snapped` rounds edges rather than origin-and-size.
    @Test func complementaryFractionsAbutExactly() {
        let left = WindowLayout.edge(.left, .twoThirds).frame(in: bounds, current: window)
        let right = WindowLayout.edge(.right, .oneThird).frame(in: bounds, current: window)
        #expect(left.maxX == right.minX)
        #expect(left.minX == bounds.minX)
        #expect(right.maxX == bounds.maxX)
    }

    @Test func halvesAbutExactly() {
        let left = WindowLayout.edge(.left, .oneHalf).frame(in: bounds, current: window)
        let right = WindowLayout.edge(.right, .oneHalf).frame(in: bounds, current: window)
        #expect(left.maxX == right.minX)
    }

    // MARK: - Quarters

    @Test func quartersTileTheScreenExactly() {
        let frames = LayoutCorner.allCases.map {
            WindowLayout.corner($0).frame(in: bounds, current: window)
        }

        // No two quarters overlap.
        for i in frames.indices {
            for j in frames.indices where j > i {
                let overlap = frames[i].intersection(frames[j])
                #expect(overlap.isNull || overlap.width == 0 || overlap.height == 0)
            }
        }

        // Together they cover the whole usable area.
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        #expect(union == bounds)
    }

    @Test func topLeftQuarter() {
        let f = WindowLayout.corner(.topLeft).frame(in: bounds, current: window)
        #expect(f == CGRect(x: 0, y: 25, width: 756, height: 460))
    }

    @Test func bottomRightQuarterIsFlushWithBothFarEdges() {
        let f = WindowLayout.corner(.bottomRight).frame(in: bounds, current: window)
        #expect(f.maxX == bounds.maxX)
        #expect(f.maxY == bounds.maxY)
    }

    // MARK: - Maximise and centre

    @Test func maximizeFillsTheBounds() {
        #expect(WindowLayout.maximize.frame(in: bounds, current: window) == bounds)
    }

    @Test func centerPreservesSize() {
        let f = WindowLayout.center.frame(in: bounds, current: window)
        #expect(f.width == window.width)
        #expect(f.height == window.height)
        #expect(f.midX == bounds.midX)
        #expect(f.midY == bounds.midY)
    }

    @Test func centerClampsAnOversizedWindow() {
        let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        let f = WindowLayout.center.frame(in: bounds, current: huge)
        #expect(f == bounds)
    }

    // MARK: - Awkward bounds

    /// A non-integral usable area must still produce integral, abutting edges.
    @Test func nonIntegralBoundsStillAbut() {
        let odd = CGRect(x: 0, y: 0.5, width: 1000.5, height: 700.25)
        let left = WindowLayout.edge(.left, .twoThirds).frame(in: odd, current: window)
        let right = WindowLayout.edge(.right, .oneThird).frame(in: odd, current: window)
        #expect(left.maxX == right.minX)
        #expect(right.maxX == odd.maxX)
    }

    /// A display arranged left of, and above, the primary has a negative origin.
    @Test func negativeOriginBounds() {
        let secondary = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
        let f = WindowLayout.edge(.left, .oneHalf).frame(in: secondary, current: window)
        #expect(f == CGRect(x: -1920, y: -180, width: 960, height: 1080))

        let right = WindowLayout.edge(.right, .oneHalf).frame(in: secondary, current: window)
        #expect(right.maxX == secondary.maxX)
        #expect(f.maxX == right.minX)
    }

    @Test func zeroSizedBoundsDoNotProduceNegativeExtents() {
        let empty = CGRect(x: 10, y: 10, width: 0, height: 0)
        let f = WindowLayout.edge(.left, .oneHalf).frame(in: empty, current: window)
        #expect(f.width >= 0)
        #expect(f.height >= 0)
    }
}
