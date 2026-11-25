import Foundation

/// Writing through the source: `submit` hands the source each `ItemWrite` and follows it to its answer, and the
/// property edits and link replacements follow their writes further. Saved views and attachments are written elsewhere.
extension MarfaLibrary {
    func awaitLinks(_ links: Set<WriteID>, thenUnlink unlinks: [EdgeDraft], failing title: String, recordingIn step: LinkStep) {
        let group = UUID()
        replacements[group] = Replacement(awaiting: links, unlinks: unlinks, failing: title, step: step)
        step.heldBack = group
        for link in links { replacing[link] = group }
    }

    /// A link refused or held drops the removal, which leaves the old link beside any new one taken. The removals
    /// sent are the step's too, and their skips are told once.
    func settleReplacement(_ id: WriteID, _ outcome: WriteOutcome) {
        guard let group = replacing.removeValue(forKey: id), var replacement = replacements[group] else { return }
        switch outcome {
        case .accepted, .merged:
            replacement.awaiting.remove(id)
            guard replacement.awaiting.isEmpty else {
                replacements[group] = replacement
                return
            }
            dropReplacement(group)
            gatheringSkips(failing: replacement.failing) {
                unlink(replacement.unlinks, failing: replacement.failing, recordingIn: replacement.step)
            }
        case .conflicted, .refused, .blocked, .dead:
            dropReplacement(group)
        }
    }

    /// The removals held back for `group` are not sent, as when the step is undone before the new links are answered.
    func dropReplacement(_ group: UUID) {
        guard let replacement = replacements.removeValue(forKey: group) else { return }
        for link in replacement.awaiting { replacing[link] = nil }
        replacement.step.heldBack = nil
    }

    /// Every write the library makes goes through here, so a refusal reaches the person under `title`, as does
    /// a write made after the source closed, which nothing keeps.
    @discardableResult
    func submit(_ write: ItemWrite, failing title: String) -> WriteID {
        sendWaitingText(before: write)
        let id = WriteID()
        let unqueued = Self.unqueuedText(write)
        let refusal = Refusal(title: title, text: unqueued ?? Self.createdText(write), unqueuedText: unqueued)
        refusals[id] = refusal
        if let run = undoRun { undoRuns[id] = run }
        if !source.submit(write, as: id, undoing: undoRun?.group) {
            refusals[id] = nil
            undoRuns[id] = nil
            notices.notKept(title, text: refusal.text)
        } else {
            gather(id)
        }
        return id
    }

    /// The text the person typed into a write, which nothing else holds once the package refuses it before queueing:
    /// a body, a create's title, body and text values, since the person typed them in quick add, a tag, and the text values
    /// of a property edit, a title among them, or of a change of type, the values typed in its sheet among them.
    private static func unqueuedText(_ write: ItemWrite) -> String? {
        switch write {
        case .editBody(_, let text, _, _):
            return text
        case .create:
            return createdText(write)
        case .editProperties(_, let changes, _), .retype(_, _, let changes, _):
            let texts = changes.sorted { $0.key < $1.key }.flatMap { $0.value.map(texts(in:)) ?? [] }
            return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        case .tag(_, let tag, on: true) where tag != ItemTag.favorite:
            return tag
        default:
            return nil
        }
    }

    /// The text values a property holds, those inside a list of entries among them.
    private static func texts(in value: PropertyValue) -> [String] {
        switch value {
        case .string(let text): [text]
        case .array(let values): values.flatMap(texts(in:))
        case .object(let fields): fields.sorted { $0.key < $1.key }.flatMap { texts(in: $0.value) }
        case .null, .bool, .number, .double: []
        }
    }

    /// The text a create holds, its title, body and text values, which a source that closes before it answers
    /// gives back to the person.
    private static func createdText(_ write: ItemWrite) -> String? {
        guard case .create(_, let draft) = write else { return nil }
        let values = draft.properties.sorted { $0.key < $1.key }.compactMap { $0.value.string }
        return ([draft.title, draft.body] + values).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A property edit is on its way until the copy takes or refuses it, and followed until the server's final answer
    /// (`MarfaLibrary+PropertyEdits`). Nil where the source took nothing.
    @discardableResult
    func submitPropertyEdit(_ item: ItemID, _ changes: [String: PropertyValue?], base: ItemVersion, failing title: String) -> PropertyEdit? {
        let mark = (lastPropertyWrite ?? 0) + 1
        lastPropertyWrite = mark
        let edit = newEdit(of: item, changes)
        let id = submit(.editProperties(item, changes, base: base), failing: title)
        guard refusals[id] != nil else { return nil }
        propertyWrites[id] = item
        propertyMarks[id] = mark
        propertyEdits[id] = edit
        for key in changes.keys { newestEdits[item, default: [:]][key] = edit }
        return edit
    }

    func propertyAnswered(_ id: WriteID, _ outcome: WriteOutcome, holding: [String: PropertyValue]?) {
        guard let edit = propertyEdits[id], let kept = PropertyEdit.kept(edit.changes.keys, after: outcome, holding: holding, left: edit.left) else { return }
        edit.kept = kept
        propertyEdits[id] = nil
    }

    /// The items were read after any answer published before, so the copy shows what those answers left.
    func forgetAnsweredEdits(of items: Set<ItemID>) {
        for item in items where newestEdits[item] != nil {
            newestEdits[item] = newestEdits[item]?.filter { $0.value.kept == nil }
            if newestEdits[item]?.isEmpty == true { newestEdits[item] = nil }
        }
    }

    func isWritingProperties(of id: ItemID) -> Bool { propertyWrites.values.contains(id) }

    func tookPropertyWrite(_ mark: Int) -> Bool { takenMarks.contains(mark) }

    /// An editor asks about its writes as it next draws, so only the latest marks are kept.
    func remember(taken mark: Int) {
        takenMarks.insert(mark)
        guard takenMarks.count > Self.takenMarkLimit, let last = lastPropertyWrite else { return }
        takenMarks = takenMarks.filter { $0 > last - Self.takenMarkLimit }
    }

    private static let takenMarkLimit = 256

    /// A create is followed to its answer, so one refused before the source holds the item is told to the window that made it.
    func submitCreate(_ id: ItemID, _ draft: ItemDraft, failing title: String) {
        let write = submit(.create(id: id, draft), failing: title)
        if refusals[write] != nil { creating[write] = id } else { refusedCreations.insert(id) }
    }
}
