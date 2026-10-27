import MarfaIcons
import SwiftUI

/// What the sidebar asks for to choose a type's icon.
struct TypeIconRequest: Identifiable, Hashable {
    let type: TypeID
    var id: TypeID { type }
}

/// Chooses the icon of a type from the Lucide names Marfa accepts, each drawn as MAPP will draw it. The choice is kept
/// on the server for every app, and the new icon shows at once. Use Default hands the choice back to the type.
struct TypeIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TypeIconPickerModel
    @FocusState private var searchFocused: Bool

    init(request: TypeIconRequest, library: any ItemLibrary) {
        _model = State(initialValue: TypeIconPickerModel(type: request.type, library: library))
    }

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 6)]

    var body: some View {
        let results = model.results
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an Icon").interfaceFont(.title2.bold())
            Text("The icon for \(model.typeLabel) shows in every app that uses your Marfa server.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search Icons", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("TypeIconSearch")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        Button { choose(name) } label: {
                            TypeIcon(name: name)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(name == model.current ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
                                .contentShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(IconNameSearch.title(of: name))
                        .accessibilityLabel(IconNameSearch.title(of: name))
                        .accessibilityAddTraits(name == model.current ? .isSelected : [])
                        .accessibilityIdentifier("TypeIcon.\(name)")
                    }
                }
                .padding(4)
            }
            .frame(height: 280)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: model.search) }
            }
            if !model.canChoose, !model.isWorking, model.failure == nil {
                Text("Icons are kept on your server, so you can choose one once MAPP is connected.")
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failure = model.failure {
                Text(failure.message)
                    .interfaceFont(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("TypeIconFailure")
            }
            HStack {
                Button("Use Default") { choose(nil) }
                    .disabled(!model.canChoose)
                    .accessibilityIdentifier("TypeIconUseDefault")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TypeIconPicker")
    }

    private func choose(_ name: String?) {
        Task { if await model.choose(name) { dismiss() } }
    }
}
