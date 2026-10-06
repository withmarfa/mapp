import SwiftUI

/// The chosen type, for the window's content column where a note is otherwise: an item type with its place in the
/// hierarchy, its fields and the edge types that connect it, or an edge type with the rules it holds.
struct TypeDetailView: View {
    let browser: TypesBrowser

    var body: some View {
        Group {
            if let detail = browser.selectedItemType {
                ItemTypePage(detail: detail, browser: browser)
            } else if let detail = browser.selectedEdgeType {
                EdgeTypePage(detail: detail, browser: browser)
            } else {
                ContentUnavailableView(
                    "No Type Selected", systemImage: "square.stack.3d.up",
                    description: Text("Choose a type to see its fields and connections."))
            }
        }
        .accessibilityIdentifier("MarfaTypes")
    }
}

// MARK: Item type

private struct ItemTypePage: View {
    let detail: ItemTypeDetail
    let browser: TypesBrowser

    var body: some View {
        Form {
            TypeHeader(label: detail.type.label, id: detail.type.id.rawValue, description: detail.type.description)

            Section {
                if !detail.parents.isEmpty {
                    LabeledContent("Parent types") {
                        HStack(spacing: 4) {
                            ForEach(Array(detail.parents.enumerated()), id: \.element.id) { index, parent in
                                if index > 0 { Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.tertiary) }
                                TypeLink(reference: parent, browser: browser)
                            }
                        }
                    }
                }
                if let version = detail.type.version {
                    LabeledContent("Version") { Text(version, format: .number.grouping(.never)) }
                }
                if !detail.type.roles.isEmpty {
                    LabeledContent("Roles") { Text(detail.type.roles.formatted(.list(type: .and, width: .narrow))) }
                }
                LabeledContent("Title") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(detail.titleProperty).monospaced()
                        if !detail.declaresTitle {
                            Text("Not a field of this type").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Body") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(detail.bodyProperty).monospaced()
                        if !detail.declaresBody {
                            Text("Not a field of this type").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Fields") {
                if detail.fields.isEmpty {
                    Text("This type has no fields.").foregroundStyle(.secondary)
                }
                ForEach(detail.fields) { row in
                    FieldRowView(row: row, browser: browser)
                }
            }

            if !detail.compatibleWith.isEmpty || !detail.compatibleFrom.isEmpty {
                Section {
                    if !detail.compatibleWith.isEmpty {
                        LabeledContent("Compatible with") { TypeLinks(references: detail.compatibleWith, browser: browser) }
                    }
                    if !detail.compatibleFrom.isEmpty {
                        LabeledContent("Compatible from") { TypeLinks(references: detail.compatibleFrom, browser: browser) }
                    }
                } header: {
                    Text("Compatibility")
                } footer: {
                    Text("A type that is compatible with another claims to have at least the other’s fields.")
                }
            }

            Section {
                ForEach(detail.edgeTypes) { link in
                    EdgeLinkRow(link: link, browser: browser)
                }
            } header: {
                Text("Edge types")
            } footer: {
                Text("Edge types that do not limit their types connect every type, so they are not listed here.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct FieldRowView: View {
    let row: ItemTypeDetail.FieldRow
    let browser: TypesBrowser

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.field.label)
                Text(row.field.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let description = row.field.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case .choice(let values) = row.field.kind, !values.isEmpty {
                    Text(values.formatted(.list(type: .or, width: .narrow)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.field.kind.wording)
                if row.field.required {
                    Text("Required").font(.caption).foregroundStyle(.secondary)
                }
                if let source = row.inheritedFrom {
                    HStack(spacing: 2) {
                        Text("Inherited from")
                        TypeLink(reference: source, browser: browser)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        // Contained rather than combined, so the link to the declaring type stays reachable on its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MarfaTypeField.\(row.field.key)")
    }
}

private struct EdgeLinkRow: View {
    let link: ItemTypeDetail.EdgeLink
    let browser: TypesBrowser

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(link.role.wording)
                if let reverse = link.edge.reverseName {
                    Text("Reverse name: \(reverse)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        } label: {
            Button(link.edge.label) { browser.select(link.edge.selection) }
                .buttonStyle(.link)
        }
    }
}

// MARK: Edge type

private struct EdgeTypePage: View {
    let detail: EdgeTypeDetail
    let browser: TypesBrowser

    var body: some View {
        Form {
            TypeHeader(label: detail.edge.label, id: detail.edge.id, description: detail.edge.description)

            Section {
                LabeledContent("Reverse name") {
                    if let reverse = detail.edge.reverseName {
                        Text(reverse).monospaced()
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Written at") { Text(detail.edge.writtenAtWording) }
                LabeledContent("When an item is deleted") { Text(detail.edge.cascadeWording) }
            }

            Section {
                EndRow(
                    title: "From", types: detail.sourceTypes, roles: detail.sourceRoles, allowsAny: detail.edge.allowsAnySource(),
                    wording: detail.edge.sourceEndWording, browser: browser)
                EndRow(
                    title: "To", types: detail.targetTypes, roles: detail.targetRoles, allowsAny: detail.edge.allowsAnyTarget(),
                    wording: detail.edge.targetEndWording, browser: browser)
            } header: {
                Text("Ends")
            } footer: {
                Text("An edge points from one item to another.")
            }

            if !detail.edge.properties.isEmpty {
                Section("Properties") {
                    ForEach(detail.edge.properties) { property in
                        PropertyRow(property: property)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EndRow: View {
    let title: LocalizedStringKey
    let types: [TypeReference]
    let roles: [String]
    let allowsAny: Bool
    let wording: String
    let browser: TypesBrowser

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                if allowsAny {
                    Text("Any type")
                } else {
                    TypeLinks(references: types, browser: browser)
                    ForEach(roles, id: \.self) { role in
                        Text(roleWording(role))
                    }
                }
                Text(wording).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PropertyRow: View {
    let property: ItemTypeInfo.Field

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.label)
                Text(property.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let description = property.description {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(property.kind.wording)
                if property.required { Text("Required").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Shared

private struct TypeHeader: View {
    let label: String
    let id: String
    let description: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.title.bold())
                Text(id).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if let description {
                    Text(description).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A type that selects it when pressed, or plain text where the catalogue lacks it.
private struct TypeLink: View {
    let reference: TypeReference
    let browser: TypesBrowser

    var body: some View {
        if reference.isKnown {
            Button(reference.label) { browser.select(.item(reference.id)) }
                .buttonStyle(.link)
        } else {
            Text(reference.label).monospaced()
        }
    }
}

private struct TypeLinks: View {
    let references: [TypeReference]
    let browser: TypesBrowser

    var body: some View {
        WrappingLayout(spacing: 8) {
            ForEach(references) { reference in
                TypeLink(reference: reference, browser: browser)
            }
        }
    }
}

/// Lays its views out in lines that break where the width runs out, as text does, so a long list of types stays
/// readable at large text sizes. Each line ends at the trailing edge, where the values of a form sit.
private struct WrappingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(in: proposal.width ?? .infinity, subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(in: bounds.width, subviews) {
            var x = bounds.maxX - line.width
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(in available: CGFloat, _ subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap = lines[lines.count - 1].indices.isEmpty ? 0 : spacing
            if !lines[lines.count - 1].indices.isEmpty, lines[lines.count - 1].width + gap + size.width > available {
                lines.append(Line())
            }
            let last = lines.count - 1
            lines[last].width += (lines[last].indices.isEmpty ? 0 : spacing) + size.width
            lines[last].height = max(lines[last].height, size.height)
            lines[last].indices.append(index)
        }
        return lines
    }
}
