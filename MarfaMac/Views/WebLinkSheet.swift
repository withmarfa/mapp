import SwiftUI

/// Asks for the address the Link command sets on the selection. Return adds or changes it; Cancel or Escape leaves the text
/// as it was. When the caret is in a link, Delete takes it off.
struct WebLinkSheet: View {
    let editor: EditorController
    let request: EditorController.WebLinkRequest
    @State private var address: String
    @State private var refused = false
    @FocusState private var isFieldFocused: Bool

    init(editor: EditorController, request: EditorController.WebLinkRequest) {
        self.editor = editor
        self.request = request
        _address = State(initialValue: request.address)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.removable ? "Edit Link" : "Link").interfaceFont(.title2.bold())
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Web Address")
                TextField("Web Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .appFocusRing(isFocused: isFieldFocused)
                    .onSubmit(add)
                    .accessibilityIdentifier("WebLinkField")
            }
            if refused {
                Text("Enter a web, email, or phone address.")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            HStack {
                if request.removable {
                    Button("Delete", action: editor.removeWebLink)
                        .appButton(.destructive)
                        .accessibilityIdentifier("WebLinkRemove")
                }
                Spacer()
                Button("Cancel", role: .cancel) { editor.cancelWebLink() }
                    .keyboardShortcut(.cancelAction)
                    .appButton(.secondary)
                Button(request.removable ? "Done" : "Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .appButton(.primary)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("WebLinkAdd")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: address) { refused = false }
        .task { isFieldFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WebLinkSheet")
    }

    private func add() {
        Task { refused = !(await editor.setWebLink(address)) }
    }
}
