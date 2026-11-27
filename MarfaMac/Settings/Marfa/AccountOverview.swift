import Foundation
import MarfaAPI
import Observation

/// Shares the server’s attention list and readings between Account, Connection and the sidebar.
@Observable @MainActor final class AccountOverview {
    private let context: OwnerContext

    private(set) var concerns: [AttentionConcern] = []
    private(set) var metrics: InstanceMetricsReading?
    private var update: UpdateStatus?
    private(set) var owner: String?

    var updateReady: String? {
        guard releaseFailure == nil, let update, update.available, let latest = update.latest?.version else { return nil }
        if metricsFailure == nil, let installed = metrics?.version {
            guard let offered = PluginVersion(latest), let running = PluginVersion(installed), offered > running else { return nil }
        }
        return latest
    }
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private let metricsRead = OwnerLoader.ReadStatus()
    private let updateRead = OwnerLoader.ReadStatus()
    var metricsFailure: OwnerFailure? { metricsRead.failure }
    var releaseFailure: OwnerFailure? { updateRead.failure }
    var hasLoaded: Bool { loader.hasLoaded }

    init(context: OwnerContext) {
        self.context = context
    }

    var attentionBadge: Int? { failure != nil || concerns.isEmpty ? nil : concerns.count }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            concerns = try await context.calls.attention()
        }, secondary: [
            .required(metricsRead) { [self] () throws(OwnerFailure) in metrics = try await context.calls.instanceMetrics() },
            .required(updateRead) { [self] () throws(OwnerFailure) in update = try await context.calls.updateStatus() },
            .quiet { [self] () throws(OwnerFailure) in
                let profile = try await context.calls.profile()
                owner = profile.name ?? profile.username
            },
        ])
    }

}
