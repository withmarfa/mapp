import AppKit
import SwiftUI

extension NSView {
    /// `rect` (the view's bounds where nil) in screen coordinates.
    func screenRect(of rect: NSRect?) -> NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(rect ?? bounds, to: nil))
    }
}

/// A borderless panel that can take the keyboard, so a field in it types, and is never the main window.
final class ValueEditPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: Panel

/// The designed and the blend variants: a child window under the value, in N1's shape. They differ in the surface and
/// the row metrics only.
@MainActor
final class ValueEditPanelSession: ValueEditSession {
    enum Surface { case designed, glass }

    let request: ValueEditRequest
    let model: ValueEditModel
    let anchor: NSView
    private let rect: NSRect?
    private let settings: ValueEditSettings
    private let surface: Surface
    private var panel: ValueEditPanel?
    private weak var parent: NSWindow?
    private var savedResponder: NSResponder?

    var window: NSWindow? { panel }

    init(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?, settings: ValueEditSettings, surface: Surface) {
        self.request = request
        self.anchor = anchor
        self.rect = rect
        self.settings = settings
        self.surface = surface
        model = ValueEditModel(request)
    }

    private var metrics: ValueEditMetrics { surface == .designed ? .designed : .menu }

    func open() {
        guard let parent = anchor.window else { return }
        self.parent = parent
        savedResponder = parent.firstResponder
        let host = NSHostingView(rootView: ValueEditContent(model: model, metrics: metrics).interfaceTextStyle())
        host.sizingOptions = []
        let panel = ValueEditPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = parent.effectiveAppearance
        panel.contentView = surfaceView(around: host)
        self.panel = panel
        model.layoutChanged = { [weak self] in self?.layout() }
        layout()
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    private func surfaceView(around host: NSView) -> NSView {
        host.autoresizingMask = [.width, .height]
        switch surface {
        case .designed:
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = settings.panelRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.layer?.borderWidth = 0.5
            effect.layer?.borderColor = NSColor.separatorColor.cgColor
            host.frame = effect.bounds
            effect.addSubview(host)
            return effect
        case .glass:
            let glass = NSGlassEffectView()
            glass.cornerRadius = settings.panelRadius
            glass.style = settings.clearGlass ? .clear : .regular
            glass.contentView = host
            return glass
        }
    }

    private func layout() {
        guard let panel, let parent, let target = anchor.screenRect(of: rect) else { return }
        var visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? target.insetBy(dx: -400, dy: -400)
        // Sideways a panel stays in its window, which it belongs to; up and down it may leave it, as a menu does.
        let inside = parent.frame.insetBy(dx: 8, dy: 0)
        visible = CGRect(x: max(visible.minX, inside.minX), y: visible.minY, width: min(visible.maxX, inside.maxX) - max(visible.minX, inside.minX), height: visible.height)
        let natural = model.naturalHeight > 0 ? model.naturalHeight : estimatedHeight
        let placement = ValuePanelFrame.placement(
            anchor: target, visible: visible, contentHeight: natural, floor: settings.widthFloor, ceiling: settings.widthCeiling,
            gap: settings.gap)
        model.maxHeight = placement.frame.height
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
    }

    private var estimatedHeight: CGFloat {
        switch model.kind {
        case .date: 420
        default: CGFloat(model.rows.count) * metrics.rowHeight + 2 * metrics.padding + (model.hasSearch ? 64 : 0)
        }
    }

    func anchorMoved() { layout() }

    func close(restoringFocus: Bool) {
        guard let panel else { return }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        guard restoringFocus, let parent else { return }
        parent.makeKey()
        if let saved = savedResponder, parent.firstResponder !== saved { parent.makeFirstResponder(saved) }
    }
}

// MARK: Popover

/// The system's popover. Its content is the designed panel's rows for the dates, people and tags a menu cannot hold, in
/// the system's metrics; the popover variant uses it for every kind.
@MainActor
final class ValueEditPopoverSession: NSObject, ValueEditSession, NSPopoverDelegate {
    let request: ValueEditRequest
    let model: ValueEditModel
    let anchor: NSView
    private let rect: NSRect?
    private let settings: ValueEditSettings
    private let metrics: ValueEditMetrics
    private let popover = NSPopover()
    private var savedResponder: NSResponder?

    var window: NSWindow? { popover.contentViewController?.view.window }

    init(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?, settings: ValueEditSettings, metrics: ValueEditMetrics) {
        self.request = request
        self.anchor = anchor
        self.rect = rect
        self.settings = settings
        self.metrics = metrics
        model = ValueEditModel(request)
        super.init()
    }

    private var width: CGFloat { min(max((rect ?? anchor.bounds).width, settings.widthFloor), max(settings.widthFloor, settings.widthCeiling)) }

    /// The tallest a popover is made before its list scrolls.
    private var room: CGFloat { max(240, ((anchor.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 160) }

    func open() {
        savedResponder = anchor.window?.firstResponder
        let host = NSHostingController(rootView: ValueEditContent(model: model, metrics: metrics).interfaceTextStyle())
        host.sizingOptions = []
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
        model.maxHeight = room
        model.layoutChanged = { [weak self] in self?.layout() }
        popover.contentSize = NSSize(width: width, height: model.kind == .tags ? 200 : 160)
        // A value on the page is as wide as the column; its arrow belongs by the text at the start of it.
        var target = rect ?? anchor.bounds
        target.size.width = min(target.width, 120)
        popover.show(relativeTo: target, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }

    private func layout() {
        let height = min(model.naturalHeight, room)
        guard height > 0, abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = NSSize(width: width, height: height)
    }

    func anchorMoved() {}

    func close(restoringFocus: Bool) {
        popover.delegate = nil
        if popover.isShown { popover.close() }
        guard restoringFocus, let window = anchor.window else { return }
        window.makeKey()
        if let saved = savedResponder, window.firstResponder !== saved { window.makeFirstResponder(saved) }
    }

    func popoverDidClose(_ notification: Notification) {
        model.close()
    }
}

// MARK: Menu

/// The system's menu, for a list of words: nothing in it is drawn by hand.
@MainActor
final class ValueEditMenuSession: NSObject, ValueEditSession {
    let request: ValueEditRequest
    let model: ValueEditModel
    let anchor: NSView
    private let rect: NSRect?
    private let settings: ValueEditSettings
    private var menu: NSMenu?

    var window: NSWindow? { nil }

    init(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?, settings: ValueEditSettings) {
        self.request = request
        self.anchor = anchor
        self.rect = rect
        self.settings = settings
        model = ValueEditModel(request)
        super.init()
    }

    func open() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = (rect ?? anchor.bounds).width
        for row in model.rows {
            switch row.role {
            case .header:
                menu.addItem(.sectionHeader(title: row.title))
            case .separator:
                menu.addItem(.separator())
            case .option, .create:
                let item = NSMenuItem(title: row.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = row.id
                item.state = row.isCurrent ? .on : .off
                if case .status(let group) = row.mark { item.image = Self.markImage(for: group) }
                menu.addItem(item)
            }
        }
        self.menu = menu
        let value = rect ?? anchor.bounds
        let point = NSPoint(x: value.minX, y: anchor.isFlipped ? value.maxY + settings.gap : value.minY - settings.gap)
        // Tracking a menu runs its own event loop, which waits until the click that asked for it has been handled.
        Task { [weak self] in
            guard let self, let menu = self.menu else { return }
            menu.popUp(positioning: nil, at: point, in: anchor)
            model.close()
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.activate(id)
    }

    private static func markImage(for group: StatusGroup?) -> NSImage? {
        let renderer = ImageRenderer(content: StatusMark(mark: .init(group: group), size: 10).padding(2))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }

    func anchorMoved() {}

    func close(restoringFocus: Bool) {
        menu?.cancelTracking()
        menu = nil
    }
}
