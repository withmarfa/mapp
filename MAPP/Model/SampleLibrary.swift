import Foundation

/// Notes to try the app with, written as files into a folder of the app's own, for the UI tests and screenshots.
/// Nothing ships with them.
nonisolated enum SampleLibrary {
    /// Writes the sample notes into an empty folder: each note as a file named after its first line, in its
    /// folder, favorited in its front matter, with the dates it was written and edited. Two are then trashed.
    static func write(to root: URL, bin: URL, now: Date = .now) throws {
        let files = FileManager()
        try? files.removeItem(at: root)
        try? files.removeItem(at: bin)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let calendar = Calendar.current

        /// Never later than now, so a note written "this morning" is not in the future before breakfast.
        func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return min(date, now)
        }

        var trashed: [String] = []
        func note(
            _ body: String,
            _ folder: String? = nil,
            daysAgo: Int,
            hour: Int,
            minute: Int = 0,
            editedDaysAgo: Int? = nil,
            favorite: Bool = false,
            deleted: Bool = false
        ) throws {
            var file = NoteFile(text: body + "\n")
            if favorite { try file.setFavorite(true) }
            let name = NoteText.fileName(for: body)
            let path = folder.map { "\($0)/\(name).md" } ?? "\(name).md"
            let url = root.appending(path: path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: url)
            let created = date(daysAgo: daysAgo, hour: hour, minute: minute)
            let modified = editedDaysAgo.map { date(daysAgo: $0, hour: hour + 1, minute: minute) } ?? created
            try files.setAttributes([.creationDate: created, .modificationDate: modified], ofItemAtPath: url.path)
            if deleted { trashed.append(path) }
        }

        try note(kitchenQuotes, "Home", daysAgo: 0, hour: 9, minute: 12, favorite: true)
        var gardenBody = gardenIdeas
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MAPPGallerySampleImages"),
           let photo = Bundle.main.url(forResource: "item-preview-photo", withExtension: "png") {
            let destination = root.appending(path: "Attachments/Gallery.png")
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: photo).write(to: destination)
            gardenBody += "\n\n![Garden](Attachments/Gallery.png)\n"
        }
        #endif
        try note(gardenBody, daysAgo: 0, hour: 7, minute: 55)
        try note(weeklyReview, "Work", daysAgo: 0, hour: 8, minute: 30)
        try note(accountant, daysAgo: 1, hour: 16, minute: 40)
        try note(readingList, "Reading", daysAgo: 1, hour: 21, minute: 5, favorite: true)
        try note(podcastIdea, daysAgo: 1, hour: 12, minute: 20)
        try note(lisbon, "Personal", daysAgo: 3, hour: 19, minute: 20)
        try note(designReview, "Work", daysAgo: 4, hour: 11)
        try note(recipes, "Home", daysAgo: 5, hour: 18, minute: 30)
        try note(bikeService, "Personal", daysAgo: 6, hour: 8, minute: 45)
        try note(hiringLoop, "Work", daysAgo: 9, hour: 14, editedDaysAgo: 4)
        try note(usefulCommands, "Work", daysAgo: 12, hour: 10, minute: 15)
        try note(boilerManual, "Home", daysAgo: 18, hour: 20)
        try note(designOfEverydayThings, "Reading", daysAgo: 24, hour: 21, minute: 10, editedDaysAgo: 2)
        try note(giftIdeas, "Personal", daysAgo: 40, hour: 13)
        try note(quarterlyPlanning, "Work", daysAgo: 55, hour: 9, minute: 30, editedDaysAgo: 1)
        try note(runningPlan, "Personal", daysAgo: 80, hour: 7)
        try note(patternLanguage, "Reading", daysAgo: 200, hour: 21)
        try note(movingChecklist, "Home", daysAgo: 420, hour: 10)
        try note(oldPackingList, "Personal", daysAgo: 30, hour: 9, deleted: true)
        try note(draftAgenda, "Work", daysAgo: 15, hour: 17, deleted: true)

        let store = FolderStore(root: root, bin: bin)
        for path in trashed {
            store.perform(.trash(path: path, id: UUID(), date: date(daysAgo: 2, hour: 10)))
        }
        store.drain()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MAPPCollectionSample") {
            try CollectionSample.write(to: root, now: now)
        }
        #endif
    }
}

nonisolated private let kitchenQuotes = """
# Kitchen quotes

Three quotes in so far. Waiting on the fourth before deciding.

| Supplier | Quote | Lead time | Notes |
| --- | ---: | --- | --- |
| Harbour Joinery | £14,200 | 8 weeks | Includes worktops |
| Oak & Iron | £11,850 | 12 weeks | Worktops extra |
| Northside Kitchens | £13,400 | 6 weeks | Fits in-house |

## Next

- [x] Measure the alcove
- [ ] Ask Oak & Iron about worktop pricing
- [ ] Book a second site visit

> Whatever we choose, the sink stays under the window.
"""

nonisolated private let gardenIdeas = """
# Garden ideas

Raised beds along the south fence, and somewhere to sit in the evening sun.

- Two beds, 1.2 m wide
- Gravel path between them
- Climbing roses on the back wall
"""

nonisolated private let weeklyReview = """
# Weekly review

What moved, what is stuck, what to drop.

## Moved

- Onboarding flow is with the team for review
- Supplier contract signed

## Stuck

- Waiting on legal for the data agreement

## Drop

- The second analytics dashboard
"""

nonisolated private let accountant = """
# Call with the accountant

Questions to raise before the end of the quarter.

- [ ] Confirm the VAT return date
- [x] Send last year's receipts
- [ ] Ask about the pension contribution
"""

nonisolated private let readingList = """
# Reading list

- [x] The Design of Everyday Things
- [ ] A Pattern Language
- [ ] Thinking in Systems
- [ ] The Mythical Man-Month
"""

nonisolated private let podcastIdea = """
Podcast idea: short episodes on the history of everyday objects. The paperclip, the zip, the pencil.
"""

nonisolated private let lisbon = """
# Trip to Lisbon

Three days in October. Flights booked, hotel still to choose.

| Day | Plan |
| --- | --- |
| Thursday | Arrive, dinner in Alfama |
| Friday | Belém in the morning, LX Factory after |
| Saturday | Train to Sintra |

## Packing

- [ ] Adapter
- [x] Walking shoes
- [ ] Rain jacket
"""

nonisolated private let designReview = """
# Design review

Keep the list pane calm. Fewer badges, clearer dates.

1. Dates on the right, never wrapped
2. Previews at two lines
3. One accent, used for selection only

> If it needs explaining, it is not finished.
"""

nonisolated private let recipes = """
# Recipes to try

- Slow-roast tomatoes
- A proper ragù
- Lemon and thyme chicken
    - Needs a good pan
    - Serve with greens
"""

nonisolated private let bikeService = """
# Bike service

Booked for Saturday morning. Ask them to check the rear brake and replace the chain if it has stretched.
"""

nonisolated private let hiringLoop = """
# Hiring loop

Four stages, one week end to end.

| Stage | Who | Length |
| :--- | :---: | ---: |
| Intro call | Hiring manager | 30 min |
| Work sample | Two engineers | 90 min |
| Team conversation | Three from the team | 45 min |
| Close | Hiring manager | 30 min |

Keep the work sample close to the real job. No puzzles.
"""

nonisolated private let usefulCommands = """
# Useful commands

Short commands worth keeping to hand.

```sh
git log --oneline -10
git switch -c feature/name
```

Use `git restore` rather than `git checkout` for files.
"""

nonisolated private let boilerManual = """
# Boiler

Model and settings, so nobody has to find the manual again.

- Pressure should sit between **1.0** and **1.5** bar
- Service due every autumn
- Reset button is behind the flap, bottom left
"""

nonisolated private let designOfEverydayThings = """
# The Design of Everyday Things

Notes as I read.

- *Affordances* say what is possible; *signifiers* say where to act.
- Feedback has to be immediate, or it is not feedback.
- When people make mistakes, the design is usually at fault.

See also [the revised edition](https://en.wikipedia.org/wiki/The_Design_of_Everyday_Things).

## The psychology of everyday actions

- The gulf of execution: working out how to do what you want.
- The gulf of evaluation: working out whether it happened.
- Seven stages of action: goal, plan, specify, perform, perceive, interpret, compare.
- Most everyday actions run on the lower, subconscious stages.

## Knowledge in the head and in the world

- Precise behaviour can come from imprecise knowledge, when the world holds the rest.
- Constraints narrow the choices: physical, cultural, semantic and logical.
- Natural mapping puts controls where their effects are.
- A good design makes the right action the obvious one.

## Knowing what to do

- Forcing functions stop the wrong action before it happens.
- Interlocks, lock-ins and lockouts are all forcing functions.
- Conventions are powerful and slow to change.
- Standardise only when nothing else works.

## Human error? No, bad design

- Slips are errors of action; mistakes are errors of intention.
- Design for error: make it easy to see, easy to undo.
- Checklists work when they are short and in the right place.
- Root cause analysis stops too early when it stops at a person.

## The design challenge

- Solve the right problem: observe, ideate, prototype, test.
- Human-centred design is iterative by nature.
- Complexity is fine; confusion is not.
- Good design is noticed least when it works best.
"""

nonisolated private let giftIdeas = """
# Gift ideas

- A good bread knife
- Tickets to the autumn concert series
- A print from the market stall by the station
"""

nonisolated private let quarterlyPlanning = """
# Quarterly planning

Three outcomes, not ten.

1. Ship the new onboarding
2. Halve the time to first value
3. Retire the old admin screens

---

Everything else is a maybe.
"""

nonisolated private let runningPlan = """
# Running plan

| Week | Tuesday | Thursday | Sunday |
| --- | --- | --- | --- |
| 1 | 5 km easy | 6 × 400 m | 8 km |
| 2 | 5 km easy | 3 × 1 km | 10 km |
| 3 | 6 km easy | Tempo 20 min | 12 km |
"""

nonisolated private let patternLanguage = """
# A Pattern Language

Pattern 159, light on two sides of every room. Worth remembering for the kitchen.
"""

nonisolated private let movingChecklist = """
# Moving checklist

- [x] Redirect post
- [x] Transfer the broadband
- [x] Update the electoral roll
- [x] Meter readings on the day
"""

nonisolated private let oldPackingList = """
# Old packing list

Superseded by the Lisbon note.
"""

nonisolated private let draftAgenda = """
# Draft agenda

An earlier version of the planning agenda.
"""
