import SwiftUI

/// What waits in the toolbar while the window shows a place that is not a saved view with something a view could keep
/// and the panel is closed: Save as View. It is locked, as a person's layout must not lose it. A view needs no Save,
/// since each change to it is written as it is made.
struct ViewChangeItems: CustomizableToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some CustomizableToolbarContent {
        let showsSaveAs = browser.offersViewOptions && !browser.showsViewPanel && SavedViews.hasChoicesToKeep(browser, in: library)
        let canSaveAs = SavedViews.canSave(browser, in: library)
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

/// What the panel offers above it in the right sidebar's toolbar: Done, which closes it and makes a new view, and for a
/// type's list or another place that is not a view, Save as View… beside it. Return is Done, unless the page has the
/// keyboard. Being in a toolbar only while the panel is, they are locked and come and go.
struct ViewPanelToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let panel: ViewPanel
    let editor: EditorController?

    var body: some CustomizableToolbarContent {
        let returnKey: KeyboardShortcut? = editor?.isFocused == true ? nil : .defaultAction
        let canSaveAs = SavedViews.canSave(browser, in: library)
        ToolbarItem(id: "viewPanelSaveAs") {
            Button("Save as View…") { browser.openNewViewPanel(in: library) }
                .disabled(!canSaveAs)
                .help(canSaveAs ? String(localized: "Make a view of what this window shows") : String(localized: "Saving a view needs your Marfa server"))
                .accessibilityIdentifier("ViewPanelSaveAs")
        }
        .customizationBehavior(.disabled)
        .hidden(panel.purpose != .place)
        ToolbarItem(id: "viewPanelDone") {
            Button("Done") { Task { await browser.finishViewPanel(in: library, order: order) } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(returnKey)
                .accessibilityIdentifier("ViewPanelDone")
        }
        .customizationBehavior(.disabled)
    }
}
