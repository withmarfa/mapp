#if DEBUG
import Foundation
import Marfa
import MarfaTesting
import struct MarfaCore.KeptFetch

/// A Marfa library to try the app with, held in memory by marfa-swift's fake working copy, for the UI tests and
/// screenshots. A debug build launched with `-MAPPSampleLibrary` connects to it as if to a server. Nothing ships
/// with it, and nothing it holds outlives the run.
nonisolated enum SampleLibrary {
    static let flag = "-MAPPSampleLibrary"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    /// With the sample flag, starts with no server set instead of the sample, as a first launch does, still clear of
    /// the person's saved server and Keychain.
    static var startsUnconfigured: Bool { ProcessInfo.processInfo.arguments.contains("-MAPPSampleUnconfigured") }

    /// Also asks for the tasks and events a board and a timeline show.
    static var withCollections: Bool { ProcessInfo.processInfo.arguments.contains("-MAPPCollectionSample") }

    /// The address the sample answers at. Nothing is ever sent to it.
    static let connection: MarfaConnection = {
        do {
            return try MarfaConnection(address: "https://sample.marfa.invalid")
        } catch {
            preconditionFailure("The sample address was refused: \(error)")
        }
    }()

    static let name = "Sample Library"

    /// Opens the sample in place of a server's copy: its own items and edges, or those given, as for a preview.
    static func open(
        _ connection: MarfaConnection, items given: [Marfa.Item]? = nil, edges: [Marfa.Edge]? = nil, now: Date = .now
    ) -> MarfaSource {
        let fake = WorkingCopy.fake(
            items: given ?? items(now: now, tasksAndEvents: withCollections),
            edges: edges ?? (given == nil ? memberships(now: now) : []), itemTypes: itemTypes,
            edgeTypes: edgeTypes, views: views)
        let server = SampleServer(copy: fake.copy)
        let source = MarfaSource(copy: fake.copy, connection: connection, reading: server, refreshing: server)
        source.events.yield(.paint)
        return source
    }

    // MARK: Catalogue

    /// The built-in types the sample uses, as Marfa's catalogue defines them, and one of its own.
    static let itemTypes: [Marfa.ItemType] = [
        ItemType(
            id: "core.note", label: "Note", description: "A piece of writing.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.note"),
                TypeField(name: "body", type: "string", declaredBy: "core.note"),
            ], titleField: "title", bodyField: "body"),
        ItemType(
            id: "core.task", label: "Task", description: "Something to do.",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.task"),
                TypeField(name: "body", type: "string", declaredBy: "core.task"),
                TypeField(
                    name: "status", type: "status", declaredBy: "core.task",
                    definition: ["status_values": [
                        ["value": "pending", "group": "not_started"], ["value": "in_progress", "group": "in_progress"],
                        ["value": "completed", "group": "completed"], ["value": "canceled", "group": "canceled"],
                    ]]),
                TypeField(
                    name: "priority", type: "enum", declaredBy: "core.task",
                    definition: ["enum_values": ["low", "medium", "high"]]),
                TypeField(name: "due_at", type: "datetime", declaredBy: "core.task"),
                TypeField(
                    name: "assignees", type: "array", declaredBy: "core.task",
                    definition: ["items_type": "object", "items_fields": [
                        "name": ["type": "string"], "email": ["type": "email"],
                    ]]),
            ], titleField: "title", bodyField: "body"),
        ItemType(
            id: "core.event", label: "Event", description: "Something that happens at a time.",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.event"),
                TypeField(name: "body", type: "string", declaredBy: "core.event"),
                TypeField(name: "starts_at", type: "datetime", declaredBy: "core.event"),
                TypeField(
                    name: "attendees", type: "array", declaredBy: "core.event",
                    definition: ["items_type": "object", "items_fields": [
                        "name": ["type": "string"], "email": ["type": "email"],
                        "response": ["type": "enum", "enum_values": ["needs_action", "accepted", "declined", "tentative"]],
                    ]]),
            ], titleField: "title", bodyField: "body"),
        ItemType(
            id: "core.entity.person", label: "Person", description: "Someone you know.",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.entity"),
                TypeField(name: "job_title", type: "string", declaredBy: "core.entity.person"),
                TypeField(
                    name: "emails", type: "array", declaredBy: "core.entity",
                    definition: ["items_type": "object", "items_fields": [
                        "value": ["type": "email", "required": true], "label": ["type": "string"],
                    ]]),
                TypeField(
                    name: "phones", type: "array", declaredBy: "core.entity",
                    definition: ["items_type": "object", "items_fields": [
                        "value": ["type": "string", "required": true], "label": ["type": "string"],
                    ]]),
                TypeField(
                    name: "addresses", type: "array", declaredBy: "core.entity",
                    definition: ["items_type": "object", "items_fields": [
                        "label": ["type": "string"], "street_address": ["type": "string"], "locality": ["type": "string"],
                        "region": ["type": "string"], "postal_code": ["type": "string"], "country": ["type": "string"],
                    ]]),
            ], titleField: "title"),
        ItemType(
            id: "core.media", label: "Media", description: "Something to read, watch or play.",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.media"),
                TypeField(
                    name: "progress", type: "status", declaredBy: "core.media",
                    definition: ["status_values": [
                        ["value": "wishlist", "group": "not_started"], ["value": "in_progress", "group": "in_progress"],
                        ["value": "finished", "group": "completed"], ["value": "abandoned", "group": "canceled"],
                    ]]),
                TypeField(name: "rating", type: "integer", declaredBy: "core.media", definition: ["minimum": 1, "maximum": 5]),
            ], titleField: "title"),
        ItemType(
            id: "sample.project", label: "Project", description: "Work with an outcome.", parent: "core.note",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.note"),
                TypeField(name: "body", type: "string", declaredBy: "core.note"),
                TypeField(name: "description", type: "string", declaredBy: "sample.project"),
            ], titleField: "title", bodyField: "body"),
        ItemType(
            id: "core.collection", label: "Collection",
            description: "Items of any type that you gather together. Members join it through the in-collection edge, and it can hold any item but another container.",
            fields: [
                TypeField(name: "title", type: "string", required: true, description: "Name of the collection", declaredBy: "core.collection"),
                TypeField(
                    name: "description", type: "string", description: "What the collection gathers", declaredBy: "core.collection"),
            ], titleField: "title", bodyField: "description", roles: ["container"]),
    ]

    static let edgeTypes: [Marfa.EdgeType] = [
        EdgeType(
            id: "parent-of", label: "Children", reverseLabel: "Parent", description: "Files one item under another.",
            cardinality: "one-to-many", reverseName: "child-of", writtenAt: .target, cascadeOnDelete: "cascade",
            shipped: true),
        EdgeType(id: "about", label: "About", reverseLabel: "Subject of", cardinality: "many-to-many", shipped: true),
        EdgeType(id: "references", label: "References", reverseLabel: "Referenced by", cardinality: "many-to-many", shipped: true),
        EdgeType(
            id: "supersedes", label: "Supersedes", reverseLabel: "Superseded by", cardinality: "one-to-one", shipped: true),
        EdgeType(
            id: "attached-to", label: "Attached to", reverseLabel: "Attachments", cardinality: "many-to-one", reverseName: "has-attachment",
            shipped: true),
        EdgeType(
            id: "in-collection", label: "In collection", reverseLabel: "Contents",
            description: "Source item is a member of the target container.", cardinality: "many-to-many",
            targetTypeConstraints: ["role:container"],
            properties: [TypeField(name: "position", type: "number", description: "Ordering within the collection (1-based).", declaredBy: "in-collection")],
            shipped: true),
    ]

    /// The sample's catalogue as the app reads it.
    static var catalogue: Catalogue { MarfaMapping.catalogue(itemTypes: itemTypes, edgeTypes: edgeTypes) }

    // MARK: Views

    /// Views as another app might have saved them, held by the fake copy and read through it like a real copy's.
    /// The fake cannot judge a query's `filter`, so each asks only for types, state, order and grouping.
    static let views: [SavedView] = [
        SavedView(
            id: "view-recent-notes",
            version: 1,
            settings: ViewSettings(
                title: "Recent Notes",
                query: ViewQuery(types: ["core.note"], states: [.active]),
                sort: [ViewSort(by: "updated_at", direction: .descending)])),
        SavedView(
            id: "view-tasks-by-priority",
            version: 1,
            settings: ViewSettings(
                title: "Tasks by Priority",
                query: ViewQuery(types: ["core.task"], states: [.active]),
                sort: [ViewSort(by: "updated_at", direction: .descending)],
                group: ViewGrouping(by: "properties.priority"))),
    ]

    // MARK: Items

    static func items(now: Date, tasksAndEvents: Bool) -> [Marfa.Item] {
        let calendar = Calendar.current
        /// Never later than now, so a note written "this morning" is not in the future before breakfast.
        func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return min(date, now)
        }

        var rows: [Marfa.Item] = []
        func note(
            _ id: String, _ text: String, inbox: Bool = false, daysAgo: Int, hour: Int, minute: Int = 0,
            editedDaysAgo: Int? = nil, favorite: Bool = false, trashed: Bool = false
        ) {
            let (title, body) = split(text)
            var properties: JSONObject = ["body": .string(body)]
            if let title { properties["title"] = .string(title) }
            let created = date(daysAgo: daysAgo, hour: hour, minute: minute)
            let edited = editedDaysAgo.map { date(daysAgo: $0, hour: hour + 1, minute: minute) } ?? created
            rows.append(row(
                id, type: "core.note", properties: properties, tier: inbox ? .feed : .library,
                state: trashed ? .trashed : .active, created: created, edited: edited,
                tags: favorite ? [ItemTag.favorite] : []))
        }

        note("kitchen-quotes", kitchenQuotes, daysAgo: 0, hour: 9, minute: 12, favorite: true)
        note("garden-ideas", gardenIdeas, inbox: true, daysAgo: 0, hour: 7, minute: 55)
        note("weekly-review", weeklyReview, daysAgo: 0, hour: 8, minute: 30)
        note("accountant", accountant, inbox: true, daysAgo: 1, hour: 16, minute: 40)
        note("reading-list", readingList, daysAgo: 1, hour: 21, minute: 5, favorite: true)
        note("podcast-idea", podcastIdea, inbox: true, daysAgo: 1, hour: 12, minute: 20)
        note("lisbon", lisbon, daysAgo: 3, hour: 19, minute: 20)
        note("design-review", designReview, daysAgo: 4, hour: 11)
        note("recipes", recipes, daysAgo: 5, hour: 18, minute: 30)
        note("bike-service", bikeService, daysAgo: 6, hour: 8, minute: 45)
        note("hiring-loop", hiringLoop, daysAgo: 9, hour: 14, editedDaysAgo: 4)
        note("useful-commands", usefulCommands, daysAgo: 12, hour: 10, minute: 15)
        note("boiler", boilerManual, daysAgo: 18, hour: 20)
        note("design-of-everyday-things", designOfEverydayThings, daysAgo: 24, hour: 21, minute: 10, editedDaysAgo: 2)
        note("gift-ideas", giftIdeas, daysAgo: 40, hour: 13)
        note("quarterly-planning", quarterlyPlanning, daysAgo: 55, hour: 9, minute: 30, editedDaysAgo: 1)
        note("running-plan", runningPlan, daysAgo: 80, hour: 7)
        note("pattern-language", patternLanguage, daysAgo: 200, hour: 21)
        note("moving-checklist", movingChecklist, daysAgo: 420, hour: 10)
        note("old-packing-list", oldPackingList, daysAgo: 30, hour: 9, trashed: true)
        note("draft-agenda", draftAgenda, daysAgo: 15, hour: 17, trashed: true)
        for collection in collections {
            let created = date(daysAgo: collection.daysAgo, hour: 9)
            rows.append(row(
                collection.id, type: "core.collection",
                properties: ["title": .string(collection.title), "description": .string(collection.description)],
                created: created, edited: created))
        }

        guard tasksAndEvents else { return rows }
        for (index, task) in tasks.enumerated() {
            var properties: JSONObject = [
                "title": .string(task.title), "body": .string(task.body), "priority": .string(task.priority),
            ]
            if !task.status.isEmpty { properties["status"] = .string(task.status) }
            if index == 0 { properties["assignees"] = [["name": "Ruth Okonjo", "email": "ruth@example.com"], ["email": "sam@example.com"]] }
            let created = date(daysAgo: index + 1, hour: 10)
            rows.append(row("task-\(index + 1)", type: "core.task", properties: properties, created: created, edited: created))
        }
        for (index, session) in sessions.enumerated() {
            var properties: JSONObject = ["title": .string(session.title), "body": .string(session.body)]
            if let offset = session.day {
                let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
                let start = calendar.date(bySettingHour: session.hour, minute: 0, second: 0, of: day) ?? day
                properties["starts_at"] = .string(stamp(start))
            }
            if index == 0 {
                properties["attendees"] = [
                    ["name": "Ruth Okonjo", "email": "ruth@example.com", "response": "accepted"],
                    ["email": "sam@example.com", "response": "needs_action"],
                ]
            }
            let created = date(daysAgo: 7, hour: 9)
            rows.append(row("event-\(index + 1)", type: "core.event", properties: properties, created: created, edited: created))
        }
        let met = date(daysAgo: 20, hour: 9)
        rows.append(row("person-1", type: "core.entity.person", properties: [
            "title": "Ruth Okonjo", "job_title": "Editor",
            "emails": [["value": "ruth@example.com", "label": "work"], ["value": "ruth@home.example", "label": "home"]],
            "phones": [["value": "+44 20 7946 0000"]],
            "addresses": [["label": "work", "street_address": "1 High Street", "locality": "London", "country": "GB"]],
        ], created: met, edited: met))
        rows.append(row("media-1", type: "core.media", properties: [
            "title": "The Design of Everyday Things", "progress": "in_progress", "rating": 5,
        ], created: met, edited: met))
        return rows
    }

    /// The sample's collections. Home orders its members by position; Reading gives none, so it lists them by title.
    static let collections: [(id: String, title: String, description: String, daysAgo: Int, members: [String], positioned: Bool)] = [
        ("collection-home", "Home", "Looking after the flat.", 30, ["boiler", "bike-service", "moving-checklist"], true),
        ("collection-reading", "Reading", "Books and ideas worth keeping.", 60,
         ["reading-list", "pattern-language", "design-of-everyday-things"], false),
    ]

    /// Each sample collection's members, through `in-collection`.
    static func memberships(now: Date) -> [Marfa.Edge] {
        collections.flatMap { collection in
            collection.members.enumerated().map { index, member in
                Marfa.Edge(
                    id: "\(collection.id)-\(member)", sourceId: member, targetId: collection.id, edgeType: "in-collection",
                    properties: collection.positioned ? ["position": .number(Double(index + 1))] : [:], version: 1,
                    createdAt: stamp(now), updatedAt: stamp(now))
            }
        }
    }

    /// A note's heading is its title, and the text below it its body. A note with no heading has no title.
    private static func split(_ text: String) -> (title: String?, body: String) {
        guard text.hasPrefix("# ") else { return (nil, text) }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = String(lines[0].dropFirst(2))
        let body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .newlines) : ""
        return (title, body)
    }

    static func row(
        _ id: String, type: String, properties: JSONObject, tier: Marfa.Tier = .library,
        state: Marfa.ItemState = .active, created: Date, edited: Date, tags: [String] = []
    ) -> Marfa.Item {
        Marfa.Item(
            id: id, type: type, properties: properties, state: state, tier: tier, version: 1, schemaVersion: 1,
            source: "sample", sourceId: nil, occurredAt: stamp(created), createdAt: stamp(created),
            updatedAt: stamp(edited), tags: tags)
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// The sample's server: always reachable, its copy always whole, so the library shows no fill and its writes drain
/// at once. The fake copy answers the drain.
private nonisolated struct SampleServer: MarfaReading, MarfaRefreshing {
    let copy: WorkingCopy

    private var whole: Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    func status() async throws -> Status { whole }
    func items() async throws -> Rows<Marfa.Item> { try await MarfaRead(copy: copy).items() }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
        try await MarfaRead(copy: copy).edges(ofTypes: types)
    }
    func edges(touching id: String) async throws -> [Marfa.Edge] { try await MarfaRead(copy: copy).edges(touching: id) }
    func items(_ ids: [String]) async throws -> Rows<Marfa.Item> { try await MarfaRead(copy: copy).items(ids) }
    func edges(_ ids: [String]) async throws -> [Marfa.Edge] { try await MarfaRead(copy: copy).edges(ids) }
    func changes(since cursor: ChangeCursor?, most: Int) async throws -> CopyChanges {
        try await MarfaRead(copy: copy).changes(since: cursor, most: most)
    }
    func views() async throws -> Rows<LibraryView> { try await MarfaRead(copy: copy).views() }
    func items(inView id: String) async throws -> [Marfa.Item] { try await MarfaRead(copy: copy).items(inView: id) }
    func links(in id: String) async throws -> BodyLinks { try await MarfaRead(copy: copy).links(in: id) }
    func links(in ids: [String]) async throws -> [String: BodyLinks] { try await MarfaRead(copy: copy).links(in: ids) }

    func readStatus() async throws -> Status { whole }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        throw FakeCopyError.unsupported(call: "hydrate")
    }
    func catchUp() async throws {}
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
}

nonisolated private let tasks: [(title: String, status: String, priority: String, body: String)] = [
    ("Find a quieter reading layout", "pending", "high", "Compare a narrow reading column with properties beside it."),
    ("Choose the first three collections", "pending", "medium", "Start with the places used every day."),
    ("Test the new item flow", "in_progress", "high", "Try an empty note, a task and an item with required fields."),
    ("Give the board room to breathe", "in_progress", "medium", "Compare comfortable cards with a compact layout."),
    ("Review the source information", "pending", "medium", "Waiting for a source sample with an author and publication date."),
    ("Keep the view picker in one place", "completed", "high", "Switch views without moving the surrounding controls."),
    ("Try a weekly planning view", "canceled", "low", "Keep undated items visible so nothing disappears."),
    ("Decide where this belongs", "", "low", "An item without a status still needs a place on the board."),
]

nonisolated private let sessions: [(title: String, day: Int?, hour: Int, body: String)] = [
    ("Morning review", 0, 9, "A sample planning session. Open this page from the timeline and return without losing your place."),
    ("Reader layout workshop", 0, 11, "A sample planning session. Open this page from the timeline and return without losing your place."),
    ("Collection planning", 1, 10, "A sample planning session. Open this page from the timeline and return without losing your place."),
    ("Board interaction review", 2, 14, "A sample planning session. Open this page from the timeline and return without losing your place."),
    ("Look back at the week", -1, 16, "A sample planning session. Open this page from the timeline and return without losing your place."),
    ("Schedule the next comparison", nil, 9, "This session has no date yet. It remains visible below the dated sessions."),
]

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
#endif
