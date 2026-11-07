import SwiftUI

/// The versions of an item as a thread, newest first, in blocks. Each is a dot on a thin line, the time it was saved
/// and what it changed; the newest is the item as it is now.
struct VersionThreadColumn: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.undoManager) private var undoManager
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let mode: VersionHistoryMode
    let list: VersionList?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Version History").interfaceFont(.title3.weight(.semibold))
            if let count = countText {
                Text(count).interfaceFont(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// How many versions are listed. While the server's history is still being read, or was stopped short, the count
    /// is of those read, so it does not claim to be all of them.
    private var countText: String? {
        guard mode.thread.phase == .loaded, let list else { return nil }
        let count = list.entries.count
        return list.isComplete
            ? String(localized: "^[\(count) version](inflect: true)")
            : String(localized: "\(count) or more versions")
    }

    @ViewBuilder private var content: some View {
        switch mode.thread.phase {
        case .idle, .loading:
            ProgressView("Loading versions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Color.clear
        case .loaded:
            if let list { thread(list) }
        }
    }

    private func thread(_ list: VersionList) -> some View {
        let blocks = list.blocks(now: now, calendar: .autoupdatingCurrent)
        let selection = Binding<String?> {
            mode.thread.selection
        } set: { id in
            // Choosing nothing, as a modifier-click on the chosen row would, keeps the version shown.
            if let id { mode.thread.selection = id }
        }
        return List(selection: selection) {
            ForEach(blocks) { block in
                Text(VersionBlocks.title(of: block.kind, now: now, calendar: .autoupdatingCurrent))
                    .interfaceFont(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, block.id == blocks.first?.id ? 0 : 10)
                    .accessibilityAddTraits(.isHeader)
                    .listRowSeparator(.hidden)
                ForEach(block.elements) { entry in
                    row(entry, in: block, list: list)
                    if entry.isCurrent, !list.isComplete { gap }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: list.entries.map(\.id)) { mode.thread.selection }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                Button("Restore Version", systemImage: "arrow.uturn.backward") {
                    mode.thread.selection = id
                    if let details { details.restoreFromHistory(in: library, undoManager: undoManager) }
                }
                .disabled(mode.isRestoring || mode.restoreCheck(of: id, in: library)?.isReady != true)
            }
        }
        .accessibilityIdentifier("VersionHistoryThread")
    }

    private func row(_ entry: VersionEntry, in block: VersionBlock<VersionEntry>, list: VersionList) -> some View {
        let isFirst = block.elements.first?.id == entry.id
        // The line runs on through the stretch not read yet, which sits just under the newest version.
        let isLast = block.elements.last?.id == entry.id && !(entry.isCurrent && !list.isComplete)
        return VersionThreadRow(
            entry: entry,
            when: entry.written.map { VersionBlocks.when($0, format: dateFormat, now: now, calendar: .autoupdatingCurrent) }
                ?? String(localized: "Version \(entry.version)"),
            summary: list.summary(of: entry, in: library.catalogue),
            isSelected: mode.thread.selection == entry.id, isFirst: isFirst, isLast: isLast)
            .tag(entry.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .accessibilityIdentifier("VersionHistoryRow.\(entry.version)")
    }

    /// Where the versions not read yet would be: still being read, stopped by an error, or left for Load More.
    private var gap: some View {
        VStack(alignment: .leading, spacing: 4) {
            if mode.thread.isLoadingMore {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading earlier versions…").foregroundStyle(.secondary)
                }
            } else {
                if let failure = mode.thread.moreFailure {
                    Text(failure.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button(mode.thread.moreFailure == nil ? "Load More" : "Try Again") { mode.thread.loadMore() }
                    .accessibilityIdentifier("VersionHistoryLoadMore")
            }
        }
        .interfaceFont(.callout)
        .padding(.leading, 22)
        .padding(.vertical, 6)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
    }
}

/// One version in the thread.
private struct VersionThreadRow: View {
    let entry: VersionEntry
    let when: String
    let summary: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    /// How far down a row its dot sits: its padding and half of the time's line.
    @ScaledMetric private var dotY: CGFloat = 15

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(when).interfaceFont(.body)
                Text(summary).interfaceFont(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if entry.isCurrent {
                Text("Current").interfaceFont(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 22)
        .padding(.vertical, 7)
        .background(alignment: .leading) { rail }
        .accessibilityElement(children: .combine)
    }

    private var rail: some View {
        GeometryReader { geometry in
            let x: CGFloat = 5
            Path { path in
                path.move(to: CGPoint(x: x, y: isFirst ? dotY : 0))
                path.addLine(to: CGPoint(x: x, y: isLast ? dotY : geometry.size.height))
            }
            .stroke(.separator, lineWidth: 1)
            Circle()
                .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 9, height: 9)
                .position(x: x, y: dotY)
        }
        .frame(width: 10)
    }
}
