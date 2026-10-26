import SwiftUI

/// The list of Settings pages, which the content column shows while Settings is the place. It is drawn as the item
/// list is, on the window's content background with the same rounded selection, and its groups are told apart by
/// space rather than by headings.
struct SettingsPageList: View {
    let browser: Browser

    var body: some View {
        List(selection: Binding<SettingsPage?> {
            browser.settingsPage
        } set: { page in
            if let page { browser.settingsPage = page }
        }) {
            ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { index, pages in
                if index > 0 {
                    // A row of its own, since a section header would be a heading and a row's padding would be
                    // part of its selection.
                    Color.clear
                        .frame(height: 12)
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
                ForEach(pages) { page in
                    Text(page.title)
                        .interfaceFont(.body)
                        .frame(minHeight: 30)
                        .tag(page)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("SettingsPage-\(page.rawValue)")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .accessibilityIdentifier("SettingsPageList")
    }
}

/// Settings when no library is open, so the window has no list or item page to give way: the page list and the
/// page in a split view of their own, and a button back to the window as it was.
struct SettingsWorkspace: View {
    @Bindable var browser: Browser
    @State private var listWidth = ColumnWidth.settings.stored()

    var body: some View {
        NavigationSplitView {
            SettingsPageList(browser: browser)
                .navigationSplitViewColumnWidth(
                    min: ColumnWidth.settings.range.lowerBound, ideal: listWidth, max: ColumnWidth.settings.range.upperBound)
        } detail: {
            SettingsPageView(page: browser.settingsPage, browser: browser)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { browser.leaveSettings() }
                            .accessibilityIdentifier("SettingsDone")
                    }
                }
        }
        .accessibilityIdentifier("SettingsWorkspace")
    }
}
