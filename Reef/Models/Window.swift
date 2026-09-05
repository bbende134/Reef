//
//  Window.swift
//  Reef
//
//  Created by Xander Gouws on 12-09-2025.
//

import Foundation
import Cocoa


class Window: Identifiable {
    var id: CGWindowID { cgWindowID ?? 0 }
    var element: AXUIElement
    var cgWindowID: CGWindowID?
    var application: Application

    init(_ element: AXUIElement, _ application: Application) {
        self.element = element
        self.cgWindowID = element.getWindowID()
        self.application = application
    }
    
    var title: String {
        if let title: String = self.element.getAttributeValue(.title) {
            return title
        }
        
        return application.title
    }
    
    func focus() {
        do {
            try self.element.performAction(.raise)
            self.application.activate()
        } catch {
            try? self.application.reopen()
        }
    }
    
    static func getFrontWindow() -> Window? {
        guard let frontApplication = Application.getFrontApplication() else {
            return nil
        }
        
        if let focusedWindow = frontApplication.getFocusedWindow() {
            return focusedWindow
        }
        
        if let firstWindow = frontApplication.getFirstWindow() {
            return firstWindow
        }
        
        return nil
    }
}

// MARK: - Geometry and state
//
// Everything alignment needs to know before it touches a window.

extension Window {
    /// The window's frame in Accessibility space (top-left origin, y down).
    var axFrame: CGRect? {
        element.axFrame
    }

    /// The owning application's AX element. Nil once the app has terminated.
    var applicationElement: AXUIElement? {
        application.element
    }

    var subrole: String? {
        element.getAttributeValue(.subrole)
    }

    /// `Application.getAXWindows()` returns everything under `AXWindows`, which includes
    /// dialogs, sheets and floating panels. A nil subrole is treated as permissive.
    var isStandardWindow: Bool {
        guard let subrole else { return true }
        return subrole == NSAccessibility.Subrole.standardWindow.rawValue
    }

    /// True in *native* full screen. Writing position or size to such a window leaves it
    /// in a corrupted half-full-screen state, so alignment refuses instead.
    var isFullScreen: Bool {
        element.getAttributeValue(.fullScreen) ?? false
    }

    var isMinimized: Bool {
        element.getAttributeValue(.minimized) ?? false
    }

    var isResizable: Bool {
        element.isAttributeSettable(.size)
    }

    /// Whether alignment can act on this window at all, and why not if it cannot.
    var alignmentRefusal: WindowAlignmentRefusal? {
        if isMinimized { return .minimized }
        if isFullScreen { return .fullScreen }
        if !isStandardWindow { return .notStandardWindow }
        if !isResizable { return .notResizable }
        return nil
    }
}

/// Why a window cannot be aligned. Surfaced only as a beep plus a debug log — the panel
/// is a transient overlay and an alert would be worse than the problem.
enum WindowAlignmentRefusal: String {
    case minimized
    case fullScreen
    case notStandardWindow
    case notResizable
    case noFrame
    case noScreen
    /// `R` pressed on a window Reef has not moved, so there is nothing to go back to.
    case noHistory
}
