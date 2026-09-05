//
//  WindowRegistry.swift
//  Reef
//
//  Remembers windows across macOS Spaces.
//
//  The Accessibility API only reports an application's windows on the Space you are
//  currently on: an app whose windows all live on another desktop returns an empty list.
//  There is no public API to enumerate the rest — CGWindowList can count them but will
//  not give their titles without Screen Recording permission, and hands back no element
//  to act on.
//
//  What does work: an AXUIElement captured while its window was on the current Space
//  stays valid after you leave that Space, and its title stays readable. So Reef keeps
//  every window handle it has ever seen, discards the ones that die, and offers the
//  survivors alongside whatever Accessibility can reach right now.
//
//  The honest limitation: Reef can only know about a Space it has seen you visit since
//  it launched. The list fills in as you work rather than being complete at startup.
//

import Cocoa

/// Only ever used from the main thread: the notification observers below are
/// delivered on the main queue, and every read goes through the cycle panel.
final class WindowRegistry {
    static let shared = WindowRegistry()

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    private var entries: [CGWindowID: Entry] = [:]
    private var started = false

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
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            record(pid: app.processIdentifier)
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

    /// Windows this app owns that Accessibility cannot reach right now but which are
    /// still alive — in practice, the ones sitting on another Space.
    func offSpaceWindows(pid: pid_t, excluding liveIDs: Set<CGWindowID>) -> [AXUIElement] {
        entries
            .filter { $0.value.pid == pid && !liveIDs.contains($0.key) }
            .sorted { $0.key < $1.key }          // stable order between invocations
            .compactMap { isAlive($0.value.element) ? $0.value.element : nil }
    }

    /// Drops handles whose windows have closed.
    func prune() {
        entries = entries.filter { isAlive($0.value.element) }
    }

    /// A dead element fails every attribute read; a live one answers with its title.
    private func isAlive(_ element: AXUIElement) -> Bool {
        let title: String? = element.getAttributeValue(.title)
        return title != nil
    }
}
