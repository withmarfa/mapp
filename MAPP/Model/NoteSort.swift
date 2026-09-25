import Foundation

nonisolated enum NoteSort: String, CaseIterable {
    case dateEdited
    case dateCreated
    case title

    func date(of note: Note) -> Date {
        switch self {
        case .dateCreated: note.created
        case .dateEdited, .title: note.modified
        }
    }

    func sorted(_ notes: [Note]) -> [Note] {
        switch self {
        case .title:
            notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateEdited, .dateCreated:
            notes.sorted { date(of: $0) > date(of: $1) }
        }
    }
}
