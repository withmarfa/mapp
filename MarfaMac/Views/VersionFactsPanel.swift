import SwiftUI

/// The panel beside Version History: who wrote the version chosen and when, what it changed from the version before, and
/// what has changed since, as a heading and plain rows, with no box.
struct VersionFactsPanel: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let mode: VersionHistoryMode
    let list: VersionList?
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @State private var facts: VersionFacts?

    private struct Job: Hashable {
        let entry: String?
        let revision: Int
        let snapshots: Int
        let isComplete: Bool
        let format: DateFormat
    }

    var body: some View {
        ScrollView {
            if let facts {
                VStack(alignment: .leading, spacing: 0) {
                    thisVersion(facts)
                    if facts.hasEarlier || facts.version == 1 { changedHere(facts) }
                    if !facts.isCurrent { changedSince(facts) }
                }
                .interfaceFont(.body)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .accessibilityIdentifier("VersionHistoryFacts")
        .task(id: Job(
            entry: mode.thread.selection, revision: library.contentRevision, snapshots: mode.thread.snapshots.count,
            isComplete: mode.thread.isComplete, format: dateFormat)
        ) { await refresh() }
    }

    /// Worked out away from the main actor, since comparing two long texts takes a moment.
    private func refresh() async {
        guard let list, let entry = list.entry(mode.thread.selection), let current = list.current else {
            facts = nil
            return
        }
        let older = list.older(than: entry)
        let catalogue = library.catalogue
        let format = dateFormat
        facts = await Task.detached(priority: .userInitiated) {
            VersionFacts.make(for: entry, after: older, current: current, in: catalogue, dateFormat: format)
        }.value
    }

    private func thisVersion(_ facts: VersionFacts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("This Version", isFirst: true)
            fact(Text("Written By")) {
                if let writer = facts.writtenBy {
                    Text(verbatim: writer)
                } else {
                    Text("Not known").foregroundStyle(.secondary)
                }
            }
            fact(Text("Version")) { Text("\(facts.version) of \(facts.latest)") }
            fact(Text("Saved")) {
                if let saved = facts.saved {
                    let text = DateDisplay.text(of: saved, place: .value, format: dateFormat)
                    Text(verbatim: facts.savedIsApproximate ? String(localized: "About \(text)") : text)
                } else {
                    Text("Not known").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func changedHere(_ facts: VersionFacts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Changed Here")
            if facts.changedHere.isEmpty {
                Text(facts.hasEarlier ? "No change to the text, title or fields." : "The first version.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(facts.changedHere) { row in fact(Text(verbatim: row.label)) { Text(verbatim: row.value) } }
            }
        }
    }

    private func changedSince(_ facts: VersionFacts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Changed Since", count: facts.changedSince.count)
            if facts.changedSince.isEmpty {
                Text("Nothing has changed since.").foregroundStyle(.secondary)
            } else {
                ForEach(facts.changedSince) { row in fact(Text(verbatim: row.label)) { Text(verbatim: row.value) } }
            }
        }
    }

    /// A name in a column of one width, and what it says beside it on one line.
    private func fact(_ name: Text, @ViewBuilder value: () -> some View) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        return HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
            name.foregroundStyle(.secondary).lineLimit(1).frame(width: 84 * scale, alignment: .leading)
            value().lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4 * scale)
        .frame(minHeight: 26 * scale)
        .accessibilityElement(children: .combine)
    }

    private func heading(_ title: LocalizedStringKey, count: Int? = nil, isFirst: Bool = false) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        return HStack(alignment: .firstTextBaseline, spacing: 7 * scale) {
            Text(title)
            if let count, count > 0 {
                Text(count, format: .number).monospacedDigit().fontWeight(.regular).foregroundStyle(.tertiary)
            }
        }
        .interfaceFont(.callout.weight(.semibold))
        .padding(.top, (isFirst ? 4 : 22) * scale)
        .padding(.bottom, 8 * scale)
        .accessibilityAddTraits(.isHeader)
    }
}
