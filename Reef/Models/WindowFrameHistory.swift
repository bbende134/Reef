//
//  WindowFrameHistory.swift
//  Reef
//
//  Remembers where a window was before Reef first moved it, so `restore` can put it back.
//  Pure: no AppKit, no Accessibility.
//

import Foundation
import CoreGraphics

/// Record-once, take-once storage of pre-alignment frames, keyed by window.
///
/// "Record once" is the important semantic: aligning left, then right, then restoring
/// should return the window to where it was *before the first* alignment, not to the
/// left half. So `record` is a no-op if an entry already exists, and `take` clears it.
struct WindowFrameHistory {
    /// Windows Reef has moved in one session is small; the cap only guards against a
    /// long-running process accumulating entries for windows that are long gone.
    static let defaultCapacity = 64

    private var frames: [CGWindowID: CGRect] = [:]
    /// Least-recently-touched first.
    private var order: [CGWindowID] = []
    private let capacity: Int

    init(capacity: Int = WindowFrameHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    var count: Int { frames.count }

    /// Stores `frame` for `id` unless something is already stored.
    ///
    /// `id == 0` is Reef's sentinel for "no CGWindowID available" (see `Window.id`), and
    /// every such window would collide on the same key, so those are refused outright.
    mutating func record(_ frame: CGRect, for id: CGWindowID) {
        guard id != 0 else { return }
        guard frames[id] == nil else {
            touch(id)
            return
        }

        frames[id] = frame
        order.append(id)
        evictIfNeeded()
    }

    /// Returns the stored frame and forgets it.
    mutating func take(for id: CGWindowID) -> CGRect? {
        guard id != 0, let frame = frames.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        return frame
    }

    /// Non-destructive read, for UI that wants to know whether restore is available.
    func peek(for id: CGWindowID) -> CGRect? {
        guard id != 0 else { return nil }
        return frames[id]
    }

    mutating func removeAll() {
        frames.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ id: CGWindowID) {
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        order.append(id)
    }

    private mutating func evictIfNeeded() {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            frames.removeValue(forKey: oldest)
        }
    }
}
