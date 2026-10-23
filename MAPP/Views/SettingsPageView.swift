import AppKit
import SwiftUI

/// One page of Settings: a title with a line under it, then the page's grouped form, centered in a column that
/// stays readable however wide the window is. The whole page scrolls as one.
struct SettingsPageView: View {
    let page: SettingsPage

    private static let contentWidth: CGFloat = 620

    var body: some View {
        // The page is at least as tall as the window, so a page with an empty state centers it in the space under
        // the title.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
                .frame(maxWidth: Self.contentWidth)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(page.title)
        .id(page)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsDetail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(page.title)
                .interfaceFont(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(page.summary)
                .interfaceFont(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Self.headerInset)
        .padding(.top, 32)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Where a grouped form starts its text: the form's own margin, then the section's inset.
    private static let headerInset: CGFloat = 30

@ViewBuilder private var content: some View {
        switch page {
        case .appearance: AppearanceSettings()
        case .editor: EditorSettings()
        case .sidebar: SidebarSettings()
        case .library: LibrarySettings()
        case .recentlyDeleted: RecentlyDeletedSettings()
        case .about: AboutSettings()
        }
    }
}

extension View {
    /// The form every page of Settings is: grouped, on the window's own background.
    func settingsForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
    }
}

private struct AppearanceSettings: View {
    var body: some View {
        Form {
            Section {
                InterfaceTextOptions()
            } header: {
                Text("Text")
            } footer: {
                Text("Changes text in the sidebar, lists, and controls. Note text size is set in Editor.")
            }
            Section("Notes List") {
                OrderOptions()
                ListPreviewOptions()
            }
        }
        .labelStyle(.titleOnly)
        .settingsForm()
    }
}

private struct EditorSettings: View {
    var body: some View {
        Form {
            Section("Page Layout") {
                PageWidthOptions()
                ReadingWidthOptions()
            }
            Section("Text") { TextOptions() }
        }
        .labelStyle(.titleOnly)
        .settingsForm()
    }
}

/// The name of the library in use: a server's host, or the notes folder's name.
@MainActor
enum LibraryDescription {
    static func name(_ libraries: Libraries) -> String {
        switch libraries.mode {
        case .marfa, .opening, .failed:
            if let address = libraries.host.configuredConnection?.address {
                return address.host() ?? address.absoluteString
            }
            return String(localized: "Marfa")
        case .files:
            guard let url = libraries.folder.url else { return String(localized: "No folder chosen") }
            return FileManager.default.displayName(atPath: url.path)
        }
    }
}

private struct AboutSettings: View {
    @Environment(Libraries.self) private var libraries

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
                Text(Self.name)
                    .interfaceFont(.title2.weight(.semibold))
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("A notes app for Marfa.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("AboutApp")
            Form {
                Section {
                    LabeledContent("Library", value: LibraryDescription.name(libraries))
                }
            }
            .settingsForm()
        }
    }

    private static var name: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "MAPP"
    }

    /// The version and build, as the About window gives them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }
}
