import SwiftUI

/// Make Text Bigger, Make Text Smaller and Actual Size. They act on the note text size while a note's page has the
/// keyboard and on the interface's Base Text Size elsewhere, so the commands read the same whichever they change.
struct TextZoom: Equatable {
    enum Step { case bigger, smaller, actual }

    let key: String
    let sizes: [Int]
    let defaultSize: Int

    static let note = TextZoom(key: PageKey.textSize, sizes: PageStyle.textSizes, defaultSize: PageStyle().textSize)
    static let interface = TextZoom(key: InterfaceKey.textSize, sizes: InterfaceStyle.textSizes, defaultSize: InterfaceStyle.defaultTextSize)

    static func acting(pageFocused: Bool) -> TextZoom { pageFocused ? .note : .interface }

    /// The size after the step, or nil where it changes nothing. A stored size that is not one of the steps moves to
    /// the nearest step in the direction asked.
    func size(after step: Step, from current: Int) -> Int? {
        let next: Int? = switch step {
        case .bigger: sizes.first { $0 > current }
        case .smaller: sizes.last { $0 < current }
        case .actual: defaultSize
        }
        return next == current ? nil : next
    }

    func apply(_ step: Step, in defaults: UserDefaults = .standard) {
        let current = defaults.object(forKey: key) as? Int ?? defaultSize
        if let size = size(after: step, from: current) { defaults.set(size, forKey: key) }
    }
}

/// The three commands as menu items, for the View menu, which keeps both sizes in view so the items follow them.
struct TextZoomCommands: View {
    @AppStorage(PageKey.textSize) private var noteSize = PageStyle().textSize
    @AppStorage(InterfaceKey.textSize) private var interfaceSize = InterfaceStyle.defaultTextSize
    let pageFocused: Bool

    var body: some View {
        let zoom = TextZoom.acting(pageFocused: pageFocused)
        let current = pageFocused ? noteSize : interfaceSize
        // ⌘= is the same key as ⌘+ without Shift, and AppKit matches a "+" shortcut with it.
        Button("Make Text Bigger", systemImage: "textformat.size.larger") { zoom.apply(.bigger) }
            .keyboardShortcut("+")
            .disabled(zoom.size(after: .bigger, from: current) == nil)
        Button("Make Text Smaller", systemImage: "textformat.size.smaller") { zoom.apply(.smaller) }
            .keyboardShortcut("-")
            .disabled(zoom.size(after: .smaller, from: current) == nil)
        Button("Actual Size", systemImage: "textformat.size") { zoom.apply(.actual) }
            .keyboardShortcut("0")
    }
}
