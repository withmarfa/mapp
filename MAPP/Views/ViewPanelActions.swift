import SwiftUI

/// What the panel does with its changes: Cancel and Save while something changed, one Done when nothing did, and
/// Save as View for a place that is not a view. Return saves and Escape cancels. It is mounted at the top of the panel
/// for now; a later step moves it into the inspector's toolbar, so it reads and changes only the browser's panel and
/// takes nothing from the panel's layout.
struct ViewPanelActions: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let window = panel.isNew ? SavedViews.window(browser, in: library, order: order) : SavedViews.window(browser, in: library)
        let state = browser.viewPanelState(window: window, in: library)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch state {
                case .unchanged where panel.purpose == .place:
                    Button("Save as View…") { browser.openNewViewPanel(in: library) }
                        .disabled(!SavedViews.canSave(browser, in: library))
                        .help(SavedViews.canSave(browser, in: library) ? "" : String(localized: "This place can’t be saved as a view."))
                        .accessibilityIdentifier("ViewPanelSaveAs")
                    Spacer(minLength: 0)
                    done
                case .unchanged:
                    Spacer(minLength: 0)
                    done
                case .ready, .blocked:
                    Button("Cancel") { browser.cancelViewPanel(in: library) }
                        .keyboardShortcut(.cancelAction)
                        .disabled(panel.isSaving)
                        .accessibilityIdentifier("ViewPanelCancel")
                    Spacer(minLength: 0)
                    Button("Save") { SavedViews.save(browser, in: library, order: order) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(state != .ready || panel.isSaving)
                        .accessibilityIdentifier("ViewPanelSave")
                }
            }
            .controlSize(.regular)
            if case .blocked(let reason?) = state {
                note(reason)
            }
            if let failure = panel.failure {
                note(failure, color: .red)
            }
        }
        .confirmationDialog(
            "Save Changes to “\(panel.shownName)”?", isPresented: confirming, titleVisibility: .visible
        ) {
            Button("Save") { SavedViews.save(browser, in: library, order: order, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var done: some View {
        Button("Done") { browser.closeViewPanel(in: library) }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("ViewPanelDone")
    }

    private func note(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .interfaceFont(.callout)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
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
