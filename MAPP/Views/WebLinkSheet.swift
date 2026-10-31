import SwiftUI

/// Asks for the address the Link command sets on the selection. Return adds it; Cancel or Escape leaves the text
/// as it was. When the caret is in a link, Remove Link takes it off.
struct WebLinkSheet: View {
    let editor: EditorController
    let request: EditorController.WebLinkRequest
    @State private var address = ""
    @State private var refused = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link").interfaceFont(.title2.bold())
            TextField("Web Address", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit(add)
                .accessibilityIdentifier("WebLinkField")
            if refused {
                Text("Enter a web, email, or phone address.")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            HStack {
                if request.removable {
                    Button("Remove Link") { editor.finishWebLink(nil) }
                        .accessibilityIdentifier("WebLinkRemove")
                }
                Spacer()
                Button("Cancel", role: .cancel) { editor.cancelWebLink() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
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
        refused = !editor.finishWebLink(address)
    }
}
