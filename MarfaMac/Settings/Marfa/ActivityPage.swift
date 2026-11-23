import SwiftUI

/// The Activity page: the server's audit log as a table that is a page of its own, newest first, a page at a time. The server
/// says how many entries there are only by whether another page follows, so the foot says which entries are shown and offers
/// the older and newer page.
struct ActivityPage: View {
    let host: any MarfaSettingsHost
    @State private var model: ActivityModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: ActivityModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    /// A page over a model that already holds its state, for a render to draw.
    init(host: any MarfaSettingsHost, model: ActivityModel) {
        self.host = host
        _model = State(initialValue: model)
    }

    private var columns: [SettingsTableColumn<ActivityEntry>] {
        [
            SettingsTableColumn("When", width: SettingsTokens.Metric.Column.day) { entry in
                Text(verbatim: ActivityWording.when(entry.date)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Who", width: SettingsTokens.Metric.Column.who) { entry in
                Text(verbatim: entry.who ?? String(localized: "Unknown")).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("What") { entry in
                Text(verbatim: ActivityWording.what(entry.action)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Address", width: SettingsTokens.Metric.Column.address) { entry in
                Text(verbatim: entry.address ?? "").foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    var body: some View {
        content
            .task(id: model.filterKey) {
                if model.hasLoaded { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await model.reload()
            }
            .accessibilityIdentifier("ActivityPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, model.entries.isEmpty, !model.isFiltered {
            OwnerFailureState(page: .activity, failure: failure, host: host) { Task { await model.reload() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else {
            SettingsLogTable(
                rows: model.entries, columns: columns, count: Text("Newest first"),
                filter: {
                    SettingsTableFilter(choice: $model.kind, search: $model.search) {
                        Text("All Activity").tag(ActivityKind?.none)
                        Divider()
                        ForEach(ActivityKind.allCases, id: \.self) { kind in Text(verbatim: kind.title).tag(ActivityKind?.some(kind)) }
                    }
                },
                foot: {
                    if let failure = model.failure, !model.entries.isEmpty {
                        Text(verbatim: OwnerWording.line(failure)).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                    } else if let range = model.range {
                        Text(verbatim: range).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if model.isLoading { ProgressView().controlSize(.small) }
                    if model.isPaged {
                        SettingsButton("Newer", small: true) { Task { await model.newer() } }
                            .disabled(model.pageIndex == 0 || model.isLoading)
                            .accessibilityIdentifier("ActivityNewer")
                        SettingsButton("Older", small: true) { Task { await model.older() } }
                            .disabled(!model.hasNext || model.isLoading)
                            .accessibilityIdentifier("ActivityOlder")
                    }
                },
                empty: {
                    if let failure = model.failure {
                        OwnerFailureState(page: .activity, failure: failure, host: host) { Task { await model.reload() } }
                    } else if model.isFiltered {
                        SettingsStateContent(symbol: "magnifyingglass", title: Text("Nothing Matches"), line: Text("No activity fits this filter."), action: nil)
                    } else {
                        SettingsStateContent(
                            symbol: "list.bullet.rectangle", title: Text("No Activity Yet"),
                            line: Text("What happens in \(host.serverName) is recorded here."), action: nil)
                    }
                })
        }
    }
}
