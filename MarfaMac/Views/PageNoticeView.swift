import SwiftUI

/// A page's notice (`PageNotice`) as the file page and the saved web page draw it: one quiet line in the page's column,
/// 13 points at the default text size, with its one action as plain words and, for the pictures' notice, a close button.
/// The web head draws the same line in `editor/src/notice.ts`. A screen reader hears it once, when it appears.
struct PageNoticeView: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let notice: PageNotice
    let run: (PageNotice.Action) -> Void
    var close: (() -> Void)?

    var body: some View {
        let size = CGFloat(textSize)
        VStack(alignment: .leading, spacing: size * 18 / 13) {
            line(size)
            // Where the text is withheld, what it would have said.
            if let reason = notice.reason {
                Text(verbatim: reason)
                    .foregroundStyle(.secondary)
                    .font(.system(size: size))
                    .textSelection(.enabled)
                    .padding(.horizontal, size * 12 / 13)
            }
        }
        // Said once, as the notice appears or says something else, and not again for a redraw.
        .onChange(of: notice.words, initial: true) { _, words in
            AccessibilityNotification.Announcement(words).post()
        }
    }

    private func line(_ size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: size * 7 / 13) {
            Image(systemName: notice.symbol)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size * 18 / 13)
                .accessibilityHidden(true)
            Text(verbatim: notice.words)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let label = notice.actionLabel, let action = notice.action {
                Button { run(action) } label: {
                    Text(label).font(.system(size: size, weight: .medium)).fixedSize()
                }
                .buttonStyle(.plain)
                .appFocusRing(RoundedRectangle(cornerRadius: size * 4 / 13, style: .continuous))
                .padding(.leading, size * 7 / 13)
                .accessibilityIdentifier("PageNoticeAction")
            }
            if notice.isClosable, let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: size * 9 / 13, weight: .bold))
                }
                .appButton(.plain, size: .small, icon: true)
                .help("Close")
                .accessibilityLabel("Close")
                .accessibilityIdentifier("PageNoticeClose")
                .padding(.leading, -size * 2 / 13)
            }
        }
        .font(.system(size: size))
        .lineSpacing(size * 2 / 13)
        .padding(EdgeInsets(top: size * 9 / 13, leading: size * 12 / 13, bottom: size * 9 / 13, trailing: size * 12 / 13))
        .background(.quinary, in: RoundedRectangle(cornerRadius: size * 10 / 13, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PageNotice")
    }
}

extension PageNotice.Action {
    /// Carries out the action for the item the page shows. None writes or drops text: Recover changes the item's state,
    /// Open Copy opens another item, and Load Pictures is the page's own (`loadPictures`).
    @MainActor func run(
        for item: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, openWindow: OpenWindowAction,
        loadPictures: () -> Void = {}
    ) {
        switch self {
        case .recover: library.recover([item], undoManager: undoManager)
        case .openCopy(let copy): openWindow(value: copy)
        case .loadPictures: loadPictures()
        }
    }
}
