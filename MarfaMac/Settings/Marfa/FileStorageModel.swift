import Foundation
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

    init(context: OwnerContext) {
        self.context = context
    }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            stores = try await context.calls.fileStores()
        }, secondary: [
            .required(metricsRead) { [self] () throws(OwnerFailure) in metrics = try await context.calls.instanceMetrics() },
        ])
    }
}
