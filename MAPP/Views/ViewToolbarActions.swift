import SwiftUI

extension View {
    /// Edit View at the title this view gives its window, for any layout.
    func viewEditHover(_ browser: Browser, title: String, subtitle: String) -> some View {
        overlay(alignment: .topLeading) { ViewEditHover(browser: browser, title: title, subtitle: subtitle).ignoresSafeArea(.container, edges: .top) }
    }
}

extension String {
    /// A window's subtitle as plain text, to measure where its title ends: the count, and what the Text version adds.
    static func windowSubtitle(count: Int, isSearching: Bool, suffix: String? = nil, isEdited: Bool) -> String {
        let counted = isSearching ? AttributedString(localized: "^[\(count) result](inflect: true)") : AttributedString(localized: "^[\(count) item](inflect: true)")
        var text = String(counted.characters)
        if let suffix { text = String(localized: "\(text), \(suffix)") }
        return isEdited ? String(localized: "\(text), edited") : text
    }
}

/// Edit View at the window's title: a quiet pencil that shows while the pointer is over the title, drawn over the toolbar
/// so it takes no room from the items beside it and never moves the search field. macOS has no toolbar placement in
/// the title's own area, and a toolbar item would keep its room while hidden. The pencil is not focusable and is hidden
/// from VoiceOver; the keyboard and VoiceOver reach Edit View through its menu command and the command palette.
struct ViewEditHover: View {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    let browser: Browser
    /// What the toolbar writes in the column's title area, so the pencil can follow it.
    let title: String
    let subtitle: String
    @State private var isHovering = false

    /// Where the system starts the title, from the column's leading edge, and the height of its area.
    private static let leading: CGFloat = 20
    private static let height: CGFloat = 44
    private static let pencilWidth: CGFloat = 22

    var body: some View {
        let isAvailable = SavedViews.canEdit(browser, in: library) && !browser.showsViewPanel && browser.offersViewOptions
            && !browser.isSearchExpanded
        if isAvailable {
            HStack(spacing: 6) {
                Color.clear.frame(width: Self.leading + Self.textWidth(title, subtitle))
                Button { browser.openViewPanel(in: library) } label: {
                    Image(systemName: "pencil")
                        .interfaceFont(.caption.weight(.semibold))
                        .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: Self.pencilWidth, height: Self.height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("Edit View")
                .accessibilityHidden(true)
            }
            .frame(height: Self.height)
            .background { PointerOver(isInside: $isHovering, target: Self.pencilWidth) { browser.openViewPanel(in: library) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private static func textWidth(_ title: String, _ subtitle: String) -> CGFloat {
        let bold = NSFont.systemFont(ofSize: 13, weight: .bold)
        let small = NSFont.systemFont(ofSize: 11)
        let widest = max((title as NSString).size(withAttributes: [.font: bold]).width,
                         (subtitle as NSString).size(withAttributes: [.font: small]).width)
        return widest.rounded(.up)
    }
}

/// Reports whether the pointer is over its area without taking any click, so the title beneath still drags the window.
/// The titlebar sits above the page's content and takes a click before SwiftUI's button under it, so a click on the
/// area's trailing `target` width is heard here, as the field in `ColumnSearch` hears its clicks.
private struct PointerOver: NSViewRepresentable {
    @Binding var isInside: Bool
    let target: CGFloat
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
        view.onChange = { isInside = $0 }
        view.target = target
        view.onClick = onClick
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        var onClick: () -> Void = {}
        var target: CGFloat = 0
        private var isInside = false
        private var monitor: Any?
        private var menuEnd: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { set(true) }
        override func mouseExited(with event: NSEvent) { set(false) }

        private func set(_ value: Bool) {
            isInside = value
            onChange(value)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            // A menu that is tracking swallows the exit, so the pointer's place is read again when one closes.
            menuEnd = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.set(self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)))
                }
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

        private func take(windowNumber: Int, at location: CGPoint) -> Bool {
            guard isInside, windowNumber == window?.windowNumber else { return false }
            let point = convert(location, from: nil)
            guard bounds.contains(point), point.x >= bounds.maxX - target else { return false }
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
