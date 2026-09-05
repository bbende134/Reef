//
//  CyclePanelController.swift
//  Reef
//
//  Created by Xander Gouws on 23-01-2026.
//

import AppKit
import SwiftUI


@MainActor
final class CyclePanelController: NSObject {
    private(set) var panel: CyclePanel!
    private let state = CyclePanelState()
    private let modifierManager: ModifierManager
    private let aligner = WindowAligner()
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var currentApplication: Application?
    private var panelAnchorCenter: CGPoint?

    private static let releaseModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// The chord the user holds to keep the panel open, snapshotted when it opens.
    ///
    /// The key monitor needs this to tell "plain H" from "H with the corner modifier",
    /// and reading it once per session beats reaching into the modifier manager per keystroke.
    private var activateModifiers: NSEvent.ModifierFlags = [.control]

    private var minPanelContentHeight: CGFloat {
        // Minimum height that still matches the layout for one row.
        CyclePanelMetrics.contentHeight(rowCount: 1, includesHintRow: state.showsAlignmentHints)
    }
    
    init(modifierManager: ModifierManager) {
        self.modifierManager = modifierManager
        super.init()
        createPanel()
    }
    
    private func createPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: CyclePanelMetrics.contentWidth, height: 300)
        panel = CyclePanel(contentRect: contentRect)
        
        let contentView = CyclePanelView(state: state)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        guard let containerView = panel.contentView else { return }
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    // Called when user presses the configured window-switching shortcut.
    func showSwitcher(for application: Application, startIndex: Int = 0) {
        currentApplication = application
        state.setApplication(application)

        // The selection has changed, so a half/third cycle in progress no longer applies.
        aligner.resetCycle()
        activateModifiers = modifierManager.activateModifiers
        
        // Instant switch if the user opted in and there is one actual window
        if UserDefaults.standard.string(forKey: "instantSwitch") == "whenOnlyOneWindowOpen",
           state.items.count == 1,
           case .window = state.currentItem {
            activateSelectedWindow()
            return
        }
        
        // If starting index is provided (e.g., already on that app), use it
        if startIndex > 0 && startIndex < state.items.count {
            state.selectedIndex = startIndex
        }
        
        if !panel.isVisible {
            panel.center()
            panelAnchorCenter = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            updatePanelSize()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            installFlagsMonitor()
            installKeyDownMonitor()
        } else {
            if panelAnchorCenter == nil {
                panelAnchorCenter = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            }
            updatePanelSize()
        }
    }

    private func updatePanelSize() {
        let desiredContentHeight = CyclePanelMetrics.contentHeight(
            rowCount: state.items.count,
            includesHintRow: state.showsAlignmentHints
        )

        let maxContentHeightByScreen: CGFloat = {
            let visibleFrameHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height
                ?? CyclePanelMetrics.maxFrameHeightCap
            let maxFrameHeight = min(CyclePanelMetrics.maxFrameHeightCap, visibleFrameHeight * 0.6)
            let maxFrameRect = NSRect(x: 0, y: 0,
                                      width: CyclePanelMetrics.contentWidth,
                                      height: maxFrameHeight)
            return panel.contentRect(forFrameRect: maxFrameRect).height
        }()

        let clampedContentHeight = max(minPanelContentHeight, min(desiredContentHeight, maxContentHeightByScreen))
        let targetContentRect = NSRect(x: 0, y: 0,
                                       width: CyclePanelMetrics.contentWidth,
                                       height: clampedContentHeight)
        let targetFrameSize = panel.frameRect(forContentRect: targetContentRect).size

        // Keep the panel pinned to the same center while the switcher shortcut is held.
        let center = panelAnchorCenter ?? CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let newOrigin = CGPoint(
            x: center.x - targetFrameSize.width / 2,
            y: center.y - targetFrameSize.height / 2
        )
        let newFrame = NSRect(origin: newOrigin, size: targetFrameSize)

        panel.setFrame(newFrame, display: true, animate: false)
    }
    
    // Called when user presses the switcher shortcut again while panel is visible.
    func cycleNext() {
        state.cycleNext()
        // A different window is selected now; the next H starts at a half again.
        aligner.resetCycle()
    }
    
    func isShowingSwitcher(for application: Application) -> Bool {
        guard let currentApplication else { return false }
        
        if let currentBundleID = currentApplication.bundleIdentifier,
           let targetBundleID = application.bundleIdentifier {
            return currentBundleID == targetBundleID
        }
        
        if let currentURL = currentApplication.bundleUrl,
           let targetURL = application.bundleUrl {
            return currentURL == targetURL
        }
        
        return currentApplication.title == application.title
    }
    
    // Called when user releases a configured switcher modifier.
    func activateSelectedWindow() {
        guard let item = state.currentItem else {
            hideSwitcher()
            return
        }
        
        switch item {
        case .window(let window):
            window.focus()
            hideSwitcher()
        case .action:
            let application = currentApplication
            hideSwitcher()
            
            Task { @MainActor in
                guard let application else {
                    NSSound.beep()
                    return
                }
                
                let success = await application.performNoWindowAction()
                if !success {
                    NSSound.beep()
                }
            }
        }
    }

    // MARK: - Alignment

    /// Applies an alignment to the highlighted window.
    ///
    /// Deliberately does not raise or focus: leaving focus alone is what lets you align
    /// one window, tap the digit to move to the next, align that too, and release Ctrl
    /// once. Releasing Ctrl then runs `activateSelectedWindow()`, which raises without
    /// touching geometry, so the alignment survives.
    private func handleAlignment(_ command: AlignmentCommand) {
        guard let window = state.currentWindow else {
            // The selection is a launch/focus action, not a window.
            NSSound.beep()
            return
        }

        switch aligner.perform(command, on: window) {
        case .applied(let layout):
            state.lastLayout = layout
        case .restored:
            state.lastLayout = nil
        case .refused(let reason):
            NSSound.beep()
            print("Alignment refused for \(window.title): \(reason.rawValue)")
        }
    }
    
    private func hideSwitcher() {
        removeFlagsMonitor()
        removeKeyDownMonitor()
        panel.orderOut(nil)
        state.reset()
        aligner.resetCycle()
        currentApplication = nil
        panelAnchorCenter = nil
    }
    
    private func installFlagsMonitor() {
        guard localFlagsMonitor == nil, globalFlagsMonitor == nil else { return }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            
            self.activateIfSwitcherModifierWasReleased(event.modifierFlags)
            
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.activateIfSwitcherModifierWasReleased(event.modifierFlags)
            }
        }
    }

    private func activateIfSwitcherModifierWasReleased(_ modifierFlags: NSEvent.ModifierFlags) {
        guard panel.isVisible else { return }

        let requiredModifiers = modifierManager.activateModifiers.intersection(Self.releaseModifierMask)
        guard !requiredModifiers.isEmpty else { return }

        let pressedModifiers = modifierFlags.intersection(Self.releaseModifierMask)
        if !requiredModifiers.isSubset(of: pressedModifiers) {
            activateSelectedWindow()
        }
    }
    
    private func removeFlagsMonitor() {
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }

        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isVisible else { return event }

            // Escape closes the switcher.
            if event.keyCode == AlignmentKeyMap.keyCodeEscape {
                Task { @MainActor in
                    self.hideSwitcher()
                }
                return nil
            }

            // Auto-repeat would race through the half/third/two-thirds cycle while a
            // key is simply held down.
            if event.isARepeat { return nil }

            guard let chord = AlignmentKeyMap.chord(from: event, base: self.activateModifiers),
                  let command = AlignmentKeyMap.command(for: chord) else {
                return event
            }

            Task { @MainActor in
                self.handleAlignment(command)
            }

            // Swallow it: above five windows the panel list lives in a ScrollView, and
            // an unswallowed arrow key would scroll it as well as align.
            return nil
        }
    }
    
    private func removeKeyDownMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }
    
    deinit {
        // Capture the monitor in a local variable before deinit (while still on main actor)
        let localMonitor = localFlagsMonitor
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        let globalMonitor = globalFlagsMonitor
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        let keyMonitor = keyDownMonitor
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}
