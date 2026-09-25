import SwiftUI

struct NoteList: View {
    @Environment(NoteLibrary.self) private var library
    @Bindable var browser: Browser
    let sort: NoteSort
    @State private var daysSeen = 0

    var body: some View {
        // Reading the counter ties the dates and sections to the day changing, so "Today" moves at midnight.
        let _ = daysSeen
        let now = library.now()
        let sections = browser.sections(in: library, sort: sort, now: now)
        let ids = sections.flatMap { $0.notes.map(\.id) }
        List(selection: $browser.selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteRow(
                            note: note,
                            dateLabel: NoteDate.listLabel(for: sort.date(of: note), now: now),
                            folderName: browser.showsFolders ? folderName(for: note) : nil
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
        .dragContainerSelection(Array(browser.selection))
        .onChange(of: ids) { old, new in
            browser.selection = Browser.selection(browser.selection, keptFrom: old, in: new)
        }
        .contextMenu(forSelectionType: Note.ID.self) { ids in
            NoteActions(ids: ids)
        }
        .overlay {
            if ids.isEmpty {
                if browser.isSearching {
                    ContentUnavailableView.search(text: browser.searchText)
                } else {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                }
            }
        }
        .navigationTitle(browser.isSearching ? String(localized: "Search") : library.name(of: browser.item))
        .navigationSubtitle(browser.isSearching
            ? Text("^[\(ids.count) result](inflect: true)")
            : Text("^[\(ids.count) note](inflect: true)"))
    }

    private func folderName(for note: Note) -> String {
        note.folderID.flatMap { library.folder($0)?.name } ?? String(localized: "Inbox")
    }
}

/// Laid out as Mail lays out a message, so the date lines up at the trailing edge and two lines of preview
/// keep every row the same height.
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
