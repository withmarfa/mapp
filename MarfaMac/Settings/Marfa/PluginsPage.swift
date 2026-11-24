import Marfa
import MarfaAPI
import SwiftUI

/// The Plugins page: what the owner added to the server, the newer versions the plugins release lists, and what it lists that
/// is not installed. Each plugin opens a page of its own, installed or not. A plugin whose types carry guidance is not
/// installed from here, since Marfa refuses an app that: the page gives the command to run instead.
struct PluginsPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: PluginsModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = PluginsAccess(
            ownItems: { [host] in host.itemCount(ofType: $0) }, chooseBundle: { [host] in await host.chooseBundleFile() })
        _model = State(initialValue: PluginsModel(context: OwnerContext(host: host), calls: host.pluginCalls, access: access))
    }

    static func subpage(named name: String, title: String) -> SettingsSubpage {
        SettingsSubpage(id: "plugin:" + name, title: title)
    }

    private var openName: String? {
        guard let id = subpage?.id, id.hasPrefix("plugin:") else { return nil }
        return String(id.dropFirst(7))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .settingsSheet(presenting: model.removal != nil, dismiss: { model.cancelRemoval() }) {
                if let removal = model.removal { PluginRemovalSheet(model: model, removal: removal) }
            }
            .accessibilityIdentifier("PluginsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .plugins, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let name = openName {
            if let plugin = model.plugin(name) {
                PluginDetail(model: model, plugin: plugin, host: host)
            } else if let entry = model.entry(name) {
                ReleasedPluginDetail(model: model, entry: entry, host: host)
            } else if case .reading = model.release {
                OwnerLoading()
            } else if case .unreadable(let failure) = model.release {
                SettingsPageState(
                    symbol: "exclamationmark.triangle", title: Text("The Plugins Release Couldn’t Be Read"),
                    line: Text(verbatim: PluginWording.line(failure)), action: ("Try Again", { Task { await model.readRelease() } }))
            } else if case .notRead = model.release {
                SettingsPageState(
                    symbol: "puzzlepiece.extension", title: Text("The Plugins Release Wasn’t Read"),
                    action: ("Try Again", { Task { await model.readRelease() } }))
            } else {
                SettingsPageState(
                    symbol: "puzzlepiece.extension", title: model.notice.map { Text(verbatim: $0.title) } ?? Text("This Plugin Isn’t Here"),
                    line: Text(verbatim: model.notice?.line ?? String(localized: "It was removed, or the release no longer lists it.")),
                    action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    // MARK: The list

    private var list: some View {
        SettingsPageColumn {
            PluginNotices(model: model, host: host, plugin: nil)
            installedSection
            updatesSection
            availableSection
        }
    }

    private var installedSection: some View {
        SettingsSection(
            name: Text("Installed"), line: Text("What you added to \(host.serverName). Browse \(host.pluginCalls.releaseName) under Available.")
        ) {
            if model.installed.isEmpty {
                SettingsRow("No Plugins Installed", look: .off)
            }
            ForEach(model.installed) { plugin in
                SettingsLinkRow(
                    verbatim: plugin.title, line: plugin.description, lead: .well(host.markGlyph(plugin.mark)), value: plugin.version
                ) { navigation?.push(Self.subpage(named: plugin.name, title: plugin.title)) }
            }
        }
    }

    @ViewBuilder private var updatesSection: some View {
        let updates = model.updates
        if !updates.isEmpty {
            SettingsSection("Plugin Updates") {
                ForEach(updates) { update in
                    PluginUpdateRow(model: model, update: update, host: host) {
                        navigation?.push(Self.subpage(named: update.id, title: update.installed.title))
                    }
                }
            }
        }
    }

    private var availableSection: some View {
        SettingsSection(name: Text("Available"), line: Text("Nothing is installed until you choose it.")) {
            switch model.release {
            case .reading:
                SettingsRow("Reading the Plugins Release…") { ProgressView().controlSize(.small) }
            case .notRead:
                SettingsRow("The Plugins Release Wasn’t Read") {
                    SettingsButton("Try Again") { Task { await model.readRelease() } }
                }
            case .unreadable(let failure):
                SettingsProblemRow(
                    title: Text("The Plugins Release Couldn’t Be Read"), line: Text(verbatim: PluginWording.line(failure)),
                    symbol: "exclamationmark.triangle", tone: .orange,
                    actions: [SettingsProblemAction("Try Again") { Task { await model.readRelease() } }])
            case .read:
                if model.available.isEmpty {
                    SettingsRow("Nothing More Is Available", look: .off)
                }
                ForEach(model.available) { entry in
                    SettingsLinkRow(
                        verbatim: entry.title, line: entry.description, lead: .well(host.markGlyph(entry.mark)),
                        value: entry.version.description
                    ) { navigation?.push(Self.subpage(named: entry.name, title: entry.title)) }
                }
            }
            SettingsAddRow("Install From a File…") { Task { await model.installFile() } }
                .disabled(model.isInstallingFile)
        }
    }
}

/// What the last thing asked did or did not do, and the command a plugin that carries guidance is installed with.
private struct PluginNotices: View {
    let model: PluginsModel
    let host: any MarfaSettingsHost
    /// The plugin the page is about, or nil on the list, which shows what was not about one plugin and every notice.
    let plugin: String?

    var body: some View {
        Group {
            if let notice = model.notice {
                SettingsSection(name: nil) {
                    SettingsRow(
                        title: Text(verbatim: notice.title), line: Text(verbatim: notice.line), lead: .symbol("checkmark.circle"), lines: nil
                    ) { SettingsButton("Close") { model.closeNotice() } }
                }
            }
            if let problem = model.problem, plugin == nil || problem.plugin == plugin {
                PluginProblem(problem: problem, model: model, host: host)
            }
            if plugin == nil, let command = model.commands[""] {
                PluginCommandSection(
                    model: model, name: Text("Install From the Command Line"),
                    line: Text(verbatim: PluginWording.line(.carriesGuidance)), command: command)
            }
        }
    }
}

/// A refusal in words: Allow More… where it is a permission, both releases where the server is too old.
private struct PluginProblem: View {
    let problem: PluginsModel.Problem
    let model: PluginsModel
    let host: any MarfaSettingsHost

    var body: some View {
        if case .owner(let failure) = problem.failure {
            SettingsSection(name: nil) {
                OwnerProblemRow(
                    title: LocalizedStringKey(problem.title), failure: failure, page: .plugins, host: host,
                    additionalActions: [SettingsProblemAction("Close", perform: model.closeProblem)])
            }
        } else {
            let title = problem.plugin.flatMap { model.plugin($0)?.title ?? model.entry($0)?.title }
            SettingsSection(name: nil) {
                SettingsProblemRow(
                    title: Text(verbatim: problem.title), line: Text(verbatim: PluginWording.line(problem.failure, title: title)),
                    actions: [SettingsProblemAction("Close", perform: model.closeProblem)])
            }
        }
    }
}

/// The command to run for a plugin the app does not install, with a button that copies it.
private struct PluginCommandSection: View {
    let model: PluginsModel
    let name: Text
    let line: Text
    let command: String

    var body: some View {
        SettingsSection(name: name, line: line) {
            SettingsRow(verbatim: command) {
                SettingsButton(model.copied == command ? "Copied" : "Copy") { model.copyCommand(command) }
            }
        }
    }
}

/// One row of Plugin Updates: what the newer version adds, and Update, or the command where it carries guidance.
private struct PluginUpdateRow: View {
    let model: PluginsModel
    let update: PluginsModel.Update
    let host: any MarfaSettingsHost
    let open: () -> Void

    private var line: String {
        if case .failed(let failure)? = model.bundles[update.id] { return PluginWording.line(failure) }
        var line = PluginWording.updateLine(adds: model.adds(update))
        if model.heldCommand(update.id) != nil { line += " " + String(localized: "It carries guidance, so it updates from the command line.") }
        return line
    }

    var body: some View {
        SettingsRow(
            verbatim: "\(update.installed.title) \(update.entry.version)", line: line,
            lead: .well(host.markGlyph(update.installed.mark)), lines: nil
        ) {
            if model.isWorking(update.id) {
                ProgressView().controlSize(.small)
            } else if let command = model.heldCommand(update.id) {
                SettingsButton(model.copied == command ? "Copied" : "Copy Command") { model.copyCommand(command) }
            } else if case .failed? = model.bundles[update.id] {
                SettingsButton("Try Again") { Task { await model.readAgain(update.id) } }
            } else {
                SettingsButton("Update", role: .update) { Task { await model.install(update.entry, asUpdate: true) } }
            }
        }
    }
}

// MARK: An installed plugin

/// An installed plugin's page.
private struct PluginDetail: View {
    let model: PluginsModel
    let plugin: InstalledPlugin
    let host: any MarfaSettingsHost

    private var update: PluginsModel.Update? { model.update(for: plugin.name) }

    private var headLine: String {
        var line = PluginWording.head(version: plugin.version, maker: plugin.maker, marfa: plugin.marfa)
        if let entry = model.entry(plugin.name), entry.sha256.lowercased() == plugin.fingerprint, entry.version.description == plugin.version {
            line += " " + String(localized: "From the plugins release.")
        }
        return line
    }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(
                lead: SettingsWell(size: SettingsTokens.Metric.headTile) { host.markGlyph(plugin.mark) },
                title: Text(verbatim: plugin.title), line: Text(verbatim: headLine)
            ) {
                if model.isWorking(plugin.name) {
                    ProgressView().controlSize(.small)
                } else if let update, model.heldCommand(plugin.name) == nil {
                    SettingsButton(verbatim: String(localized: "Update to \(update.entry.version.description)"), role: .update) {
                        Task { await model.install(update.entry, asUpdate: true) }
                    }
                }
            }
            PluginNotices(model: model, host: host, plugin: plugin.name)
            if update != nil, let command = model.heldCommand(plugin.name) {
                PluginCommandSection(
                    model: model, name: Text("Update From the Command Line"),
                    line: Text(verbatim: PluginWording.line(.carriesGuidance)),
                    command: command)
            }
            adds
            about
            SettingsSection("Remove") {
                SettingsRow(
                    verbatim: String(localized: "Remove \(plugin.title)"),
                    line: plugin.connector == nil
                        ? String(localized: "Its types and items stay.") : String(localized: "Its connector stops. Its types and items stay.")
                ) {
                    SettingsButton("Remove…", role: .destructive) { model.askToRemove(plugin) }
                        .disabled(model.isWorking(plugin.name))
                }
            }
        }
        .task(id: plugin.name) { await model.open(plugin.name) }
    }

    private var adds: some View {
        SettingsSection("What It Adds") {
            if let connector = plugin.connector { connectorRow(connector) }
            ForEach(plugin.types, id: \.self) { id in
                SettingsRow(verbatim: model.typeTitle(id), line: typeLine(id), lead: .custom(host.typeMark(for: id)))
            }
            ForEach(plugin.edgeTypes, id: \.self) { id in
                SettingsRow(verbatim: id, line: String(localized: "A kind of link between items."), lead: .symbol("link"))
            }
            if plugin.connector == nil, plugin.types.isEmpty, plugin.edgeTypes.isEmpty {
                SettingsRow("Nothing That Remains", look: .off)
            }
        }
    }

    private func typeLine(_ id: String) -> String {
        let items = model.items(ofType: id)
        let count = items == 1 ? String(localized: "1 item.") : String(localized: "\(items.formatted()) items.")
        guard let parent = model.typeInfo[id]?.parent else { return count }
        return String(localized: "Based on \(model.typeTitle(parent)). ") + count
    }

    /// The connector's row, which opens the connector's own page, where Allow More… is asked if that page needs it.
    private func connectorRow(_ connector: InstalledPlugin.Connector) -> some View {
        let line: String
        if plugin.host != nil, let name = model.hostName(of: plugin) {
            line = String(localized: "Connects \(connector.sourceName). Runs on \(name).")
        } else if plugin.host != nil {
            line =
                host.grants.contains(.connectorsManage)
                ? String(localized: "Connects \(connector.sourceName). Runs on a machine you linked.")
                : String(localized: "Connects \(connector.sourceName). Seeing where it runs needs Manage Connectors.")
        } else {
            line = String(localized: "Connects \(connector.sourceName). It runs on no machine yet.")
        }
        return SettingsLinkRow(verbatim: String(localized: "Connector"), line: line, lead: .well(symbol: "arrow.triangle.2.circlepath")) {
            host.show(.connectors, subpage: ConnectorsPage.subpage(plugin: plugin.name, title: plugin.title))
        }
    }

    private var about: some View {
        SettingsSection("About") {
            SettingsRow(verbatim: String(localized: "Description"), line: plugin.description, lines: nil)
            if let installed = plugin.installedAt {
                SettingsRow(
                    title: Text("Installed"), line: plugin.installedBy.map { Text(verbatim: String(localized: "By \($0).")) }
                ) { SettingsValue(verbatim: OwnerWording.day(installed)) }
            }
            SettingsRow(verbatim: String(localized: "Fingerprint"), line: plugin.fingerprint, lines: nil)
        }
    }
}

// MARK: A plugin that is not installed

/// What the release lists, read from its checked bundle before anything is installed: what Install registers, its version and
/// the oldest Marfa it needs.
private struct ReleasedPluginDetail: View {
    let model: PluginsModel
    let entry: ReleasePlugin
    let host: any MarfaSettingsHost

    var body: some View {
        content
            .task(id: entry.name) { await model.readBundle(of: entry) }
    }

    @ViewBuilder private var content: some View {
        switch model.bundles[entry.name] {
        case .read(let bundle)?:
            detail(bundle)
        case .failed(let failure)?:
            SettingsPageState(
                symbol: "exclamationmark.triangle", title: Text("This Plugin Couldn’t Be Read"), line: Text(verbatim: PluginWording.line(failure)),
                action: ("Try Again", { Task { await model.readAgain(entry.name) } }))
        case .reading?, nil:
            OwnerLoading()
        }
    }

    private func detail(_ bundle: ReleaseBundle) -> some View {
        let contents = bundle.plugin
        let command = model.heldCommand(entry.name)
        return SettingsPageColumn {
            SettingsHead(
                lead: SettingsWell(size: SettingsTokens.Metric.headTile) { host.markGlyph(contents.mark) },
                title: Text(verbatim: contents.title),
                line: Text(verbatim: PluginWording.head(version: contents.version.description, maker: contents.maker, marfa: contents.marfa.description))
            ) {
                if model.isWorking(entry.name) {
                    ProgressView().controlSize(.small)
                } else if command == nil {
                    SettingsButton("Install", role: .update) { Task { await model.install(entry) } }
                }
            }
            PluginNotices(model: model, host: host, plugin: entry.name)
            if let command {
                PluginCommandSection(
                    model: model, name: Text("Install From the Command Line"), line: Text(verbatim: PluginWording.line(.carriesGuidance)),
                    command: command)
            }
            SettingsSection(name: Text("What Install Adds"), line: Text("Nothing is added until you install it.")) {
                if let connector = bundle.connector {
                    SettingsRow(
                        title: Text("Connector"), line: Text(verbatim: connectorLine(connector, in: bundle)),
                        lead: .well(symbol: "arrow.triangle.2.circlepath"), lines: nil)
                }
                ForEach(bundle.types, id: \.id) { type in
                    SettingsRow(
                        verbatim: type.label ?? type.id, line: type.description, lead: .well(host.markGlyph(type.icon ?? "")), lines: nil)
                }
                ForEach(bundle.edgeTypes, id: \.id) { edge in
                    SettingsRow(verbatim: edge.label ?? edge.id, line: edge.description, lead: .symbol("link"), lines: nil)
                }
            }
            SettingsSection("About") {
                SettingsRow(verbatim: String(localized: "Description"), line: contents.description, lines: nil)
                SettingsRow("Version") { SettingsValue(verbatim: contents.version.description) }
                SettingsRow("Oldest Marfa", line: "The oldest Marfa this version works with.") {
                    SettingsValue(verbatim: contents.marfa.description)
                }
            }
        }
    }

    private func connectorLine(_ connector: ReleaseBundle.Connector, in bundle: ReleaseBundle) -> String {
        let titles = connector.kinds.map { kind in bundle.types.first { $0.id == kind.type }?.label ?? kind.name }
        let what = PluginWording.list(titles)
        let runs = String(localized: "It runs on a machine you link.")
        if connector.kinds.allSatisfy({ $0.direction == "in" }) {
            return String(localized: "Brings in \(what) from \(connector.sourceName). ") + runs
        }
        return String(localized: "Keeps \(what) in step with \(connector.sourceName). ") + runs
    }
}

// MARK: Removing

/// What removing a plugin takes and what stays, before it is sent.
struct PluginRemovalSheet: View {
    let model: PluginsModel
    let removal: PluginsModel.Removal

    private var plugin: InstalledPlugin { removal.plugin }

    private var stays: String {
        let items = removal.items == 1 ? String(localized: "1 item") : String(localized: "\(removal.items.formatted()) items")
        return removal.types.count == 1
            ? String(localized: "Its type and \(items). Delete them in Types if you want.")
            : String(localized: "Their types and \(items). Delete them in Types if you want.")
    }

    var body: some View {
        SettingsSheet(
            title: Text("Remove \(plugin.title)?"),
            line: plugin.connector == nil
                ? Text("Nothing you brought in is deleted.") : Text("Its connector stops and is removed. Nothing you brought in is deleted."),
            isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                if plugin.connector != nil {
                    SettingsSection("Removed") {
                        SettingsRow("The Connector", line: "It stops running.", lead: .symbol("arrow.triangle.2.circlepath"))
                        SettingsRow("Its Settings and Secrets", line: "Set them again if you install it later.", lead: .symbol("key"))
                        SettingsRow(
                            "Its Mapping", line: "Where it put things, and any rewrite it asked for. Map it again if you install it later.",
                            lead: .symbol("arrow.left.arrow.right"), lines: nil)
                    }
                }
                SettingsSection("Stays") {
                    if removal.types.isEmpty {
                        SettingsRow("Nothing Remains", line: "The plugin brought no types.", lead: .symbol("tray"))
                    } else {
                        SettingsRow(
                            verbatim: removal.types.count <= 3
                                ? PluginWording.list(removal.types.map(\.title)) : String(localized: "\(removal.types.count) Types"),
                            line: stays, lead: .symbol("tray.full"), lines: nil)
                    }
                }
            }
        } leading: {
            SettingsButton("Remove", role: .destructive) { Task { await model.confirmRemoval() } }
        } buttons: {
            SettingsButton("Cancel") { model.cancelRemoval() }
        }
    }
}
