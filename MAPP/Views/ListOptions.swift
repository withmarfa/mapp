import SwiftUI

/// Where the list's settings are kept, shared by every view that reads or sets them.
nonisolated enum ListKey {
    /// The density of every list (`Density`), until a saved view or a place chooses its own.
    static let density = "listDensity"
    static let all = [density]
}
