import SwiftUI

/// What the Sources page asks for to rename a source or choose its mark.
struct SourceEditRequest: Identifiable, Hashable {
    let code: String
    let mode: SourceEditModel.Mode
    var id: String { "\(mode):\(code)" }
}

/// Renames a source. The name is kept on the server for every app, and shows at once.
struct SourceNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SourceEditModel
    @FocusState private var focused: Bool

    init(request: SourceEditRequest, library: any ItemLibrary) {
        _model = State(initialValue: SourceEditModel(code: request.code, mode: .name, library: library))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Source").interfaceFont(.title2.bold())
            Text("The name shows in every app that uses your Marfa server.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(!model.canChange)
                .onSubmit(rename)
                .accessibilityIdentifier("SourceName")
            SourceEditNotes(model: model)
            HStack {
                Button("Use Default Name") { run { await model.useDefaultName() } }
                    .disabled(!model.canUseDefaultName)
                    .accessibilityIdentifier("SourceUseDefaultName")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.canCancel)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canRename)
                    .accessibilityIdentifier("SourceRename")
            }
        }
        .padding(20)
        .frame(width: 400)
        .interactiveDismissDisabled(!model.canCancel)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SourceNameSheet")
    }

    private func rename() { run { await model.rename() } }

    private func run(_ change: @escaping () async -> Bool) {
        Task { if await change() { dismiss() } }
    }
}

/// Chooses the mark of a source from the Lucide and Simple Icons sets, each drawn as MAPP will draw it. The mark is
/// saved as a full ID, such as `simple-icons:readwise`, on the server for every app.
struct SourceMarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SourceEditModel
    @FocusState private var searchFocused: Bool

    init(request: SourceEditRequest, library: any ItemLibrary) {
        _model = State(initialValue: SourceEditModel(code: request.code, mode: .mark, library: library))
    }

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 6)]

    var body: some View {
        let results = model.results
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Mark").interfaceFont(.title2.bold())
            Text("The mark for \(model.current.name) shows in every app that uses your Marfa server.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Icon Set", selection: $model.set) {
                ForEach(IconSet.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Search Icons", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("SourceMarkSearch")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(results, id: \.self) { icon in
                        Button { choose(icon) } label: {
                            RowIconImage(icon: .type(icon))
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(icon == model.current.mark ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
                                .contentShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(IconNameSearch.title(of: icon))
                        .accessibilityLabel(IconNameSearch.title(of: icon))
                        .accessibilityAddTraits(icon == model.current.mark ? .isSelected : [])
                        .accessibilityIdentifier("SourceMark.\(icon)")
                    }
                }
                .disabled(!model.canChange)
                .padding(4)
            }
            .frame(height: 280)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: model.search) }
            }
            SourceEditNotes(model: model)
            HStack {
                Button("Remove Mark") { choose(nil) }
                    .disabled(!model.canRemoveMark)
                    .accessibilityIdentifier("SourceRemoveMark")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.canCancel)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(!model.canCancel)
        .onAppear { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SourceMarkSheet")
    }

    private func choose(_ id: String?) {
        Task { if await model.chooseMark(id) { dismiss() } }
    }
}

/// Says why a source can't be changed now, or why the server refused the change.
private struct SourceEditNotes: View {
    let model: SourceEditModel

    var body: some View {
        if let failure = model.failure {
            Text(failure.message)
                .interfaceFont(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("SourceEditFailure")
        } else if model.canCancel, !model.canChange {
            Text("Sources are named on your server, so you can change one once MAPP is connected.")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
