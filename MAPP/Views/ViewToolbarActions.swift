import SwiftUI

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

/// What the panel does with its changes, above it in the right sidebar's toolbar: Done, or Cancel once something
/// changed, and Save. Save keeps a view's changes, with Save as New View in its menu, and makes a new view of a place
/// that is not one. Return saves, unless the page has the keyboard, and Escape leaves. Being in a toolbar only while
/// the panel is, they are locked and come and go.
struct ViewPanelToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel
    let editor: EditorController?

    var body: some CustomizableToolbarContent {
        let state = browser.viewPanelState(window: SavedViews.panelWindow(browser, in: library, order: order), in: library)
        let returnKey: KeyboardShortcut? = editor?.isFocused == true ? nil : .defaultAction
        ToolbarItem(id: "viewPanelLeave") {
            Group {
                if state == .unchanged {
                    Button("Done") { browser.closeViewPanel(in: library) }
                        .accessibilityIdentifier("ViewPanelDone")
                } else {
                    Button("Cancel") { browser.cancelViewPanel(in: library) }
                        .disabled(panel.isSaving)
                        .accessibilityIdentifier("ViewPanelCancel")
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .customizationBehavior(.disabled)
        ToolbarItem(id: "viewPanelSave") {
            ViewPanelSaveButton(browser: browser, panel: panel, state: state, returnKey: returnKey)
        }
        .customizationBehavior(.disabled)
    }
}

private struct ViewPanelSaveButton: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel
    let state: Browser.ViewPanelState
    let returnKey: KeyboardShortcut?

    var body: some View {
        switch panel.purpose {
        case .place:
            let canSave = SavedViews.canSave(browser, in: library)
            Button("Save") { browser.openNewViewPanel(in: library) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(returnKey)
                .disabled(!canSave)
                .help(canSave ? String(localized: "Save what this window shows as a view") : String(localized: "This place can’t be saved as a view."))
                .accessibilityIdentifier("ViewPanelSave")
        case .new:
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(returnKey)
                .disabled(state != .ready || panel.isSaving)
                .accessibilityIdentifier("ViewPanelSave")
        case .edit:
            // A menu with a primary action is the system's split button: Save, and Save as New View in its menu.
            Menu {
                Button("Save as New View…") { browser.openNewViewPanel(in: library) }
                    .disabled(!SavedViews.canSave(browser, in: library))
            } label: {
                Text("Save")
            } primaryAction: {
                save()
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(state != .ready || panel.isSaving)
            .background {
                Button("Save") { save() }
                    .keyboardShortcut(returnKey)
                    .disabled(state != .ready || panel.isSaving)
                    .hidden()
            }
            .accessibilityIdentifier("ViewPanelSave")
        }
    }

    private func save() {
        guard state == .ready else { return }
        SavedViews.save(browser, in: library, order: order)
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
