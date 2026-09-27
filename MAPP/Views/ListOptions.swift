import SwiftUI

/// Where the list's settings are kept, shared by every view that reads or sets them.
enum ListKey {
    static let previewLines = "listPreviewLines"
    static let defaultPreviewLines = 2
    static let all = [previewLines]
}

/// How many lines of each note's text its row shows under the title, as Mail offers for its messages. Every row
/// reserves the lines whether its note fills them or not, so the rows stay one height.
struct ListPreviewOptions: View {
    @AppStorage(ListKey.previewLines) private var previewLines = ListKey.defaultPreviewLines

    var body: some View {
        Picker("List Preview", systemImage: "text.alignleft", selection: $previewLines) {
            Text("None").tag(0)
            Text("1 Line").tag(1)
            Text("2 Lines").tag(2)
        }
    }
}
