#if DEBUG
import Foundation
import Marfa

/// The rows of Castell Studio that the design boards name, in the days the boards put them: today is the board's Monday, so
/// "Yesterday" is 1 and "Saturday" 2. The rest of the 1,205 is generated to each source's and type's count.
nonisolated extension SampleCastell.Maker {
    typealias Spec = SampleCastell.Spec
    typealias Quota = SampleCastell.Quota
    private typealias Code = SampleCastell.Code
    private typealias Kind = SampleCastell.Kind

    private static let lisbon = "project-lisbon-zine"
    private static let trust = "project-lewes-trust"
    private static let site = "project-studio-site"
    private static let fair = "project-print-fair"

    mutating func addStudio() {
        var specs: [Spec] = []
        func make(
            _ id: String, _ type: String, _ title: String?, _ source: String, _ day: Int, _ time: String = "09:00",
            tier: Marfa.Tier = .library, state: Marfa.ItemState = .active, body: String = "", parent: String? = nil,
            due: Int? = nil, props: JSONObject = [:], collections: [String] = [], favorite: Bool = false
        ) {
            specs.append(Spec(
                id: id, type: type, title: title, body: body, source: source, day: day, time: time, tier: tier, state: state,
                tags: favorite ? [ItemTag.favorite] : [], props: props, due: due, parent: parent, collections: collections))
        }
        func task(
            _ id: String, _ title: String, _ source: String, _ day: Int, _ time: String = "10:00", priority: String = "medium",
            status: String = "not_started", due: Int? = nil, parent: String? = nil, state: Marfa.ItemState = .active
        ) {
            make(id, Kind.task, title, source, day, time, state: state, parent: parent, due: due,
                 props: ["priority": .string(priority), "status": .string(status)])
        }
        let mfm = Code.marfaForMac, raycast = Code.raycast, claude = Code.claude, studio = Code.studioFolder
        let readwise = Code.readwise, rss = Code.rss, github = Code.github

        // Projects, and the tasks under them several levels deep.
        make(Self.lisbon, Kind.project, "The Lisbon zine", mfm, 30, "09:00",
             body: "Thirty-two pages on a week in Lisbon, riso printed, for the print fair in March. Ines draws the cover and the chapter openers.\n\n## What is decided\n\nA5, 32 pages plus cover, 250 copies.\n\n## Still open\n\nThe cover stock, and whether the hand-stamped fifty are worth the evening they will take.",
             props: ["description": "A week in Lisbon, in print."], favorite: true)
        make(Self.trust, Kind.project, "Lewes Trust annual report", mfm, 40, "09:00")
        make(Self.site, Kind.project, "The studio site refresh", mfm, 50, "09:00")
        task("t-print", "Print the Lisbon zine for the March fair", mfm, 0, "08:15", priority: "high", status: "in_progress", due: 17, parent: Self.lisbon)
        task("t-quote", "Get a second quote for the print run", mfm, 3, due: 2, parent: "t-print")
        task("t-pages", "Check the page order against the dummy", mfm, 3, parent: "t-print")
        task("t-delivery", "Confirm the delivery date with Calverts", mfm, 3, parent: "t-quote")
        task("t-cover", "Choose the cover stock for the zine", mfm, 4, priority: "high", due: 0, parent: Self.lisbon)
        task("t-photograph", "Photograph the glaze tests for the zine", mfm, 5, parent: Self.lisbon)
        task("t-samples", "Order the paper samples from Calverts", mfm, 6, parent: "note-paper")
        task("t-ines", "Reply to Ines about the zine proofs", raycast, 3, "10:00", due: -1, parent: Self.lisbon)
        task("t-invoice", "Send the Lewes Trust their invoice", raycast, 1, priority: "high", due: 0, parent: Self.trust)
        task("t-extra-proof", "Add the extra proof round to the invoice", raycast, 1, parent: "t-invoice")
        task("t-sign-off", "Ask Ruth who signs it off", raycast, 1, parent: "t-invoice")
        task("t-printer", "Find out what the trust's printer needs, and by when, before the photographs are chosen", mfm, 2, parent: Self.trust)
        task("t-photos", "Ask Ruth for the trustees' photographs", mfm, 2, parent: "t-printer")
        task("t-about", "Rewrite the studio site's about page", mfm, 4, parent: Self.site)
        task("t-newsletter", "Each newsletter leads with what is new in the studio", mfm, 4, due: 2, parent: "t-about")
        task("t-pages-tidy", "Tidy the studio site's project pages", mfm, 4, priority: "high", due: 3, parent: Self.site)
        task("t-signup", "Make the newsletter sign-up work on phones", mfm, 5, parent: Self.site)
        task("t-grid", "Keep the gallery grid aligned when the window resizes", github, 11, parent: Self.site)
        task("t-brochure", "Quote for the Harbour Joinery brochure", mfm, 5, due: 7)
        task("t-backup", "Back up the photo library to the NAS", mfm, 6)
        task("t-printer-setup", "Set up the new printer in the studio", mfm, 6, priority: "low")
        task("t-books", "Return the sample books to the paper merchant", mfm, 7, priority: "low", due: 4)
        task("t-domain", "Renew the studio domain", raycast, 0, "09:52")
        task("t-shop", "Move the shop page to the new template", mfm, 5, parent: "t-pages-tidy", state: .archived)
        task("t-appendix", "Cut the appendix to four pages", mfm, 5, parent: "t-printer", state: .trashed)
        make("note-paper", Kind.note, "Paper for the zine", mfm, 17, "10:00", parent: Self.lisbon)
        make("event-feira", Kind.event, "Feira Gráfica, the Lisbon print fair", mfm, 20, "09:00", parent: Self.lisbon,
             props: ["starts_at": .string(Self.stamp(start + 100 * 86_400 + 10 * 3600))])

        // The board's Library list, in order.
        make("note-glaze-workshop", Kind.note, "Notes from the glaze workshop", raycast, 0, "09:40",
             body: "Cone 6 in the electric kiln, three tests a tile. The celadon wants a thin coat over iron slip.",
             collections: ["collection-glaze"])
        make("bm-oil", Kind.bookmark, "Three coats of oil, a day apart", rss, 0, "08:12", props: ["url": "https://greenwoodjournal.example/three-coats"])
        make("bm-spoon", Kind.bookmark, "Spoon carving for beginners", rss, 0, "07:40",
             body: "Start with green wood and a straight knife. A spoon is three cuts repeated a few hundred times, and the first twenty spoons are for the fire.\n\nBirch and sycamore forgive the most. Keep the blank in a bag between sessions, so it dries as slowly as you carve.",
             props: ["url": "https://greenwoodjournal.example/spoon-carving-for-beginners"])
        make("note-trust-wants", Kind.note, "What the trust wants from the report", claude, 0, "07:02")
        make("bm-planes", Kind.bookmark, "Bench planes, sharpened properly", rss, 1, "08:00", props: ["url": "https://example.com/bench-planes"])
        make("img-4821", Kind.image, "IMG_4821.HEIC", mfm, 1, "09:10", props: ["mime_type": "image/heic"])
        make("article-chalk", Kind.article, "Chalk streams of the South Downs", readwise, 1, "08:40", props: ["url": "https://example.com/chalk-streams"])
        make("note-uncoated", Kind.note, "Ask Calverts whether the uncoated stock comes in a heavier weight", raycast, 1, "08:20")
        make("msg-proofs", Kind.message, "Re: proofs, second round", studio, 1, "07:30", body: "The second proofs are ready at the trade counter.")
        make("hl-chalk", Kind.highlight, nil, readwise, 1, "07:00", body: "A chalk stream is rain that fell on the hill thirty years ago.")
        make("event-ruth", Kind.event, "Planning call with Ruth", mfm, 2, "10:00",
             props: ["starts_at": .string(Self.stamp(start - 2 * 86_400 + 15 * 3600))])
        make("note-kiln-14", Kind.note, "Kiln log, firing 14", studio, 2, "09:00")
        make("img-drawers", Kind.image, "Harbour Joinery: drawer fronts", mfm, 4, "11:00")
        make("bm-finishes", Kind.bookmark, "Wood finishes compared", readwise, 5, "09:00", props: ["url": "https://example.com/finishes"])
        make("note-trust-comments", Kind.note, "Lewes Trust: comments on the draft", claude, 6, "09:00")
        make("person-ines", Kind.person, "Ines Barros", mfm, 7, "09:00", props: ["job_title": "Illustrator"])
        make("place-calverts", Kind.place, "Calverts, the printers", mfm, 9, "09:00", props: ["address": "Calverts, 31 Cliffe High Street, Lewes", "latitude": .number(50.8747), "longitude": .number(0.0121)])
        make("book-cliff", Kind.book, "The cliff path, by Alice Tarrant", readwise, 14, "09:00")
        make("pr-photos", Kind.pullRequest,
             "Load large photos in steps, so the gallery never waits for the largest one before it shows the rest", github, 6, "09:48",
             body: "Each photo now loads a small preview first, then the full image. The grid lays out from the previews, so nothing moves when the large files land.\n\n## What changed\n\nThe gallery asks for a 40 pixel preview of every photo before anything else.",
             props: ["status": "merged", "url": "https://github.com/mcastell/studio-site/pull/418"])

        // Collections, and the items only they gather.
        make("collection-glaze", Kind.collection, "Glaze tests", mfm, 23, "14:20", props: ["description": "Every test tile worth keeping, and what was on it."])
        make("collection-zine-photos", Kind.collection, "Zine photographs", claude, 2, "09:00")
        make("collection-print-fair", Kind.collection, "Print fair, March", mfm, 3, "09:00")
        make("collection-reading", Kind.collection, "Reading for the report", mfm, 4, "09:00")
        make("img-celadon", Kind.image, "Celadon over iron slip, cone 6", mfm, 1, "18:20", collections: ["collection-glaze"])
        make("note-batch-9", Kind.note, "Glaze tests, batch 9", mfm, 7, "10:00", collections: ["collection-glaze"])
        make("note-shino", Kind.note, "Shino recipe from Ruth", mfm, 8, "10:00", collections: ["collection-glaze"])
        for (index, name) in ["Zine cover, first proof", "Zine spread, the harbour", "Zine spread, the tram", "Zine back cover", "Zine endpapers, riso test", "Zine cover, hand-stamped"].enumerated() {
            make("img-zine-\(index)", Kind.image, name, mfm, 2 + index, "12:00", collections: ["collection-zine-photos"])
        }
        make("note-fair-layout", Kind.note, "Print fair: stall layout", mfm, 3, "10:00", collections: ["collection-print-fair"])
        make("event-fair", Kind.event, "Lewes print fair, March", mfm, 3, "10:00",
             props: ["starts_at": .string(Self.stamp(start + 90 * 86_400 + 9 * 3600))], collections: ["collection-print-fair"])
        make("t-van", Kind.task, "Book the van for the print fair", raycast, 5, "10:00", due: 0, props: ["priority": "medium", "status": "not_started"],
             collections: ["collection-print-fair"])

        // The Feed.
        make("feed-oil", Kind.bookmark, "Linseed, tung or Danish: which oil for a worktop", rss, 0, "09:12", tier: .feed,
             body: "All three are thin coats wiped back after twenty minutes. Linseed yellows, tung takes a week to cure, and Danish oil is mostly varnish, which is why it is the one that survives a kitchen.")
        make("feed-dovetails", Kind.bookmark, "A sharper way to cut dovetails", rss, 0, "08:30", tier: .feed,
             body: "Saw to the waste side of the line and stop paring so early. Most gaps in a dovetail come from the chisel, and the saw is blamed for them.")
        make("feed-van", Kind.message, "Re: van hire for the print fair", studio, 1, "15:27", tier: .feed,
             body: "The long wheelbase is free that weekend and takes both tables flat. They want it back by nine on Monday, and the deposit comes off the card when the keys go back.\n\nCollection is from the yard on Davey's Lane, any time after eight on the Friday.")
        make("feed-van-first", Kind.message, "Van hire for the print fair", studio, 2, "14:00", tier: .feed,
             body: "Can we fit both tables flat in the long wheelbase?")
        link("feed-van", "note-fair-layout", MarfaMapping.threadEdge)
        link("feed-van-first", "note-fair-layout", MarfaMapping.threadEdge)
        make("feed-fold", Kind.highlight, nil, readwise, 1, "11:00", tier: .feed, body: "Paper remembers every fold, so make the first one the one you meant.")
        make("feed-fold-first", Kind.highlight, nil, readwise, 5, "11:00", tier: .feed, body: "The grain always tells you which way the page wants to turn.")
        make("feed-fold-second", Kind.highlight, nil, readwise, 3, "11:00", tier: .feed, body: "A good binding is quiet in the hand.")
        for id in ["feed-fold", "feed-fold-first", "feed-fold-second"] { link(id, "book-cliff", MarfaMapping.excerptEdge) }
        make("feed-corner", Kind.article, "The corner printer comes back", readwise, 1, "10:00", tier: .feed,
             body: "Short runs made the small press shop worth opening again. A hundred copies used to be a favour, and it is now most of the work.")
        for (index, entry) in [
            ("Milk paint, and when not to use it", 1, rss), ("Why a card scraper beats sandpaper on oak", 1, rss),
            ("Two-colour riso without the muddy overlap", 2, rss), ("Calverts: paper prices from January", 2, raycast),
            ("Ash glazes from the wood stove", 3, rss), ("Sweet peas, sown in autumn", 4, rss),
            ("A plane iron, flattened in ten minutes", 4, rss), ("Staples or thread: binding a short zine", 5, rss),
            ("What kiln wash is for, and when to skip it", 6, rss), ("Leaf mould, and how long it really takes", 7, rss),
        ].enumerated() {
            make("feed-bm-\(index)", Kind.bookmark, entry.0, entry.2, entry.1, "09:00", tier: .feed,
                 body: "It wants bare wood and it will not forgive a sealed surface.")
        }

        // The archive, from the Library and the Feed, and the bin.
        make("old-stall", Kind.project, "A stall at the Lewes print fair", mfm, 4, "09:00", state: .archived)
        for (id, title, source) in [("old-pack", "Pack the car for the Lewes print fair", mfm), ("old-cards", "Print the price cards for the fair", mfm), ("old-pay", "Pay for the stall at the Lewes print fair", raycast)] {
            make(id, Kind.task, title, source, 4, "09:00", state: .archived, parent: "old-stall", props: ["priority": "medium", "status": "completed"])
        }
        make("old-sold", Kind.note, "Lewes print fair: what sold, and to whom", mfm, 4, "09:00", state: .archived)
        make("old-proofs", Kind.file, "Zine proofs, first round.pdf", studio, 11, state: .archived)
        make("old-proofs-hj", Kind.file, "Harbour Joinery: first proofs.pdf", studio, 11, state: .archived)
        make("old-kiln-9", Kind.note, "Kiln log, firing 9", studio, 12, state: .archived)
        make("old-kiln-8", Kind.note, "Kiln log, firing 8", studio, 21, state: .archived)
        make("old-batch-4", Kind.note, "Glaze tests, batch 4", studio, 21, state: .archived)
        make("old-newsletter", Kind.note, "Newsletter, October", mfm, 26, state: .archived)
        make("old-insurance", Kind.task, "Renew the public liability insurance", raycast, 40, state: .archived, props: ["priority": "medium", "status": "completed"])
        make("old-accounts", Kind.task, "File the accounts for 2025", raycast, 40, state: .archived, props: ["priority": "high", "status": "completed"])
        make("old-open-studio", Kind.event, "Open studio weekend, September", mfm, 54, state: .archived)
        make("old-sketches", Kind.image, "Harbour Joinery: first sketches", mfm, 54, state: .archived)
        make("old-post", Kind.bookmark, "A cheaper way to post zines abroad", rss, 62, tier: .feed, state: .archived)
        make("old-quote", Kind.message, "Re: quote for last year's report", studio, 75, tier: .feed, state: .archived)
        make("old-cards-xmas", Kind.task, "Post the Christmas cards", raycast, 82, state: .archived, props: ["priority": "low", "status": "completed"])
        make("old-business", Kind.task, "Order business cards from Calverts", mfm, 82, state: .archived, props: ["priority": "low", "status": "completed"])
        make("old-riso", Kind.event, "Risograph workshop at Kiln House", mfm, 91, state: .archived)
        make("old-lights", Kind.task, "Return the borrowed lights to Ruth", mfm, 104, state: .archived, props: ["priority": "low", "status": "completed"])
        make("old-chest", Kind.task, "Build a plan chest for the studio", mfm, 143, state: .archived, props: ["priority": "medium", "status": "completed"])
        make("bin-packing", Kind.note, "Old packing list", mfm, 30, state: .trashed)
        make("bin-agenda", Kind.note, "Draft agenda for the open studio", mfm, 15, state: .trashed)

        var named: [String: Int] = [:]
        for spec in specs {
            if spec.state == .active { named["\(spec.tier)|\(spec.source)|\(spec.type)", default: 0] += 1 }
            add(spec)
        }

        let library: [Quota] = [
            Quota(source: studio, type: Kind.note, count: 45), Quota(source: studio, type: Kind.message, count: 132),
            Quota(source: studio, type: Kind.file, count: 135), Quota(source: studio, type: Kind.image, count: 21),
            Quota(source: mfm, type: Kind.image, count: 59), Quota(source: mfm, type: Kind.event, count: 50),
            Quota(source: mfm, type: Kind.person, count: 45), Quota(source: mfm, type: Kind.place, count: 19),
            Quota(source: mfm, type: Kind.project, count: 9), Quota(source: mfm, type: Kind.collection, count: 3),
            Quota(source: mfm, type: Kind.file, count: 14), Quota(source: mfm, type: Kind.task, count: 18),
            Quota(source: mfm, type: Kind.note, count: 119),
            Quota(source: readwise, type: Kind.highlight, count: 130), Quota(source: readwise, type: Kind.article, count: 67),
            Quota(source: readwise, type: Kind.book, count: 25), Quota(source: readwise, type: Kind.bookmark, count: 19),
            Quota(source: rss, type: Kind.bookmark, count: 140),
            Quota(source: raycast, type: Kind.note, count: 40), Quota(source: raycast, type: Kind.task, count: 60),
            Quota(source: raycast, type: Kind.bookmark, count: 9),
            Quota(source: claude, type: Kind.note, count: 19), Quota(source: claude, type: Kind.task, count: 16),
            Quota(source: claude, type: Kind.collection, count: 1),
            Quota(source: github, type: Kind.task, count: 9), Quota(source: github, type: Kind.pullRequest, count: 1),
        ]
        for quota in library { fill(quota, named: named["library|\(quota.source)|\(quota.type)"] ?? 0) }
        let feed: [Quota] = [
            Quota(source: rss, type: Kind.bookmark, count: 11), Quota(source: raycast, type: Kind.bookmark, count: 1),
            Quota(source: readwise, type: Kind.highlight, count: 20), Quota(source: readwise, type: Kind.article, count: 12),
            Quota(source: studio, type: Kind.message, count: 13), Quota(source: github, type: Kind.issue, count: 6),
            Quota(source: github, type: Kind.pullRequest, count: 6),
        ]
        for quota in feed { fill(quota, named: named["feed|\(quota.source)|\(quota.type)"] ?? 0, tier: .feed, nearest: 0, within: 30, prefix: "feed") }
        fill(Quota(source: raycast, type: Kind.task, count: 12), named: 0, state: .archived, prefix: "old")
        fill(Quota(source: mfm, type: Kind.task, count: 12), named: 0, state: .archived, prefix: "old")
        fill(Quota(source: studio, type: Kind.note, count: 10), named: 0, state: .archived, prefix: "old")
        fill(Quota(source: rss, type: Kind.bookmark, count: 5), named: 0, state: .archived, prefix: "old")
        fill(Quota(source: studio, type: Kind.file, count: 3), named: 0, state: .archived, prefix: "old")
        fill(Quota(source: mfm, type: Kind.note, count: 6), named: 0, state: .trashed, prefix: "bin")

        // The sub-items of a few generated projects, so the sidebar's counts are not all there is under them.
        let projects = items.filter { $0.type == Kind.project && $0.state == .active }.map(\.id)
        let loose = items.filter { $0.type == Kind.task && $0.state == .active && $0.id.hasPrefix("f-") }.map(\.id)
        for (index, task) in loose.enumerated() where index % 2 == 0 {
            link(projects[index / 2 % projects.count], task, "parent-of")
        }

        // Reading for the report gathers the articles, books and highlights.
        let reading = items.filter {
            $0.tier == .library && $0.state == .active && [Kind.article, Kind.book, Kind.highlight].contains($0.type)
        }
        for item in reading.prefix(214) { join(item.id, "collection-reading") }
    }
}
#endif
