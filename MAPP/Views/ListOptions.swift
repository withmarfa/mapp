import SwiftUI

/// Where the list's settings are kept, shared by every view that reads or sets them.
nonisolated enum ListKey {
    static let previewLines = "listPreviewLines"
    static let defaultPreviewLines = 2
    static let showsPictures = "listShowsPictures"
    /// The row style of every list (`ListRowStyle.forEveryList`).
    static let rowStyle = "listRowStyle"
    static let showsTypeWhenMixed = "listShowsTypeWhenMixed"
    static let all = [previewLines, showsPictures, rowStyle, showsTypeWhenMixed]
}

/// What every list's rows show, as Mail offers it for its messages: how many lines of each item's text sit under the
/// title (a row with less text takes less room), whether pictures show, and whether a list that mixes types names them.
struct ListPreviewOptions: View {
    @AppStorage(ListKey.previewLines) private var previewLines = ListKey.defaultPreviewLines
    @AppStorage(ListKey.showsPictures) private var showsPictures = true
    @AppStorage(ListKey.showsTypeWhenMixed) private var showsType = true

    var body: some View {
        Picker("Preview", selection: $previewLines) {
            Text("None").tag(0)
            Text("1 Line").tag(1)
            Text("2 Lines").tag(2)
        }
        Toggle("Show Pictures", isOn: $showsPictures)
        Toggle("Show the Type When a List Mixes Types", isOn: $showsType)
    }
}
