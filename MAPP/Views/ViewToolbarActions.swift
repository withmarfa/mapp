import SwiftUI

extension EnvironmentValues {
    /// The identifier of the toolbar layout the window's columns share, for a view that adds its own items to it.
    @Entry var toolbarLayout = WindowToolbarLayout.list
}

extension View {
    /// Names the view in the window and draws its title in the toolbar, with Edit View beside it, for any layout.
    /// The window keeps the name (`navigationTitle`) for the Window menu and Mission Control; the toolbar's own title is
    /// removed for `ViewTitleItem`, since SwiftUI offers no way to put a control beside the system's title.
    func viewTitle(_ browser: Browser, title: String, subtitle: Text) -> some View {
        modifier(ViewTitleModifier(browser: browser, title: title, subtitle: subtitle))
    }
}

private struct ViewTitleModifier: ViewModifier {
    @Environment(\.toolbarLayout) private var layout
    let browser: Browser
    let title: String
    let subtitle: Text

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar(removing: .title)
            .toolbar(id: layout) { ViewTitleItem(browser: browser, title: title, subtitle: subtitle) }
    }
}

/// The view's title and subtitle, as the toolbar sets its own, at the toolbar's leading side with Edit View after them.
/// The pencil shows while the pointer is over the item or the button has the keyboard. Its room is kept whether or not
/// it shows, so hovering moves nothing, and a title too long for the room ends in an ellipsis before it. It comes and
/// goes with the title it names, so it is locked out of the tray.
struct ViewTitleItem: CustomizableToolbarContent {
    let browser: Browser
    let title: String
    let subtitle: Text

    var body: some CustomizableToolbarContent {
        // The search field takes the title's place while it is out, so the title comes and goes with it.
        if !browser.isSearchExpanded {
            ToolbarItem(id: "viewTitle", placement: .navigation) {
                ViewTitle(browser: browser, title: title, subtitle: subtitle)
            }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
        }
    }
}

private struct ViewTitle: View {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var hasFocus: Bool
    @State private var isHovering = false
    let browser: Browser
    let title: String
    let subtitle: Text

    /// The most room the title takes, so a long one never crowds the buttons beside it.
    private static let widest: CGFloat = 320

    var body: some View {
        let canEdit = SavedViews.canEdit(browser, in: library) && !browser.showsViewPanel && browser.offersViewOptions
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).foregroundStyle(appearsActive ? .primary : .secondary)
                subtitle.font(.subheadline).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button("Edit View", systemImage: "pencil") { browser.openViewPanel(in: library) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .interfaceFont(.caption.weight(.semibold))
                .foregroundStyle(appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 28)
                .contentShape(.rect)
                .focused($hasFocus)
                .opacity(canEdit && (isHovering || hasFocus) ? 1 : 0)
                .allowsHitTesting(canEdit)
                .accessibilityHidden(!canEdit)
                .help("Edit View")
                .accessibilityIdentifier("EditViewToolbar")
        }
        .onHover { isHovering = $0 }
        .frame(maxWidth: Self.widest, alignment: .leading)
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
