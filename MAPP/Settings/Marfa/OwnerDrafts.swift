import Foundation

/// What a page holds that the person typed and has not kept, as the app hands it back when Settings closes or the app quits.
nonisolated enum OwnerDraft: Equatable, Sendable {
    /// Text the person typed, which the app gives back where they can get it again.
    case typed(title: String, text: String)
    /// Something done that cannot be shown again, which the app tells the person about.
    case told(title: String, message: String)
}

/// A page's model that can hold a draft.
@MainActor protocol OwnerDraftHolding: AnyObject {
    /// What was typed and not kept, taken from the holder: it holds nothing afterwards.
    func takeDrafts() -> [OwnerDraft]
}

/// The models of the owner's pages that are open, so the app can ask them for their drafts without reaching into a page.
/// It holds none of them: a page that goes away takes its model with it.
@MainActor final class OwnerDrafts {
    private struct Holder {
        weak var value: (any OwnerDraftHolding)?
    }

    private var holders: [Holder] = []

    /// Registers `holder` once, for as long as it lives.
    func register(_ holder: any OwnerDraftHolding) {
        holders.removeAll { $0.value == nil }
        guard !holders.contains(where: { $0.value === holder }) else { return }
        holders.append(Holder(value: holder))
    }

    /// Everything the open pages hold, taken from them.
    func takeAll() -> [OwnerDraft] {
        holders.removeAll { $0.value == nil }
        return holders.flatMap { $0.value?.takeDrafts() ?? [] }
    }
}
