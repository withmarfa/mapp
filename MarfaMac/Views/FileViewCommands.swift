import SwiftUI

/// The commands of an image's or a PDF's page that the corner's controls also run: Zoom In, Zoom Out, Actual Size,
/// Zoom to Fit, and for a PDF Next Page and Previous Page. Each is defined once, for the View menu and the palette.
///
/// While a file page shows these commands, they hold ⌘+, ⌘− and ⌘0, and the text-size commands (`TextZoomCommands`) are
/// not offered, so a key sizes the file or the text and never both.
enum FileViewCommand: CaseIterable {
    case zoomIn, zoomOut, actualSize, zoomToFit, nextPage, previousPage

    /// The commands a page of `kind` offers, in menu order.
    static func offered(for kind: FileViewKind) -> [FileViewCommand] {
        switch kind {
        case .image: [.zoomIn, .zoomOut, .actualSize, .zoomToFit]
        case .pdf: allCases
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .zoomToFit: "Zoom to Fit"
        case .nextPage: "Next Page"
        case .previousPage: "Previous Page"
        }
    }

    var systemImage: String {
        switch self {
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .actualSize: "1.magnifyingglass"
        case .zoomToFit: "arrow.up.left.and.down.right.magnifyingglass"
        case .nextPage: "chevron.down"
        case .previousPage: "chevron.up"
        }
    }

    /// The command whose key sizes the file. Zoom In, Zoom Out and Actual Size share the keys of the text size commands, so
    /// one choice in Settings holds for the file and for the text, and a key sizes one or the other, never both.
    var shortcutCommand: ShortcutCommand {
        switch self {
        case .zoomIn: .makeTextBigger
        case .zoomOut: .makeTextSmaller
        case .actualSize: .actualSize
        case .zoomToFit: .zoomToFit
        case .nextPage: .nextPage
        case .previousPage: .previousPage
        }
    }

    func isEnabled(on viewing: FileViewing) -> Bool {
        switch self {
        case .zoomIn: viewing.canZoomIn
        case .zoomOut: viewing.canZoomOut
        case .actualSize: !viewing.isSize(1)
        case .zoomToFit: viewing.zoom != .fit
        case .nextPage: viewing.pages?.canGoForward == true
        case .previousPage: viewing.pages?.canGoBack == true
        }
    }

    func perform(on viewing: FileViewing) {
        guard isEnabled(on: viewing) else { return }
        switch self {
        case .zoomIn: viewing.zoomIn()
        case .zoomOut: viewing.zoomOut()
        case .actualSize: viewing.setScale(1)
        case .zoomToFit: viewing.fit()
        case .nextPage: viewing.goToNextPage()
        case .previousPage: viewing.goToPreviousPage()
        }
    }
}

/// The commands as View menu items for the file page in front, the pages' commands after a divider, and for a PDF the
/// background its pages sit on.
struct FileViewCommands: View {
    let viewing: FileViewing
    let shortcuts: ShortcutBindings
    @AppStorage(PDFBackground.key) private var background = PDFBackground.gray

    /// Gray is the default, so it is stored as no choice.
    private var storedBackground: Binding<PDFBackground> {
        Binding {
            background
        } set: { choice in
            if choice == .gray { UserDefaults.standard.removeObject(forKey: PDFBackground.key) } else { background = choice }
        }
    }

    var body: some View {
        let commands = FileViewCommand.offered(for: viewing.kind)
        ForEach(commands.filter { ![.nextPage, .previousPage].contains($0) }, id: \.self) { command in
            button(command)
        }
        if commands.contains(.nextPage) {
            Divider()
            button(.nextPage)
            button(.previousPage)
            Divider()
            Picker("PDF Background", selection: storedBackground) {
                ForEach(PDFBackground.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func button(_ command: FileViewCommand) -> some View {
        Button(command.title, systemImage: command.systemImage) { command.perform(on: viewing) }
            .shortcut(command.shortcutCommand, shortcuts)
            .disabled(!command.isEnabled(on: viewing))
    }
}
