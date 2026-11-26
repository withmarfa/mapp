import Foundation

/// A person as a message writes them, `Ines Barros <ines@barroslima.example>`: the name a page draws as a person, and the
/// address it draws in grey after it. A bare address or a name alone is a name with no address.
nonisolated struct PersonAddress: Equatable, Sendable {
    let name: String
    let address: String?

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(">"), let open = trimmed.lastIndex(of: "<") {
            let address = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            let name = trimmed[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            if !name.isEmpty {
                self.name = name
                self.address = address.isEmpty ? nil : address
                return
            }
            if !address.isEmpty {
                self.name = address
                self.address = nil
                return
            }
        }
        name = trimmed
        address = nil
    }
}
