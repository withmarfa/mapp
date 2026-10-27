import SwiftUI

/// The switch between a type's own items and its items with its subtypes' (`Browser.placeItems`), as Obsidian's stack
/// button does for a folder. The list's toolbar, the View menu and the palette all offer it, for a type that has
/// subtypes holding items.
enum IncludeSubtypes {
    static let symbol = "square.3.layers.3d"
}

extension Browser {
    /// Includes or leaves out the subtypes' items in the open type's list, and remembers the choice for that type.
    func setStacksSubtypes(_ isOn: Bool, in library: any ItemLibrary) {
        guard let type = stackableType(in: library) else { return }
        if isOn { stackedTypes.insert(type) } else { stackedTypes.remove(type) }
        IncludedSubtypes.update { $0.set(type, included: isOn) }
    }

    /// The open type's switch, for a control.
    func stacksSubtypesBinding(in library: any ItemLibrary) -> Binding<Bool> {
        Binding {
            self.stacksSubtypes(in: library)
        } set: {
            self.setStacksSubtypes($0, in: library)
        }
    }
}

/// The list toolbar's button.
struct IncludeSubtypesButton: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        let isOn = browser.stacksSubtypes(in: library)
        Toggle(isOn: browser.stacksSubtypesBinding(in: library)) {
            Label("Include Subtypes", systemImage: IncludeSubtypes.symbol)
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(isOn ? Text("Show only this type’s own items") : Text("Include the items of its subtypes in this list"))
        .accessibilityIdentifier("IncludeSubtypesToolbar")
    }
}

/// The View menu's command.
struct IncludeSubtypesCommand: View {
    let browser: Browser?
    let library: (any ItemLibrary)?

    var body: some View {
        if let browser, let library, browser.stackableType(in: library) != nil {
            Toggle("Include Subtypes", systemImage: IncludeSubtypes.symbol, isOn: browser.stacksSubtypesBinding(in: library))
        } else {
            Toggle("Include Subtypes", systemImage: IncludeSubtypes.symbol, isOn: .constant(false)).disabled(true)
        }
    }
}
