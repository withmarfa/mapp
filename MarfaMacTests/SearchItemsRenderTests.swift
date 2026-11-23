import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// Draws Search Items offscreen, in light, to set beside the design's board. Each picture is attached to its test as a PNG
/// and, where `MARFA_MAC_RENDER_DIR` is set, saved there. Skipped by name where that is unset, as the `measure` suites are.
/// The result bundle holds the attachments (`xcresulttool export attachments`).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MARFA_MAC_RENDER_DIR"] != nil), .serialized, .hangLimit)
struct SearchItemsRenderTests {
    private static let size = CGSize(width: 760, height: 560)

    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary()
        func add(_ title: String, _ type: String, source: String? = nil, body: String = "") {
            var item = FakeItemLibrary.note(title, modified: .now.addingTimeInterval(-Double(library.items.count) * 3600))
            item.type = TypeID(type)
            item.source = source
            library.items.append(item)
            library.bodies[item.id] = body
        }
        add("Oak species for the worktops", "core.note", body: "Oak and ash for the Harbour Joinery worktops.")
        add("Order oak for the Harbour Joinery workshop", "core.task")
        add("Oak species and their grain", "core.note", body: "How oak grain differs.")
        add("Oak worktop quotation, Harbour Joinery", "core.note")
        for number in 1...36 { add("Oak seating fix \(number)", "core.task", source: "github") }
        library.sources = SourceDirectory(infos: [
            "github": SourceInfo(code: "github", name: "GitHub", mark: "simple-icons:github", hasChosenName: true)
        ])
        return library
    }

    /// The palette's own scroll view draws none of its rows in a host with no screen, so this draws the parts it is made
    /// of, in its own order and measures: the field, the filter row, the rows with the section's header, the left-out
    /// line, and the bar. What each says is what `library` answers to the same search the palette makes.
    private func render(filters: PaletteFilters, name: String) async throws {
        let library = library()
        let libraries = Libraries.standard()
        libraries.searchLeaveOuts.update(libraries.libraryKey) { $0.sources = ["github"] }
        let narrowing = SearchNarrowing(
            types: filters.types, excludesTypes: filters.negated.contains(.type), leaveOut: libraries.searchLeaveOut)
        let found = library.search("oak", narrowedBy: narrowing)
        let leftOut = library.searchLeftOut("oak", narrowedBy: narrowing)
        let line = SearchLeftOutLine.text(
            for: leftOut.items, isCapped: leftOut.isCapped, narrowing: narrowing, catalogue: library.catalogue, sources: library.sources)
        let now = library.now()
        let entries = found.items.map { item in
            PaletteEntry(
                id: item.id.rawValue, title: item.displayTitle, detail: library.placeLabel(of: item),
                snippet: library.body(of: item.id)?.text ?? library.placeLabel(of: item),
                date: DateDisplay.text(of: item.modified, place: .list, format: DateFormat.standard, now: now),
                icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true, action: {})
        }
        let state = PaletteFilterState()
        state.filters = filters
        let panel = VStack(spacing: 0) {
            HStack(spacing: PaletteMetrics.markGap) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: PaletteMetrics.markWidth)
                Text(verbatim: "oak").interfaceFont(.title3)
                Spacer()
                Text(entries.count == 1 ? "1 result" : "\(entries.count) results").foregroundStyle(.secondary)
            }
            .padding(.horizontal, PaletteMetrics.markInset)
            .padding(.top, 18)
            .padding(.bottom, 12)
            if !filters.isEmpty { PaletteFilterRow(state: state) }
            VStack(alignment: .leading, spacing: 0) {
                PaletteSectionHeader(title: String(localized: "Items"))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    PaletteRow(entry: entry, query: "oak", isHighlighted: index == 0, isSearch: true, onHover: {}, onRun: {})
                }
                if let line { PaletteLeftOutLine(text: line, show: {}) }
            }
            .padding(.horizontal, PaletteMetrics.listInset)
            .padding(.bottom, 56)
        }
        .frame(width: 680)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: FloatingPanelMetrics.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FloatingPanelMetrics.cornerRadius, style: .continuous).stroke(.primary.opacity(0.12)))
        .padding(40)
        .environment(\.library, library)
        .environment(libraries)
        .environment(\.colorScheme, .light)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: panel)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        Attachment.record(png, named: "\(name).png")
        if let path = ProcessInfo.processInfo.environment["MARFA_MAC_RENDER_DIR"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: folder.appending(path: "\(name).png"))
        }
    }

    @Test func searchItemsWithWhatIsLeftOutMatchingToo() async throws {
        try await render(filters: PaletteFilters(), name: "search-items-left-out-line")
    }

    @Test func searchItemsWithATypeFilter() async throws {
        try await render(filters: PaletteFilters(types: [TypeID("core.task")]), name: "search-items-type-filter")
    }
}
