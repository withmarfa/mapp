import SwiftUI

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
