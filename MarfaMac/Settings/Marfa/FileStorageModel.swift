import Foundation
import Marfa
import Observation

/// Where the server keeps files, and the files nothing uses. Its own settings (copies, reserve, reading, fetching, clean-up)
/// are This Marfa's (`InstanceSettingsModel`); this is only what the server reports.
@Observable @MainActor final class FileStorageModel {
    private let context: OwnerContext

    private(set) var stores: FileStores?
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private(set) var metrics: InstanceMetricsReading?
    var fileBytes: Int? { metrics?.fileBytes }
    private let metricsRead = OwnerLoader.ReadStatus()
    var fileBytesFailure: OwnerFailure? { metricsRead.failure }
    /// The usage bar. It loads on its own, so a failure there leaves the file locations on the page.
    private let usageLoader = OwnerLoader()
    private(set) var usage: StorageBar.Reading?
    var usageFailure: OwnerFailure? { usageLoader.failure }
    /// The load whose answer may still be drawn. A newer load, or one cancelled by leaving the page, drops an older answer.
    private var usageGeneration = 0

    init(context: OwnerContext) {
        self.context = context
    }

    static func readsUsage(_ grants: Set<InstancePermission>) -> Bool {
        grants.contains(.instanceRead)
    }

    func load() async {
        async let places: Void = loadPlaces()
        async let bar: Void = loadUsageIfAllowed()
        _ = await (places, bar)
    }

    /// Reads the bar again. The rest of the page is left as it is.
    func loadUsage() async {
        let mine = usageGeneration + 1
        await usageLoader.load(in: context, waitForPrevious: true, primary: { [self] () throws(OwnerFailure) in
            usageGeneration = mine
            let answer = try await context.calls.storageUsage()
            guard mine == usageGeneration, !Task.isCancelled else { return }
            usage = StorageBar.reading(from: answer)
        })
    }

    private func loadPlaces() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            stores = try await context.calls.fileStores()
        }, secondary: [
            .required(metricsRead) { [self] () throws(OwnerFailure) in metrics = try await context.calls.instanceMetrics() },
        ])
    }

    private func loadUsageIfAllowed() async {
        guard Self.readsUsage(context.grants()) else { return }
        await loadUsage()
    }
}
