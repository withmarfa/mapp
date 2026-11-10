import SwiftUI

/// The Lists page of Settings: the row style every list starts from, what every list shows, and a style for each type.
struct ListsSettings: View {
    @Environment(\.library) private var library

    var body: some View {
        Form {
            Section("Row Style") { RowStyleTiles() }
            Section("In Every List") {
                ListPreviewOptions()
                OrderOptions()
            }
            .labelStyle(.titleOnly)
            if let library {
                TypeStyleSection(library: library)
            }
        }
        .settingsForm()
    }
}

/// The three styles every list can take, drawn small, the chosen one with an edge in the accent color.
private struct RowStyleTiles: View {
    @AppStorage(ListKey.rowStyle) private var stored = ListRowStyle.standard

    var body: some View {
        let chosen = ListRowStyle.resolve(rowStyle: stored)
        HStack(alignment: .top, spacing: 10) {
            ForEach(ListRowStyle.forEveryList) { style in
                Button { stored = style } label: {
                    VStack(spacing: 6) {
                        RowStyleSketch(style: style)
                            .frame(height: 96)
                            .background(.background, in: .rect(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(style == chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: style == chosen ? 2 : 0.5)
                            }
                        Text(style.title)
                            .foregroundStyle(style == chosen ? .primary : .secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(style == chosen ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A row style as a few lines of grey, enough to tell the three apart.
private struct RowStyleSketch: View {
    let style: ListRowStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 9 : 11) {
            ForEach(0..<(style == .compact ? 4 : 2), id: \.self) { _ in row }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func line(_ width: CGFloat, _ weight: HierarchicalShapeStyle = .tertiary) -> some View {
        Capsule().fill(weight).frame(width: width, height: 4)
    }

    @ViewBuilder private var row: some View {
        switch style {
        case .compact:
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 7, height: 7)
                line(48, .secondary)
                Spacer(minLength: 0)
                line(12)
            }
        case .withPictures:
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    line(52, .secondary)
                    line(70)
                    line(30)
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 22, height: 22)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    line(52, .secondary)
                    Spacer(minLength: 0)
                    line(14)
                }
                line(80)
                line(30)
            }
        }
    }
}

/// Each type the library holds, with the style its rows take. A type with no choice shows the style its fields start
/// it from, and picking Default goes back to that.
private struct TypeStyleSection: View {
    let library: any ItemLibrary
    @AppStorage(ListKey.typeStyles) private var choices = ListTypeStyles()

    var body: some View {
        let catalogue = library.catalogue
        Section {
            ForEach(library.itemTypeCounts) { type in
                let started = ListRowStyle.fromFields(of: type.id, in: catalogue)
                Picker(selection: Binding<ListRowStyle?> {
                    choices[type.id] ?? started
                } set: { choices[type.id] = $0 }) {
                    Text("Default").tag(ListRowStyle?.none)
                    Divider()
                    ForEach(ListRowStyle.allCases) { style in Text(style.title).tag(Optional(style)) }
                } label: {
                    Label { Text(verbatim: type.label) } icon: { TypeGlyph(id: type.icon) }
                }
                .accessibilityIdentifier("ListStyle")
            }
        } header: {
            Text("For Particular Types")
        } footer: {
            Text("A type starts from its fields: one with a status gets the Task row, one with pictures the picture row.")
        }
    }
}
