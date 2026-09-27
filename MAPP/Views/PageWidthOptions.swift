import SwiftUI

/// Where the page's width is kept, shared by every view that reads or sets it.
enum PageKey {
    static let fullWidth = "fullWidthPages"
}

/// How wide a note's text runs: a comfortable measure for reading, or the window's whole width. Offered alike
/// by the View menu and Settings.
struct PageWidthOptions: View {
    @AppStorage(PageKey.fullWidth) private var fullWidth = false

    var body: some View {
        Picker("Page Width", systemImage: "arrow.left.and.right", selection: $fullWidth) {
            Text("Standard").tag(false)
            Text("Full Width").tag(true)
        }
    }
}
