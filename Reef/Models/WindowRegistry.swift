//
//  WindowRegistry.swift
//  Reef
//
//  Remembers windows across macOS Spaces.
//
//  The Accessibility API only reports an application's windows on the Space you are
//  currently on: an app whose windows all live on another desktop returns an empty list.
//
//  Two sources fill the gap:
//
//  - Handles already seen. An AXUIElement captured while its window was on the current
//    Space stays valid after you leave that Space, so every handle Reef has seen is kept
//    until its window dies.
//  - Discovery. CGWindowList names every window id an app owns on every Space (though not
//    their titles, without Screen Recording). For ids no handle covers yet, Reef rebuilds
//    the element from a remote token (see RemoteWindowElements), which reaches Spaces you
//    have not visited since Reef started, including full-screen ones.
//
import Cocoa
import os

/// Only ever used from the main thread: the notification observers below are
/// delivered on the main queue, and every read goes through the cycle panel.
final class WindowRegistry {
    static let shared = WindowRegistry()

    /// Whether the switcher should reach beyond the space you are currently on.
    /// Defaults to on; surfaced in Preferences -> General.
    static let preferenceKey = "includeWindowsFromOtherSpaces"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) != nil else { return true }
        return defaults.bool(forKey: preferenceKey)
    }

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    private let log = Logger(subsystem: "xandergouws.Reef", category: "WindowRegistry")

    private var entries: [CGWindowID: Entry] = [:]
    private var started = false

    /// Window ids that CGWindowList reports but discovery could not match to an element:
    /// offscreen helper surfaces, mostly. Remembered so they do not trigger a rescan on
    /// every refresh. Cleared per pid when that app's windows change.
    private var unresolvable: [pid_t: Set<CGWindowID>] = [:]

    /// Begins observing the events after which a new Space's windows become visible.
    func start() {
        guard !started else { return }
        started = true

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAll()
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.prune()
        }

        refreshAll()
    }

    /// Records whatever Accessibility can currently see, for every ordinary app.
    func refreshAll() {
        let onScreenWindows = CGWindowCatalog.current()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let liveIDs = record(pid: pid)
            discover(pid: pid, excluding: liveIDs, catalog: onScreenWindows)
        }
        prune()
    }

    /// Folds one application's currently reachable windows into the registry.
    @discardableResult
    func record(pid: pid_t) -> Set<CGWindowID> {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows: [AXUIElement] = appElement.getAttributeValue(.windows) else { return [] }

        var ids = Set<CGWindowID>()
        for window in windows {
            guard let id = window.getWindowID(), id != 0 else { continue }
            ids.insert(id)
            entries[id] = Entry(element: window, pid: pid)
        }
        return ids
    }

    /// Finds elements for this app's windows that no handle covers yet: windows on
    /// Spaces Reef has never been shown.
    func discover(pid: pid_t, excluding liveIDs: Set<CGWindowID>, catalog: CGWindowCatalog? = nil) {
        guard WindowRegistry.isEnabled else { return }

        let catalog = catalog ?? CGWindowCatalog.current()
        let owned = catalog.windowIDs(pid: pid)
        let skipped = unresolvable[pid, default: []]
        let wanted = owned.subtracting(liveIDs).subtracting(entries.keys).subtracting(skipped)
        guard !wanted.isEmpty else { return }

        let (found, complete) = RemoteWindowElements.find(pid: pid, wanted: wanted)
        for (id, element) in found {
            entries[id] = Entry(element: element, pid: pid)
        }

        // Only give up on ids after a scan that ran to the end: one cut short by the time
        // budget says nothing about the ids it did not reach.
        log.debug("discover pid \(pid): wanted \(wanted.count), found \(found.count), complete \(complete)")

        let missing = complete ? wanted.subtracting(found.keys) : []
        unresolvable[pid] = skipped.union(missing).intersection(owned)
    }

    /// Windows this app owns that Accessibility cannot reach right now but which are
    /// still alive — in practice, the ones sitting on another Space. Front-most first,
    /// in the window server's order, so the one you used last is nearest.
    func offSpaceWindows(pid: pid_t, excluding liveIDs: Set<CGWindowID>) -> [AXUIElement] {
        guard WindowRegistry.isEnabled else { return [] }

        let order = CGWindowCatalog.current().order
        return entries
            .filter { $0.value.pid == pid && !liveIDs.contains($0.key) }
            .sorted { (order[$0.key] ?? .max, $0.key) < (order[$1.key] ?? .max, $1.key) }
            .compactMap { isAlive($0.value.element) && isSwitchable($0.value.element) ? $0.value.element : nil }
    }

    /// Drops handles whose windows have closed.
    func prune() {
        entries = entries.filter { isAlive($0.value.element) }

        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        unresolvable = unresolvable.filter { running.contains($0.key) }
    }

    /// Discovery returns every window-role element, including sheets' hosts and panels;
    /// only what a person would switch to belongs in the switcher.
    private func isSwitchable(_ element: AXUIElement) -> Bool {
        let subrole: String? = element.getAttributeValue(.subrole)
        guard let subrole else { return true }
        return subrole == NSAccessibility.Subrole.standardWindow.rawValue
            || subrole == NSAccessibility.Subrole.dialog.rawValue
    }

    /// A dead element fails every attribute read; a live one answers with its title.
    private func isAlive(_ element: AXUIElement) -> Bool {
        let title: String? = element.getAttributeValue(.title)
        return title != nil
    }
}

/// A snapshot of the window server's list of ordinary windows on every Space.
///
/// Needs no permission: without Screen Recording the titles are withheld, but ids, owners
/// and layers are not, which is all discovery needs.
struct CGWindowCatalog {
    /// Window id -> owning pid, for layer-0 (ordinary) windows.
    let owners: [CGWindowID: pid_t]
    /// Window id -> position in the server's front-to-back order.
    let order: [CGWindowID: Int]

    static func current() -> CGWindowCatalog {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        var owners: [CGWindowID: pid_t] = [:]
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int else { continue }

            // Zero-size and tiny surfaces are never real windows.
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               (bounds["Width"] ?? 0) < 50 || (bounds["Height"] ?? 0) < 50 {
                continue
            }

            let id = CGWindowID(number)
            owners[id] = pid_t(pid)
            order[id] = index
        }
        return CGWindowCatalog(owners: owners, order: order)
    }

    func windowIDs(pid: pid_t) -> Set<CGWindowID> {
        Set(owners.compactMap { $0.value == pid ? $0.key : nil })
    }
}
