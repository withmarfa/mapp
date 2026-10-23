import SwiftUI

/// The list of Settings pages, which the content column shows while Settings is the place. It is a sidebar-style
/// list in groups, so a page is chosen the way a place is.
struct SettingsPageList: View {
    let browser: Browser

    var body: some View {
        List(selection: Binding<SettingsPage?> {
            browser.settingsPage
        } set: { page in
            if let page { browser.settingsPage = page }
        }) {
            ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, pages in
                Section {
                    ForEach(pages) { page in
                        Label {
                            Text(page.title).interfaceFont(.body)
                        } icon: {
                            Image(systemName: page.symbol).interfaceFont(.body)
                        }
                        .tag(page)
                        .accessibilityIdentifier("SettingsPage-\(page.rawValue)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .accessibilityIdentifier("SettingsPageList")
    }
}

/// Settings when no library is open, so the window has no list or item page to give way: the page list and the
/// page in a split view of their own, and a button back to the window as it was.
struct SettingsWorkspace: View {
    @Bindable var browser: Browser

    var body: some View {
        NavigationSplitView {
            SettingsPageList(browser: browser)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            SettingsPageView(page: browser.settingsPage)
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
