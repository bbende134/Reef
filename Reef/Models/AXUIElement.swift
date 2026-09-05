import Foundation
import Cocoa

extension NSAccessibility.Attribute {
    /// Undocumented, absent from every SDK header. AppKit and Chromium set it on the
    /// *application* element while an assistive client is listening; while it is true,
    /// frame writes are animated or ignored outright.
    static let enhancedUserInterface = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")

    /// Undocumented. Bool on a window element, true in native full screen.
    /// (`AXFullScreenButton` exists publicly; the state attribute does not.)
    static let fullScreen = NSAccessibility.Attribute(rawValue: "AXFullScreen")
}

extension AXUIElement {
    func getAttributeValue<T>(_ attribute: NSAccessibility.Attribute) -> T? {
        var value: AnyObject?

        let result = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value as? T
    }

    func performAction(_ action: NSAccessibility.Action) throws(AXError) {
        let result = AXUIElementPerformAction(self, action.rawValue as CFString)

        guard result == .success else {
            throw result
        }
    }

    func getWindowID() -> CGWindowID? {
        var windowID = CGWindowID(0)

        let result = _AXUIElementGetWindow(self, &windowID)

        guard result == .success else {
            return nil
        }

        return windowID
    }

    // MARK: - Reading geometry
    //
    // `getAttributeValue<T>` cannot serve position or size: the Accessibility API hands
    // back an AXValue box, not a CGPoint/CGSize, so `value as? CGPoint` always fails.

    /// Fetches an attribute that is boxed in an `AXValue`.
    ///
    /// Checks `CFGetTypeID` rather than using a conditional cast, which is not reliable
    /// for CoreFoundation types bridged through `AnyObject`.
    func getAXValue(_ attribute: NSAccessibility.Attribute) -> AXValue? {
        var value: AnyObject?

        let result = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        return (value as! AXValue)
    }

    func getPoint(_ attribute: NSAccessibility.Attribute) -> CGPoint? {
        guard let boxed = getAXValue(attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(boxed, .cgPoint, &point) else { return nil }
        return point
    }

    func getSize(_ attribute: NSAccessibility.Attribute) -> CGSize? {
        guard let boxed = getAXValue(attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(boxed, .cgSize, &size) else { return nil }
        return size
    }

    /// Position plus size, in Accessibility space (top-left origin, y down, global
    /// across displays). There is no public `AXFrame`, so it is composed here.
    var axFrame: CGRect? {
        guard let origin = getPoint(.position), let size = getSize(.size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Writing

    func setAttributeValue(_ attribute: NSAccessibility.Attribute, _ value: CFTypeRef) throws(AXError) {
        let result = AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)

        guard result == .success else {
            throw result
        }
    }

    func setAttributeValue(_ attribute: NSAccessibility.Attribute, _ point: CGPoint) throws(AXError) {
        var point = point
        guard let boxed = AXValueCreate(.cgPoint, &point) else {
            throw AXError.illegalArgument
        }
        try setAttributeValue(attribute, boxed)
    }

    func setAttributeValue(_ attribute: NSAccessibility.Attribute, _ size: CGSize) throws(AXError) {
        var size = size
        guard let boxed = AXValueCreate(.cgSize, &size) else {
            throw AXError.illegalArgument
        }
        try setAttributeValue(attribute, boxed)
    }

    func setAttributeValue(_ attribute: NSAccessibility.Attribute, _ flag: Bool) throws(AXError) {
        let boxed: CFTypeRef = flag ? kCFBooleanTrue : kCFBooleanFalse
        try setAttributeValue(attribute, boxed)
    }

    /// Whether the app will accept a write to this attribute at all — fixed-size utility
    /// windows report false for `.size`.
    func isAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(self, attribute.rawValue as CFString, &settable)
        return result == .success && settable.boolValue
    }

    /// Bounds how long a wedged app can block the caller.
    ///
    /// Per the header, passing the system-wide element sets this process-globally;
    /// setting it on any other element affects only that exact object instance.
    @discardableResult
    func setMessagingTimeout(_ seconds: Float) -> AXError {
        AXUIElementSetMessagingTimeout(self, seconds)
    }
}

extension AXError: @retroactive _BridgedNSError {}
extension AXError: @retroactive _ObjectiveCBridgeableError {}
extension AXError: @retroactive Error {}

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError
