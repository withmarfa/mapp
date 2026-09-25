import SwiftUI

struct NoteList: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let item: SidebarItem
    let searchText: String
    let sort: NoteSort
    @Binding var selection: Set<Note.ID>
    @State private var daysSeen = 0

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var notes: [Note] {
        isSearching ? library.notes(matching: searchText) : library.notes(in: item)
    }

    var body: some View {
        // Reading the counter ties the dates and sections to the day changing, so "Today" moves at midnight.
        let _ = daysSeen
        let notes = notes
        let now = library.now()
        let sections = NoteGroup.sections(
            of: notes,
            sort: sort,
            pinnedFirst: !isSearching && item != .pinned && item != .recentlyDeleted,
            now: now
        )
        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteRow(
                            note: note,
                            dateLabel: NoteDate.listLabel(for: sort.date(of: note), now: now),
                            folderName: folderName(for: note)
                        )
                        .draggable(containerItemID: note.id)
                        .listRowSeparator(note.id == section.notes.last?.id ? .hidden : .automatic, edges: .bottom)
                    }
                } header: {
                    if let group = section.group {
                        Text(group.title())
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("NoteList")
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                daysSeen += 1
            }
        }
        .dragContainer(for: NoteReference.self) { ids in
            ids.compactMap { library.note($0) }.map { NoteReference(id: $0.id, markdown: $0.body) }
        }
        .dragContainerSelection(Array(selection))
        .contextMenu(forSelectionType: Note.ID.self) { ids in
            NoteActions(ids: ids)
        }
        .overlay {
            if notes.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                }
            }
        }
        .navigationTitle(isSearching ? String(localized: "Search") : library.name(of: item))
        .navigationSubtitle(isSearching
            ? Text("^[\(notes.count) result](inflect: true)")
            : Text("^[\(notes.count) note](inflect: true)"))
    }

    /// The folder is shown only where the list mixes notes from several places.
    private func folderName(for note: Note) -> String? {
        let mixed = isSearching || item == .allNotes || item == .pinned || item == .recentlyDeleted
        guard mixed else { return nil }
        return note.folderID.flatMap { library.folder($0)?.name } ?? String(localized: "Inbox")
    }
}

/// A note in the list, laid out as Mail lays out a message: title and date, then two lines of preview.
struct NoteRow: View {
    let note: Note
    let dateLabel: String
    let folderName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(note.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            if let folderName {
                Label(folderName, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
