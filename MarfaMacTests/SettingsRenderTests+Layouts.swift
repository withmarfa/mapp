import SwiftUI
import Testing
@testable import MarfaMac

/// Draws the Layouts pages from the sample library, for a pull request's pictures. Skipped unless `MARFA_MAC_SETTINGS_RENDERS`
/// names a folder.
extension SettingsRenderTests {
    /// Libraries holding the sample library, as the running app opens it with `-MarfaMacSampleLibrary`.
    private func sampled(_ configure: (Libraries) -> Void = { _ in }) async throws -> (Libraries, HostBench) {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "SettingsRenderTests-\(UUID().uuidString)"))
        let libraries = Libraries(
            host: bench.host(opener: { connection, _, _ in SampleLibrary.open(connection) }), defaults: defaults,
            handOverPages: { $0(true) })
        try await libraries.host.connect(address: SampleLibrary.connection.address.absoluteString, key: "k")
        #expect(await eventually { libraries.current?.isLoaded == true })
        configure(libraries)
        return (libraries, bench)
    }

    private func layouts(_ libraries: Libraries, subpage: SettingsSubpage? = nil) -> some View {
        LayoutsPage()
            .environment(libraries)
            .environment(libraries.host)
            .environment(\.library, libraries.current)
            .environment(\.settingsSubpage, subpage)
    }

    @Test func layoutsList() async throws {
        let (libraries, bench) = try await sampled()
        _ = bench
        try await SettingsRender.png(
            RenderedWindow(selection: .layouts, detail: layouts(libraries)), size: CGSize(width: Self.size.width, height: 1_100),
            named: "Layouts")
    }

    @Test func layoutsTypePageWithItemsToPreview() async throws {
        let (libraries, bench) = try await sampled()
        _ = bench
        let note = TypeID("core.note")
        let label = libraries.current?.catalogue.label(for: note) ?? "Note"
        try await SettingsRender.png(
            RenderedWindow(selection: .layouts, detail: layouts(libraries, subpage: LayoutsSubpage.subpage(for: note, label: label))),
            size: CGSize(width: Self.size.width, height: 1_300), named: "Layouts, a type with a preview")
    }

    @Test func layoutsTypePage() async throws {
        let (libraries, bench) = try await sampled { libraries in
            guard let library = libraries.current else { return }
            libraries.typeLooks.change(TypeID("core.task"), in: libraries.libraryKey, catalogue: library.catalogue) {
                $0.secondary = [.opening]
            }
        }
        _ = bench
        let task = TypeID("core.task")
        let label = libraries.current?.catalogue.label(for: task) ?? "Task"
        try await SettingsRender.png(
            RenderedWindow(selection: .layouts, detail: layouts(libraries, subpage: LayoutsSubpage.subpage(for: task, label: label))),
            size: CGSize(width: Self.size.width, height: 1_300), named: "Layouts, a type")
    }
}
