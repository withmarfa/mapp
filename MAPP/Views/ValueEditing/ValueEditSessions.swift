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

/// A child window under the value, in the shape of a system menu on the system's glass.
@MainActor
final class ValueEditPanelSession: ValueEditSession {
    let request: ValueEditRequest
    let model: ValueEditModel
    let anchor: NSView
    private var rect: NSRect?
    private var panel: ValueEditPanel?
    private weak var parent: NSWindow?
    private var savedResponder: NSResponder?
    private var layoutPending = false
    /// What the content wants across, worked out once so the panel does not change width as the person types.
    private var width: CGFloat?

    var window: NSWindow? { panel }

    init(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?) {
        self.request = request
        self.anchor = anchor
        self.rect = rect
        model = ValueEditModel(request)
    }

    func open() {
        guard let parent = anchor.window else { return }
        self.parent = parent
        savedResponder = parent.firstResponder
        let host = NSHostingView(rootView: ValueEditContent(model: model).interfaceTextStyle())
        host.sizingOptions = []
        let panel = ValueEditPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = parent.effectiveAppearance
        panel.contentView = Self.surface(holding: host, style: ValuePanelStyle.stored(), appearance: panel.appearance)
        self.panel = panel
        model.layoutChanged = { [weak self] in self?.layoutSoon() }
        width = model.fittingWidth(scale: InterfaceStyle.scale(for: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize))
        layout()
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The panel's ground: the system's glass, or, in Solid, the window's own color. Either is cut to the panel's corners
    /// by its own layer, so nothing square is left behind it.
    private static func surface(holding host: NSView, style: ValuePanelStyle, appearance: NSAppearance?) -> NSView {
        switch style {
        case .glass:
            let glass = NSGlassEffectView()
            glass.cornerRadius = ValueEditMetrics.panelRadius
            glass.contentView = host
            return glass
        case .solid:
            let solid = SolidSurface()
            solid.wantsLayer = true
            solid.layer?.cornerRadius = ValueEditMetrics.panelRadius
            solid.layer?.cornerCurve = .continuous
            solid.layer?.masksToBounds = true
            host.frame = solid.bounds
            host.autoresizingMask = [.width, .height]
            solid.addSubview(host)
            return solid
        }
    }

    /// Draws the window's color, resolved again whenever the appearance changes.
    private final class SolidSurface: NSView {
        override func updateLayer() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }

        override var wantsUpdateLayer: Bool { true }
    }

    /// The content reports its height from inside a SwiftUI update, where a window resize leaves the glass at the size it
    /// had before, so the panel is resized once that update is over, and once for any number of reports.
    private func layoutSoon() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.layoutPending = false
            self?.layout()
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
            anchor: target, visible: visible, contentHeight: natural, floor: ValueEditMetrics.widthFloor, ceiling: ValueEditMetrics.widthCeiling,
            gap: ValueEditMetrics.gap, fitting: width, centered: request.isCentered)
        model.maxHeight = placement.frame.height
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
        // A frame the window already has still leaves its content at an older size when the content view was not told.
        panel.contentView?.frame = NSRect(origin: .zero, size: placement.frame.size)
    }

    private var estimatedHeight: CGFloat {
        switch model.kind {
        case .date: 420
        default: CGFloat(model.rows.count) * ValueEditMetrics.rowHeight + 2 * ValueEditMetrics.padding + (model.hasSearch ? 64 : 0)
        }
    }

    func anchorMoved() { layoutSoon() }

    func valueMoved(to rect: NSRect) {
        guard self.rect != rect else { return }
        self.rect = rect
        layoutSoon()
    }

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

extension ValueEditModel {
    /// The width the panel needs for its rows and its chip, within the bounds of its kind (`ValueEditMetrics.widthBounds`),
    /// or nil where the value's own width decides.
    func fittingWidth(scale: CGFloat) -> CGFloat? {
        guard let bounds = ValueEditMetrics.widthBounds(for: kind) else { return nil }
        let font = NSFont.systemFont(ofSize: ValueEditMetrics.textSize * scale)
        func text(_ string: String) -> CGFloat { (string as NSString).size(withAttributes: [.font: font]).width }
        let edges = (2 * 8 + 2 * ValueEditMetrics.padding) * scale
        var widest: CGFloat = 0
        for row in rows where row.role == .option || row.role == .create {
            let mark = row.mark == .none ? 0 : 21 * scale
            let detail = row.detail.map { text($0) + 8 * scale } ?? 0
            widest = max(widest, mark + text(row.title) + detail + 8 * scale)
        }
        if !holdsMany {
            for chip in chips { widest = max(widest, 21 * scale + text(chip.title) + 28 * scale) }
        }
        return min(max(widest + edges, bounds.lowerBound * scale), bounds.upperBound * scale)
    }
}
