import AppKit

/// A window for a test that needs one. WebKit and SwiftUI lay it out, draw it and give it the keyboard as any
/// other, but it is fully transparent: the tests run in the app while the person works, and windows flashing up in
/// front of them are confusing.
final class TestWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        alphaValue = 0
    }

    /// Keeps the size a test asks for. AppKit fits a titled window to its screen, and a runner's screen can be narrower
    /// than the window a test needs; this one is never seen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
