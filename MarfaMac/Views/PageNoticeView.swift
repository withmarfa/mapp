import SwiftUI

/// A page's notices (`PageNotice`) as the file page and the saved web page draw them: quiet lines in the page's column,
/// 13 points at the default text size, each with its one action as a small gray button and, for the pictures' notice, a
/// close button. The wash reaches 12 points beyond the text, so its symbol stands where the text does. The web head
/// draws the same lines in `editor/src/notice.ts`. A screen reader hears them once, when they appear or say something
/// else.
struct PageNoticeView: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let notices: [PageNotice]
    let run: (PageNotice) -> Void
    var close: (() -> Void)?
    /// The width of the text column, which decides whether an action stands beside the words or under them.
    @State private var columnWidth: CGFloat = 0

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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
        // Said once, as a notice appears or says something else, and not again for a redraw.
        .onChange(of: notices.map(\.words), initial: true) { _, words in
            AccessibilityNotification.Announcement(words.joined(separator: " ")).post()
        }
    }

    /// Narrower than this, the words would wrap to four short lines beside the button, so the button stands under them.
    private func isNarrow(_ size: CGFloat) -> Bool { columnWidth > 0 && columnWidth < size * 316 / 13 }

    @ViewBuilder private func actionButton(_ notice: PageNotice, _ size: CGFloat) -> some View {
        if let label = notice.actionLabel, notice.action != nil {
            let beside = !isNarrow(size)
            Button { run(notice) } label: {
                Text(label).fixedSize()
            }
            .appButton(.secondary, size: .small)
            // Taller than the line it stands in, so beside the words it takes the difference off its margins and the
            // line keeps its height.
            .padding(.vertical, beside ? -size * 3 / 13 : 0)
            .padding(.leading, beside ? size * 7 / 13 : 0)
            .accessibilityIdentifier("PageNoticeAction")
        }
    }

    private func line(_ notice: PageNotice, _ size: CGFloat) -> some View {
        let underWords = isNarrow(size)
        return HStack(alignment: .top, spacing: size * 7 / 13) {
            Image(systemName: notice.symbol)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size * 18 / 13)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: size * 6 / 13) {
                Text(verbatim: notice.words)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if underWords { actionButton(notice, size) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !underWords { actionButton(notice, size) }
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
