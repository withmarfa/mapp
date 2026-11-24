import Marfa
import SwiftUI

/// The Types page: the owner's own types, those plugins brought and those Marfa ships, each opening a page of its own. A type
/// of the owner's changes in place (its name, plural, icon, base, description and status words); a plugin's or Marfa's takes
/// only a child type and an icon. Guidance is edited on the owner's types and shown, with the guidance of the types above, on the rest.
struct TypesPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: TypesModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = TypeAccess(
            ownItems: { [host] in host.itemCount(ofType: $0) }, currentIcon: { [host] in host.typeIcon(of: $0) },
            setIcon: { [host] icon, id in await host.changeTypeIcon(icon, ofType: id) }, markSets: host.markSets,
            marks: { [host] query, set in host.marks(matching: query, in: set) }, plural: { [host] in host.typePlural(of: $0) })
        _model = State(initialValue: TypesModel(context: OwnerContext(host: host), calls: host.typeCalls, access: access))
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
                back()
            }
            .onChange(of: model.made) {
                guard let id = model.made, let type = model.record(id) else { return }
                model.acknowledgeMade()
                push(subpage(for: type))
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
                            action: ("Back", back))
                    }
                } else {
                    TypeDetail(model: model, type: type, host: host)
                }
            } else {
                SettingsPageState(
                    symbol: "shippingbox", title: Text("This Type Is Gone"), line: Text("It was deleted, here or somewhere else."),
                    action: ("Back", back))
            }
        } else {
            list
        }
    }

    // MARK: The list

    private var list: some View {
        SettingsPageColumn {
            SettingsSection("Yours") {
                if model.yours.isEmpty {
                    SettingsEmptyCard(symbol: "shippingbox", title: Text("No Types of Your Own"), line: Text("Base a type on one below to make your own."))
                }
                ForEach(model.yours) { row($0) }
                SettingsAddRow("New Type…") { model.beginChild(of: nil) }
            }
            if !model.fromPlugins.isEmpty {
                SettingsSection("From Plugins", line: "Their plugins keep them. Add a child type to change one.") {
                    ForEach(model.fromPlugins) { row($0) }
                }
            }
            SettingsSection("Built In", line: "Every Marfa has these. Base a type on one to add to it.") {
                ForEach(model.builtIn) { row($0) }
            }
        }
    }

    private func row(_ type: TypeRecord) -> some View {
        SettingsLinkRow(
            verbatim: model.title(of: type), line: model.subtitle(of: type), lead: .custom(host.typeMark(for: type.id)),
            value: model.count(of: type.id).formatted()
        ) { push(subpage(for: type)) }
    }
}
