import Foundation

/// The notes the app starts with until it has storage.
extension NoteLibrary {
    static func sample(now: @escaping () -> Date = Date.init) -> NoteLibrary {
        let work = Folder(name: "Work")
        let home = Folder(name: "Home")
        let personal = Folder(name: "Personal")
        let reading = Folder(name: "Reading")
        let reference = now()
        let calendar = Calendar.current

        /// Never later than now, so a note written "this morning" is not in the future before breakfast.
        func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: reference) ?? reference
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return min(date, reference)
        }

        func note(
            _ body: String,
            _ folder: Folder? = nil,
            daysAgo: Int,
            hour: Int,
            minute: Int = 0,
            editedDaysAgo: Int? = nil,
            pinned: Bool = false,
            deleted: Bool = false
        ) -> Note {
            Note(
                body: body,
                created: date(daysAgo: daysAgo, hour: hour, minute: minute),
                modified: editedDaysAgo.map { date(daysAgo: $0, hour: hour + 1, minute: minute) },
                folderID: folder?.id,
                isPinned: pinned,
                deleted: deleted ? date(daysAgo: 2, hour: 10) : nil
            )
        }

        let notes = [
            note(kitchenQuotes, home, daysAgo: 0, hour: 9, minute: 12, pinned: true),
            note(gardenIdeas, daysAgo: 0, hour: 7, minute: 55),
            note(weeklyReview, work, daysAgo: 0, hour: 8, minute: 30),
            note(accountant, daysAgo: 1, hour: 16, minute: 40),
            note(readingList, reading, daysAgo: 1, hour: 21, minute: 5, pinned: true),
            note(podcastIdea, daysAgo: 1, hour: 12, minute: 20),
            note(lisbon, personal, daysAgo: 3, hour: 19, minute: 20),
            note(designReview, work, daysAgo: 4, hour: 11),
            note(recipes, home, daysAgo: 5, hour: 18, minute: 30),
            note(bikeService, personal, daysAgo: 6, hour: 8, minute: 45),
            note(hiringLoop, work, daysAgo: 9, hour: 14, editedDaysAgo: 4),
            note(usefulCommands, work, daysAgo: 12, hour: 10, minute: 15),
            note(boilerManual, home, daysAgo: 18, hour: 20),
            note(designOfEverydayThings, reading, daysAgo: 24, hour: 21, minute: 10, editedDaysAgo: 2),
            note(giftIdeas, personal, daysAgo: 40, hour: 13),
            note(quarterlyPlanning, work, daysAgo: 55, hour: 9, minute: 30, editedDaysAgo: 1),
            note(runningPlan, personal, daysAgo: 80, hour: 7),
            note(patternLanguage, reading, daysAgo: 200, hour: 21),
            note(movingChecklist, home, daysAgo: 420, hour: 10),
            note(oldPackingList, personal, daysAgo: 30, hour: 9, deleted: true),
            note(draftAgenda, work, daysAgo: 15, hour: 17, deleted: true),
        ]
        return NoteLibrary(notes: notes, folders: [work, home, personal, reading], now: now)
    }
}

private let kitchenQuotes = """
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

private let gardenIdeas = """
# Garden ideas

Raised beds along the south fence, and somewhere to sit in the evening sun.

- Two beds, 1.2 m wide
- Gravel path between them
- Climbing roses on the back wall
"""

private let weeklyReview = """
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

private let accountant = """
# Call with the accountant

Questions to raise before the end of the quarter.

- [ ] Confirm the VAT return date
- [x] Send last year's receipts
- [ ] Ask about the pension contribution
"""

private let readingList = """
# Reading list

- [x] The Design of Everyday Things
- [ ] A Pattern Language
- [ ] Thinking in Systems
- [ ] The Mythical Man-Month
"""

private let podcastIdea = """
Podcast idea: short episodes on the history of everyday objects. The paperclip, the zip, the pencil.
"""

private let lisbon = """
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

private let designReview = """
# Design review

Keep the list pane calm. Fewer badges, clearer dates.

1. Dates on the right, never wrapped
2. Previews at two lines
3. One accent, used for selection only

> If it needs explaining, it is not finished.
"""

private let recipes = """
# Recipes to try

- Slow-roast tomatoes
- A proper ragù
- Lemon and thyme chicken
    - Needs a good pan
    - Serve with greens
"""

private let bikeService = """
# Bike service

Booked for Saturday morning. Ask them to check the rear brake and replace the chain if it has stretched.
"""

private let hiringLoop = """
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

private let usefulCommands = """
# Useful commands

Short commands worth keeping to hand.

```sh
git log --oneline -10
git switch -c feature/name
```

Use `git restore` rather than `git checkout` for files.
"""

private let boilerManual = """
# Boiler

Model and settings, so nobody has to find the manual again.

- Pressure should sit between **1.0** and **1.5** bar
- Service due every autumn
- Reset button is behind the flap, bottom left
"""

private let designOfEverydayThings = """
# The Design of Everyday Things

Notes as I read.

- *Affordances* say what is possible; *signifiers* say where to act.
- Feedback has to be immediate, or it is not feedback.
- When people make mistakes, the design is usually at fault.

See also [the revised edition](https://en.wikipedia.org/wiki/The_Design_of_Everyday_Things).
"""

private let giftIdeas = """
# Gift ideas

- A good bread knife
- Tickets to the autumn concert series
- A print from the market stall by the station
"""

private let quarterlyPlanning = """
# Quarterly planning

Three outcomes, not ten.

1. Ship the new onboarding
2. Halve the time to first value
3. Retire the old admin screens

---

Everything else is a maybe.
"""

private let runningPlan = """
# Running plan

| Week | Tuesday | Thursday | Sunday |
| --- | --- | --- | --- |
| 1 | 5 km easy | 6 × 400 m | 8 km |
| 2 | 5 km easy | 3 × 1 km | 10 km |
| 3 | 6 km easy | Tempo 20 min | 12 km |
"""

private let patternLanguage = """
# A Pattern Language

Pattern 159, light on two sides of every room. Worth remembering for the kitchen.
"""

private let movingChecklist = """
# Moving checklist

- [x] Redirect post
- [x] Transfer the broadband
- [x] Update the electoral roll
- [x] Meter readings on the day
"""

private let oldPackingList = """
# Old packing list

Superseded by the Lisbon note.
"""

private let draftAgenda = """
# Draft agenda

An earlier version of the planning agenda.
"""
