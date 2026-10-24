import Foundation

#if DEBUG
nonisolated enum CollectionSample {
    static func write(to root: URL, now: Date) throws {
        let tasks = [
            ("Find a quieter reading layout", "pending", "high", "Compare a narrow reading column with properties beside it."),
            ("Choose the first three collections", "pending", "medium", "Start with the places used every day."),
            ("Test the new item flow", "in_progress", "high", "Try an empty note, a task and an item with required fields."),
            ("Give the board room to breathe", "in_progress", "medium", "Compare comfortable cards with a compact layout."),
            ("Review the source information", "blocked", "medium", "Waiting for a source sample with an author and publication date."),
            ("Keep the view picker in one place", "completed", "high", "Switch views without moving the surrounding controls."),
            ("Try a weekly planning view", "someday", "low", "Keep undated items visible so nothing disappears."),
            ("Decide where this belongs", "", "low", "An item without a status still needs a place on the board.")
        ]
        for (title, status, priority, body) in tasks {
            try write(title, type: "aic.ticket.task", folder: "Board", properties: "priority: \(priority)\n" + (status.isEmpty ? "" : "status: \(status)\n"), body: body, root: root)
        }
        let sessions = [("Morning review", 0, 9), ("Reader layout workshop", 0, 11), ("Collection planning", 1, 10), ("Board interaction review", 2, 14), ("Look back at the week", -1, 16)]
        for (title, offset, hour) in sessions {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            try write(title, type: "aic.agent.session", folder: "Agenda", properties: "starts_at: \(date.ISO8601Format())\n", body: "A sample planning session. Open this page from the agenda and return without losing your place.", root: root)
        }
        try write("Schedule the next comparison", type: "aic.agent.session", folder: "Agenda", properties: "", body: "This session has no date yet. It remains visible below the dated sessions.", root: root)
    }

    private static func write(_ title: String, type: String, folder: String, properties: String, body: String, root: URL) throws {
        let directory = root.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = "---\ntype: \(type)\ntitle: \(title)\n\(properties)---\n\n# \(title)\n\n\(body)\n"
        try Data(text.utf8).write(to: directory.appending(path: title + ".md"))
    }
}
#endif
