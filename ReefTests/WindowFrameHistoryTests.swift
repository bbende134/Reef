import Testing
import CoreGraphics
@testable import Reef

struct WindowFrameHistoryTests {

    private let a = CGRect(x: 10, y: 20, width: 300, height: 200)
    private let b = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func recordThenTakeReturnsTheFrame() {
        var history = WindowFrameHistory()
        history.record(a, for: 1)
        #expect(history.take(for: 1) == a)
    }

    /// The point of "record once": align left, then right, then restore should return to
    /// where the window was before the *first* move, not to the left half.
    @Test func recordingTwiceKeepsTheOriginalFrame() {
        var history = WindowFrameHistory()
        history.record(a, for: 1)
        history.record(b, for: 1)
        #expect(history.take(for: 1) == a)
    }

    @Test func takeClearsTheEntry() {
        var history = WindowFrameHistory()
        history.record(a, for: 1)
        _ = history.take(for: 1)
        #expect(history.take(for: 1) == nil)
    }

    @Test func takingAnUnknownWindowReturnsNil() {
        var history = WindowFrameHistory()
        #expect(history.take(for: 42) == nil)
    }

    @Test func peekDoesNotClear() {
        var history = WindowFrameHistory()
        history.record(a, for: 1)
        #expect(history.peek(for: 1) == a)
        #expect(history.take(for: 1) == a)
    }

    /// `Window.id` falls back to 0 when no CGWindowID is available, and every such window
    /// would collide on that key.
    @Test func windowIdZeroIsRefused() {
        var history = WindowFrameHistory()
        history.record(a, for: 0)
        #expect(history.peek(for: 0) == nil)
        #expect(history.take(for: 0) == nil)
        #expect(history.count == 0)
    }

    @Test func entriesAreEvictedOnceOverCapacity() {
        var history = WindowFrameHistory(capacity: 3)
        for id in CGWindowID(1)...CGWindowID(5) {
            history.record(CGRect(x: CGFloat(id), y: 0, width: 10, height: 10), for: id)
        }
        #expect(history.count == 3)
        // The two oldest are gone, the three newest survive.
        #expect(history.peek(for: 1) == nil)
        #expect(history.peek(for: 2) == nil)
        #expect(history.peek(for: 5) != nil)
    }

    @Test func removeAllClearsEverything() {
        var history = WindowFrameHistory()
        history.record(a, for: 1)
        history.record(b, for: 2)
        history.removeAll()
        #expect(history.count == 0)
    }
}
