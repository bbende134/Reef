//
//  CyclePanelState.swift
//  Reef
//
//  Created by Xander Gouws on 23-01-2026.
//

import Foundation

enum CyclePanelAction {
    case launchApp
    case openWindow
    
    var title: String {
        switch self {
        case .launchApp:
            return "Launch app"
        case .openWindow:
            return "Focus app"
        }
    }
}

enum CyclePanelItem {
    case window(Window)
    case action(CyclePanelAction)
}

@MainActor
final class CyclePanelState: ObservableObject {
    @Published var applicationTitle: String = ""
    @Published var items: [CyclePanelItem] = []
    @Published var selectedIndex: Int = 0
    /// The alignment most recently applied to the selected window, for the row badge.
    /// Nil whenever the selection changes or nothing has been aligned yet.
    @Published var lastLayout: WindowLayout?
    
    var windows: [Window] {
        items.compactMap { item in
            if case let .window(window) = item {
                return window
            }
            
            return nil
        }
    }
    
    var currentItem: CyclePanelItem? {
        guard !items.isEmpty, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }
    
    var currentWindow: Window? {
        guard let currentItem else { return nil }
        
        if case let .window(window) = currentItem {
            return window
        }
        
        return nil
    }
    
    var currentAction: CyclePanelAction? {
        guard let currentItem else { return nil }
        
        if case let .action(action) = currentItem {
            return action
        }
        
        return nil
    }
    
    /// Whether the alignment hint footer should be shown.
    ///
    /// Hidden when the selection is a launch/focus action rather than a window, since
    /// none of the alignment keys apply to it. Defaults to on.
    var showsAlignmentHints: Bool {
        guard currentWindow != nil else { return false }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "showAlignmentHints") != nil else { return true }
        return defaults.bool(forKey: "showAlignmentHints")
    }

    func setApplication(_ application: Application) {
        self.applicationTitle = application.title
        
        let windows = application.getWindows()
        if windows.isEmpty {
            let action: CyclePanelAction = application.isRunning ? .openWindow : .launchApp
            self.items = [.action(action)]
        } else {
            self.items = windows.map(CyclePanelItem.window)
        }
        
        self.selectedIndex = 0
        self.lastLayout = nil
    }
    
    func cycleNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        lastLayout = nil
    }
    
    func reset() {
        items = []
        selectedIndex = 0
        applicationTitle = ""
        lastLayout = nil
    }
}
