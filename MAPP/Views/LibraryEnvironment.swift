import SwiftUI

extension EnvironmentValues {
    /// The library the window shows; nil before a library is open.
    @Entry var library: (any ItemLibrary)?
}

/// The window's library, for a view that is only ever shown with one, as a view reading an observable object
/// from the environment would require it.
@propertyWrapper
struct CurrentLibrary: DynamicProperty {
    @Environment(\.library) private var library

    var wrappedValue: any ItemLibrary {
        guard let library else { preconditionFailure("No library in the environment") }
        return library
    }
}
