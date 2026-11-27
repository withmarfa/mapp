import Marfa
import SwiftUI

/// The Types page: one list of the types the server lists, under tabs for where each came from, each opening a page of its
/// own. A registered type the sign-in may write changes in place (its name, plural, icon, base, description and status
/// words), including one an app registered; a plugin's or Marfa's takes only a child type and an icon. Guidance is edited
/// on a type the sign-in may write and shown, with the guidance of the types above, on the rest.
struct TypesPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: TypesModel
    @State private var tab = TypesModel.TypesTab.all
    @State private var sort = TypesModel.TypeColumnSort.type(ascending: true)
    @State private var selected: String?
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = TypeAccess(
            ownItems: { [host] in host.itemCount(ofType: $0) }, currentIcon: { [host] in host.typeIcon(of: $0) },
            setIcon: { [host] icon, id in await host.changeTypeIcon(icon, ofType: id) }, markSets: host.markSets,
            marks: { [host] query, set in host.marks(matching: query, in: set) }, plural: { [host] in host.typePlural(of: $0) })
        _model = State(initialValue: TypesModel(
            context: OwnerContext(host: host), calls: host.typeCalls, access: access, ownVendor: host.ownAppVendor))
    }

    private func subpage(for type: TypeRecord) -> SettingsSubpage {
        SettingsSubpage(id: "type:" + type.id, title: model.title(of: type))
    }

    private func subpage(for field: TypeFieldRecord, of type: TypeRecord) -> SettingsSubpage {
        SettingsSubpage(id: "field:\(type.id):\(field.key)", title: TypesModel.title(of: field))
    }

    /// The type a sub-page is about, and the field it opens when it is a field's page.
    private var place: (type: String, field: String?)? {
        guard let id = subpage?.id else { return nil }
        if id.hasPrefix("type:") { return (String(id.dropFirst(5)), nil) }
        if id.hasPrefix("field:") {
            let parts = id.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        return nil
    }

    private var openID: String? { place?.type }
    private var openFieldKey: String? { place?.field }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .onChange(of: subpage, initial: true) { openPlace() }
            .onChange(of: model.hasLoaded) { openPlace() }
            .onChange(of: model.deleted) {
                guard model.deleted != nil else { return }
                model.acknowledgeDeleted()
                navigation?.back()
            }
            .onChange(of: model.made) {
                guard let id = model.made, let type = model.record(id) else { return }
                model.acknowledgeMade()
                navigation?.push(subpage(for: type))
            }
            .settingsSheet(presenting: model.hasSheet, dismiss: { model.closeSheet() }) { TypeSheet(model: model, host: host) }
            .accessibilityIdentifier("TypesPage")
    }

    private func openPlace() {
        guard let id = openID else { return model.close() }
        if let key = openFieldKey { model.openField(key, of: id) } else {
            model.open(id)
            model.closeField()
        }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .types, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let type = model.record(id) {
                if let key = openFieldKey {
                    if let field = model.ownField(key, of: id) {
                        FieldDetail(model: model, type: type, field: field, host: host)
                    } else {
                        SettingsPageState(
                            symbol: "textformat", title: Text("This Field Is Gone"), line: Text("It was removed, here or somewhere else."),
                            action: ("Back", { navigation?.back() }))
                    }
                } else {
                    TypeDetail(model: model, type: type, host: host)
                }
            } else {
                SettingsPageState(
                    symbol: "shippingbox", title: Text("This Type Is Gone"), line: Text("It was deleted, here or somewhere else."),
                    action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    // MARK: The list

    private var rows: [TypesModel.TypeListRow] { model.rows(in: tab, sortedBy: sort) }

    private var list: some View {
        SettingsPageColumn {
            LinksSection(host: host)
            SettingsListHeader {
                SettingsTabs(tabs: tabs, selection: $tab)
            } trailing: {
                SettingsButton("New Type…") { model.beginChild(of: nil) }
            }
            if rows.isEmpty {
                SettingsEmptyCard(symbol: "shippingbox", title: emptyTitle, line: emptyLine)
            } else {
                SettingsSectionTable(
                    rows: rows, columns: columns, isSelected: { $0.id == selected },
                    onOpen: { row in
                        selected = row.id
                        navigation?.push(subpage(for: row.type))
                    })
            }
        }
        .onChange(of: tab) { selected = model.keptSelection(selected, in: rows) }
        .onChange(of: listedIDs) {
            if tab == .fromApps, !model.showsFromApps { tab = .all }
            selected = model.keptSelection(selected, in: model.rows(in: tab, sortedBy: sort))
        }
    }

    private var listedIDs: [String] { model.records.map(\.id) }

    private var tabs: [SettingsTabs<TypesModel.TypesTab>.Tab] {
        var tabs: [SettingsTabs<TypesModel.TypesTab>.Tab] = [
            .init(value: .all, title: "All", count: model.count(in: .all)),
            .init(value: .yours, title: "Yours", count: model.count(in: .yours)),
            .init(value: .builtIn, title: "Built In", count: model.count(in: .builtIn)),
            .init(value: .fromPlugins, title: "From Plugins", count: model.count(in: .fromPlugins)),
        ]
        if model.showsFromApps {
            tabs.append(.init(value: .fromApps, title: "From Apps", count: model.count(in: .fromApps)))
        }
        return tabs
    }

    private var columns: [SettingsTableColumn<TypesModel.TypeListRow>] {
        [
            SettingsTableColumn(
                "Type", sortedAscending: sort.ascending(for: .type), onSort: { sort = sort.toggled(.type) }
            ) { row in
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    host.typeMark(for: row.type.id)
                    Text(verbatim: model.title(of: row.type))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, CGFloat(row.depth) * SettingsTokens.Metric.typeTableIndent)
            },
            SettingsTableColumn(
                "From", width: SettingsTokens.Metric.Column.who, sortedAscending: sort.ascending(for: .source),
                onSort: { sort = sort.toggled(.source) }
            ) { row in
                Text(verbatim: model.sourceTitle(of: row.type)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn(
                "Items", width: SettingsTokens.Metric.Column.day, numeric: true, sortedAscending: sort.ascending(for: .items),
                onSort: { sort = sort.toggled(.items) }
            ) { row in
                Text(verbatim: model.count(of: row.type.id).formatted()).foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    private var emptyTitle: Text {
        switch tab {
        case .all: Text("No Types")
        case .yours: Text("No Types of Your Own")
        case .builtIn: Text("No Built In Types")
        case .fromPlugins: Text("No Types from Plugins")
        case .fromApps: Text("No Types from Apps")
        }
    }

    private var emptyLine: Text {
        switch tab {
        case .yours: Text("Base a type on one to make your own.")
        case .fromPlugins: Text("A plugin brings its types with it.")
        case .fromApps: Text("An app’s types are listed here.")
        default: Text("Nothing is listed on this tab.")
        }
    }
}
