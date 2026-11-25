#if DEBUG
import Foundation
import Marfa

/// Castell Studio, the library the design boards draw: Mira Castell's studio of notes, tasks, bookmarks, highlights, files and
/// messages, kept by apps and connectors. A debug build asks for it with `-MarfaMacCastellStudio`, for the 1,205 items the
/// boards count, or with `-MarfaMacHeavySample`, for about fifty thousand to time the app on. Everything is a pure function of
/// the day it is asked on, so two runs make the same library.
///
/// The Library counts the boards state hold here: 1,205 items, and 223 notes, 103 tasks, 168 bookmarks, 130 highlights and 149
/// files, 69 in the Feed, 4 collections and 7 sources whose counts add to the Library's. The sources count Library items only,
/// as the Sources board does. The heavy library holds 48,312 Library items with the sidebar's counts for its types.
nonisolated enum SampleCastell {
    nonisolated enum Size: Sendable { case studio, heavy }

    static let flag = "-MarfaMacCastellStudio"
    static let heavyFlag = "-MarfaMacHeavySample"

    /// The size of library the launch asked for with the sample flag, if any.
    static var requested: Size? {
        guard SampleLibrary.isRequested else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(heavyFlag) ? .heavy : arguments.contains(flag) ? .studio : nil
    }

    nonisolated struct World: Sendable {
        var items: [Marfa.Item]
        var edges: [Marfa.Edge]
    }

    // MARK: Sources

    nonisolated enum Code {
        static let marfaForMac = "oauth:marfa-for-mac"
        static let raycast = "oauth:raycast"
        static let claude = "oauth:claude"
        static let studioFolder = "studio-folder"
        static let readwise = "readwise"
        static let rss = "rss"
        static let github = "github"
        static let calendar = "google-calendar"
        static let contacts = "contacts"
        static let shortcuts = "shortcuts"
        static let letterboxd = "letterboxd"

        /// What a connector only reads, so its items are held read only. Readwise and Contacts sync both ways.
        static let readOnly: Set<String> = [rss, github, calendar, letterboxd]
    }

    static let sourceInfos: [SourceInfo] = [
        SourceInfo(code: Code.marfaForMac, name: "Marfa for Mac", mark: nil, nameOrigin: .app),
        SourceInfo(code: Code.raycast, name: "Raycast", mark: nil, nameOrigin: .app),
        SourceInfo(code: Code.claude, name: "Claude", mark: nil, nameOrigin: .app),
        SourceInfo(code: Code.studioFolder, name: "Studio folder", mark: nil, nameOrigin: .key),
        SourceInfo(code: Code.readwise, name: "Readwise", mark: nil, nameOrigin: .set),
        SourceInfo(code: Code.rss, name: "RSS", mark: nil, nameOrigin: .set),
        SourceInfo(code: Code.github, name: "GitHub", mark: nil, nameOrigin: .set),
        SourceInfo(code: Code.calendar, name: "Google Calendar", mark: nil, nameOrigin: .set),
        SourceInfo(code: Code.contacts, name: "Contacts", mark: nil, nameOrigin: .set),
        SourceInfo(code: Code.shortcuts, name: "Shortcuts", mark: nil, nameOrigin: .key),
        SourceInfo(code: Code.letterboxd, name: "Letterboxd", mark: nil, nameOrigin: .set),
    ]

    // MARK: Types

    nonisolated enum Kind {
        static let note = "core.note"
        static let task = "core.task"
        static let event = "core.event"
        static let person = "core.entity.person"
        static let place = "core.entity.place"
        static let project = "sample.project"
        static let collection = "core.collection"
        static let bookmark = "core.bookmark"
        static let highlight = "core.highlight"
        static let article = "core.article"
        static let book = "core.book"
        static let message = "core.message"
        static let file = "core.file"
        static let image = "core.file.image"
        static let issue = "github.issue"
        static let pullRequest = "github.pull_request"
        static let media = "core.media"
    }

    /// The types the library holds that the sample's base catalogue and the gallery's do not.
    static let extraTypes: [Marfa.ItemType] = [
        ItemType(
            id: Kind.highlight, label: "Highlight", description: "A passage worth keeping.",
            fields: [
                TypeField(name: "body", type: "string", declaredBy: Kind.highlight),
                TypeField(name: "title", type: "string", declaredBy: Kind.highlight),
            ], titleField: "title", bodyField: "body", icon: "lucide:highlighter"),
        ItemType(
            id: Kind.article, label: "Article", description: "Something written to read.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: Kind.article),
                TypeField(name: "url", type: "string", declaredBy: Kind.article),
                TypeField(name: "body", type: "string", declaredBy: Kind.article),
            ], titleField: "title", bodyField: "body", icon: "lucide:newspaper"),
        ItemType(
            id: Kind.book, label: "Book", description: "A book.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: Kind.book),
                TypeField(name: "body", type: "string", declaredBy: Kind.book),
            ], titleField: "title", bodyField: "body", icon: "lucide:book-open"),
        ItemType(
            id: Kind.message, label: "Message", description: "A message from someone.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: Kind.message),
                TypeField(name: "body", type: "string", declaredBy: Kind.message),
            ], titleField: "title", bodyField: "body", icon: "lucide:message-square"),
        ItemType(
            id: Kind.place, label: "Place", description: "Somewhere you go.", parent: "core.entity",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.entity"),
                TypeField(name: "address", type: "string", declaredBy: Kind.place),
                TypeField(name: "latitude", type: "number", declaredBy: Kind.place),
                TypeField(name: "longitude", type: "number", declaredBy: Kind.place),
            ], titleField: "title", icon: "lucide:map-pin"),
        ItemType(
            id: Kind.issue, label: "GitHub Issue", description: "An issue on GitHub.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: Kind.issue),
                TypeField(name: "body", type: "string", declaredBy: Kind.issue),
                TypeField(
                    name: "status", type: "status", declaredBy: Kind.issue,
                    definition: ["status_values": [
                        ["value": "open", "group": "in_progress"], ["value": "closed", "group": "completed"],
                    ]]),
            ], titleField: "title", bodyField: "body", icon: "lucide:terminal"),
        ItemType(
            id: Kind.pullRequest, label: "GitHub Pull Request", description: "A pull request on GitHub.",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: Kind.pullRequest),
                TypeField(name: "body", type: "string", declaredBy: Kind.pullRequest),
                TypeField(
                    name: "status", type: "status", declaredBy: Kind.pullRequest,
                    definition: ["status_values": [
                        ["value": "open", "group": "in_progress"], ["value": "merged", "group": "completed"],
                        ["value": "closed", "group": "canceled"],
                    ]]),
                TypeField(name: "url", type: "string", declaredBy: Kind.pullRequest),
            ], titleField: "title", bodyField: "body", icon: "lucide:terminal"),
    ]

    /// The catalogue's types for a Castell Studio library: the sample's own, the gallery's file, image and bookmark, and these.
    static var itemTypes: [Marfa.ItemType] {
        SampleLibrary.itemTypes + SampleGallery.types + extraTypes
    }

    // MARK: The source names the sample answers with

    static let sourceNames = SampleSourceNames(infos: sourceInfos)

    // MARK: Making the library

    /// What a library of `size` holds on the day of `now`.
    static func world(_ size: Size, now: Date = .now) -> World {
        var made = Maker(now: now)
        switch size {
        case .studio: made.addStudio()
        case .heavy: made.addHeavy()
        }
        return World(items: made.items, edges: made.edges)
    }

    /// How many active Library items each source wrote, as the Sources board counts.
    static func libraryCounts(of items: [Marfa.Item]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items where item.state == .active && item.tier == .library { counts[item.source, default: 0] += 1 }
        return counts
    }
}

/// The sample's answer to what the server knows of its sources: names, and how many Library items each wrote.
nonisolated struct SampleSourceNames: SourceNameSource {
    let infos: [SourceInfo]

    func sources() async throws(SourceEditFailure) -> [SourceInfo] { infos }

    func counts() async throws(SourceEditFailure) -> [String: Int] {
        guard let size = SampleCastell.requested else { return [:] }
        return SampleCastell.libraryCounts(of: SampleCastell.world(size).items)
    }

    func connectors() async throws(SourceEditFailure) -> ConnectorKeepers { ConnectorKeepers() }

    func update(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async throws(SourceEditFailure) -> SourceInfo {
        throw .unsupported
    }
}

nonisolated extension SampleCastell {
    /// A row to make: where it came from, what it is and when. Named rows are the ones a board shows; the rest fill a quota.
    nonisolated struct Spec {
        var id: String
        var type: String
        var title: String?
        var body = ""
        var source: String
        var day: Int
        var time = "09:00"
        var tier: Marfa.Tier = .library
        var state: Marfa.ItemState = .active
        var tags: [String] = []
        var props: JSONObject = [:]
        var due: Int?
        var parent: String?
        var collections: [String] = []
    }

    /// How many active Library items of a type from a source the library holds, named rows included.
    nonisolated struct Quota {
        var source: String
        var type: String
        var count: Int
    }

    nonisolated struct Maker {
        let now: Date
        let start: Int
        let nowEpoch: Int
        var items: [Marfa.Item] = []
        var edges: [Marfa.Edge] = []
        /// The members each collection id has been given.
        var members: [String: [String]] = [:]

        init(now: Date) {
            self.now = now
            nowEpoch = Int(now.timeIntervalSince1970)
            start = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        }

        /// The moment `day` days ago at `time`, never later than now.
        func epoch(day: Int, time: String) -> Int {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            let seconds = (parts.first ?? 0) * 3600 + (parts.count > 1 ? parts[1] : 0) * 60
            return min(start - day * 86_400 + seconds, nowEpoch)
        }

        // MARK: Rows

        mutating func add(_ spec: Spec) {
            var properties = spec.props
            if let title = spec.title { properties["title"] = .string(title) }
            if !spec.body.isEmpty { properties["body"] = .string(spec.body) }
            if let due = spec.due { properties["due_at"] = .string(Self.stamp(start + due * 86_400 + 16 * 3600)) }
            let created = Self.stamp(epoch(day: spec.day, time: spec.time))
            items.append(Marfa.Item(
                id: spec.id, type: spec.type, properties: properties, state: spec.state, tier: spec.tier, version: 1,
                schemaVersion: 1, source: spec.source, sourceId: nil, occurredAt: created, createdAt: created,
                updatedAt: created, tags: spec.tags, readOnly: Code.readOnly.contains(spec.source)))
            if let parent = spec.parent { link(parent, spec.id, "parent-of") }
            for collection in spec.collections { join(spec.id, collection) }
        }

        mutating func link(_ from: String, _ to: String, _ type: String) {
            let stamped = Self.stamp(nowEpoch)
            edges.append(Marfa.Edge(
                id: "\(type)-\(from)-\(to)", fromId: from, toId: to, edgeType: type, properties: [:], version: 1,
                createdAt: stamped, updatedAt: stamped))
        }

        mutating func join(_ member: String, _ collection: String) {
            link(member, collection, "in-collection")
            members[collection, default: []].append(member)
        }

        // MARK: Filling a quota

        /// Makes the rows a quota still lacks after the named ones, each older than anything named so a list's first rows are
        /// the named ones. `named` is how many of this source and type the named rows already make.
        mutating func fill(_ quota: Quota, named: Int, tier: Marfa.Tier = .library, state: Marfa.ItemState = .active, nearest: Int = 8, within: Int = 700, prefix: String = "f") {
            let lacking = quota.count - named
            guard lacking > 0 else { return }
            items.reserveCapacity(items.count + lacking)
            let key = Self.short(quota.type)
            let source = quota.source
            let seed = Self.seed(source: source, type: quota.type)
            for index in 0..<lacking {
                let n = index + seed
                let days = nearest + (index * 37 + seed * 11) % within
                let seconds = (index * 7_919 + seed * 131) % 86_400
                let created = Self.stamp(min(start - days * 86_400 + seconds, nowEpoch))
                let id = "\(prefix)-\(source.hasPrefix("oauth:") ? String(source.dropFirst(6)) : source)-\(key)-\(index)"
                items.append(Marfa.Item(
                    id: id, type: quota.type, properties: Self.properties(of: quota.type, n, index: index, now: start),
                    state: state, tier: tier, version: 1, schemaVersion: 1, source: source, sourceId: nil, occurredAt: created,
                    createdAt: created, updatedAt: created, tags: index % 41 == 0 ? [ItemTag.favorite] : [],
                    readOnly: Code.readOnly.contains(source)))
            }
        }

        // MARK: Heavy

        mutating func addHeavy() {
            let library: [Quota] = [
                Quota(source: Code.readwise, type: Kind.highlight, count: 12_518),
                Quota(source: Code.rss, type: Kind.bookmark, count: 7_940),
                Quota(source: Code.readwise, type: Kind.bookmark, count: 1_200),
                Quota(source: Code.raycast, type: Kind.bookmark, count: 400),
                Quota(source: Code.shortcuts, type: Kind.bookmark, count: 255),
                Quota(source: Code.marfaForMac, type: Kind.note, count: 3_593),
                Quota(source: Code.raycast, type: Kind.note, count: 1_500),
                Quota(source: Code.claude, type: Kind.note, count: 1_000),
                Quota(source: Code.shortcuts, type: Kind.note, count: 125),
                Quota(source: Code.marfaForMac, type: Kind.task, count: 1_011),
                Quota(source: Code.raycast, type: Kind.task, count: 769),
                Quota(source: Code.claude, type: Kind.task, count: 256),
                Quota(source: Code.studioFolder, type: Kind.file, count: 4_114),
                Quota(source: Code.letterboxd, type: Kind.media, count: 212),
                Quota(source: Code.marfaForMac, type: Kind.media, count: 5_212),
                Quota(source: Code.contacts, type: Kind.person, count: 1_268),
                Quota(source: Code.marfaForMac, type: Kind.person, count: 38),
                Quota(source: Code.studioFolder, type: Kind.message, count: 1_284),
                Quota(source: Code.marfaForMac, type: Kind.message, count: 2_088),
                Quota(source: Code.calendar, type: Kind.event, count: 2_290),
                Quota(source: Code.marfaForMac, type: Kind.event, count: 50),
                Quota(source: Code.marfaForMac, type: Kind.place, count: 412),
                Quota(source: Code.marfaForMac, type: Kind.project, count: 48),
                Quota(source: Code.marfaForMac, type: Kind.collection, count: 37),
                Quota(source: Code.github, type: Kind.issue, count: 225),
                Quota(source: Code.github, type: Kind.pullRequest, count: 467),
            ]
            for quota in library { fill(quota, named: 0) }
            // The Feed, archive and bin are small beside the Library.
            fill(Quota(source: Code.rss, type: Kind.bookmark, count: 600), named: 0, tier: .feed, nearest: 0, within: 30, prefix: "feed")
            fill(Quota(source: Code.readwise, type: Kind.highlight, count: 300), named: 0, tier: .feed, nearest: 0, within: 30, prefix: "feed")
            fill(Quota(source: Code.github, type: Kind.issue, count: 100), named: 0, tier: .feed, nearest: 0, within: 30, prefix: "feed")
            fill(Quota(source: Code.raycast, type: Kind.task, count: 300), named: 0, state: .archived, prefix: "old")
            fill(Quota(source: Code.marfaForMac, type: Kind.note, count: 150), named: 0, state: .archived, prefix: "old")
            fill(Quota(source: Code.rss, type: Kind.bookmark, count: 50), named: 0, state: .archived, prefix: "old")
            fill(Quota(source: Code.marfaForMac, type: Kind.note, count: 25), named: 0, state: .trashed, prefix: "bin")

            let held = items
            func ids(_ type: String) -> [String] {
                held.filter { $0.type == type && $0.tier == .library && $0.state == .active }.map(\.id)
            }
            let projects = ids(Kind.project)
            let tasks = ids(Kind.task)
            for (g, task) in tasks.enumerated() {
                if g % 3 == 0 {
                    link(projects[(g / 3) % projects.count], task, "parent-of")
                } else if g % 3 == 1 || g % 9 == 2 {
                    link(tasks[g - 1], task, "parent-of")
                }
            }
            let collections = ids(Kind.collection)
            let pool = items.indices.filter { items[$0].type != Kind.collection && items[$0].tier == .library && items[$0].state == .active }
            for (c, collection) in collections.enumerated() {
                for j in 0..<(5 + c % 20) {
                    join(items[pool[(c * 997 + j * 131) % pool.count]].id, collection)
                }
            }
        }

        // MARK: Time

        /// A moment as the contract writes it, in UTC, made by arithmetic because a library of fifty thousand asks for
        /// a hundred and fifty thousand of them.
        static func stamp(_ epoch: Int) -> String {
            let days = epoch >= 0 ? epoch / 86_400 : (epoch - 86_399) / 86_400
            let seconds = epoch - days * 86_400
            let z = days + 719_468
            let era = (z >= 0 ? z : z - 146_096) / 146_097
            let doe = z - era * 146_097
            let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            let mp = (5 * doy + 2) / 153
            let day = doy - (153 * mp + 2) / 5 + 1
            let month = mp < 10 ? mp + 3 : mp - 9
            let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
            func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
            return "\(year)-\(two(month))-\(two(day))T\(two(seconds / 3600)):\(two(seconds % 3600 / 60)):\(two(seconds % 60)).000Z"
        }

        // MARK: Text

        static func short(_ type: String) -> String { String(type.split(separator: ".").last ?? "x") }

        /// Where a source's items of a type start in the pools of words, so two sources' items are not alike.
        static func seed(source: String, type: String) -> Int {
            (source.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 9_973 } + type.utf8.reduce(0) { ($0 &* 17 &+ Int($1)) % 9_973 }) % 61
        }

        static let topics = [
            "Glaze", "Kiln", "Riso", "Zine", "Print fair", "Linseed oil", "Dovetails", "Worktop", "Calverts", "Lewes Trust",
            "Harbour Joinery", "Studio site", "Lisbon", "Chalk stream", "Oak", "Spoon carving", "Paper stock", "Newsletter",
        ]

        static let people = ["Ines", "Ruth", "Sam", "Hana", "Alice", "Ada", "Tom", "Priya", "Marta", "Joe", "Elif", "Noor"]
        static let surnames = ["Barros", "Okonjo", "Tarrant", "Whitlock", "Lindqvist", "Castell", "Reyes", "Hart", "Moreau", "Nakamura"]

        static let quotes = [
            "Paper remembers every fold, so make the first one the one you meant.",
            "A glaze is a glass that has been persuaded to stay where it was put.",
            "A scraper cuts where paper tears.",
            "The path keeps to the cliff edge and never once explains itself.",
            "Short runs made the small press shop worth opening again.",
            "Most gaps in a dovetail come from the chisel, and the saw is blamed for them.",
            "Slow kilns forgive a thick coat.",
            "A hundred copies used to be a favour, and it is now most of the work.",
        ]

        static func title(of type: String, _ n: Int) -> String {
            let topic = topics[n % topics.count]
            let shapes: [(String, String)]
            switch type {
            case Kind.note: shapes = [("Notes on ", ""), ("", " log, firing"), ("Ideas for ", ""), ("What I learned from ", "")]
            case Kind.task: shapes = [("Reply about ", ""), ("Order more for ", ""), ("Check the proofs for ", ""), ("Book time for ", ""), ("Write up ", "")]
            case Kind.bookmark: shapes = [("", ": a beginner's guide"), ("Why ", " is worth the trouble"), ("", ", compared"), ("A better way to do ", "")]
            case Kind.article: shapes = [("The case for ", ""), ("", " and the long view"), ("Notes toward ", "")]
            case Kind.book: shapes = [("The book of ", ""), ("", ", a history"), ("Working with ", "")]
            case Kind.message: shapes = [("Re: ", ""), ("Quote for ", ""), ("", ", second round")]
            case Kind.file: shapes = [("", " scan.pdf"), ("", " invoice.pdf"), ("", " price list.pdf")]
            case Kind.image: shapes = [("", " test tile"), ("", ", detail"), ("", " on the bench")]
            case Kind.event: shapes = [("Call about ", ""), ("", " workshop"), ("Visit for ", "")]
            case Kind.place: shapes = [("", " supplies, Lewes"), ("", " studio"), ("", " yard")]
            case Kind.project: shapes = [("", " project"), ("The ", " plan")]
            case Kind.issue: shapes = [("", " page is slow on a phone"), ("", " links break"), ("Add ", " to the footer")]
            case Kind.pullRequest: shapes = [("Load ", " in steps"), ("Fix ", " spacing"), ("Rename ", " everywhere")]
            case Kind.media: shapes = [("", " on film"), ("", ", a documentary")]
            case Kind.collection: shapes = [("", " collection")]
            default: shapes = [("", "")]
            }
            let shape = shapes[(n / topics.count) % shapes.count]
            let round = n / (topics.count * shapes.count)
            return shape.0 + topic + shape.1 + (round > 0 ? " \(round + 1)" : "")
        }

        static func properties(of type: String, _ n: Int, index: Int, now: Int) -> JSONObject {
            let name = title(of: type, n)
            let topic = topics[n % topics.count]
            let quote = quotes[n % quotes.count]
            switch type {
            case Kind.note: return ["title": .string(name), "body": .string("\(quote) Kept for the \(topic.lowercased()).")]
            case Kind.task:
                let statuses = ["not_started", "not_started", "in_progress", "completed"]
                let priorities = ["low", "medium", "high"]
                return ["title": .string(name), "body": .string("About the \(topic.lowercased())."), "status": .string(statuses[n % 4]), "priority": .string(priorities[n % 3])]
            case Kind.bookmark, Kind.article:
                return ["title": .string(name), "url": .string("https://example.com/\(Self.short(type))/\(index)"), "body": .string(quote)]
            case Kind.highlight: return ["body": .string(quote + (n >= quotes.count ? " (\(n / quotes.count + 1))" : ""))]
            case Kind.book: return ["title": .string("\(name), by \(people[n % people.count]) \(surnames[n % surnames.count])")]
            case Kind.message: return ["title": .string(name), "body": .string("\(quote) Sent about the \(topic.lowercased()).")]
            case Kind.file: return ["title": .string(name), "mime_type": "application/pdf", "size_bytes": .number(Double(20_000 + n * 97 % 900_000))]
            case Kind.image: return ["title": .string("IMG_\(4_000 + index).HEIC"), "mime_type": "image/heic", "size_bytes": .number(Double(2_000_000 + n * 313 % 4_000_000))]
            case Kind.event:
                let starts = Self.stamp(now + ((index * 7) % 120 - 60) * 86_400 + (9 + n % 8) * 3600)
                return ["title": .string(name), "starts_at": .string(starts)]
            case Kind.person: return ["title": .string("\(people[n % people.count]) \(surnames[(n / people.count) % surnames.count])\(n >= 120 ? " \(n / 120 + 1)" : "")")]
            case Kind.place:
                // Two places in three stand on the map, spread over the south of England and clustered round Lewes.
                var properties: JSONObject = ["title": .string(name), "address": .string("\(1 + n % 90) High Street, Lewes")]
                if n % 3 != 2 {
                    let near = n % 2 == 0
                    properties["latitude"] = .number(50.874 + Double((n * 7919) % 1000 - 500) / (near ? 40_000 : 400))
                    properties["longitude"] = .number(0.012 + Double((n * 104_729) % 1000 - 500) / (near ? 25_000 : 250))
                }
                return properties
            case Kind.issue: return ["title": .string(name), "body": .string(quote), "status": .string(n % 3 == 0 ? "closed" : "open")]
            case Kind.pullRequest: return ["title": .string(name), "body": .string(quote), "status": .string(["open", "merged", "closed"][n % 3])]
            case Kind.media: return ["title": .string(name), "progress": .string(["wishlist", "in_progress", "finished"][n % 3]), "rating": .number(Double(1 + n % 5))]
            case Kind.collection: return ["title": .string(name), "description": .string("Gathered for the \(topic.lowercased()).")]
            default: return ["title": .string(name)]
            }
        }
    }
}
#endif
