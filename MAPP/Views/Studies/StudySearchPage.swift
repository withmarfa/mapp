import SwiftUI

struct StudySearchPage: View {
    @Environment(\.locale) private var locale
    @Binding var query: String
    @Binding var kind: StudyRecord.Kind?
    @Binding var selection: String?
    let open: (InterfaceStudy) -> Void

    private var results: [StudyRecord] {
        StudyRecord.samples.filter { record in
            (kind == nil || record.kind == kind) && record.matches(query, locale: locale)
        }
    }

    private var selectedRecord: StudyRecord? {
        results.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            VStack(spacing: 0) {
                searchHeader
                Divider()
                if results.isEmpty {
                    ContentUnavailableView {
                        Label("No matching items", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another word or choose All Types.")
                    } actions: {
                        Button("Clear Search") {
                            query = ""
                            kind = nil
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        resultList
                            .frame(maxWidth: wide ? 370 : .infinity)
                        if wide {
                            Divider()
                            preview
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { wide ? nil : selectedRecord },
                set: { if $0 == nil { selection = nil } }
            )) { record in
                VStack(spacing: 0) {
                    HStack {
                        Text("Item preview").font(.headline)
                        Spacer()
                        Button("Done") { selection = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                    Divider()
                    StudySearchPreview(record: record) { destination in
                        selection = nil
                        open(destination)
                    }
                }
                .frame(minWidth: 400, idealWidth: 520, minHeight: 430, idealHeight: 560)
            }
        }
        .onChange(of: query) { clearHiddenSelection() }
        .onChange(of: kind) { clearHiddenSelection() }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find a thought worth returning to")
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sample titles, text, and sources", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search sample items")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(11)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Picker("Item type", selection: $kind) {
                Text("All Types").tag(Optional<StudyRecord.Kind>.none)
                ForEach(StudyRecord.Kind.allCases) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            Text("\(results.count) of \(StudyRecord.samples.count) sample items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultList: some View {
        List(selection: $selection) {
            ForEach(StudyRecord.Kind.allCases) { kind in
                let group = results.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { record in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(record.title).font(.headline)
                                Text(record.snippet)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(record.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 9)
                            .tag(record.id)
                        }
                    } header: {
                        Text(kind.title)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder private var preview: some View {
        if let selectedRecord {
            StudySearchPreview(record: selectedRecord, open: open)
        } else {
            ContentUnavailableView {
                Label("A closer look", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Select a result to read it here.")
            }
        }
    }

    private func clearHiddenSelection() {
        if selectedRecord == nil { selection = nil }
    }
}

private struct StudySearchPreview: View {
    let record: StudyRecord
    let open: (InterfaceStudy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudyEyebrow(title: record.kind.title, symbol: record.kind.symbol)
                Text(record.title)
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(record.source).font(.subheadline).foregroundStyle(.secondary)
                Divider()
                Text(record.snippet)
                    .font(.system(size: 20, design: .serif))
                    .lineSpacing(5)
                Text(record.detail)
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                if let destination = record.study {
                    Button("Open Full Page", systemImage: "arrow.up.right") {
                        open(destination)
                    }
                    .padding(.top, 8)
                }
                Divider().padding(.top, 12)
                Text("From the sample collection A garden in a small space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("View Collection") { open(.collection) }
                    .buttonStyle(.link)
            }
            .padding(32)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
