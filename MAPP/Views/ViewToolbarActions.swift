import SwiftUI

extension View {
    /// Edit View beside the title this view gives its window, for any layout.
    func viewEditHover(_ browser: Browser, title: String) -> some View {
        overlay(alignment: .topLeading) { ViewEditHover(browser: browser, title: title).ignoresSafeArea(.container, edges: .top) }
    }
}

/// Edit View beside the window's title: a quiet pencil that shows while the pointer is over the title, drawn over the
/// toolbar so it takes no room from the items beside it and never moves the search field. SwiftUI has no toolbar
/// placement beside the title (`principal` is centered), and a toolbar item would keep its room while hidden, so the
/// pencil is placed from the title's own frame, read from the toolbar's text fields each time it is needed. It shows
/// only where there is room for it before the next toolbar item. It is not focusable and is hidden from VoiceOver; the
/// keyboard and VoiceOver reach Edit View through its menu command and the command palette.
struct ViewEditHover: View {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    let browser: Browser
    /// What the toolbar writes as the column's title, which finds its text among the toolbar's views.
    let title: String
    @State private var spot = TitleSpot()

    var body: some View {
        let isAvailable = SavedViews.canEdit(browser, in: library) && !browser.showsViewPanel && browser.offersViewOptions
            && !browser.isSearchExpanded
        ZStack(alignment: .topLeading) {
            TitleSpotReader(title: title, isEnabled: isAvailable, spot: $spot) { browser.openViewPanel(in: library) }
            if isAvailable, spot.isInside, let pencil = spot.pencil {
                Button { browser.openViewPanel(in: library) } label: {
                    Image(systemName: "pencil")
                        .interfaceFont(.caption.weight(.semibold))
                        .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: pencil.width, height: pencil.height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Edit View")
                .accessibilityHidden(true)
                .offset(x: pencil.minX, y: pencil.minY)
            }
        }
        .frame(height: TitleSpotReader.TrackingView.toolbarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Where the pointer is in relation to the title, in the reader's own coordinates.
struct TitleSpot: Equatable {
    /// Whether the pointer is over the title or the pencil.
    var isInside = false
    /// Where the pencil goes, or nil while the title is not in the toolbar or leaves no room for it.
    var pencil: CGRect?
}

/// Finds the title the toolbar draws and reports the pointer's place against it, without taking any click, so the
/// title beneath still drags the window. The titlebar sits above the page's content and takes a click before SwiftUI's
/// button under it, so a click on the pencil's frame is heard here, as the field in `ColumnSearch` hears its clicks.
/// It stays in place while the pencil is unavailable, so the pointer's place is read again, not remembered, when the
/// pencil returns.
private struct TitleSpotReader: NSViewRepresentable {
    let title: String
    let isEnabled: Bool
    @Binding var spot: TitleSpot
    let onClick: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        update(view)
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        update(view)
    }

    private func update(_ view: TrackingView) {
        view.onChange = { spot = $0 }
        view.onClick = onClick
        view.set(title: title, isEnabled: isEnabled)
    }

    final class TrackingView: NSView {
        /// The height of the window's toolbar, which the title sits in.
        static let toolbarHeight: CGFloat = 52
        private static let pencilSize = CGSize(width: 22, height: 28)
        private static let gap: CGFloat = 4

        var onChange: (TitleSpot) -> Void = { _ in }
        var onClick: () -> Void = {}
        private var title = ""
        private var isEnabled = false
        private var spot = TitleSpot()
        private var isRefreshScheduled = false
        private var monitor: Any?
        private var menuEnd: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { refresh() }
        override func mouseMoved(with event: NSEvent) { refresh() }
        override func mouseExited(with event: NSEvent) { refresh() }

        /// The toolbar lays its title out after the page does, so a change of frame or of text is read on the next turn.
        override func layout() {
            super.layout()
            scheduleRefresh()
        }

        func set(title: String, isEnabled: Bool) {
            guard title != self.title || isEnabled != self.isEnabled else { return }
            self.title = title
            self.isEnabled = isEnabled
            scheduleRefresh()
        }

        private func scheduleRefresh() {
            guard !isRefreshScheduled else { return }
            isRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.isRefreshScheduled = false
                self?.refresh()
            }
        }

        private func refresh() {
            var next = TitleSpot()
            if isEnabled, let pencil = pencilFrame() {
                next.pencil = pencil
                next.isInside = hoverFrame(with: pencil).contains(pointer)
            }
            guard next != spot else { return }
            spot = next
            onChange(next)
        }

        private var pointer: NSPoint {
            guard let window else { return NSPoint(x: -1, y: -1) }
            return convert(window.mouseLocationOutsideOfEventStream, from: nil)
        }

        /// The title's text, from the toolbar's own views. Nothing here names a private class: it is the text field that
        /// holds the title, found by its text and its place over this column, and the title's area is the widest
        /// ancestor narrower than the window, which is the area the toolbar gives the title before its next item.
        private func titleFrames() -> (text: CGRect, area: CGRect)? {
            guard let window, let content = window.contentView, let themeFrame = content.superview else { return nil }
            for root in themeFrame.subviews where root !== content {
                guard let field = textFields(in: root).first(where: { field in
                    let frame = convert(field.bounds, from: field)
                    return !field.isHiddenOrHasHiddenAncestor && field.stringValue == title && bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
                }) else { continue }
                var area: NSView = field
                while let parent = area.superview, convert(parent.bounds, from: parent).width < window.frame.width - 1 { area = parent }
                let text = textFields(in: area).filter { !$0.isHiddenOrHasHiddenAncestor && !$0.stringValue.isEmpty }
                    .map { convert($0.bounds, from: $0) }.reduce(CGRect.null) { $0.union($1) }
                return (text, convert(area.bounds, from: area))
            }
            return nil
        }

        private func textFields(in view: NSView) -> [NSTextField] {
            if let field = view as? NSTextField { return [field] }
            return view.subviews.flatMap(textFields(in:))
        }

        private func pencilFrame() -> CGRect? {
            guard let (text, area) = titleFrames(), !text.isNull else { return nil }
            let size = Self.pencilSize
            let frame = CGRect(x: text.maxX + Self.gap, y: area.midY - size.height / 2, width: size.width, height: size.height)
            return frame.maxX <= area.maxX ? frame : nil
        }

        private func hoverFrame(with pencil: CGRect) -> CGRect {
            guard let (text, area) = titleFrames() else { return pencil }
            return CGRect(x: text.minX, y: area.minY, width: pencil.maxX - text.minX, height: area.height)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            scheduleRefresh()
            guard window != nil else { return }
            // A menu that is tracking swallows the exit, so the pointer's place is read again when one closes.
            menuEnd = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let number = event.windowNumber
                let location = event.locationInWindow
                let isTaken = MainActor.assumeIsolated { self?.take(windowNumber: number, at: location) ?? false }
                return isTaken ? nil : event
            }
        }

        isolated deinit { removeMonitor() }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let menuEnd { NotificationCenter.default.removeObserver(menuEnd) }
            menuEnd = nil
        }

        /// A click is taken only inside the pencil's own frame, read again now.
        private func take(windowNumber: Int, at location: CGPoint) -> Bool {
            guard isEnabled, spot.isInside, windowNumber == window?.windowNumber,
                  let pencil = pencilFrame(), pencil.contains(convert(location, from: nil))
            else { return false }
            onClick()
            return true
        }
    }
}

/// What waits in the toolbar while the window shows something unsaved and the panel is closed: Revert and Save for a
/// view, and Save as View for a place that is not one. They are locked, as a person's layout must not lose them. The
/// server's absence is said by the panel, which a Save that cannot reach it opens.
struct ViewChangeItems: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser

    var body: some CustomizableToolbarContent {
        let isAvailable = browser.offersViewOptions && !browser.showsViewPanel
        let showsChanges = isAvailable && browser.hasViewChanges
        let showsSaveAs = isAvailable && SavedViews.hasChoicesToKeep(browser, in: library)
        let canSaveAs = SavedViews.canSave(browser, in: library)
        ToolbarItem(id: "revertView") {
            Button("Revert") { browser.revertView(in: library) }
                .disabled(browser.viewPanel?.isSaving == true)
                .help("Put the view back as it was saved")
                .accessibilityIdentifier("RevertViewToolbar")
        }
        .customizationBehavior(.disabled)
        .hidden(!showsChanges)
        ToolbarItem(id: "saveView") {
            Button("Save") { SavedViews.save(browser, in: library, order: order) }
                .buttonStyle(.borderedProminent)
                .disabled(browser.viewPanel?.isSaving == true)
                .help("Save the changes to this view")
                .accessibilityIdentifier("SaveViewToolbar")
        }
        .customizationBehavior(.disabled)
        .hidden(!showsChanges)
        ToolbarItem(id: "saveAsView") {
            Button("Save as View…") { browser.openNewViewPanel(in: library) }
                .disabled(!canSaveAs)
                .help(canSaveAs ? "Make a view of what this window shows" : "Saving a view needs your Marfa server")
                .accessibilityIdentifier("SaveAsViewToolbar")
        }
        .customizationBehavior(.disabled)
        .hidden(!showsSaveAs)
    }
}

/// What the panel does with its changes, above it in the right sidebar's toolbar: Cancel and Save while something
/// changed, one Done when nothing did, and Save as View beside it for a place that is not a view. Return saves, unless
/// the page has the keyboard, and Escape cancels. Being in a toolbar only while the panel is, they are locked and come
/// and go.
struct ViewPanelToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel
    let editor: EditorController?

    var body: some CustomizableToolbarContent {
        let state = browser.viewPanelState(window: SavedViews.panelWindow(browser, in: library, order: order), in: library)
        let returnKey: KeyboardShortcut? = editor?.isFocused == true ? nil : .defaultAction
        if state == .unchanged {
            if panel.purpose == .place {
                let canSave = SavedViews.canSave(browser, in: library)
                ToolbarItem(id: "viewPanelSaveAs") {
                    Button("Save as View…") { browser.openNewViewPanel(in: library) }
                        .disabled(!canSave)
                        .help(canSave ? "" : String(localized: "This place can’t be saved as a view."))
                        .accessibilityIdentifier("ViewPanelSaveAs")
                }
                .customizationBehavior(.disabled)
            }
            ToolbarItem(id: "viewPanelDone") {
                Button("Done") { browser.closeViewPanel(in: library) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(returnKey)
                    .accessibilityIdentifier("ViewPanelDone")
            }
            .customizationBehavior(.disabled)
        } else {
            ToolbarItem(id: "viewPanelCancel") {
                Button("Cancel") { browser.cancelViewPanel(in: library) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(panel.isSaving)
                    .accessibilityIdentifier("ViewPanelCancel")
            }
            .customizationBehavior(.disabled)
            ToolbarItem(id: "viewPanelSave") {
                Button("Save") { SavedViews.save(browser, in: library, order: order) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(returnKey)
                    .disabled(state != .ready || panel.isSaving)
                    .accessibilityIdentifier("ViewPanelSave")
            }
            .customizationBehavior(.disabled)
        }
    }
}

/// What a toolbar cannot say, at the top of the panel: why Save is dimmed, and why the last save failed.
struct ViewPanelNotes: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel

    var body: some View {
        let state = browser.viewPanelState(window: SavedViews.panelWindow(browser, in: library, order: order), in: library)
        if case .blocked(let reason?) = state {
            note(reason)
        }
        if let failure = panel.failure {
            note(failure, color: .red)
        }
    }

    private func note(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .interfaceFont(.callout)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Asks before a save that would leave something out.
struct ViewSaveConfirmation: ViewModifier {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Save Changes to “\(panel.shownName)”?", isPresented: confirming, titleVisibility: .visible
        ) {
            Button("Save") { SavedViews.save(browser, in: library, order: order, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirming: Binding<Bool> {
        Binding { panel.confirmation != nil } set: { if !$0 { panel.confirmation = nil } }
    }

    /// What the view will not keep, and the conditions of its filter that stay as they are.
    private var confirmationMessage: String {
        guard let confirmation = panel.confirmation else { return "" }
        var lines: [String] = []
        if !confirmation.unkept.isEmpty {
            lines.append(String(localized: "The view won’t keep:"))
            lines += confirmation.unkept.map { "• " + SavedViews.describe($0) }
        }
        if !confirmation.unchanged.isEmpty {
            lines.append(String(localized: "The view’s filter keeps these conditions as they are:"))
            lines += confirmation.unchanged.map { "• " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}
