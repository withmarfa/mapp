import SwiftUI

/// Library identity stays separate from the selected view's title in the content column.
struct SidebarHeader: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.openURL) private var openURL
    @StoredOrder private var order
    let browser: Browser

    private var instanceName: String { LibraryDescription.name(libraries) }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Settings", systemImage: "gearshape") { browser.showSettings() }
                Button("Recently Deleted", systemImage: "trash") {
                    browser.show(.recentlyDeleted, in: library, order: order)
                }
                if let address = libraries.host.connection?.address {
                    Divider()
                    Button {
                        openURL(address)
                    } label: {
                        Label("Console", systemImage: "arrow.up.right")
                    }
                }
            } label: {
                Text(instanceName)
                    .interfaceFont(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .help("Instance")
            .accessibilityValue(instanceName)
            .accessibilityIdentifier("SidebarLibrary")
            Spacer(minLength: 0)
            Button {
                browser.palette = .search
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .accessibilityLabel("Search")
                .help("Search")
                .accessibilityIdentifier("SidebarSearch")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}
