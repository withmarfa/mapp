import AppKit
import SwiftUI

/// A PDF's page in the corner: "2 of 4" between back and forward arrows, each dimmed at its end. Each is also a menu
/// command and a palette entry (`FileViewCommand`).
struct FilePagesControl: View {
    let viewing: FileViewing
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        if let pages = viewing.pages {
            CornerButtonGroup {
                Button(FileViewCommand.previousPage.title, systemImage: "chevron.up") { viewing.goToPreviousPage() }
                    .labelStyle(.iconOnly)
                    .disabled(!pages.canGoBack)
                    .help(Text(FileViewCommand.previousPage.title))
                    .accessibilityIdentifier("FilePreviousPage")
                Text(verbatim: pages.label)
                    .font(.system(size: 13 * InterfaceStyle.scale(for: textSize), weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("FilePageLabel")
                Button(FileViewCommand.nextPage.title, systemImage: "chevron.down") { viewing.goToNextPage() }
                    .labelStyle(.iconOnly)
                    .disabled(!pages.canGoForward)
                    .help(Text(FileViewCommand.nextPage.title))
                    .accessibilityIdentifier("FileNextPage")
            }
        }
    }
}

/// The size of an image or a PDF, read as a percentage. Clicking the percentage opens a small field to type a size in:
/// Return applies it, Escape or leaving the field cancels, and a size outside 10% to 400% takes the nearest end. The
/// chevron opens the menu: Fit, the usual sizes, Zoom In and Zoom Out.
struct FileZoomControl: View {
    let viewing: FileViewing
    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        CornerButtonGroup {
            if viewing.isEditingSize {
                TextField("Size", text: $text, prompt: Text(verbatim: FileZoom.rangeLabel))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13 * scale, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .frame(width: 64 * scale)
                    .focused($isFocused)
                    .onSubmit(apply)
                    .onExitCommand(perform: stopTyping)
                    .onChange(of: text) { isInvalid = false }
                    // Leaving the field with a click elsewhere cancels it, as Escape does.
                    .onChange(of: isFocused) { wasFocused, _ in if wasFocused { stopTyping() } }
                    .onAppear { isFocused = true }
                    .help(Text("Sizes run from \(FileZoom.label(FileZoom.range.lowerBound)) to \(FileZoom.label(FileZoom.range.upperBound))."))
                    .accessibilityLabel("Size")
                    .accessibilityIdentifier("FileZoomField")
            } else {
                Button { startTyping() } label: {
                    Text(verbatim: viewing.sizeLabel).monospacedDigit().padding(.horizontal, 6)
                }
                .help("Type a Size")
                .accessibilityLabel("Size")
                .accessibilityValue(viewing.sizeLabel)
                .accessibilityIdentifier("FileZoomSize")
            }
            Menu {
                FileZoomMenu(viewing: viewing)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zoom")
            .accessibilityLabel("Zoom")
            .accessibilityIdentifier("FileZoomMenu")
        }
    }

    private func startTyping() {
        text = viewing.scale.map { String(FileZoom.percent(of: $0)) } ?? ""
        isInvalid = false
        viewing.isEditingSize = true
    }

    private func stopTyping() {
        viewing.isEditingSize = false
        isInvalid = false
    }

    private func apply() {
        guard let scale = FileZoom.parse(text) else {
            // Not a size: the field stays so it can be corrected, and says so.
            isInvalid = true
            NSSound.beep()
            return
        }
        viewing.setScale(scale)
        stopTyping()
    }
}

/// Fit, the usual sizes with the chosen one ticked, then Zoom In and Zoom Out. The keys belong to the View menu's
/// commands, which are the same ones, so this menu binds none.
private struct FileZoomMenu: View {
    let viewing: FileViewing

    var body: some View {
        Toggle(isOn: Binding { viewing.zoom == .fit } set: { _ in viewing.fit() }) { Text("Fit") }
        Divider()
        ForEach(FileZoom.menuSizes, id: \.self) { size in
            Toggle(isOn: Binding { viewing.isSize(size) } set: { _ in viewing.setScale(size) }) { Text(verbatim: FileZoom.label(size)) }
        }
        Divider()
        ForEach([FileViewCommand.zoomIn, .zoomOut], id: \.self) { command in
            Button(command.title, systemImage: command.systemImage) { command.perform(on: viewing) }
                .disabled(!command.isEnabled(on: viewing))
        }
    }
}
