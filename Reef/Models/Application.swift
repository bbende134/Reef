//
//  Application.swift
//  Reef
//
//  Created by Xander Gouws on 16-09-2025.
//

import Foundation
import Cocoa


class Application {
    var title: String
    var element: AXUIElement?

    var runningApplication: NSRunningApplication?
    var pid: pid_t?
    var bundleIdentifier: String?
    var bundleUrl: URL?
    
    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication

        self.pid = runningApplication.processIdentifier

        self.element = AXUIElementCreateApplication(self.pid!)

        self.title = runningApplication.localizedName ?? "Unknown Application"
        self.bundleIdentifier = runningApplication.bundleIdentifier
        self.bundleUrl = runningApplication.bundleURL
    }
    
    // Initialize from URL (for loading from persistence)
    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        self.bundleUrl = url
        self.bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        self.title = url.deletingPathExtension().lastPathComponent
        
        // Try to find running instance
        if let bundle = Bundle(url: url),
           let bundleIdentifier = bundle.bundleIdentifier,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            self.runningApplication = runningApp
            self.pid = runningApp.processIdentifier
            self.element = AXUIElementCreateApplication(self.pid!)
            self.title = runningApp.localizedName ?? self.title
        } else {
            self.runningApplication = nil
            self.pid = nil
            self.element = nil
        }
    }

    convenience init?(bundleIdentifier: String) {
        if let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        {
            self.init(runningApp)
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            self.init(url: url)
            return
        }

        return nil
    }
    
//    // Ensure application is running and refresh internal state
//    func ensureRunning() -> Bool {
//        guard let bundleUrl = self.bundleUrl else {
//            return false
//        }
//        
//        // Check if already running
//        if let runningApp = self.runningApplication,
//           runningApp.isTerminated == false {
//            return true
//        }
//        
//        // Try to find if it's running but we lost the reference
//        if let bundle = Bundle(url: bundleUrl),
//           let bundleIdentifier = bundle.bundleIdentifier,
//           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
//            self.runningApplication = runningApp
//            self.pid = runningApp.processIdentifier
//            self.element = AXUIElementCreateApplication(self.pid!)
//            return true
//        }
//        
//        return false
//    }
    
    func focus() {
        self.activate()
    }
    
    var isRunning: Bool {
        refreshRunningApplication() != nil
    }

    func activate(options: NSApplication.ActivationOptions = []) {
        if let runningApplication = refreshRunningApplication() {
            // App is running, just activate it
            runningApplication.activate(options: options)
        } else {
            // App not running, launch it
            try? reopen()
        }
    }
    
    func getFocusedWindow() -> Window? {
        guard let element = element,
              let windowElement: AXUIElement = element.getAttributeValue(.focusedWindow) else {
            return nil
        }
        
        return Window(windowElement, self)
    }
    
    func getFirstWindow() -> Window? {
        guard let element = element,
              let windowElements: [AXUIElement] = element.getAttributeValue(.windows) else {
            return nil
        }
        
        if let firstWindowElement = windowElements.first {
            return Window(firstWindowElement, self)
        }
        
        return nil
    }
    
    func reopen(
        configuration: NSWorkspace.OpenConfiguration = Application.defaultOpenConfiguration(),
        completion: @escaping (Result<NSRunningApplication, Error>) -> Void
    ) throws {
        guard let bundleUrl = self.bundleUrl else {
            throw ApplicationError.noBundleURL
        }
        
        NSWorkspace.shared.openApplication(
            at: bundleUrl,
            configuration: configuration,
            completionHandler: { runningApplication, error in
                if let runningApplication {
                    self.setRunningApplication(runningApplication)
                    completion(.success(runningApplication))
                    return
                }
                
                completion(.failure(error ?? ApplicationError.openFailed))
            }
        )
    }
    
    func reopen(
        configuration: NSWorkspace.OpenConfiguration = Application.defaultOpenConfiguration()
    ) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try reopen(configuration: configuration) { result in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func reopen() throws {
        try reopen(configuration: Self.defaultOpenConfiguration()) { _ in }
    }
    
    @MainActor
    func performNoWindowAction() async -> Bool {
        if let existingWindow = getWindows().first {
            existingWindow.focus()
            return true
        }
        
        let wasRunning = isRunning

        do {
            _ = try await reopen(configuration: Self.defaultOpenConfiguration(activates: true))
        } catch {
            return false
        }

        await followUpAfterReopen(wasRunning: wasRunning)
        return true
    }

    /// Launching or reopening returns before any window exists, and what the app does next
    /// varies: Safari restores last session's windows onto the Spaces they came from, so
    /// nothing appears where you are; a running app sometimes ignores the first reopen
    /// request. Watch briefly and finish the job.
    @MainActor
    private func followUpAfterReopen(wasRunning: Bool) async {
        let pollInterval: Duration = .milliseconds(150)
        let deadline = ContinuousClock.now + .seconds(wasRunning ? 2 : 5)

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)

            guard let runningApplication = refreshRunningApplication() else { continue }
            guard runningApplication.isFinishedLaunching else { continue }

            let windows = getWindows()
            guard let first = windows.first else { continue }

            // A window on this Space means the launch did what was asked.
            let onThisSpace: [AXUIElement] = element?.getAttributeValue(.windows) ?? []
            if onThisSpace.isEmpty {
                // Everything came back on other Spaces: go to it, as for any window there.
                first.focus()
            }
            return
        }

        // Still nothing: ask once more. Running apps with no windows open a fresh one on
        // reopen; the first request can be lost when it lands mid-launch or mid-quit.
        guard refreshRunningApplication() != nil, getWindows().isEmpty else { return }
        _ = try? await reopen(configuration: Self.defaultOpenConfiguration(activates: true))
    }
    
    static func getFrontApplication() -> Application? {
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        return Application(runningApplication)
    }
    
    static func activateOrLaunch(
        bundleIdentifier: String,
        bundleURL: URL,
        options: NSApplication.ActivationOptions = []
    ) {
        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        {
            runningApplication.activate(options: options)
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in }
    }

    func getAXWindows() -> [AXUIElement] {
        // A binding loaded while its app was closed has no element; nor does one whose app
        // has since quit and relaunched under a new pid. Re-resolve before reading.
        refreshRunningApplication()

        guard let element = element else {
            return []
        }
        
        // Accessibility only reports windows on the Space we are currently on. Anything
        // this app has open on another desktop is invisible here, so the registry adds
        // back the handles it has captured or discovered on other Spaces.
        let live: [AXUIElement] = element.getAttributeValue(.windows) ?? []

        guard let pid else {
            return live
        }

        let liveIDs = WindowRegistry.shared.record(pid: pid)
        WindowRegistry.shared.discover(pid: pid, excluding: liveIDs)
        let offSpace = WindowRegistry.shared.offSpaceWindows(pid: pid, excluding: liveIDs)

        // Windows on the current Space stay first, so switching within the desktop you
        // are looking at behaves exactly as it did before.
        return live + offSpace
    }
    
    func getWindows() -> [Window] {
        let axWindows = self.getAXWindows()
        var windows = axWindows.map { axWindow in
            Window(axWindow, self)
        }
        
        // Finder can expose a trailing generic "Finder" window that is not useful for switching.
        if bundleIdentifier == "com.apple.finder",
           let lastWindow = windows.last,
           lastWindow.title == "Finder" {
            windows.removeLast()
        }
        
        return windows
    }
    
    func listAvailableAttributes() -> [String] {
        guard let element = element else {
            return []
        }
        
        var attributesRef: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributesRef)
        
        guard result == .success, let attributes = attributesRef as? [String] else {
            return []
        }
        
        return attributes
    }
    
    @discardableResult
    private func refreshRunningApplication() -> NSRunningApplication? {
        if let runningApplication,
           runningApplication.isTerminated == false {
            return runningApplication
        }
        
        guard let bundleIdentifier else {
            setRunningApplication(nil)
            return nil
        }
        
        guard let detectedRunningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        else {
            setRunningApplication(nil)
            return nil
        }
        
        setRunningApplication(detectedRunningApp)
        return detectedRunningApp
    }
    
    private func setRunningApplication(_ runningApplication: NSRunningApplication?) {
        self.runningApplication = runningApplication
        
        if let runningApplication {
            self.pid = runningApplication.processIdentifier
            self.element = AXUIElementCreateApplication(runningApplication.processIdentifier)
            self.title = runningApplication.localizedName ?? self.title
            return
        }
        
        self.pid = nil
        self.element = nil
    }
    
    private static func defaultOpenConfiguration(activates: Bool = true) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return configuration
    }
    
}


enum ApplicationError: Error {
    case noBundleURL
    case openFailed
}
