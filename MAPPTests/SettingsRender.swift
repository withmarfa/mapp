import AppKit
import SwiftUI

/// Draws a view into a PNG without the screen: an `NSHostingView` in a window that is never shown, drawn with
/// `cacheDisplay(in:to:)`, in the light appearance. It draws a page and its sidebar but cannot draw the window's own
/// toolbar (the system's Back and Forward pill and the title), since there is no real window. The folder comes from the environment variable
/// `MAPP_SETTINGS_RENDERS`, and a suite that renders is skipped by name while it is unset, as the `measure` suites are.
@MainActor
enum SettingsRender {
    nonisolated static let folderVariable = "MAPP_SETTINGS_RENDERS"
    nonisolated static var isRequested: Bool { ProcessInfo.processInfo.environment[folderVariable] != nil }

    static var folder: URL? {
        ProcessInfo.processInfo.environment[folderVariable].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Writes `view` at `size` to `<folder>/<name>.png` and gives the file back.
    @discardableResult
    static func png(_ view: some View, size: CGSize, named name: String, settle: Duration = .milliseconds(400)) async throws -> URL {
        let folder = try #require(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Lets a page that reads the server or the disk finish its first read and lay out again; there is nothing to
        // wait on, since the window is never shown.
        try await Task.sleep(for: settle)
        host.layoutSubtreeIfNeeded()
        let representation = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        let file = folder.appending(path: name + ".png")
        try data.write(to: file)
        window.contentView = nil
        return file
    }
}

import Testing
