import AppKit
import SwiftUI

/// One page of Settings: a heading with a line under it, then the page's grouped form, centered in a column that
/// stays readable however wide the window is.
struct SettingsPageView: View {
    let page: SettingsPage

    private static let contentWidth: CGFloat = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .interfaceFont(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(page.summary)
                    .interfaceFont(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            content
        }
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(page.title)
        .id(page)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsDetail")
    }

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
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(Self.name)
                        .interfaceFont(.title2.weight(.semibold))
                    Text("Version \(Self.version)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("A notes app for Marfa.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("AboutApp")
            }
            Section {
                LabeledContent("Library", value: LibraryDescription.name(libraries))
            }
        }
        .settingsForm()
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
