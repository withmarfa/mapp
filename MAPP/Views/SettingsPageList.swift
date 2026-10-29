import SwiftUI

/// The list of Settings pages, which the content column shows while Settings is the place. It is drawn as the item
/// list is, on the window's content background with the same rounded selection, and its groups are told apart by
/// space rather than by headings.
struct SettingsPageList: View {
    let browser: Browser
    @Environment(Libraries.self) private var libraries
    @Environment(\.openURL) private var openURL

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
                    if page == .recentlyDeleted { consoleRow }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .accessibilityIdentifier("SettingsPageList")
    }
}

extension SettingsPageList {
    /// Not a page: it opens the server's console in the browser, which the arrow says. It stays out of the selection.
    private var consoleRow: some View {
        let address = libraries.host.connection?.address
        return Button { if let address { openURL(address) } } label: {
            HStack {
                Text("Console").interfaceFont(.body)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").imageScale(.small).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(address == nil)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .help("Open the server\u{2019}s console in the browser")
        .accessibilityHint(Text("Opens in the browser"))
        .accessibilityIdentifier("SettingsConsole")
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
