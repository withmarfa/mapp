import Foundation
import Observation

/// Every note and folder, held in memory for the views and kept in a store. Each change a person can make is
/// made here at once, handed to the store to make on disk, and undoable through the undo manager it is given.
@Observable
final class NoteLibrary {
    var notes: [Note] { didSet { cachedConnectionIndex = nil } }
    var folders: [Folder]
    private(set) var files: [AppFile] = [] { didSet { cachedConnectionIndex = nil } }
    private(set) var completedImports: [UUID: UUID] = [:]
    /// Whether the store has been read, so a window restores what it showed only once there is something to find.
    private(set) var isLoaded: Bool
    /// Notes a person has asked to erase for good, until they confirm or cancel, since that cannot be undone.
    var notesToPurge: Set<Note.ID> = []
    /// Something the store could not do, to tell the person: what failed and why.
    var failure: (title: String, message: String)?
    let now: () -> Date

    /// Derived snapshots only; source files and note identities remain the authority.
    @ObservationIgnored var cachedItemProjections: [UUID: NoteProjection] = [:]
    @ObservationIgnored var cachedConnectionIndex: NoteConnectionIndex?

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
        store?.imported = { [weak self] requestID, path in
            guard let self else { return }
            let namespace = (path as NSString).pathExtension.lowercased() == "md" ? "note:" : "file:"
            self.completedImports[requestID] = UUID(stableFrom: namespace + path)
            self.refresh()
        }
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

    func fileURL(for id: UUID) -> URL? {
        guard let file = files.first(where: { $0.id == id }) else { return nil }
        return store?.fileURL(for: file.path)
    }

    func importFiles(_ sources: [URL], folderID: Folder.ID? = nil, requestID: UUID = UUID()) {
        guard store != nil else { return }
        let prefix = folders.first(where: { $0.id == folderID }).map { $0.name + "/" } ?? ""
        for source in sources {
            perform(.importFile(path: prefix + source.lastPathComponent, source: source, requestID: requestID))
        }
    }

    func consumeImportCompletion(_ requestID: UUID) {
        completedImports[requestID] = nil
    }

    private func reconcileFiles(_ stored: [StoredFile]) {
        files = stored.map { disk in
            let previous = files.first { $0.path == disk.path || (disk.fileID != nil && $0.stored.fileID == disk.fileID) }
            return AppFile(id: previous?.id ?? UUID(stableFrom: "file:" + disk.path), stored: disk, folderID: folderID(forPath: disk.path))
        }
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
        reconcileFiles(stored.files)
        notes = loaded
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
        reconcileFiles(stored.files)

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
                    !seen.contains(updated[$0].id) && !updated[$0].isDeleted && updated[$0].fileID == fileID
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
            guard !note.isDeleted, !seen.contains(note.id), !unsaved.contains(note.path ?? "") else { return false }
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
        case .inbox: return notes.filter { !$0.isDeleted && $0.folderID == nil }
        case .allNotes: return notes.filter { !$0.isDeleted }
        case .favorites: return notes.filter { !$0.isDeleted && $0.isFavorite }
        case .favoriteItem(let id): return notes.filter { $0.id == id && !$0.isDeleted && $0.isFavorite }
        case .folder(let id): return notes.filter { !$0.isDeleted && $0.folderID == id }
        case .recentlyDeleted: return notes.filter(\.isDeleted)
        case .marfaTypes, .files: return []
        case .itemType(let typeID): return notes.filter { !$0.isDeleted && self.item($0.id)?.type?.id == typeID }
        case .project(let projectID):
            let descendants = projectDescendants(projectID)
            return notes.filter { !$0.isDeleted && (descendants.contains($0.id) || $0.id == projectID) }
        }
    }

    private func projectDescendants(_ id: UUID) -> Set<UUID> {
        let edges = connectionIndex.edges.filter { $0.name == "parent-of" }
        var result: Set<UUID> = []
        var pending = [id]
        while let current = pending.popLast() {
            for edge in edges where edge.sourceID == current && !result.contains(edge.targetID) && edge.targetID != id {
                result.insert(edge.targetID)
                pending.append(edge.targetID)
            }
        }
        return result
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

    /// Where each note is, to open it in a window of its own that finds it again at the next launch. A note
    /// is left first, so a name that follows its first line is current.
    func paths(forWindows ids: some Collection<Note.ID>) -> [String] {
        ids.compactMap { id in
            if let file = files.first(where: { $0.id == id }) { return file.path }
            leave(id)
            return self.note(id)?.path
        }
    }

    /// The note at a path, living before deleted, for a window that remembers where its note was.
    func note(at path: String) -> Note? {
        notes.first { $0.path == path && !$0.isDeleted } ?? notes.first { $0.path == path }
    }

    func count(in item: SidebarItem) -> Int {
        let fileCount: Int
        switch item {
        case .allNotes, .files: fileCount = files.count
        case .inbox: fileCount = files.filter { $0.folderID == nil }.count
        case .folder(let id): fileCount = files.filter { $0.folderID == id }.count
        default: fileCount = 0
        }
        return notes(in: item).count + fileCount
    }

    func name(of item: SidebarItem) -> String {
        switch item {
        case .inbox: String(localized: "Inbox")
        case .allNotes: String(localized: "All Notes")
        case .favorites: String(localized: "Favorites")
        case .favoriteItem(let id): self.item(id)?.title ?? ""
        case .folder(let id): folder(id)?.name ?? ""
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .marfaTypes: String(localized: "Marfa Types")
        case .files: String(localized: "Files")
        case .itemType(let typeID): typeID == "aic.project" ? String(localized: "Projects") : WorkbenchSchema.definition(typeID)?.label ?? typeID
        case .project(let id): self.item(id)?.title ?? ""

        }
    }

    // MARK: Notes

    /// A note being written. Typing is undone by the page that holds it, so this registers nothing.
    func updateBody(of id: Note.ID, to body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), let path = notes[index].path,
              notes[index].body != body, !notes[index].isDeleted
        else { return }
        unsaved.remove(path)
        notes[index].file.body = body
        notes[index].modified = now()
        edited.insert(id)
        perform(.write(path: path, text: notes[index].file.text))
    }

    /// The note is no longer on the page. A note named after its first line takes the line's new name.
    func leave(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isDeleted else { return }
        if edited.contains(id) { followFirstLine(at: index) }
        edited.remove(id)
    }

    /// Every note being written is left, so names follow first lines, and the store finishes, as the app quits.
    func finish() {
        for note in notes where edited.contains(note.id) { leave(note.id) }
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

    /// Deleted notes keep their tags as they were, since Recently Deleted shows no favorites. A note whose tags
    /// cannot be changed safely is left as written, and the person is told.
    func setFavorite(_ ids: Set<Note.ID>, _ isFavorite: Bool, undoManager: UndoManager? = nil) {
        var changes: [Note.ID: FileChange] = [:]
        var refused: [(title: String, error: NoteFile.TagEditError)] = []
        for index in notes.indices where ids.contains(notes[index].id) && !notes[index].isDeleted && notes[index].isFavorite != isFavorite {
            var file = notes[index].file
            do {
                try file.setFavorite(isFavorite)
            } catch {
                refused.append((notes[index].title, error))
                continue
            }
            guard file != notes[index].file else { continue }
            changes[notes[index].id] = FileChange(before: notes[index].file, after: file)
            notes[index].file = file
            if let path = notes[index].path { perform(.write(path: path, text: file.text)) }
        }
        if let first = refused.first {
            let title = isFavorite ? String(localized: "Can’t Add to Favorites") : String(localized: "Can’t Remove from Favorites")
            let message = switch (refused.count, first.error) {
            case (1, .unreadable):
                String(localized: "The tags of “\(first.title)” can’t be read, so its file was left unchanged.")
            case (1, .unsafe):
                String(localized: "The tags of “\(first.title)” are written in a form that can’t be changed safely, so its file was left unchanged.")
            default:
                String(localized: "Some notes have tags that can’t be read or changed safely, so their files were left unchanged.")
            }
            failure = (title, message)
        }
        guard !changes.isEmpty else { return }
        let name = isFavorite ? String(localized: "Add to Favorites") : String(localized: "Remove from Favorites")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.revertFavorites(changes, wereSetTo: isFavorite, name: name, undoManager: undoManager)
        }
    }

    nonisolated struct FileChange: Sendable {
        let before: NoteFile
        let after: NoteFile
    }

    /// Puts back the bytes each file had before a favorite change. A file whose body changed since keeps the new
    /// body under its old front matter; one whose front matter changed since has only its favorite changed back.
    private func revertFavorites(_ changes: [Note.ID: FileChange], wereSetTo isFavorite: Bool, name: String, undoManager: UndoManager?) {
        var reverted: [Note.ID: FileChange] = [:]
        var refused: [String] = []
        for index in notes.indices {
            guard let change = changes[notes[index].id], !notes[index].isDeleted else { continue }
            let current = notes[index].file
            var restored = current
            if current == change.after {
                restored = change.before
            } else if current.frontMatter == change.after.frontMatter {
                restored.restoreFrontMatter(from: change.before)
            } else if current.isFavorite == isFavorite {
                do {
                    try restored.setFavorite(!isFavorite)
                } catch {
                    refused.append(notes[index].title)
                    continue
                }
            }
            guard restored != current else { continue }
            reverted[notes[index].id] = FileChange(before: current, after: restored)
            notes[index].file = restored
            if let path = notes[index].path { perform(.write(path: path, text: restored.text)) }
        }
        if let first = refused.first {
            let title = isFavorite ? String(localized: "Can’t Remove from Favorites") : String(localized: "Can’t Add to Favorites")
            let message = refused.count == 1
                ? String(localized: "The tags of “\(first)” are written in a form that can’t be changed safely, so its file was left unchanged.")
                : String(localized: "Some notes have tags that can’t be read or changed safely, so their files were left unchanged.")
            failure = (title, message)
        }
        guard !reverted.isEmpty else { return }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.revertFavorites(reverted, wereSetTo: !isFavorite, name: name, undoManager: undoManager)
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
        let hasLinesName = notes[index].fileTitle.map { NoteText.isName($0, of: line, exactly: true) } ?? true
        guard line != named || !hasLinesName else { return }
        let title = notes[index].file.title != nil || NoteText.needsTitle(line) ? line : nil
        rename(at: index, to: NoteText.name(for: line), title: title, undoManager: nil)
    }

    private func rename(at index: Int, to name: String, title: String?, undoManager: UndoManager?, updateLinks: Bool = true) {
        let id = notes[index].id
        let oldName = notes[index].fileTitle ?? NoteText.fileName(for: notes[index].body)
        let oldTitle = notes[index].file.property("title")
        let directory = notes[index].path.map { _ in notes[index].directory } ?? directory(for: notes[index].folderID)
        let path = uniquePath(name, in: directory, except: id)
        defer {
            // A note goes by its first line again once it is given the line's name, whatever gave it; exactly the
            // line's, since a name given by hand that only resembles an earlier version's is the person's choice.
            let line = NoteText.firstLine(of: notes[index].body) ?? ""
            notes[index].namedLine = notes[index].fileTitle.flatMap { NoteText.isName($0, of: line, exactly: true) ? line : nil }
        }
        var titleFile = notes[index].file
        if title != oldTitle { titleFile.setProperty("title", title) }
        let titleProjection = NoteProjection(id: id, file: titleFile, fallbackTitle: name)
        if case .invalid = titleProjection.frontMatter {
            failure = (String(localized: "Can’t Rename Item"), String(localized: "Its metadata cannot be safely changed."))
            return
        }
        let predictedTitle = title ?? name
        var originals: [UUID: NoteFile] = [:]
        var replacements: [UUID: NoteFile] = [:]
        var spans: [UUID: [RenameReferenceSpan]] = [:]
        if updateLinks {
            let references = connectionIndex.references.filter { $0.resolution == .resolved(id) }
            let usePath = notes.contains { !$0.isDeleted && $0.id != id && $0.title.caseInsensitiveCompare(predictedTitle) == .orderedSame }
                || predictedTitle.contains(where: { "[]|#".contains($0) })
            let base = usePath ? path : predictedTitle
            guard !base.contains(where: { "[]|#".contains($0) }) else {
                failure = (String(localized: "Can’t Rename Item"), String(localized: "The new name cannot be represented safely in file links."))
                return
            }
            for candidate in notes where !candidate.isDeleted && candidate.id != id {
                let relevant = references.filter { $0.sourceID == candidate.id }
                guard !relevant.isEmpty else { continue }
                var rewrites: [String: String] = [:]
                for reference in relevant {
                    let delimiter = reference.targetTitle.firstIndex { $0 == "|" || $0 == "#" }
                    let suffix = delimiter.map { String(reference.targetTitle[$0...]) } ?? ""
                    rewrites["[[\(reference.targetTitle)]]"] = "[[\(base + suffix)]]"
                }
                var file = candidate.file
                let changed = Self.rewriteReferenceBody(file.body, rewrites: rewrites)
                file.body = changed.text
                let projection = NoteProjection(note: candidate)
                if let fields = projection.fields {
                    for field in WorkbenchSchema.definition(projection.declaredType ?? "core.note")?.relationshipFields ?? [] {
                        guard let value = fields[field] else { continue }
                        func rewrite(_ value: NoteFieldValue) -> NoteFieldValue {
                            if case .array(let values) = value { return .array(values.map(rewrite)) }
                            if case .string(let text) = value, let replacement = rewrites[text] { return .string(replacement) }
                            return value
                        }
                        let rewritten = rewrite(value)
                        if rewritten != value { file.setField(field, rewritten) }
                    }
                }
                if case .invalid = NoteProjection(id: candidate.id, file: file, fallbackTitle: candidate.title).frontMatter {
                    failure = (String(localized: "Can’t Rename Item"), String(localized: "A related file's metadata cannot be safely updated."))
                    return
                }
                if file != candidate.file {
                    originals[candidate.id] = candidate.file
                    replacements[candidate.id] = file
                    spans[candidate.id] = changed.spans
                }
            }
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
        applyItemFiles(replacements, undoManager: nil, name: String(localized: "Rename Links"))
        registerUndo(undoManager, name: String(localized: "Rename Note")) { [weak undoManager] library in
            guard let index = library.notes.firstIndex(where: { $0.id == id }), !library.notes[index].isDeleted else { return }
            library.rename(at: index, to: oldName, title: oldTitle, undoManager: undoManager, updateLinks: false)
            library.restoreRenameReferences(originals: originals, replacements: replacements, spans: spans, undoManager: undoManager)
        }
    }

    private func restoreRenameReferences(originals: [UUID: NoteFile], replacements: [UUID: NoteFile], spans: [UUID: [RenameReferenceSpan]], undoManager: UndoManager?) {
        var nextSpans: [UUID: [RenameReferenceSpan]] = [:]
        var restored: [UUID: NoteFile] = [:]
        var before: [UUID: NoteFile] = [:]
        for (sourceID, original) in originals {
            guard var current = note(sourceID)?.file, let replacement = replacements[sourceID] else { continue }
            before[sourceID] = current
            let changedSpans = spans[sourceID] ?? []
            let bodyChange = Self.revertReferenceSpans(replacement: replacement.body, current: current.body, spans: changedSpans)
            current.body = bodyChange.text
            nextSpans[sourceID] = bodyChange.spans
            let oldFields = NoteProjection(id: sourceID, file: original, fallbackTitle: "").fields ?? [:]
            let newFields = NoteProjection(id: sourceID, file: replacement, fallbackTitle: "").fields ?? [:]
            let currentFields = NoteProjection(id: sourceID, file: current, fallbackTitle: "").fields ?? [:]
            for key in Set(oldFields.keys).union(newFields.keys) where oldFields[key] != newFields[key] && currentFields[key] == newFields[key] {
                current.restoreField(key, from: original)
            }
            restored[sourceID] = current
        }
        applyItemFiles(restored, undoManager: nil, name: String(localized: "Rename Links"))
        registerUndo(undoManager, name: String(localized: "Rename Links")) { [weak undoManager] library in
            library.restoreRenameReferences(originals: before, replacements: restored, spans: nextSpans, undoManager: undoManager)
        }
    }

    private struct RenameReferenceSpan {
        let range: NSRange
        let before: String
        let after: String
    }

    private static func rewriteReferenceBody(_ body: String, rewrites: [String: String]) -> (text: String, spans: [RenameReferenceSpan]) {
        var edits: [(NSRange, String, String)] = []
        for match in body.matches(of: /\[\[([^\[\]\r\n]+)\]\]/.matchingSemantics(.unicodeScalar)) {
            let old = String(match.output.0)
            guard let new = rewrites[old], old != new else { continue }
            edits.append((NSRange(match.range, in: body), old, new))
        }
        let result = NSMutableString(string: body)
        for (range, _, new) in edits.reversed() { result.replaceCharacters(in: range, with: new) }
        var delta = 0
        let spans = edits.map { range, old, new in
            let span = RenameReferenceSpan(range: NSRange(location: range.location + delta, length: (new as NSString).length), before: old, after: new)
            delta += span.range.length - range.length
            return span
        }
        return (result as String, spans)
    }

    private static func revertReferenceSpans(replacement: String, current: String, spans: [RenameReferenceSpan]) -> (text: String, spans: [RenameReferenceSpan]) {
        let expected = Array(replacement.utf16)
        let actual = Array(current.utf16)
        let difference = actual.difference(from: expected)
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change { case .remove(let offset, _, _): removed.insert(offset); case .insert(let offset, _, _): inserted.insert(offset) }
        }
        var mapping: [Int: Int] = [:]
        var source = 0
        var destination = 0
        while source < expected.count || destination < actual.count {
            if removed.contains(source) { source += 1; continue }
            if inserted.contains(destination) { destination += 1; continue }
            guard source < expected.count, destination < actual.count else { break }
            mapping[source] = destination
            source += 1
            destination += 1
        }
        let actualString = current as NSString
        var mappedSpans: [RenameReferenceSpan] = []
        for span in spans {
            if let mapped = mapping[span.range.location], (0..<span.range.length).allSatisfy({ mapping[span.range.location + $0] == mapped + $0 }),
               mapped + span.range.length <= actualString.length,
               actualString.substring(with: NSRange(location: mapped, length: span.range.length)) == span.after {
                mappedSpans.append(.init(range: NSRange(location: mapped, length: span.range.length), before: span.before, after: span.after))
            }
        }
        let result = NSMutableString(string: current)
        for span in mappedSpans.reversed() { result.replaceCharacters(in: span.range, with: span.before) }
        var delta = 0
        let reverseSpans = mappedSpans.map { span in
            let reverse = RenameReferenceSpan(range: NSRange(location: span.range.location + delta, length: (span.before as NSString).length), before: span.after, after: span.before)
            delta += reverse.range.length - span.range.length
            return reverse
        }
        return (result as String, reverseSpans)
    }

    // MARK: Attachments

    /// Writes files a note points at, such as images pasted into it, into the attachments folder, and gives the
    /// links to them from where the note is, as standard markdown writes a relative link.
    func attach(_ files: [(name: String, data: Data)], to id: Note.ID) -> [(link: String, name: String)] {
        guard let store, let note = note(id), !note.isDeleted else { return [] }
        let depth = note.directory.split(separator: "/").count
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

    func perform(_ change: StoreChange) {
        queued += 1
        store?.perform(change)
    }

    func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (NoteLibrary) -> Void) {
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
    func uniquePath(_ name: String, in directory: String, except id: Note.ID?) -> String {
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
        let directory = notes[index].directory
        notes[index].path = to
        notes[index].folderID = folderID(forPath: to)
        // A move to another folder that failed leaves the note where it was, with links written from there.
        if !notes[index].isDeleted { rebaseLinks(at: index, from: directory) }
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
