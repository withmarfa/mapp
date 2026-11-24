import AppKit
import Marfa
import SwiftUI
import Testing
@testable import MarfaMac

/// Draws the list's rows and the right sidebar's attendee editor offscreen, in both appearances, for a person to look
/// at. The folder comes from `MARFA_MAC_LIST_RENDERS`, and the suite is skipped while it is unset, so CI never runs it.
@MainActor
enum ListRender {
    nonisolated static let folderVariable = "MARFA_MAC_LIST_RENDERS"
    nonisolated static var isRequested: Bool { ProcessInfo.processInfo.environment[folderVariable] != nil }

    static func png(_ view: some View, size: CGSize, named name: String, dark: Bool) async throws {
        let folder = try #require(ProcessInfo.processInfo.environment[folderVariable].map { URL(filePath: $0, directoryHint: .isDirectory) })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // The window is never shown, so there is nothing to wait on but the first layout.
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let representation = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try data.write(to: folder.appending(path: "\(name)-\(dark ? "dark" : "light").png"))
        window.contentView = nil
    }
}

@Suite(.enabled(if: ListRender.isRequested), .serialized, .hangLimit)
@MainActor struct ListRowRenders {
    private static let attendees = ListShape(members: [
        .init(key: "name", label: "Name", kind: .text(nil)),
        .init(key: "email", label: "Email", kind: .text(.email)),
        .init(key: "response", label: "Response", kind: .choice(["needs_action", "accepted", "declined", "tentative"])),
    ])

    private static let entries: PropertyValue = .array([
        .object(["name": .string("Ada Lovelace-Babbage"), "email": .string("ada.lovelace.babbage@example.com"), "response": .string("needs_action")]),
        .object(["name": .string("Grace Hopper"), "email": .string("grace@example.org"), "response": .string("accepted")]),
    ])

    @Test(arguments: [false, true]) func theAttendeeEditorAtTheSidebarsDefaultWidth(dark: Bool) async throws {
        let editor = InspectorBox {
            ItemPropertyRow(
                definition: .init(key: "attendees", label: "Attendees", kind: .list(Self.attendees), declaredBy: TypeID("core.event")),
                value: Self.entries, isEditable: true, onChange: { _ in true })
        }
        .padding(12)
        try await ListRender.png(editor, size: CGSize(width: 310, height: 420), named: "attendees", dark: dark)
    }

    @Test(arguments: [false, true]) func aListOfNotesWhoseTextStartsWithABulletListAndATable(dark: Bool) async throws {
        let notes = SampleLibrary.items(now: .now, tasksAndEvents: false).filter { $0.type == "core.note" }.prefix(6)
        let rows = notes.map { item -> RowContent in
            let display = SampleLibrary.display(ItemDisplayInput(type: item.type, properties: item.properties))
            return RowContent(
                title: display.name ?? "Untitled", date: "Today", secondary: display.preview,
                typeIcon: "lucide:file-text", typeLabel: "Note", mixesTypes: true)
        }
        let list = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, content in
                ItemRow(content: content).padding(.horizontal, 12)
                Divider()
            }
        }
        try await ListRender.png(list, size: CGSize(width: 330, height: 520), named: "rows", dark: dark)
    }
}
