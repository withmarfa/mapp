import SwiftUI

/// A page's notices (`PageNotice`) as the file page and the saved web page draw them: quiet lines in the page's column,
/// 13 points at the default text size, each with its one action as plain words and, for the pictures' notice, a close
/// button. The wash reaches 12 points beyond the text, so its symbol stands where the text does. The web head draws the
/// same lines in `editor/src/notice.ts`. A screen reader hears them once, when they appear or say something else.
struct PageNoticeView: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let notices: [PageNotice]
    let run: (PageNotice) -> Void
    var close: (() -> Void)?

    var body: some View {
        let size = CGFloat(textSize)
        VStack(alignment: .leading, spacing: size * 4 / 13) {
            ForEach(notices, id: \.kind) { line($0, size) }
            // Where the text is withheld, what it would have said.
            if let reason = notices.lazy.compactMap(\.reason).first {
                Text(verbatim: reason)
                    .foregroundStyle(.secondary)
                    .font(.system(size: size))
                    .textSelection(.enabled)
                    .padding(.top, size * 14 / 13)
            }
        }
        // Said once, as a notice appears or says something else, and not again for a redraw.
        .onChange(of: notices.map(\.words), initial: true) { _, words in
            AccessibilityNotification.Announcement(words.joined(separator: " ")).post()
        }
    }

    private func line(_ notice: PageNotice, _ size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: size * 7 / 13) {
            Image(systemName: notice.symbol)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size * 18 / 13)
                .accessibilityHidden(true)
            Text(verbatim: notice.words)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let label = notice.actionLabel, notice.action != nil {
                Button { run(notice) } label: {
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
        // The wash starts outside the text, so its symbol lines up with the text.
        .padding(.horizontal, -size * 12 / 13)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PageNotice")
    }
}

extension PageNotice {
    /// Carries out the notice's action for its own item. None writes or drops text: Recover changes the item's state, Open
    /// Copy opens another item, Show Changes opens Settings where the copy's changes are listed, and Load Pictures is the
    /// page's own (`loadPictures`).
    @MainActor func run(
        in library: any ItemLibrary, undoManager: UndoManager?, openWindow: OpenWindowAction,
        openSettings: (SettingsPage) -> Void, loadPictures: () -> Void = {}
    ) {
        switch action {
        case .recover: library.recover([item], undoManager: undoManager)
        case .openCopy(let copy): openWindow(value: copy)
        case .showChanges: openSettings(.connection)
        case .loadPictures: loadPictures()
        case nil: break
        }
    }
}

extension EnvironmentValues {
    /// Opens Settings, from whichever window shows the page.
    @Entry var settingsLauncher: SettingsLauncher?
}
