//
//  ReefApp.swift
//  Reef
//
//  Created by Xander Gouws on 12-09-2025.
//

import SwiftUI
import KeyboardShortcuts
import ServiceManagement

@main
struct ReefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var profileManager: ProfileManager
    @AppStorage("launchOnLogin") private var launchOnLogin = true

    init() {
        let profileManager = ProfileManager()
        _profileManager = StateObject(wrappedValue: profileManager)
        AppDelegate.profileManager = profileManager
        
        // Sync launch at login state with system
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            _launchOnLogin = AppStorage(wrappedValue: status == .enabled, "launchOnLogin")
        }
    }

    /// The menu bar icon, loaded from Resources rather than an asset catalog.
    ///
    /// `Image("menu_placeholder")` needs a compiled Assets.car, and `actool` ships only
    /// with Xcode. The imageset declared 22 pt at 1x with template rendering, so the 2x
    /// PNG is loaded and sized down to match.
    static let menuBarIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "ReefMenuIcon44", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 22, height: 22)
            return image
        }

        let fallback = NSImage(systemSymbolName: "rectangle.split.2x2",
                               accessibilityDescription: "Reef") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }()

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(profileManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(profileManager)
        } label: {
            MenuBarLabel(profileManager: profileManager)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var instance: AppDelegate!
    static var profileManager: ProfileManager!
    static private(set) var modifierManager: ModifierManager!
    
    private var cycleController: CyclePanelController!
    private var shortcutManager: ShortcutController!
    private var windowManager: PreferencesController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.instance = self
        AppDelegate.modifierManager = ModifierManager()
        
        cycleController = CyclePanelController(modifierManager: AppDelegate.modifierManager)
        shortcutManager = ShortcutController(cycleController, AppDelegate.profileManager)
        windowManager = PreferencesController()
        
        NSApp.setActivationPolicy(.accessory)
        WindowRegistry.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.profileManager.saveNow()
    }
}
