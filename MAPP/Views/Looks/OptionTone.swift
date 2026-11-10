import Foundation

/// The color of an option's dot. Marfa holds no color for an option, so it comes from a fixed palette by the option's
/// own words (the four priority words aside): the same value takes the same color on every launch and machine. The hash is FNV-1a over the UTF-8
/// bytes, since Swift's `Hasher` is seeded anew for each launch. Changing the palette or its order recolors every
/// option.
nonisolated enum OptionTone {
    /// Every tone but the neutral one, which a chip with no dot of its own keeps.
    static let palette: [TypeTone] = [.blue, .green, .orange, .red, .purple, .teal, .yellow, .pink, .indigo]

    /// The four priority words keep a color of their own, so a priority reads the same everywhere.
    private static let priorityTones: [String: TypeTone] = ["low": .purple, "medium": .yellow, "high": .red, "urgent": .blue]

    static func tone(for value: String) -> TypeTone {
        if let tone = priorityTones[value.lowercased()] { return tone }
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }

    /// The tone of an option's dot as a value panel draws it: by the option written for reading
    /// (`Field.label(ofOption:)`), so a priority's dot is the same in a panel and in a list row.
    static func tone(ofOption value: String) -> TypeTone {
        tone(for: ItemTypeInfo.Field.label(ofOption: value))
    }
}
