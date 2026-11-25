import SwiftUI

/// The switch between a type's own items and its items with its kinds' (`Browser.listing`). View Options (and so the
/// View menu) and the palette offer it, for a type that has kinds. A type lists its kinds until the person turns it
/// off.
enum IncludeKinds {
    static let symbol = "square.3.layers.3d"
}

/// The option in View Options, for a type that has kinds. It keeps a checkmark, being the one on/off choice in the menu.
struct IncludeKindsOption: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        if browser.kindsType(in: library) != nil {
            Toggle("Include Kinds", isOn: Binding { browser.listing.includesKinds } set: { browser.setIncludesKinds($0) })
                .help(browser.listing.includesKinds ? Text("Show only this type’s own items") : Text("Include the items of its kinds in this list"))
                .accessibilityIdentifier("IncludeKinds")
        }
    }
}
