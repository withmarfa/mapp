import SwiftUI

/// The item whose type's page the Customize Page sheet is open for.
struct PageCustomizationRequest: Identifiable {
    let id = UUID()
    let item: ItemID
}

/// Chooses, for the type of one item, which properties its page shows and where Linked From goes. The inspector
/// lists every property whatever is chosen here, so nothing is lost by hiding it from the page. The choice is for
/// the type, not the item, and is kept by the app (`PagePlacements`).
struct CustomizePageSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    let request: PageCustomizationRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = library.item(request.item) {
                let type = item.type
                let placement = placements.placement(of: type, in: library.catalogue)
                Text("Customize \(library.catalogue.label(for: type)) Pages").interfaceFont(.title2.bold())
                Text("Choose what the page shows. The inspector always lists everything.").foregroundStyle(.secondary)
                Form {
                    propertySection(of: item, placement: placement)
                    relationshipSection(of: item, placement: placement)
                    Section {
                        row(PagePlacement.tags, title: String(localized: "Tags"), of: type, placement: placement)
                        linkedFromPicker(of: type, placement: placement)
                    } footer: {
                        if library.catalogue.isCollection(type) {
                            Text("A collection’s contents always stay on its page.")
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("This item is no longer in the library.").foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Button("Use Defaults") {
                    if let type = library.item(request.item)?.type { placements.reset(type) }
                }
                .disabled(library.item(request.item).map { !placements.hasChoice(for: $0.type) } ?? true)
                .accessibilityIdentifier("CustomizePageReset")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("CustomizePageDone")
            }
        }
        .padding(20)
        .frame(width: 420, height: 540)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CustomizePageSheet")
    }

    @ViewBuilder
    private func propertySection(of item: Item, placement: PagePlacement) -> some View {
        let hidden = library.hiddenPropertyKeys(of: item)
        let fields = PageCustomization.fields(
            of: item, type: library.catalogue.itemTypes[item.type], hidden: hidden, catalogue: library.catalogue)
        if !fields.isEmpty {
            Section("Properties") {
                ForEach(fields, id: \.key) { field in
                    row(field.key, title: field.displayLabel, of: item.type, placement: placement)
                }
            }
        }
    }

    @ViewBuilder
    private func relationshipSection(of item: Item, placement: PagePlacement) -> some View {
        let relationships = library.relationships(for: item.id).filter { !$0.field.hasPrefix("inverse:") }
        if !relationships.isEmpty {
            Section("Relationships") {
                ForEach(relationships, id: \.field) { relationship in
                    row(relationship.field, title: ItemTypeInfo.Field.displayLabel(relationship.label), of: item.type, placement: placement)
                }
            }
        }
    }

    private func row(_ row: String, title: String, of type: TypeID, placement: PagePlacement) -> some View {
        Toggle(title, isOn: Binding(
            get: { placement.showsOnPage(row) },
            set: { placements.set($0, row: row, of: type) }))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("CustomizePageRow.\(row)")
    }

    private func linkedFromPicker(of type: TypeID, placement: PagePlacement) -> some View {
        Picker("Linked From", selection: Binding(
            get: { placement.linkedFromPlace },
            set: { placements.setLinkedFrom($0, of: type) })) {
            Text("On the Page").tag(LinkedFromPlace.page)
            Text("In the Inspector").tag(LinkedFromPlace.inspector)
        }
        .accessibilityIdentifier("CustomizePageLinkedFrom")
    }
}

/// Opens the Customize Page sheet for the type of one item, in the window whose presentation it is given.
struct CustomizePageButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?

    var body: some View {
        Button("Customize Page…", systemImage: "slider.horizontal.3") {
            if let id = ids.first { details?.pageCustomization = PageCustomizationRequest(item: id) }
        }
        .disabled(details == nil || ids.count != 1 || !PageCustomization.isAvailable(for: ids.first.flatMap { library.item($0) }))
    }
}
