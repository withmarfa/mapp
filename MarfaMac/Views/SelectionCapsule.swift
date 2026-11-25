import SwiftUI

extension SelectionSummary {
    /// Whether the window shows the capsule, which the corner and the toast lift above.
    var isCapsuleShown: Bool { facts.count > 1 }

    /// From the foot of the content to the top of the capsule and a little more, where the corner and a toast rise from.
    static func capsuleRoom(scale: CGFloat) -> CGFloat {
        WindowCorner<EmptyView, EmptyView>.inset + CornerMetrics.height * scale + 10
    }
}

/// Several chosen items as one capsule of glass at the foot of the window: the count, which lets them go, then the lead
/// command with its word where there is one (Keep in the Feed), the commands as symbols, and Delete on its own at the end.
/// Each button asks for what the item menus ask for, through the same commands, so it asks, skips, tells and undoes as
/// they do. It reads only `SelectionSummary`, which is worked out once for each change of the choice.
struct SelectionCapsule: View {
    let browser: Browser
    @CurrentLibrary private var library
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.interfaceTextSize) private var textSize

    /// What folds into More as the room narrows: the commands that need no choice at once, then the count's word.
    private enum Fold { case none, folded }

    var body: some View {
        let facts = summary?.facts ?? SelectionFacts()
        let scale = InterfaceStyle.scale(for: textSize)
        Group {
            if facts.count > 1 {
                GlassEffectContainer(spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        capsule(facts, fold: .none, scale: scale)
                        capsule(facts, fold: .folded, scale: scale)
                    }
                }
                // The arrow, even over a web view, which would draw its own pointer under the buttons.
                .pointerStyle(.default)
                .onExitCommand { browser.selection = [] }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Selection"))
                .accessibilityIdentifier("SelectionCapsule")
            }
        }
        // Said as it changes, since the count is what the person chose by pointer or key and nothing else tells it.
        .onChange(of: facts.count) { _, count in
            if count > 1 { AccessibilityNotification.Announcement(AttributedString(localized: "^[\(count) item](inflect: true) selected").text).post() }
        }
    }

    private func capsule(_ facts: SelectionFacts, fold: Fold, scale: CGFloat) -> some View {
        HStack(spacing: 8) {
            countButton(facts, compact: fold == .folded)
            if facts.isAllInBin {
                recoverButton(facts)
            } else if facts.moves.contains(.keep) {
                keepButton(facts)
            }
            if !facts.isAllInBin { symbols(facts, fold: fold, scale: scale) }
            // Delete stands apart from the commands that keep the items.
            deleteButton(facts)
                .padding(.leading, 8)
        }
        .fixedSize()
    }

    // MARK: Parts

    private func countButton(_ facts: SelectionFacts, compact: Bool) -> some View {
        Button {
            browser.selection = []
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: compact ? facts.count.formatted() : String(localized: "\(facts.count.formatted()) Selected"))
                    .monospacedDigit()
            }
        }
        .buttonStyle(CornerButtonStyle())
        .help("Deselect All")
        .accessibilityLabel(Text("Deselect All"))
        .accessibilityValue(Text(AttributedString(localized: "^[\(facts.count) item](inflect: true) selected").text))
        .accessibilityIdentifier("SelectionCount")
    }

    private func keepButton(_ facts: SelectionFacts) -> some View {
        Button {
            perform(.keep, facts)
        } label: {
            Label("Keep", systemImage: ItemMove.keep.symbol)
        }
        .buttonStyle(CornerButtonStyle())
        .help("Keep in Library")
        .accessibilityIdentifier("SelectionKeep")
    }

    private func recoverButton(_ facts: SelectionFacts) -> some View {
        Button {
            library.recover(facts.ids, undoManager: undoManager)
        } label: {
            Label("Recover", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(CornerButtonStyle())
        .accessibilityIdentifier("SelectionRecover")
    }

    private func symbols(_ facts: SelectionFacts, fold: Fold, scale: CGFloat) -> some View {
        let height = CornerMetrics.height * scale
        return HStack(spacing: 0) {
            let archive = facts.archiveMove
            symbol(archive.name, archive.symbol, id: "SelectionArchive", enabled: facts.moves.contains(archive)) {
                perform(archive, facts)
            }
            if fold == .none {
                symbol(String(localized: "Add Tag"), "tag", id: "SelectionTag", enabled: facts.canTag && details != nil) {
                    details?.tagRequest = TagRequest(ids: facts.ids, undoManager: undoManager)
                }
                symbol(String(localized: "Add to Collection"), "rectangle.stack.badge.plus", id: "SelectionCollection", enabled: facts.canCollect && details != nil) {
                    details?.collectionPick = CollectionPickRequest(ids: facts.ids, undoManager: undoManager)
                }
                symbol(String(localized: "Change Type"), "square.on.square", id: "SelectionType", enabled: facts.canChangeType && details != nil) {
                    details?.typeChange = TypeChangeRequest(ids: facts.ids, undoManager: undoManager)
                }
            }
            moreMenu(facts, fold: fold)
        }
        .buttonStyle(CapsuleSegmentStyle())
        .padding(.horizontal, 3)
        .frame(height: height)
        .glassEffect(.regular, in: .capsule)
    }

    /// One symbol of the group; its word is its help tag and its label for VoiceOver.
    private func symbol(_ title: String, _ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier(id)
    }

    /// What the symbols leave out, and what a narrow window folds in: Favorite, Move to Feed, Remove from Collection.
    private func moreMenu(_ facts: SelectionFacts, fold: Fold) -> some View {
        Menu {
            if fold == .folded {
                Button("Add Tag…", systemImage: "tag") { details?.tagRequest = TagRequest(ids: facts.ids, undoManager: undoManager) }
                    .disabled(!facts.canTag || details == nil)
                Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
                    details?.collectionPick = CollectionPickRequest(ids: facts.ids, undoManager: undoManager)
                }
                .disabled(!facts.canCollect || details == nil)
                Button("Change Type…", systemImage: "square.on.square") {
                    details?.typeChange = TypeChangeRequest(ids: facts.ids, undoManager: undoManager)
                }
                .disabled(!facts.canChangeType || details == nil)
                Divider()
            }
            Button(facts.allFavorites ? "Remove from Favorites" : "Add to Favorites", systemImage: facts.allFavorites ? "star.slash" : "star") {
                library.setFavorite(facts.ids, !facts.allFavorites, undoManager: undoManager)
            }
            .disabled(!facts.canFavorite)
            if facts.moves.contains(.moveToFeed) {
                Button(ItemMove.moveToFeed.name, systemImage: ItemMove.moveToFeed.symbol) { perform(.moveToFeed, facts) }
            }
            RemoveFromCollectionActions(selection: facts.ids, undoManager: undoManager)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel(Text("More"))
        .accessibilityIdentifier("SelectionMore")
    }

    private func deleteButton(_ facts: SelectionFacts) -> some View {
        Button {
            library.deleteAfterSaving(facts.ids, undoManager: undoManager, asking: details)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(CornerButtonStyle())
        .disabled(facts.isAllInBin && !library.reachesServer)
        .help(facts.isAllInBin ? "Delete Immediately…" : "Delete")
        .accessibilityLabel(Text(facts.isAllInBin ? "Delete Immediately…" : "Delete"))
        .accessibilityIdentifier("SelectionDelete")
    }

    private func perform(_ move: ItemMove, _ facts: SelectionFacts) {
        library.perform(move, on: facts.ids, undoManager: undoManager, details: details)
    }
}

/// One symbol of the capsule's group: a soft circle under the pointer, as the corner's segments are.
private struct CapsuleSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration)
    }

    private struct Segment: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.interfaceTextSize) private var textSize

        var body: some View {
            let scale = InterfaceStyle.scale(for: textSize)
            configuration.label
                .font(.system(size: 14 * scale, weight: .regular))
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: 34 * scale)
                .frame(maxHeight: .infinity)
                .background {
                    Circle()
                        .fill(.primary.opacity(configuration.isPressed ? 0.12 : isHovered && isEnabled ? 0.07 : 0))
                        .frame(width: 28 * scale, height: 28 * scale)
                }
                .contentShape(.rect)
                .onHover { isHovered = $0 }
        }
    }
}

/// The capsule at the foot of a layout, over the content it belongs to and never the sidebar, with the rows that run
/// under it fading out, and room left at the foot of what scrolls so the last row clears it.
private struct SelectionCapsuleFoot: ViewModifier {
    let browser: Browser
    /// Whether the content under the capsule is a layout of rows, which fade and scroll clear of it.
    let spansLayout: Bool
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isShown = summary?.isCapsuleShown == true
        let scale = InterfaceStyle.scale(for: textSize)
        content
            .contentMargins(.bottom, spansLayout && isShown ? SelectionSummary.capsuleRoom(scale: scale) : 0, for: .scrollContent)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if isShown {
                        if spansLayout {
                            Rectangle()
                                .fill(.background)
                                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                                .frame(height: SelectionSummary.capsuleRoom(scale: scale) + 28)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                        SelectionCapsule(browser: browser)
                            .padding(.horizontal, WindowCorner<EmptyView, EmptyView>.inset)
                            .padding(.bottom, WindowCorner<EmptyView, EmptyView>.inset)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isShown)
            }
    }
}

extension View {
    /// Puts the capsule for the window's chosen items at the foot of this content. `spansLayout` is for a layout of
    /// rows, whose last row scrolls clear of it.
    func selectionCapsule(for browser: Browser, spansLayout: Bool) -> some View {
        modifier(SelectionCapsuleFoot(browser: browser, spansLayout: spansLayout))
    }

    /// Escape lets go of several chosen items, in a layout that has no Escape of its own. One chosen item stays, since
    /// Escape there leaves it to the page.
    func clearsSeveralOnEscape(_ browser: Browser) -> some View {
        onKeyPress(.escape) {
            guard browser.selection.count > 1 else { return .ignored }
            browser.selection = []
            return .handled
        }
    }
}

/// ⌘⌫ deletes the chosen items, as it does in the list, and the system's Delete command too, in a layout that has no
/// handler for it. Several items ask first, as the capsule's Delete does. A choice outlives what a layout shows, as when
/// the calendar moves to another week, so a key deletes only the chosen items `shown` names.
private struct DeletesChosen: ViewModifier {
    private var delete = ChosenItemDeletion()
    let browser: Browser
    let shown: () -> Set<ItemID>

    func body(content: Content) -> some View {
        content
            .onDeleteCommand(perform: deleteChosen)
            .onKeyPress(.delete, phases: .down) { press in
                guard press.modifiers.contains(.command), !browser.selection.isEmpty else { return .ignored }
                deleteChosen()
                return .handled
            }
            // AppKit maps Command-Backspace to this text-system command before keyDown reaches SwiftUI.
            .onCommand(#selector(NSResponder.deleteToBeginningOfLine(_:))) {
                if !browser.selection.isEmpty { deleteChosen() }
            }
    }

    private func deleteChosen() {
        delete(browser, shown: shown)
    }
}

/// The focused layout deletes only its own chosen items, through the same write as the Delete command.
struct ChosenItemDeletion: DynamicProperty {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?

    func callAsFunction(_ browser: Browser, shown: () -> Set<ItemID>) {
        guard !browser.selection.isEmpty else { return }
        let ids = browser.selection.intersection(shown())
        guard !ids.isEmpty else { return }
        library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
    }
}

extension View {
    /// `shown` is read when a key is pressed, never while the layout draws.
    func deletesChosen(_ browser: Browser, shown: @escaping () -> Set<ItemID>) -> some View {
        modifier(DeletesChosen(browser: browser, shown: shown))
    }
}
