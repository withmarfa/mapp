import Foundation

/// The color of an option's dot. Marfa holds no color for an option, so it comes from a fixed palette by the option's
/// own words: the same value takes the same color on every launch and machine. The hash is FNV-1a over the UTF-8
/// bytes, since Swift's `Hasher` is seeded anew for each launch. Changing the palette or its order recolors every
/// option. A task's priority is the one exception: it takes its color from its rank (`priority(rank:of:)`).
nonisolated enum OptionTone {
    /// Every tone but the neutral one, which a chip with no dot of its own keeps.
    static let palette: [TypeTone] = [.blue, .green, .orange, .red, .purple, .teal, .yellow, .pink, .indigo]

    /// The colors of a priority from its lowest option to its highest.
    static let prioritySteps: [TypeTone] = [.purple, .yellow, .red, .blue]

    static func tone(for value: String) -> TypeTone {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }

    /// The color of the option at `rank` (0 is the lowest) among `count`. Four options take the four steps in order;
    /// another count spreads its ranks evenly over the steps, the lowest on the first and the highest on the last, each
    /// rank on the nearest step (a half rounds up), so a single option takes the first.
    static func priority(rank: Int, of count: Int) -> TypeTone {
        let last = prioritySteps.count - 1
        guard count > 1 else { return prioritySteps[0] }
        let clamped = min(max(rank, 0), count - 1)
        return prioritySteps[Int((Double(clamped) * Double(last) / Double(count - 1)).rounded(.toNearestOrAwayFromZero))]
    }

    /// The tone of an option's dot as a value panel and a list row draw it, from the field that holds it: a task's
    /// priority by the option's rank in the catalogue's order, any other option by its shown label. An option the
    /// field does not declare takes the label's color too.
    static func tone(of value: String, in field: ItemTypeInfo.Field, isPriority: Bool) -> TypeTone {
        if isPriority, let rank = field.options.firstIndex(of: value) {
            return priority(rank: rank, of: field.options.count)
        }
        return tone(for: ItemTypeInfo.Field.label(ofOption: value))
    }
}
