import Foundation

struct StudyRecord: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case reading, highlight, note

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .reading: "Reading"
            case .highlight: "Highlights"
            case .note: "Notes"
            }
        }

        var symbol: String {
            switch self {
            case .reading: "doc.richtext"
            case .highlight: "quote.opening"
            case .note: "note.text"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: LocalizedStringResource
    let source: LocalizedStringResource
    let snippet: LocalizedStringResource
    let detail: LocalizedStringResource
    var study: InterfaceStudy?

    func matches(_ query: String, locale: Locale) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let text = [title, source, snippet, detail].map { resource in
            var localized = resource
            localized.locale = locale
            return String(localized: localized)
        }.joined(separator: " ")
        return words.allSatisfy {
            text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }
    }

    static let samples: [StudyRecord] = [
        .init(id: "wet-corners", kind: .reading,
              title: "The case for small, wet corners", source: "Mara Quinn, Field & Street",
              snippet: "A little space for rain can change the way a whole garden works.",
              detail: "Begin with the place where water already lingers. Observe how it arrives and how long it stays before choosing the plants. A small rain garden can make an overlooked corner useful.", study: .reading),
        .init(id: "fewer-ideas", kind: .highlight,
              title: "Fewer ideas, held for longer", source: "Small Is Plenty, page 48",
              snippet: "A small space asks for fewer ideas, held for longer.",
              detail: "A reminder to return to a few good ideas and give them time to develop. Keep the planting simple enough to notice what changes.", study: .highlight),
        .init(id: "rain-notes", kind: .note,
              title: "After the rain", source: "Garden notebook",
              snippet: "Water stays beside the back step. The rest of the path dries quickly.",
              detail: "Watch the corner after the next three showers. Note when the puddle disappears, where the overflow goes, and whether the shaded soil stays damp through the afternoon."),
        .init(id: "shade", kind: .reading,
              title: "Planting for the quiet side", source: "Nina Vale, The Garden Letter",
              snippet: "Shade has its own seasons, and its own small changes worth noticing.",
              detail: "Repeat a few leaf shapes to give the shaded edge a rhythm. Leave room for spring growth, and keep a clear place to sit where the light reaches the wall."),
        .init(id: "paths", kind: .highlight,
              title: "Leave room for the journey", source: "The Everyday Garden, page 112",
              snippet: "The path is part of the garden, not the space left over.",
              detail: "Think about the route from the door to the seat before filling the beds. A path that invites a pause can make a small garden feel generous."),
        .init(id: "plant-list", kind: .note,
              title: "A short planting list", source: "Garden notebook",
              snippet: "Sedges, iris, and one repeated fern. Start with three kinds.",
              detail: "Compare the light and moisture each plant needs. Try a small group first and leave room to adjust after a season of watching."),
        .init(id: "seat", kind: .note,
              title: "Where the afternoon lands", source: "Garden notebook",
              snippet: "The warmest place is one step away from the spot we planned for the seat.",
              detail: "Move the chair before making a permanent base. Try the new position in morning shade and afternoon sun, with enough room to walk past it."),
        .init(id: "containers", kind: .reading,
              title: "Three pots are a garden", source: "Ellis Park, Field & Street",
              snippet: "Repetition can give a collection of containers a sense of place.",
              detail: "Use the same planting rhythm across three containers. Vary their height to catch the light, then watch how the group changes through the season.")
    ]
}
