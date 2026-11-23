import Foundation
import Observation

/// Where the server keeps files, and the files nothing uses. Its own settings (copies, reserve, reading, fetching, clean-up)
/// are This Marfa's (`InstanceSettingsModel`); this is only what the server reports.
@Observable @MainActor final class FileStorageModel {
    private let context: OwnerContext

    private(set) var stores: FileStores?
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false

    init(context: OwnerContext) {
        self.context = context
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            stores = try await context.calls.fileStores()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
        }
    }
}
