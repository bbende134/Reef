//
//  PrivateWindowAPIs.swift
//  Reef
//
//  Undocumented system calls for reaching windows on other Spaces.
//
//  Neither has a public equivalent. Both are what AltTab, yabai and Hammerspoon rely on,
//  and have been stable across macOS releases for years. SkyLight is resolved at runtime
//  with dlsym so that a missing symbol degrades to the public path instead of refusing
//  to launch, and so neither build (Xcode or SwiftPM) needs to link a private framework.
//

import Cocoa

// MARK: - Accessibility elements for windows on other Spaces

/// Builds an AXUIElement from a raw remote token. HIServices exports it; no header does.
///
/// Accessibility only hands out window elements for the current Space, but every window
/// an app owns has an element id, and an element built from (pid, id) answers attribute
/// reads wherever its window is. Brute-forcing the id reaches windows on Spaces that have
/// never been shown.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

enum RemoteWindowElements {
    /// Upper bound on element ids tried. Window ids are handed out early in an app's
    /// element table; AltTab has used the same bound for years.
    static let maxElementID: UInt64 = 1000

    /// Wall-clock budget for one scan, so a hotkey press never visibly stalls.
    static let timeBudget: TimeInterval = 0.1

    /// Finds window elements for `wanted` window ids of `pid`, stopping early once all
    /// are found. `complete` is false when the time budget cut the scan short.
    static func find(pid: pid_t, wanted: Set<CGWindowID>) -> (found: [CGWindowID: AXUIElement], complete: Bool) {
        guard !wanted.isEmpty else { return ([:], true) }

        // Token layout: pid (Int32), 0 (Int32), 'coco' (Int32), element id (UInt64).
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })

        var found: [CGWindowID: AXUIElement] = [:]
        let deadline = Date().addingTimeInterval(timeBudget)

        for elementID in 0..<maxElementID {
            if found.count == wanted.count { break }
            if Date() > deadline { return (found, false) }

            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                continue
            }

            let role: String? = element.getAttributeValue(.role)
            guard role == NSAccessibility.Role.window.rawValue,
                  let windowID = element.getWindowID(),
                  wanted.contains(windowID) else {
                continue
            }

            found[windowID] = element
        }

        return (found, true)
    }
}

// MARK: - Focusing a window on another Space

/// Brings one specific window to the front, switching Space or display as needed.
///
/// `NSRunningApplication.activate` fronts the app but lets macOS pick which window, and
/// from a background agent it is not always honoured at all. The window server's own
/// "make this process and window front" call is what the Dock and Mission Control use.
enum SkyLightFocus {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus

    /// kCPSUserGenerated: the switch is treated as if the user clicked the window.
    private static let userGenerated: UInt32 = 0x200

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    /// RTLD_DEFAULT: GetProcessForPID lives in HIServices, already loaded for Accessibility.
    private static let loaded = UnsafeMutableRawPointer(bitPattern: -2)

    private static let setFrontProcess: SetFrontProcess? = symbol(skyLight, "_SLPSSetFrontProcessWithOptions")
    private static let postEventRecord: PostEventRecord? = symbol(skyLight, "SLPSPostEventRecordTo")
    private static let getProcessForPID: GetProcessForPID? = symbol(loaded, "GetProcessForPID")

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// Returns false if the private calls are unavailable or refused, so the caller can
    /// fall back to the public path.
    @discardableResult
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let setFrontProcess, let postEventRecord, let getProcessForPID else { return false }

        // ProcessSerialNumber is two UInt32s.
        var psn = (UInt32(0), UInt32(0))
        let status = withUnsafeMutableBytes(of: &psn) { getProcessForPID(pid, $0.baseAddress!) }
        guard status == noErr else { return false }

        let result = withUnsafeMutableBytes(of: &psn) {
            setFrontProcess($0.baseAddress!, windowID, userGenerated)
        }
        guard result == .success else { return false }

        // Make the window key within its app: without this the app comes forward but
        // keyboard focus can stay on whichever of its windows was key before.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        for i in 0x20..<0x30 { bytes[i] = 0xff }

        for phase: UInt8 in [0x01, 0x02] {
            bytes[0x08] = phase
            _ = withUnsafeMutableBytes(of: &psn) { psnPointer in
                bytes.withUnsafeMutableBufferPointer { postEventRecord(psnPointer.baseAddress!, $0.baseAddress!) }
            }
        }

        return true
    }
}
