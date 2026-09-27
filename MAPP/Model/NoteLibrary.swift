import Foundation
import Observation

/// Every note and folder, held in memory for the views and kept in a store. Each change a person can make is
/// made here at once, handed to the store to make on disk, and undoable through the undo manager it is given.
@Observable
final class NoteLibrary {
    private(set) var notes: [Note]
    private(set) var folders: [Folder]
    /// Whether the store has been read, so a window restores what it showed only once there is something to find.
    private(set) var isLoaded: Bool
    /// Notes a person has asked to erase for good, until they confirm or cancel, since that cannot be undone.
    var notesToPurge: Set<Note.ID> = []
    /// Something the store could not do, to tell the person: what failed and why.
    var failure: (title: String, message: String)?
    let now: () -> Date

    @ObservationIgnored let store: NoteStore?
    @ObservationIgnored private let defaults: UserDefaults?
    /// How many changes have been handed to the store, so a reading of the folder can tell whether it saw them all.
    @ObservationIgnored private var queued = 0
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    /// Notes whose last change could not be made, which a reading of the folder leaves as they are here, so what
    /// was typed stays until it can be saved.
    @ObservationIgnored private var unsaved: Set<String> = []
    /// When each note was first found missing from the folder. Some apps save by taking a file away and writing
    /// it again, so a note goes only once it has stayed away a moment.
    @ObservationIgnored private var missingSince: [Note.ID: Date] = [:]
    @ObservationIgnored var missingGrace: TimeInterval = 2
    /// Notes changed on a page since it was last left, whose names may need to follow their first lines.
    @ObservationIgnored private var edited: Set<Note.ID> = []
    /// A new note still being typed on its first line is written once the typing pauses this long, so a
    /// one-line note is on disk before the app could be stopped.
    @ObservationIgnored var draftDelay: Duration = .seconds(2)
    @ObservationIgnored private var draftSaves: [Note.ID: Task<Void, Never>] = [:]

    private static var unreadable: (title: String, message: String) {
        (String(localized: "Can’t Read the Notes Folder"), String(localized: "It may have been moved or deleted. Choose it again in Settings."))
    }

    /// How long a note stays in Recently Deleted.
    static let trashDays = 30
    private static let folderOrderKey = "folderOrder"

    /// A library of the notes given, loaded already; with a store, each change is also made there.
    init(
        notes: [Note] = [],
        folders: [Folder] = [],
        store: NoteStore? = nil,
        defaults: UserDefaults? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.notes = notes
        self.folders = folders
        self.store = store
        self.defaults = defaults
        self.now = now
        isLoaded = true
        store?.relocated = { [weak self] from, to in self?.relocate(from, to) }
        store?.failed = { [weak self] path, message in
            let name = (path as NSString).lastPathComponent
            self?.failure = (String(localized: "Couldn’t Save “\(name)”"), message)
            self?.unsaved.insert(path)
            // What the folder holds is read again, so a change that did not happen, a folder not renamed say,
            // is not taken to have.
            self?.refresh()
        }
    }

    /// A library that reads its notes from the store, which `load()` does.
    convenience init(loadingFrom store: NoteStore, defaults: UserDefaults?, now: @escaping () -> Date = Date.init) {
        self.init(notes: [], folders: [], store: store, defaults: defaults, now: now)
        isLoaded = false
    }

    // MARK: Loading

    /// Reads the store, away from the main thread, and erases what has been in the trash too long.
    func load() async {
        guard let store else { return }
        let expiry = Calendar.current.date(byAdding: .day, value: -Self.trashDays, to: now()) ?? now()
        let read = await Task.detached { () -> StoredLibrary? in try? store.load() }.value
        if read == nil { failure = Self.unreadable }
        let stored = read ?? StoredLibrary()
        perform(.purgeTrash(before: expiry))

        let saved = defaults?.stringArray(forKey: Self.folderOrderKey) ?? []
        let names = stored.folders.sorted { a, b in
            switch (saved.firstIndex(of: a), saved.firstIndex(of: b)) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.localizedStandardCompare(b) == .orderedAscending
            }
        }
        folders = names.map { Folder(id: UUID(stableFrom: "folder:" + $0), name: $0) }
        var loaded: [Note] = []
        var ids: Set<UUID> = []
        func id(for path: String) -> UUID {
            let id = UUID(stableFrom: "note:" + path)
            return ids.insert(id).inserted ? id : UUID()
        }
        for stored in stored.notes {
            var note = Note(
                id: id(for: stored.path),
                path: stored.path,
                text: stored.text,
                created: stored.created,
                modified: stored.modified,
                folderID: folderID(forPath: stored.path)
            )
            note.fileID = stored.fileID
            loaded.append(note)
        }
        for trashed in stored.trash where trashed.trashed >= expiry {
            loaded.append(Note(
                id: id(for: "trash:" + trashed.id.uuidString),
                path: trashed.note.path,
                text: trashed.note.text,
                created: trashed.note.created,
                modified: trashed.note.modified,
                folderID: folderID(forPath: trashed.note.path),
                deleted: trashed.trashed,
                binID: trashed.id
            ))
        }
        // Notes begun while the folder was being read are kept.
        notes = loaded + notes.filter(\.isDraft)
        isLoaded = true
        if needsRefresh { refresh() }
    }

    // MARK: Changes made outside

    /// Reads the folder again after something changed in it, and brings the library into line with what is
    /// there. The store reads only once the changes handed to it are made; a reading taken while more were
    /// handed over is set aside and taken again, so the library never mistakes its own changes for another's.
    func refresh() {
        guard isLoaded, !isRefreshing else {
            needsRefresh = true
            return
        }
        Task { await reread() }
    }

    /// One reading at a time, taken again while anything changed during it. A reading taken while the library
    /// handed the store more changes is set aside until those changes stop, as when someone is typing, since
    /// they may not be in it.
    func reread() async {
        guard let store, isLoaded else { return }
        // A reading under way takes this one in, and this waits for it.
        guard !isRefreshing else {
            needsRefresh = true
            while isRefreshing { try? await Task.sleep(for: .milliseconds(20)) }
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsRefresh = false
            let generation = queued
            let stored = await Task.detached { try? store.load() }.value
            guard let stored else {
                failure = Self.unreadable
                return
            }
            if generation != queued {
                await settle()
                needsRefresh = true
                continue
            }
            reconcile(stored)
            if !missingSince.isEmpty {
                try? await Task.sleep(for: .seconds(missingGrace))
                needsRefresh = true
            }
        } while needsRefresh
    }

    /// Waits until the library has handed the store nothing new for a moment.
    private func settle() async {
        var seen = -1
        while seen != queued {
            seen = queued
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Takes in what another app did: a file changed, renamed, moved, added or deleted, and folders added or
    /// taken away. A file renamed or moved is known by its identity and stays the same note. None of this is
    /// undoable here, since it was not done here.
    private func reconcile(_ stored: StoredLibrary) {
        let names = Set(stored.folders)
        var order = folders.filter { names.contains($0.name) }
        for name in stored.folders where !order.contains(where: { $0.name == name }) {
            let stable = UUID(stableFrom: "folder:" + name)
            order.append(Folder(id: order.contains { $0.id == stable } ? UUID() : stable, name: name))
        }
        if order != folders { folders = order }

        var updated = notes
        var onDisk = Dictionary(stored.notes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let onDiskText = onDisk.mapValues(\.text)
        var seen: Set<Note.ID> = []
        func take(_ disk: StoredNote, at index: Int) {
            seen.insert(updated[index].id)
            updated[index].fileID = disk.fileID
            let moved = updated[index].path != disk.path
            if moved {
                updated[index].path = disk.path
                updated[index].folderID = folderID(forPath: disk.path)
            }
            missingSince[updated[index].id] = nil
            let rewritten = updated[index].file.text != disk.text && !unsaved.contains(disk.path)
            if rewritten {
                updated[index].file = NoteFile(text: disk.text)
                updated[index].modified = disk.modified
            }
            if moved || rewritten { updated[index].reviewNaming() }
        }
        for index in updated.indices where !updated[index].isDeleted {
            guard let path = updated[index].path, let disk = onDisk.removeValue(forKey: path) else { continue }
            take(disk, at: index)
        }
        let ids = Set(updated.map(\.id))
        for disk in onDisk.values.sorted(by: { $0.path < $1.path }) {
            let renamed = disk.fileID.flatMap { fileID in
                updated.indices.first {
                    !seen.contains(updated[$0].id) && !updated[$0].isDeleted && !updated[$0].isDraft && updated[$0].fileID == fileID
                }
            }
            if let renamed {
                take(disk, at: renamed)
            } else {
                let stable = UUID(stableFrom: "note:" + disk.path)
                var note = Note(
                    id: ids.contains(stable) ? UUID() : stable,
                    path: disk.path,
                    text: disk.text,
                    created: disk.created,
                    modified: disk.modified,
                    folderID: folderID(forPath: disk.path)
                )
                note.fileID = disk.fileID
                updated.append(note)
                seen.insert(note.id)
            }
        }
        // A written note whose file has gone was deleted by another app, and goes with it once it has stayed
        // away a moment. One whose last change failed stays, since what was typed is only here.
        let now = now()
        updated.removeAll { note in
            guard !note.isDeleted, !note.isDraft, !seen.contains(note.id), !unsaved.contains(note.path ?? "") else { return false }
            let since = missingSince[note.id] ?? now
            missingSince[note.id] = since
            return now.timeIntervalSince(since) >= missingGrace
        }
        missingSince = missingSince.filter { id, _ in updated.contains { $0.id == id } }
        // A failed change is behind a note once the folder holds what the note does, or no note is there.
        unsaved = unsaved.filter { path in
            guard let note = updated.first(where: { $0.path == path && !$0.isDeleted }) else { return false }
            return onDiskText[path] != note.file.text
        }
        if updated != notes { notes = updated }
    }

    // MARK: Reading

    func note(_ id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    func folder(_ id: Folder.ID) -> Folder? {
        folders.first { $0.id == id }
    }

    func notes(in item: SidebarItem) -> [Note] {
        switch item {
        case .inbox: notes.filter { !$0.isDeleted && $0.folderID == nil }
        case .allNotes: notes.filter { !$0.isDeleted }
        case .pinned: notes.filter { !$0.isDeleted && $0.isPinned }
        case .folder(let id): notes.filter { !$0.isDeleted && $0.folderID == id }
        case .recentlyDeleted: notes.filter(\.isDeleted)
        }
    }

    /// Search covers every note that has not been deleted, whichever sidebar item is selected.
    func notes(matching query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return notes.filter {
            !$0.isDeleted && ($0.body.range(of: query, options: options) != nil || $0.title.range(of: query, options: options) != nil)
        }
    }

    /// Where each note is, to open it in a window of its own that finds it again at the next launch. A new
    /// note is written first, so it has somewhere to be; one with nothing in it has nowhere yet, and stays.
    func paths(forWindows ids: some Collection<Note.ID>) -> [String] {
        ids.compactMap { id in
            guard let note = note(id), !(note.isDraft && NoteText.isBlank(note.body)) else { return nil }
            leave(id)
            return self.note(id)?.path
        }
    }

    /// The note at a path, living before deleted, for a window that remembers where its note was.
    func note(at path: String) -> Note? {
        notes.first { $0.path == path && !$0.isDeleted } ?? notes.first { $0.path == path }
    }

    func count(in item: SidebarItem) -> Int {
        notes(in: item).count
    }

    func name(of item: SidebarItem) -> String {
        switch item {
        case .inbox: String(localized: "Inbox")
        case .allNotes: String(localized: "All Notes")
        case .pinned: String(localized: "Pinned")
        case .folder(let id): folder(id)?.name ?? ""
        case .recentlyDeleted: String(localized: "Recently Deleted")
        }
    }

    // MARK: Notes

    /// A new, empty note placed where it will show in `item`: in that folder, pinned when made from Pinned, and in
    /// the Inbox otherwise. It has no file until its first line is written.
    @discardableResult
    func newNote(in item: SidebarItem, undoManager: UndoManager? = nil) -> Note {
        var file = NoteFile(text: "")
        if item == .pinned { file.setFlag("pinned", true) }
        var note = Note(text: file.text, created: now())
        if case .folder(let id) = item { note.folderID = folder(id)?.id }
        notes.append(note)
        let id = note.id
        registerUndo(undoManager, name: String(localized: "New Note")) { [weak undoManager] library in
            library.discard(id, undoManager: undoManager)
        }
        return note
    }

    /// A note being written. A new note gets its file, named after its first line, once that line is finished
    /// or the typing pauses. Typing is undone by the page that holds it, so this registers nothing.
    func updateBody(of id: Note.ID, to body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body,
              !notes[index].isDeleted
        else { return }
        if let path = notes[index].path { unsaved.remove(path) }
        notes[index].file.body = body
        notes[index].modified = now()
        edited.insert(id)
        if notes[index].isDraft {
            draftSaves[id]?.cancel()
            if NoteText.hasCompleteFirstLine(body) {
                writeDraft(at: index)
            } else if !NoteText.isBlank(body) {
                draftSaves[id] = Task { [weak self, draftDelay] in
                    try? await Task.sleep(for: draftDelay)
                    guard !Task.isCancelled, let self,
                          let index = notes.firstIndex(where: { $0.id == id }), notes[index].isDraft, !notes[index].isDeleted
                    else { return }
                    writeDraft(at: index)
                }
            }
        } else if let path = notes[index].path {
            perform(.write(path: path, text: notes[index].file.text))
        }
    }

    /// The note is no longer on the page. A new note is written with what it has, or let go if it has nothing,
    /// as Notes lets an empty new note go. A note named after its first line takes the line's new name.
    func leave(_ id: Note.ID) {
        draftSaves.removeValue(forKey: id)?.cancel()
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isDeleted else { return }
        if notes[index].isDraft {
            if NoteText.isBlank(notes[index].body) {
                notes.remove(at: index)
            } else {
                writeDraft(at: index)
            }
        } else if edited.contains(id) {
            followFirstLine(at: index)
        }
        edited.remove(id)
    }

    /// Every note being written is left, so new notes with something in them get their files and names follow
    /// their first lines, and the store finishes, as the app quits.
    func finish() {
        for note in notes where note.isDraft || edited.contains(note.id) { leave(note.id) }
        store?.drain()
    }

    func delete(_ ids: Set<Note.ID>, undoManager: UndoManager? = nil) {
        place(ids, undoManager: undoManager, name: deleteName(ids.count)) { $0.isDeleted = true }
    }

    func recover(_ ids: Set<Note.ID>, undoManager: UndoManager? = nil) {
        place(ids, undoManager: undoManager, name: String(localized: "Recover")) { $0.isDeleted = false }
    }

    /// Erases notes in Recently Deleted for good. Nothing brings them back, so this is not undoable and the
    /// views confirm it first.
    func deletePermanently(_ ids: Set<Note.ID>) {
        for note in notes where ids.contains(note.id) && note.isDeleted {
            if let binID = note.binID { perform(.purge(id: binID)) }
        }
        notes.removeAll { ids.contains($0.id) && $0.isDeleted }
        notesToPurge.subtract(ids)
    }

    /// Moving a note into a folder, or back to the Inbox with `nil`, also recovers it if it was deleted. A folder
    /// that no longer exists takes nothing.
    func move(_ ids: Set<Note.ID>, to folderID: Folder.ID?, undoManager: UndoManager? = nil) {
        guard folderID.map({ folder($0) != nil }) ?? true else { return }
        place(ids, undoManager: undoManager, name: String(localized: "Move")) {
            $0.folderID = folderID
            $0.isDeleted = false
        }
    }

    /// Deleted notes keep their pin as it was, since Recently Deleted shows no pins.
    func setPinned(_ ids: Set<Note.ID>, _ pinned: Bool, undoManager: UndoManager? = nil) {
        let name = pinned ? String(localized: "Pin") : String(localized: "Unpin")
        let changed = notes.filter { ids.contains($0.id) && !$0.isDeleted && $0.isPinned != pinned }.map(\.id)
        guard !changed.isEmpty else { return }
        for index in notes.indices where changed.contains(notes[index].id) {
            notes[index].file.setFlag("pinned", pinned)
            if let path = notes[index].path { perform(.write(path: path, text: notes[index].file.text)) }
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setPinned(Set(changed), !pinned, undoManager: undoManager)
        }
    }

    /// Whether another note in the same folder already has the file name, ignoring case, as the Finder does.
    func isNoteNameTaken(_ name: String, for id: Note.ID) -> Bool {
        guard let note = note(id) else { return false }
        let directory = note.path.map { _ in note.directory } ?? directory(for: note.folderID)
        let path = directory.isEmpty ? "\(name).md" : "\(directory)/\(name).md"
        return isPathTaken(path, except: id)
    }

    /// Renames the note's file. Marfa keeps a note's title in its front matter when it has one, so that is
    /// changed too. A new note is written under the name. An empty name, or one another note has, is refused.
    func renameNote(_ id: Note.ID, to name: String, undoManager: UndoManager? = nil) {
        let name = NoteText.fileSafe(name)
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isDeleted, !name.isEmpty,
              !isNoteNameTaken(name, for: id)
        else { return }
        let title = notes[index].file.title.map { _ in name }
        rename(at: index, to: name, title: title, undoManager: undoManager)
    }

    /// A note named after its first line whose line has changed takes the new line's name, numbered if another
    /// note has it, and its new `title` where it keeps one or the line has characters a name cannot. Marfa sees
    /// one rename, made as the person leaves the note rather than as they type.
    private func followFirstLine(at index: Int) {
        guard let named = notes[index].namedLine else { return }
        let line = NoteText.firstLine(of: notes[index].body) ?? ""
        guard line != named else { return }
        let title = notes[index].file.title != nil || NoteText.needsTitle(line) ? line : nil
        rename(at: index, to: NoteText.name(for: line), title: title, undoManager: nil)
    }

    private func rename(at index: Int, to name: String, title: String?, undoManager: UndoManager?) {
        let id = notes[index].id
        let oldName = notes[index].fileTitle ?? NoteText.fileName(for: notes[index].body)
        let oldTitle = notes[index].file.property("title")
        let directory = notes[index].path.map { _ in notes[index].directory } ?? directory(for: notes[index].folderID)
        let path = uniquePath(name, in: directory, except: id)
        defer {
            // A note goes by its first line again once it is given the line's name, whatever gave it.
            let line = NoteText.firstLine(of: notes[index].body) ?? ""
            notes[index].namedLine = notes[index].fileTitle.flatMap { NoteText.isName($0, of: line) ? line : nil }
        }
        guard path != notes[index].path || title != oldTitle else { return }
        if title != oldTitle { notes[index].file.setProperty("title", title) }
        if let from = notes[index].path {
            if path != from { perform(.move(from: from, to: path)) }
            notes[index].path = path
            if title != oldTitle { perform(.write(path: path, text: notes[index].file.text)) }
        } else {
            notes[index].path = path
            perform(.create(path: path, text: notes[index].file.text))
        }
        registerUndo(undoManager, name: String(localized: "Rename Note")) { [weak undoManager] library in
            guard let index = library.notes.firstIndex(where: { $0.id == id }), !library.notes[index].isDeleted else { return }
            library.rename(at: index, to: oldName, title: oldTitle, undoManager: undoManager)
        }
    }

    // MARK: Attachments

    /// The directory a note's file is in, or will be in once it is written.
    func directory(of note: Note) -> String {
        note.path == nil ? directory(for: note.folderID) : note.directory
    }

    /// Writes files a note points at, such as images pasted into it, into the attachments folder, and gives the
    /// links to them from where the note is, as standard markdown writes a relative link.
    func attach(_ files: [(name: String, data: Data)], to id: Note.ID) -> [(link: String, name: String)] {
        guard let store, let note = note(id), !note.isDeleted else { return [] }
        let depth = directory(of: note).split(separator: "/").count
        return files.map { file in
            let path = store.freeAttachmentPath(named: Self.attachmentName(file.name))
            perform(.attach(path: path, data: file.data))
            let encoded = path.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: NoteText.linkPathAllowed) ?? String($0)
            }
            let link = (Array(repeating: "..", count: depth) + encoded).joined(separator: "/")
            return (link, ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
    }

    /// A file's name as the attachments folder can take it, keeping its extension, which says what it is.
    static func attachmentName(_ name: String) -> String {
        // A name such as `.png` is all extension.
        let bare = name.hasPrefix(".") && !name.dropFirst().contains(".")
        let ext = bare ? String(name.dropFirst()) : (name as NSString).pathExtension
        let stem = bare ? "" : NoteText.fileSafe((name as NSString).deletingPathExtension)
        let fitted = NoteText.fitted(stem, room: ext.utf8.count + 1)
        let base = fitted.isEmpty ? String(localized: "Image") : fitted
        return ext.isEmpty ? base : "\(base).\(NoteText.fileSafe(ext))"
    }


    // MARK: Folders

    @discardableResult
    func newFolder(undoManager: UndoManager? = nil) -> Folder {
        let name = newFolderName()
        let folder = Folder(name: name)
        setFolders(folders + [folder], undoManager: undoManager, name: String(localized: "New Folder"))
        return folder
    }

    /// Whether the name cannot be a folder's: another folder has it, ignoring case as the Finder does, or it is
    /// the attachments folder's.
    func isFolderNameTaken(_ name: String, except id: Folder.ID? = nil) -> Bool {
        let name = NoteText.fileSafe(name)
        if name.localizedCaseInsensitiveCompare(FolderStore.attachments) == .orderedSame { return true }
        return folders.contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Renames the folder's directory. An empty name, or one another folder already has, is refused and
    /// leaves the name as it was.
    func rename(_ id: Folder.ID, to name: String, undoManager: UndoManager? = nil) {
        let name = NoteText.fileSafe(name)
        guard let index = folders.firstIndex(where: { $0.id == id }), !name.isEmpty,
              !isFolderNameTaken(name, except: id)
        else { return }
        var order = folders
        order[index].name = name
        setFolders(order, undoManager: undoManager, name: String(localized: "Rename Folder"))
    }

    /// Deleting a folder moves its notes to Recently Deleted, as Notes does, and takes the directory away.
    /// Undo brings both back in one step.
    func deleteFolder(_ id: Folder.ID, undoManager: UndoManager? = nil) {
        guard folder(id) != nil else { return }
        let name = String(localized: "Delete Folder")
        undoManager?.beginUndoGrouping()
        place(Set(notes.filter { $0.folderID == id && !$0.isDeleted }.map(\.id)), undoManager: undoManager, name: name) {
            $0.isDeleted = true
        }
        setFolders(folders.filter { $0.id != id }, undoManager: undoManager, name: name)
        undoManager?.endUndoGrouping()
    }

    /// Moves the folders, in the order given, to sit before `target`, or at the end when it is `nil`.
    func moveFolders(_ ids: [Folder.ID], before target: Folder.ID?, undoManager: UndoManager? = nil) {
        let moving = ids.compactMap { folder($0) }
        var order = folders.filter { !ids.contains($0.id) }
        let index = target.flatMap { target in order.firstIndex { $0.id == target } } ?? order.endIndex
        order.insert(contentsOf: moving, at: index)
        setFolders(order, undoManager: undoManager, name: String(localized: "Move Folder"))
    }

    // MARK: Undoable primitives
    //
    // Each primitive registers its own inverse, so undoing registers the redo without extra bookkeeping.
    // A primitive that would change nothing registers nothing, and an inverse whose note has gone does nothing.

    /// Where a note is: its folder, and whether it is in Recently Deleted.
    struct Placement: Equatable {
        var folderID: Folder.ID?
        var isDeleted: Bool
    }

    private func place(_ ids: Set<Note.ID>, undoManager: UndoManager?, name: String, _ change: (inout Placement) -> Void) {
        var placements: [Note.ID: Placement] = [:]
        for note in notes where ids.contains(note.id) {
            let current = Placement(folderID: note.folderID, isDeleted: note.isDeleted)
            var placement = current
            change(&placement)
            if placement != current { placements[note.id] = placement }
        }
        apply(placements, undoManager: undoManager, name: name)
    }

    private func apply(_ placements: [Note.ID: Placement], undoManager: UndoManager?, name: String) {
        guard !placements.isEmpty else { return }
        var previous: [Note.ID: Placement] = [:]
        for (id, placement) in placements {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            previous[id] = Placement(folderID: notes[index].folderID, isDeleted: notes[index].isDeleted)
            relocate(at: index, to: placement)
        }
        notes.removeAll { $0.isDraft && $0.isDeleted }
        // A new note deleted with nothing in it is gone, with nothing to bring back.
        previous = previous.filter { id, _ in notes.contains { $0.id == id } }
        guard !previous.isEmpty else { return }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.apply(previous, undoManager: undoManager, name: name)
        }
    }

    /// Makes one note's placement so, on disk as in memory.
    private func relocate(at index: Int, to placement: Placement) {
        let note = notes[index]
        let fileName = note.fileTitle ?? NoteText.fileName(for: note.body)
        switch (note.isDeleted, placement.isDeleted) {
        case (false, true):
            // A new note with something in it is written first, so undoing the deletion brings it back.
            if note.isDraft, !NoteText.isBlank(note.body) {
                writeDraft(at: index)
            }
            notes[index].deleted = now()
            guard let path = notes[index].path else { return }
            let binID = UUID()
            notes[index].binID = binID
            perform(.trash(path: path, id: binID, date: notes[index].deleted!))
        case (true, false):
            // A note comes back where it was, or into the folder it is moved to, under the name it had. A folder
            // that has gone since cannot take it, so it comes back to the Inbox.
            let folderID = placement.folderID.flatMap { folder($0)?.id }
            let returning = folderID == note.folderID && note.path.map { self.folderID(forPath: $0) == folderID } == true
            let directory = returning ? note.directory : directory(for: folderID)
            let path = uniquePath(fileName, in: directory, except: note.id)
            notes[index].deleted = nil
            notes[index].folderID = folderID
            if let binID = note.binID {
                perform(.restore(id: binID, path: path))
                notes[index].binID = nil
                notes[index].path = path
            }
        case (false, false):
            notes[index].folderID = placement.folderID
            guard let from = note.path else { return }
            let path = uniquePath(fileName, in: directory(for: placement.folderID), except: note.id)
            perform(.move(from: from, to: path))
            notes[index].path = path
            rebaseLinks(at: index, from: note.directory)
        case (true, true):
            notes[index].folderID = placement.folderID
        }
    }

    /// Takes away a new note, as undoing New Note does. One already written goes to Recently Deleted instead,
    /// so nothing typed is lost.
    private func discard(_ id: Note.ID, undoManager: UndoManager?) {
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isDeleted else { return }
        let note = notes[index]
        if note.isDraft {
            notes.remove(at: index)
            registerUndo(undoManager, name: String(localized: "New Note")) { [weak undoManager] library in
                library.notes.append(note)
                library.registerUndo(undoManager, name: String(localized: "New Note")) { library in
                    library.discard(id, undoManager: undoManager)
                }
            }
        } else {
            delete([id], undoManager: undoManager)
        }
    }

    private func setFolders(_ order: [Folder], undoManager: UndoManager?, name: String) {
        guard order != folders else { return }
        let previous = folders
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Set(order.map(\.id))
        for folder in order {
            if let before = old[folder.id] {
                if before.name != folder.name {
                    perform(.moveFolder(from: before.name, to: folder.name))
                    renamePaths(from: before.name, to: folder.name)
                }
            } else {
                perform(.createFolder(path: folder.name))
            }
        }
        for folder in previous where !new.contains(folder.id) {
            perform(.removeFolder(path: folder.name))
        }
        folders = order
        defaults?.set(order.map(\.name), forKey: Self.folderOrderKey)
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setFolders(previous, undoManager: undoManager, name: name)
        }
    }

    private func perform(_ change: StoreChange) {
        queued += 1
        store?.perform(change)
    }

    private func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (NoteLibrary) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(name)
    }

    // MARK: Paths

    /// A note moved to another depth gets its links into the attachments folder written from where it now is.
    private func rebaseLinks(at index: Int, from old: String) {
        guard let path = notes[index].path else { return }
        let body = NoteText.rebasingAttachmentLinks(in: notes[index].body, from: old, to: notes[index].directory)
        guard body != notes[index].body else { return }
        notes[index].file.body = body
        perform(.write(path: path, text: notes[index].file.text))
    }

    /// A new note's file, named after its first line; a line with characters a name cannot hold is kept whole
    /// as the note's `title`.
    private func writeDraft(at index: Int) {
        draftSaves.removeValue(forKey: notes[index].id)?.cancel()
        let note = notes[index]
        let line = NoteText.firstLine(of: note.body) ?? ""
        if NoteText.needsTitle(line) { notes[index].file.setProperty("title", line) }
        let path = uniquePath(NoteText.name(for: line), in: directory(for: note.folderID), except: note.id)
        notes[index].path = path
        notes[index].namedLine = line
        perform(.create(path: path, text: notes[index].file.text))
    }

    /// The directory a folder's notes are in, relative to the notes folder; the Inbox is the notes folder itself.
    private func directory(for folderID: Folder.ID?) -> String {
        folderID.flatMap { folder($0)?.name } ?? ""
    }

    /// The folder a path is in: the directory at the top of the notes folder that holds it, however deep. A
    /// trashed note whose folder has gone since is in none.
    private func folderID(forPath path: String) -> Folder.ID? {
        let components = path.split(separator: "/")
        guard components.count > 1, let top = components.first else { return nil }
        return folders.first { $0.name == top }?.id
    }

    private func isPathTaken(_ path: String, except id: Note.ID?) -> Bool {
        notes.contains { $0.id != id && !$0.isDeleted && $0.path?.localizedCaseInsensitiveCompare(path) == .orderedSame }
    }

    /// `name.md` in the directory, or the first free name numbered after it, as the Finder numbers a copy.
    private func uniquePath(_ name: String, in directory: String, except id: Note.ID?) -> String {
        let prefix = directory.isEmpty ? "" : directory + "/"
        var candidate = "\(prefix)\(name).md"
        var number = 2
        while isPathTaken(candidate, except: id) {
            candidate = "\(prefix)\(name) \(number).md"
            number += 1
        }
        return candidate
    }

    private func renamePaths(from old: String, to new: String) {
        for index in notes.indices {
            guard let path = notes[index].path, path.hasPrefix(old + "/") else { continue }
            notes[index].path = new + path.dropFirst(old.count)
        }
    }

    /// The store could not use a path, since something it had not been told of was there, and used another, or
    /// could not move a file, which stayed where it was.
    private func relocate(_ from: String, _ to: String) {
        defer { store?.acknowledgeRelocation(of: from) }
        guard let index = notes.firstIndex(where: { $0.path == from && !$0.isDeleted })
            ?? notes.firstIndex(where: { $0.path == from })
        else { return }
        notes[index].path = to
        notes[index].folderID = folderID(forPath: to)
        // A note following its first line whose file kept a name the line no longer gives is renamed again when
        // it is next left, so a rename that failed is tried once more rather than forgotten.
        if let line = notes[index].namedLine, let name = notes[index].fileTitle, !NoteText.isName(name, of: line) {
            notes[index].namedLine = name
            edited.insert(notes[index].id)
        }
    }

    private func newFolderName() -> String {
        var name = String(localized: "New Folder")
        var number = 2
        while isFolderNameTaken(name) {
            name = String(localized: "New Folder \(number)")
            number += 1
        }
        return name
    }

    private func deleteName(_ count: Int) -> String {
        count == 1 ? String(localized: "Delete Note") : String(localized: "Delete Notes")
    }
}
