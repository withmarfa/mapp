import Foundation
import Testing
@testable import MarfaMac

/// The list's search tokens: what they keep beside the typed words, and what typing offers. Dates and locales are given by
/// each test, never read from the machine.
@MainActor
struct SearchTokenTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    /// Noon on a day, so no change of clocks moves it to another.
    private static func noon(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar = calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static let target = FilterTarget.edited

    // MARK: What tokens keep

    @Test func tokensAndWordsTogetherKeepOnlyWhatBothKeep() throws {
        let early = Self.noon(2026, 3, 2), late = Self.noon(2026, 3, 20)
        let library = FakeItemLibrary(
            items: [FakeItemLibrary.note("Zine plan", modified: early), FakeItemLibrary.note("Zine cover", modified: late),
                    FakeItemLibrary.note("Garden", modified: early), FakeItemLibrary.note("Tent", modified: late)],
            now: late)
        let browser = Browser()
        func titles() -> [String] { browser.filteredItems(in: library).map(\.title).sorted() }
        let token = FilterClause(field: Self.target.id, op: .on, values: [FilterDays.text(of: early, calendar: .current)])

        browser.searchText = "zine"
        #expect(titles() == ["Zine cover", "Zine plan"], "the words alone")
        browser.addSearchToken(token)
        #expect(titles() == ["Zine plan"], "the token keeps only what was edited on its day, within what the words found")
        browser.searchText = ""
        #expect(titles() == ["Garden", "Zine plan"], "the token alone, in the other direction: the words no longer narrow")
        browser.removeSearchToken(token)
        #expect(titles().count == 4)
    }

    @Test func aTokenMarfaCanSayIsInTheSearchesOwnFilter() throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Zine", modified: Self.noon(2026, 3, 2))], now: Self.noon(2026, 3, 20))
        let browser = Browser()
        browser.searchText = "zine"
        browser.addSearchToken(FilterClause(field: Self.target.id, op: .before, values: ["2026-04-01"]))
        guard case .query(let query) = browser.searchScope(in: library) else {
            Issue.record("a place that lists items searches by query")
            return
        }
        #expect(query.filter != nil, "so the 500 the search is cut to is counted after the token")
    }

    @Test func leavingThePlaceOrClearingPutsTokensAway() {
        let browser = Browser()
        browser.addSearchToken(FilterClause(field: "tier", op: .is, values: ["feed"]))
        browser.searchText = "zine"
        browser.isSearchExpanded = true
        browser.clearSearch()
        #expect(browser.searchTokens.isEmpty && browser.searchText.isEmpty && !browser.isSearchExpanded)
    }

    // MARK: What typing offers

    private func context(calendar: Calendar = SearchTokenTests.calendar, now: Date = SearchTokenTests.noon(2026, 3, 20)) -> SearchOffers.Context {
        var values = SearchOffers.Values()
        values.tags = ["zine", "garden"]
        return SearchOffers.Context(targets: [.tags, .tier, .edited, .created], values: values, calendar: calendar, now: now)
    }

    @Test func aTagIsOfferedBeforeTheWordsThemselves() {
        let offers = SearchOffers.make(text: "zin", in: context())
        #expect(offers.first?.clause?.field == FilterTarget.tags.id)
        #expect(offers.first?.value == "zine")
        #expect(offers.last?.kind == .text)
    }

    @Test func theFeedIsOfferedAsWhereAnItemCameFrom() {
        let offers = SearchOffers.make(text: "feed", in: context())
        let clause = offers.compactMap(\.clause).first { $0.field == FilterTarget.tier.id }
        #expect(clause?.values == ["feed"])
    }

    @Test func aTokenAlreadyMadeIsNotOfferedAgain() {
        let made = FilterClause(field: FilterTarget.tags.id, op: .includes, values: ["zine"])
        let offers = SearchOffers.make(text: "zine", in: context(), existing: [made])
        #expect(!offers.compactMap(\.clause).contains(made))
    }

    @Test func aFieldThePlaceLacksOffersNothing() {
        var lacking = context()
        lacking.targets = [.tier]
        #expect(SearchOffers.make(text: "zine", in: lacking).compactMap(\.clause).isEmpty)
    }

    @Test func veryLongWordsOfferOnlyThemselves() {
        let offers = SearchOffers.make(text: String(repeating: "zine ", count: 4_000), in: context())
        #expect(offers.compactMap(\.clause).isEmpty)
        #expect(offers.last?.kind == .text)
    }

    /// A day written the way each locale writes it is read back as that day, in the locale's own order of day and month.
    @Test(arguments: ["en_GB", "en_US", "de_DE", "ja_JP", "fr_FR"])
    func aDayTypedInTheLocalesOwnWordsIsThatDay(identifier: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: identifier)
        let day = Self.noon(2026, 3, 4, in: calendar)
        for template in ["yMMMd", "yMd", "yMMMMd"] {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: calendar.locale)
            let text = formatter.string(from: day)
            let span = try #require(SearchDates.parse(text, calendar: calendar, now: day), "\(text) in \(identifier)")
            #expect(calendar.component(.month, from: span.start) == 3 && calendar.component(.day, from: span.start) == 4, "\(text) in \(identifier)")
            #expect(span.start == span.end)
        }
    }

    @Test func aMonthIsASpanOfItsDays() throws {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = Self.calendar.locale
        formatter.timeZone = Self.calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMM", options: 0, locale: Self.calendar.locale)
        let text = formatter.string(from: Self.noon(2026, 2, 10))
        let span = try #require(SearchDates.parse(text, calendar: Self.calendar, now: Self.noon(2026, 3, 20)))
        #expect(Self.calendar.component(.day, from: span.start) == 1)
        #expect(Self.calendar.component(.day, from: span.end) == 28)
    }

    @Test func aDateIsOfferedOnTheFirstDatedFields() throws {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = Self.calendar.locale
        formatter.timeZone = Self.calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMd", options: 0, locale: Self.calendar.locale)
        let text = formatter.string(from: Self.noon(2026, 3, 4))
        let clauses = SearchOffers.make(text: text, in: context()).compactMap(\.clause)
        #expect(clauses.map(\.field).contains(FilterTarget.edited.id))
        #expect(clauses.allSatisfy { $0.op == .on && $0.values == ["2026-03-04"] })
    }
}
