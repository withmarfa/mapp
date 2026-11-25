import AppKit
import SwiftUI

/// The versions of an item as a thread, newest first, in blocks. Each has the mark of the kind of sign-in that wrote it,
/// the time it was saved, what it changed and who wrote it; the newest is the item as it is now.
struct VersionThreadColumn: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.undoManager) private var undoManager
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let mode: VersionHistoryMode
    let list: VersionList?
    let now: Date

    /// How far the title, the marks and the writers' names are from the column's edge: 20, as the board has them. A
    /// `List(.inset)` already keeps its rows 16 from the edge (measured), so each row's own inset is the rest.
    private static let edge: CGFloat = 20
    private static let rowInsets = EdgeInsets(top: 0, leading: edge - 16, bottom: 0, trailing: edge - 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Version History").interfaceFont(.title2.weight(.bold))
            if let count = countText {
                Text(count).interfaceFont(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Self.edge)
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
            ? AttributedString(localized: "^[\(count) version](inflect: true)").text
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
                    .foregroundStyle(VersionLooks.faint)
                    .padding(.top, block.id == blocks.first?.id ? 0 : 10)
                    .accessibilityAddTraits(.isHeader)
                    .listRowSeparator(.hidden)
                    .listRowInsets(Self.rowInsets)
                ForEach(block.elements) { entry in
                    row(entry, list: list)
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
                Button("Copy Text") { copyText(of: id, in: list) }
                    .disabled(list.entry(id)?.content.text == nil)
            }
        }
        .accessibilityIdentifier("VersionHistoryThread")
    }

    /// Puts the version's text on the clipboard, exactly as the version holds it.
    private func copyText(of id: String, in list: VersionList) {
        guard let text = list.entry(id)?.content.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func row(_ entry: VersionEntry, list: VersionList) -> some View {
        VersionThreadRow(
            entry: entry,
            when: entry.written.map { VersionBlocks.when($0, format: dateFormat, now: now, calendar: .autoupdatingCurrent) }
                ?? String(localized: "Version \(entry.version)"),
            summary: list.summary(of: entry, in: library.catalogue))
            .tag(entry.id)
            .listRowSeparator(.hidden)
            .listRowInsets(Self.rowInsets)
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
        .padding(.leading, 25)
        .padding(.vertical, 6)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .listRowInsets(Self.rowInsets)
    }
}

/// One version in the thread: the mark of who wrote it, the time with Current beside the newest, what changed under it
/// and the writer's name at the end.
private struct VersionThreadRow: View {
    let entry: VersionEntry
    let when: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: entry.isCurrent ? "clock" : PanelHistory.symbol(of: entry.writer))
                .frame(width: 16, height: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text(when).interfaceFont(.body.weight(.medium)).lineLimit(1)
                    if entry.isCurrent {
                        Text("Current")
                            .interfaceFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 17)
                            .background(VersionLooks.currentWash, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text(summary).interfaceFont(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let writer = entry.writer {
                Text(verbatim: writer.displayName).interfaceFont(.subheadline).foregroundStyle(VersionLooks.faint).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
