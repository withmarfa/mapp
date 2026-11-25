import Foundation
import Marfa

extension ValueEditModel {
    /// Whether row `id` adds what the person typed in full: the Add or Create row, or a suggestion that is the same.
    func isTypedEntry(_ id: String) -> Bool {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != "create" else { return true }
        guard !typed.isEmpty else { return false }
        switch kind {
        case .tags: return id == "tag:" + ItemTag.normalized(typed)
        case .words: return id.lowercased() == "word:" + typed.lowercased()
        case .people(_, let shape):
            let person = PeopleSuggestions.entry(from: typed, shape: shape).flatMap { PeopleSuggestions.Person(entry: $0, shape: shape) }
            return person.map { id == "person:" + $0.identity } ?? false
        default: return false
        }
    }

    /// A new entry the list refused: the notice says why, and one the person typed stays in the search field as
    /// unsaved input.
    func refuse(_ reason: String?, typed: Bool) {
        notice = reason
        if typed { unsaved = UnsavedInput(text: query, reason: reason) }
    }

    /// Gives back what `unsaved` holds, once, then forgets it: text goes to the clipboard with a notice, and a time
    /// the person cleared, which has no text to give back, is told as a change not kept, which a quit waits for. What
    /// the value or the list holds by now is not lost.
    func handBackUnsaved(reason: String? = nil) {
        guard let input = unsaved else { return }
        unsaved = nil
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = reason ?? input.reason
        if isDate {
            guard text != timeText(of: input.base), !holdsTime(text) else { return }
            guard text.isEmpty else { return handBack(text, reason: reason) }
            let label = kind.field?.label ?? ""
            let why = reason ?? refusalReason(String(localized: "The value could not be saved."))
            library.notices.notKept(
                String(localized: "Property Not Saved"), text: nil, reason: String(localized: "The time in “\(label)” wasn’t cleared. \(why)"),
                standsAlone: true)
        } else if !holds(entry: text) {
            handBack(text, reason: reason)
        }
    }

    /// Whether the list already holds what the person typed.
    private func holds(entry text: String) -> Bool {
        switch kind {
        case .tags:
            // An item moved to Recently Deleted still holds a tag saved before the move.
            let tag = ItemTag.normalized(text)
            let items = request.targets.compactMap(library.item)
            let taking = items.filter { $0.allows(.tags) }
            let judged = taking.isEmpty ? items : taking
            return !judged.isEmpty && judged.allSatisfy { library.tags(of: $0).contains(tag) }
        case .words:
            return heldWords.contains { $0.lowercased() == text.lowercased() }
        case .people(_, let shape):
            guard let person = PeopleSuggestions.entry(from: text, shape: shape).flatMap({ PeopleSuggestions.Person(entry: $0, shape: shape) }) else { return false }
            return PeopleSuggestions.held(in: value, shape: shape).contains { $0.person.identity == person.identity }
        default:
            return false
        }
    }

    /// Gives the person text this panel cannot keep through the notices, which put it on the clipboard.
    private func handBack(_ text: String, reason: String? = nil) {
        guard !text.isEmpty else { return }
        let typed = kind.field.map { "\($0.label): \(text)" } ?? text
        let title = kind == .tags ? String(localized: "Tag Not Added") : String(localized: "Property Not Saved")
        library.notices.notKept(title, text: typed, reason: reason ?? refusalReason(String(localized: "The value could not be saved.")))
    }

    /// Whether the panel has a search field that takes a new tag, word or person.
    var takesNewEntries: Bool {
        switch kind {
        case .tags, .words, .people: true
        default: false
        }
    }
}
