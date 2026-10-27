import AppKit
import SwiftUI

/// One page of Settings: its title, then the page's grouped form, centered in a column that
/// stays readable however wide the window is. The whole page scrolls as one.
struct SettingsPageView: View {
    let page: SettingsPage
    let browser: Browser

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
        .navigationTitle(page.title)
        .id(page)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SettingsDetail")
    }

    private var header: some View {
        Text(page.title)
            .interfaceFont(.title.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Self.headerInset)
            .padding(.top, 32)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where a grouped form starts its text: the form's own margin, then the section's inset.
    private static let headerInset: CGFloat = 30

    @ViewBuilder private var content: some View {
        switch page {
        case .appearance: AppearanceSettings()
        case .editor: EditorSettings()
        case .sidebar: SidebarSettings()
        case .library: LibrarySettings(browser: browser)
        case .thisMarfa: ThisMarfaSettings()
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
            Section {
                ColumnWidthOptions()
            } header: {
                Text("Default Column Widths")
            } footer: {
                Text("Where each column starts in a new window. Dragging a column to a new width changes only that window.")
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
            Section {
                RemotePictureOptions()
            } header: {
                Text("Pictures")
            } footer: {
                Text("A note names the website of a picture at a web address and loads it only when you choose to, or always for items that came from another service. Pictures you have loaded stay on this Mac until you disconnect the library.")
            }
        }
        .labelStyle(.titleOnly)
        .settingsForm()
    }
}

private struct RemotePictureOptions: View {
    @AppStorage(RemotePictureSetting.key) private var setting = RemotePictureSetting.standard

    var body: some View {
        Picker("Remote Pictures", selection: $setting) {
            ForEach(RemotePictureSetting.allCases) { option in
                switch option {
                case .ask: Text("Ask")
                case .always: Text("Always")
                case .never: Text("Never")
                }
            }
        }
        .accessibilityIdentifier("RemotePictures")
    }
}

/// The name of the library in use: the name a server gave itself, or its host until one has been read.
@MainActor
enum LibraryDescription {
    static func name(_ libraries: Libraries) -> String {
        guard let connection = libraries.host.configuredConnection else { return String(localized: "Marfa") }
        if let name = libraries.host.instanceName(for: connection) { return name }
        return connection.address.host() ?? connection.address.absoluteString
    }
}

/// What the app is, the library it reads and where to find the project, as the About window of a Mac app gives them.
private struct AboutSettings: View {
    @Environment(Libraries.self) private var libraries

    private static let source = URL(string: "https://github.com/withmarfa/mapp")!
    private static let license = URL(string: "https://github.com/withmarfa/mapp/blob/main/LICENSE")!
    private static let docs = URL(string: "https://docs.marfa.so")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
                Text(Self.name)
                    .interfaceFont(.title2.weight(.semibold))
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("A notes app for your Marfa server.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("AboutApp")
            Form {
                if let connection = libraries.host.configuredConnection {
                    Section("Library") {
                        LabeledContent("Name", value: LibraryDescription.name(libraries))
                        LabeledContent("Address", value: connection.address.absoluteString)
                    }
                }
                Section {
                    LabeledContent("Source") { Link("github.com/withmarfa/mapp", destination: Self.source) }
                    LabeledContent("Marfa") { Link("docs.marfa.so", destination: Self.docs) }
                    LabeledContent("License") { Link("Apache-2.0", destination: Self.license) }
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
