import SwiftUI

/// The right sidebar of Version History: who wrote the version chosen and when, what it changed from the version
/// before, and what has changed since, in the grouped boxes the item's inspector uses.
struct VersionFactsPanel: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let mode: VersionHistoryMode
    let list: VersionList?
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
                VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                    thisVersion(facts)
                    if facts.hasEarlier || facts.version == 1 { changedHere(facts) }
                    if !facts.isCurrent { changedSince(facts) }
                }
                .sharesInspectorNameColumn()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            heading("This Version")
            InspectorBox {
                InspectorRow(name: "Written by") {
                    if let writer = facts.writtenBy {
                        InspectorText(text: writer)
                    } else {
                        Text("Not known").foregroundStyle(.secondary)
                    }
                }
                InspectorRow(name: "Version") {
                    InspectorText(text: String(localized: "\(facts.version) of \(facts.latest)"), keepsOneLine: true)
                }
                InspectorRow(name: "Saved") {
                    if let saved = facts.saved {
                        let text = DateDisplay.text(of: saved, place: .value, format: dateFormat)
                        InspectorText(text: facts.savedIsApproximate ? String(localized: "About \(text)") : text, keepsOneLine: true)
                    } else {
                        Text("Not known").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func changedHere(_ facts: VersionFacts) -> some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            heading("Changed Here")
            InspectorBox {
                if facts.changedHere.isEmpty {
                    Text(facts.hasEarlier ? "No change to the text, title or fields." : "The first version.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(facts.changedHere) { row in
                        InspectorRow(fieldLabel: row.label) { InspectorText(text: row.value) }
                    }
                }
            }
        }
    }

    private func changedSince(_ facts: VersionFacts) -> some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            heading("Changed Since", count: facts.changedSince.count)
            InspectorBox {
                if facts.changedSince.isEmpty {
                    Text("Nothing has changed since.").foregroundStyle(.secondary)
                } else {
                    ForEach(facts.changedSince) { row in
                        InspectorRow(fieldLabel: row.label) { InspectorText(text: row.value) }
                    }
                }
            }
        }
    }

    private func heading(_ title: LocalizedStringKey, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if let count, count > 0 {
                Text(count, format: .number).monospacedDigit().fontWeight(.regular).foregroundStyle(.secondary)
            }
        }
        .interfaceFont(.body.weight(.semibold))
        .padding(.horizontal, InspectorMetrics.headingInset)
        .accessibilityAddTraits(.isHeader)
    }
}
