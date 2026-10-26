import SwiftUI

/// Lists an item's earlier versions as the server kept them, shows the one chosen beside the item as it is now, and
/// restores its text and title as a new edit, so what it replaces stays in the history.
struct VersionHistorySheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: VersionHistoryRequest
    @State private var model: ItemHistoryModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version History").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            if let model {
                VersionHistoryBody(model: model, request: request, close: { dismiss() })
            } else {
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 780, height: 500)
        .task {
            guard model == nil else { return }
            let model = ItemHistoryModel(id: request.item, source: library.history)
            self.model = model
            model.load()
        }
        .onDisappear { model?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("VersionHistorySheet")
    }

    private var subtitle: String {
        if let item = library.item(request.item) {
            String(localized: "Earlier versions of “\(item.title)”.")
        } else {
            String(localized: "This item is no longer in the library.")
        }
    }
}

private struct VersionHistoryBody: View {
    @CurrentLibrary private var library
    @Bindable var model: ItemHistoryModel
    let request: VersionHistoryRequest
    let close: () -> Void
    /// Whether a restore is waiting for the open pages to hand over their last edit.
    @State private var isRestoring = false

    var body: some View {
        // Read on each change of the library, so an item changed or deleted elsewhere is judged as it stands now.
        let check = model.selected.map { library.restoreCheck(of: $0, for: request.item) }
        VStack(alignment: .leading, spacing: 12) {
            content
            if let reason = reason(for: check) {
                Text(reason)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("VersionHistoryReason")
            }
            HStack {
                Spacer()
                Button("Done", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") { restore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRestore(check))
                    .accessibilityIdentifier("VersionHistoryRestore")
            }
        }
    }

    private var isDeleted: Bool { library.item(request.item)?.state == .trashed }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading versions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let failure):
            ContentUnavailableView {
                Label("No Versions to Show", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(isDeleted ? String(localized: "This item is in Recently Deleted, where its history can’t be read. Recover it to see its versions.") : failure.message)
            } actions: {
                if failure != .unsupported { Button("Try Again") { model.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            HStack(alignment: .top, spacing: 12) {
                list.frame(width: 230)
                preview
            }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 2) {
                    Text(when(snapshot))
                    if let who = who(snapshot) {
                        Text(who).interfaceFont(.callout).foregroundStyle(.secondary)
                    }
                }
                .tag(snapshot.id)
                .accessibilityIdentifier("VersionHistoryRow.\(snapshot.version)")
            }
            if model.hasMore || model.moreFailure != nil {
                loadMore
            }
        }
        .overlay {
            if model.snapshots.isEmpty && !model.hasMore {
                ContentUnavailableView("No Earlier Versions", systemImage: "clock.arrow.circlepath",
                    description: Text("This item hasn’t been changed since it was made, or the server has kept no earlier version of it."))
            }
        }
    }

    private var loadMore: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let failure = model.moreFailure {
                Text(failure.message).interfaceFont(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Load More") { model.loadMore() }
                    .disabled(model.isLoadingMore)
                if model.isLoadingMore { ProgressView().controlSize(.small) }
            }
        }
        .selectionDisabled()
    }

    @ViewBuilder private var preview: some View {
        if let snapshot = model.selected {
            let catalogue = library.catalogue
            let current = library.body(of: request.item)?.text
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    pane(String(localized: "This Version"), title: snapshot.title(in: catalogue), text: snapshot.text(in: catalogue))
                    pane(String(localized: "Now"), title: library.item(request.item)?.title, text: current)
                }
                fields(of: snapshot, in: catalogue)
            }
        } else {
            ContentUnavailableView("Choose a Version", systemImage: "text.alignleft",
                description: Text("Pick one on the left to read it beside the item as it is now."))
        }
    }

    private func pane(_ heading: String, title: String?, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).interfaceFont(.headline)
            if let title, !title.isEmpty { Text(title).interfaceFont(.callout.bold()) }
            ScrollView {
                if let text {
                    let excerpt = TextExcerpt(text)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: excerpt.text).textSelection(.enabled)
                        if excerpt.omitted > 0 {
                            Text("\(excerpt.omitted.formatted()) more characters aren’t shown.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No text").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(.background.secondary, in: .rect(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func fields(of snapshot: ItemSnapshot, in catalogue: Catalogue) -> some View {
        let fields = snapshot.fields(in: catalogue)
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Other Fields in This Version").interfaceFont(.headline)
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: field.label).foregroundStyle(.secondary)
                        Text(verbatim: field.value).textSelection(.enabled).lineLimit(2)
                    }
                    .interfaceFont(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func when(_ snapshot: ItemSnapshot) -> String {
        guard let written = snapshot.written else { return String(localized: "Version \(snapshot.version)") }
        return written.formatted(date: .abbreviated, time: .shortened)
    }

    private func who(_ snapshot: ItemSnapshot) -> String? {
        guard let writer = snapshot.writer else { return nil }
        guard writer.name.isEmpty else { return writer.name }
        return switch writer.kind {
        case .browser: String(localized: "Browser")
        case .app: String(localized: "App")
        case .key: String(localized: "Key")
        case .local: String(localized: "This device")
        }
    }

    /// Why Restore is dimmed, in words, once a version is chosen.
    private func reason(for check: RestoreCheck?) -> String? {
        switch check {
        case nil, .ready?: nil
        case .unchanged?: String(localized: "The item already has this version’s text and title.")
        case .unavailable(let reason)?: reason
        }
    }

    private func canRestore(_ check: RestoreCheck?) -> Bool {
        if case .ready? = check { return !isRestoring }
        return false
    }

    private func restore() {
        guard let snapshot = model.selected else { return }
        isRestoring = true
        // A restore refused leaves the sheet open, with the notice the library tells.
        library.restoreVersionAfterSaving(snapshot, of: request.item, undoManager: request.undoManager) { restored in
            isRestoring = false
            if restored { close() }
        }
    }
}

/// Opens the Version History sheet for one item, in the window whose presentation it is given. It stays available
/// offline and for a deleted item, since the sheet says plainly what it can't show.
struct VersionHistoryButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        Button("Version History…", systemImage: "clock.arrow.circlepath") {
            if let id = ids.first { details?.history = VersionHistoryRequest(item: id, undoManager: undoManager) }
        }
        .disabled(details == nil || ids.count != 1 || ids.first.flatMap { library.item($0) } == nil)
    }
}

/// The item the Version History sheet is open for, with the undo manager of the window it was asked for in, since
/// the sheet has its own.
struct VersionHistoryRequest: Identifiable {
    let id = UUID()
    let item: ItemID
    let undoManager: UndoManager?
}

extension ItemLibrary {
    /// Restores the version once every open page has handed over what was just typed, so the restore is based on the
    /// text the person sees. `done` says whether it was sent.
    func restoreVersionAfterSaving(
        _ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?, then done: @escaping (Bool) -> Void
    ) {
        EditorController.flushAll(leaving: false) { [self] kept in
            guard kept else {
                notices.tell(String(localized: "Can’t Restore Version"), String(localized: "Finish editing the current note, then try again."))
                return done(false)
            }
            done(restoreVersion(snapshot, of: id, undoManager: undoManager))
        }
    }
}
