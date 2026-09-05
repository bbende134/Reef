//
//  Checks/main.swift
//
//  The unit tests, in a form that runs without Xcode.
//
//  `ReefTests/` uses swift-testing, and neither swift-testing nor XCTest ships with the
//  Command Line Tools — both live inside Xcode.app, and `swift test` cannot find them
//  either. So the same assertions live here as a plain executable that `./check.sh`
//  compiles against the pure model sources and runs.
//
//  Keep this in sync with ReefTests/ if you ever build with full Xcode.
//

import Foundation
import CoreGraphics
import AppKit

var failures = 0
func check(_ ok: Bool, _ label: String) {
    if !ok { print("FAIL: \(label)"); failures += 1 }
}

let bounds = CGRect(x: 0, y: 25, width: 1512, height: 920)
let window = CGRect(x: 300, y: 300, width: 400, height: 300)

// --- WindowLayout expectations, mirroring WindowLayoutTests ---
check(WindowLayout.edge(.left, .oneHalf).frame(in: bounds, current: window)
      == CGRect(x: 0, y: 25, width: 756, height: 920), "leftHalf")
check(WindowLayout.edge(.right, .oneThird).frame(in: bounds, current: window)
      == CGRect(x: 1008, y: 25, width: 504, height: 920), "rightThird")
check(WindowLayout.edge(.top, .oneHalf).frame(in: bounds, current: window)
      == CGRect(x: 0, y: 25, width: 1512, height: 460), "topHalf")

let bt = WindowLayout.edge(.bottom, .twoThirds).frame(in: bounds, current: window)
check(bt.maxY == bounds.maxY && bt.width == bounds.width, "bottomTwoThirds flush")

let l23 = WindowLayout.edge(.left, .twoThirds).frame(in: bounds, current: window)
let r13 = WindowLayout.edge(.right, .oneThird).frame(in: bounds, current: window)
check(l23.maxX == r13.minX, "complementary abut (\(l23.maxX) vs \(r13.minX))")

let lh = WindowLayout.edge(.left, .oneHalf).frame(in: bounds, current: window)
let rh = WindowLayout.edge(.right, .oneHalf).frame(in: bounds, current: window)
check(lh.maxX == rh.minX, "halves abut")

let quarters = LayoutCorner.allCases.map { WindowLayout.corner($0).frame(in: bounds, current: window) }
for i in quarters.indices { for j in quarters.indices where j > i {
    let o = quarters[i].intersection(quarters[j])
    check(o.isNull || o.width == 0 || o.height == 0, "quarters \(i)/\(j) disjoint")
}}
check(quarters.dropFirst().reduce(quarters[0]) { $0.union($1) } == bounds, "quarters tile bounds")
check(WindowLayout.corner(.topLeft).frame(in: bounds, current: window)
      == CGRect(x: 0, y: 25, width: 756, height: 460), "topLeft quarter")
let br = WindowLayout.corner(.bottomRight).frame(in: bounds, current: window)
check(br.maxX == bounds.maxX && br.maxY == bounds.maxY, "bottomRight flush")

check(WindowLayout.maximize.frame(in: bounds, current: window) == bounds, "maximize")
let c = WindowLayout.center.frame(in: bounds, current: window)
check(c.width == 400 && c.height == 300 && c.midX == bounds.midX && c.midY == bounds.midY, "center")
check(WindowLayout.center.frame(in: bounds, current: CGRect(x: 0, y: 0, width: 5000, height: 5000)) == bounds,
      "center clamps oversized")

let odd = CGRect(x: 0, y: 0.5, width: 1000.5, height: 700.25)
let ol = WindowLayout.edge(.left, .twoThirds).frame(in: odd, current: window)
let or_ = WindowLayout.edge(.right, .oneThird).frame(in: odd, current: window)
check(ol.maxX == or_.minX, "non-integral abut (\(ol.maxX) vs \(or_.minX))")
check(or_.maxX == odd.maxX, "non-integral right flush")

let sec = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
check(WindowLayout.edge(.left, .oneHalf).frame(in: sec, current: window)
      == CGRect(x: -1920, y: -180, width: 960, height: 1080), "negative origin left half")
let secR = WindowLayout.edge(.right, .oneHalf).frame(in: sec, current: window)
check(secR.maxX == sec.maxX, "negative origin right flush")

let empty = WindowLayout.edge(.left, .oneHalf).frame(in: CGRect(x: 10, y: 10, width: 0, height: 0), current: window)
check(empty.width >= 0 && empty.height >= 0, "zero bounds non-negative")

// --- AlignmentCycleState ---
var st = AlignmentCycleState()
check(st.layout(for: .edge(.left)) == .edge(.left, .oneHalf), "cycle 1")
check(st.layout(for: .edge(.left)) == .edge(.left, .oneThird), "cycle 2")
check(st.layout(for: .edge(.left)) == .edge(.left, .twoThirds), "cycle 3")
check(st.layout(for: .edge(.left)) == .edge(.left, .oneHalf), "cycle wraps")
check(st.layout(for: .edge(.top)) == .edge(.top, .oneHalf), "group change resets")
st.reset()
check(st.layout(for: .edge(.right)) == .edge(.right, .oneHalf), "reset")
var st2 = AlignmentCycleState()
check(st2.layout(for: .corner(.left)) == .corner(.topLeft), "corner 1")
check(st2.layout(for: .corner(.left)) == .corner(.bottomLeft), "corner 2")
check(st2.layout(for: .corner(.left)) == .corner(.topLeft), "corner wraps")
check(st2.layout(for: .corner(.top)) == .corner(.topLeft), "corner group change")
check(AlignmentCycleState.layout(for: .edge(.bottom), step: 4) == .edge(.bottom, .oneThird), "pure step 4")
check(AlignmentCycleState.layout(for: .corner(.right), step: 3) == .corner(.bottomRight), "pure corner step 3")

// --- ScreenGeometry ---
let m: CGFloat = 1080
for r in [CGRect(x: 0, y: 0, width: 100, height: 100),
          CGRect(x: -1920, y: -180, width: 1920, height: 1080),
          CGRect(x: 37.5, y: 12.25, width: 800.75, height: 600.5)] {
    check(ScreenGeometry.flipped(ScreenGeometry.flipped(r, primaryMaxY: m), primaryMaxY: m) == r, "flip involution")
}
check(ScreenGeometry.flipped(CGRect(x: 0, y: 0, width: 1920, height: 100), primaryMaxY: m)
      == CGRect(x: 0, y: 980, width: 1920, height: 100), "flip rect")
check(ScreenGeometry.flipped(CGRect(x: 0, y: -900, width: 1440, height: 900), primaryMaxY: m).minY == m,
      "display below primary")
check(ScreenGeometry.flipped(CGPoint(x: 42, y: 300), primaryMaxY: m) == CGPoint(x: 42, y: 780), "flip point")

let screens = [CGRect(x: 0, y: 0, width: 1000, height: 1000), CGRect(x: 1000, y: 0, width: 1000, height: 1000)]
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 100, y: 100, width: 50, height: 50), screenFrames: screens) == 0, "contained")
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 850, y: 0, width: 200, height: 100), screenFrames: screens) == 0, "straddle 0")
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 950, y: 0, width: 200, height: 100), screenFrames: screens) == 1, "straddle 1")
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 1500, y: 500, width: 0, height: 0), screenFrames: screens) == 1, "degenerate centre")
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 5000, y: 5000, width: 10, height: 10), screenFrames: screens) == nil, "offscreen")
check(ScreenGeometry.indexOfScreen(containing: CGRect(x: 0, y: 0, width: 10, height: 10), screenFrames: []) == nil, "no screens")

let sf = CGRect(x: 0, y: 0, width: 1512, height: 982)
check(ScreenGeometry.clampedForSafeArea(CGRect(x: 0, y: 0, width: 1512, height: 945), screenFrame: sf, safeAreaTop: 37)
      == CGRect(x: 0, y: 0, width: 1512, height: 945), "menu bar shown untouched")
let hidden = ScreenGeometry.clampedForSafeArea(CGRect(x: 0, y: 0, width: 1512, height: 982), screenFrame: sf, safeAreaTop: 37)
check(hidden.maxY == 945 && hidden.minY == 0, "auto-hidden menu bar clamped")
check(ScreenGeometry.clampedForSafeArea(CGRect(x: 0, y: 0, width: 1920, height: 1055),
      screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0)
      == CGRect(x: 0, y: 0, width: 1920, height: 1055), "no notch")

// --- AlignmentKeyMap ---
func ch(_ k: UInt16, _ c: Character?, _ corner: Bool = false) -> AlignmentKeyMap.Chord {
    AlignmentKeyMap.Chord(keyCode: k, character: c, hasCornerModifier: corner)
}
check(AlignmentKeyMap.command(for: ch(4, "h")) == .edge(.left), "h")
check(AlignmentKeyMap.command(for: ch(37, "l")) == .edge(.right), "l")
check(AlignmentKeyMap.command(for: ch(40, "k")) == .edge(.top), "k")
check(AlignmentKeyMap.command(for: ch(38, "j")) == .edge(.bottom), "j")
check(AlignmentKeyMap.command(for: ch(4, "h", true)) == .corner(.left), "opt-h")
check(AlignmentKeyMap.command(for: ch(46, "m")) == .maximize, "m")
check(AlignmentKeyMap.command(for: ch(8, "c")) == .center, "c")
check(AlignmentKeyMap.command(for: ch(15, "r")) == .restore, "r")
check(AlignmentKeyMap.command(for: ch(46, "m", true)) == nil, "opt-m rejected")
check(AlignmentKeyMap.command(for: ch(99, "h")) == .edge(.left), "character wins over keycode")
check(AlignmentKeyMap.command(for: ch(4, "ő")) == nil, "wrong character rejected")
check(AlignmentKeyMap.command(for: ch(123, nil)) == .edge(.left), "left arrow")
check(AlignmentKeyMap.command(for: ch(126, nil, true)) == .corner(.top), "opt-up arrow")
check(AlignmentKeyMap.command(for: ch(18, "1")) == nil, "digit 1 falls through")
check(AlignmentKeyMap.command(for: ch(29, "0")) == nil, "digit 0 falls through")
check(AlignmentKeyMap.command(for: ch(999, nil)) == nil, "unknown keycode")
check(AlignmentKeyMap.cornerModifier(base: [.control]) == .option, "corner mod default")
check(AlignmentKeyMap.cornerModifier(base: [.control, .option]) == .shift, "corner mod avoids option")
check(AlignmentKeyMap.cornerModifier(base: [.control, .option, .shift]) == .command, "corner mod falls to command")

// --- WindowFrameHistory ---
let a = CGRect(x: 10, y: 20, width: 300, height: 200)
let b = CGRect(x: 0, y: 0, width: 800, height: 600)
var h1 = WindowFrameHistory(); h1.record(a, for: 1)
check(h1.take(for: 1) == a, "record/take")
var h2 = WindowFrameHistory(); h2.record(a, for: 1); h2.record(b, for: 1)
check(h2.take(for: 1) == a, "record once keeps original")
var h3 = WindowFrameHistory(); h3.record(a, for: 1); _ = h3.take(for: 1)
check(h3.take(for: 1) == nil, "take clears")
var h4 = WindowFrameHistory(); h4.record(a, for: 0)
check(h4.peek(for: 0) == nil && h4.count == 0, "id 0 refused")
var h5 = WindowFrameHistory(capacity: 3)
for id in CGWindowID(1)...CGWindowID(5) { h5.record(CGRect(x: CGFloat(id), y: 0, width: 10, height: 10), for: id) }
check(h5.count == 3 && h5.peek(for: 1) == nil && h5.peek(for: 2) == nil && h5.peek(for: 5) != nil, "LRU eviction")

print(failures == 0 ? "ALL \(failures == 0 ? "CHECKS" : "") PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
