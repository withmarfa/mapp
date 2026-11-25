import Foundation

/// A place asked to open in a main window of its own. Only a view can open a window, and the new one takes the place as
/// it first shows the library (`MainView`).
@MainActor
enum PlaceWindows {
    private static var waiting: PlaceView?

    static func ask(_ place: PlaceView) { waiting = place }

    /// The place waiting, which only the first window to ask is given.
    static func take() -> PlaceView? {
        defer { waiting = nil }
        return waiting
    }
}
