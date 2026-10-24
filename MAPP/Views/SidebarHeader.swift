import SwiftUI

/// Library identity stays separate from the selected view's title in the content column.
struct SidebarHeader: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.openURL) private var openURL
    @StoredOrder private var order
    let browser: Browser

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
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                    Text(LibraryDescription.name(libraries))
                        .interfaceFont(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Instance")
            .accessibilityValue(LibraryDescription.name(libraries))
            .accessibilityIdentifier("SidebarLibrary")
            Spacer(minLength: 0)
            Button {
                browser.palette = .search
            } label: {
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
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
