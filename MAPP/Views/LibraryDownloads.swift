import SwiftUI

struct LibraryDownloads: View {
    let files: any DownloadedFiles
    @State private var state: DownloadedFileState?
    @State private var working = false
    @State private var readFailed = false
    @State private var actionFailed = false

    private static let sizes: [UInt64] = [1, 5, 10, 25, 100].map { $0 * 1_000_000_000 }

    var body: some View {
        Section {
            if let state {
                LabeledContent("Space Used") {
                    if let bytes = state.bytes { Text(Self.size(bytes)) }
                    else { Text("Unavailable") }
                }
                Picker("Download Limit", selection: Binding(
                    get: { state.budget },
                    set: { budget in change { try await files.setBudget(budget) } }
                )) {
                    Text("Automatic").tag(DownloadBudget.automatic)
                    ForEach(Self.sizes, id: \.self) { bytes in
                        Text(Self.size(bytes)).tag(DownloadBudget.bytes(bytes))
                    }
                    if case .bytes(let bytes) = state.budget, !Self.sizes.contains(bytes) {
                        Text(Self.size(bytes)).tag(state.budget)
                    }
                    Text("Keep All Downloads").tag(DownloadBudget.keepAll)
                }
                .disabled(working)
                if state.budget == .automatic, let limit = state.limit {
                    Text("Current limit: \(Self.size(limit))")
                        .foregroundStyle(.secondary)
                }
                if let attachments = state.attachments {
                    Text("^[\(attachments.held) attachment](inflect: true) kept offline")
                    if attachments.missing > 0 {
                        Text("^[\(attachments.missing) attachment](inflect: true) not yet offline")
                            .foregroundStyle(.secondary)
                        ForEach(attachments.reasons, id: \.reason) { missing in
                            Text(DownloadWording.reason(missing))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Attachment counts are unavailable.")
                        .foregroundStyle(.secondary)
                }
                Button("Remove Downloaded Files") {
                    change { try await files.removeDownloadedFiles() }
                }
                .disabled(working)
            } else {
                Text("Reading downloaded files…").foregroundStyle(.secondary)
            }
            if readFailed {
                Text("Couldn’t read downloaded files. MAPP will try again.")
                    .foregroundStyle(.secondary)
            }
            if actionFailed {
                Text("Couldn’t change downloaded files. Check the current limit and try again.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Downloaded Files")
        } footer: {
            Text("Attachments stay offline and don’t count toward the limit. Removing downloads keeps attachments and files waiting to upload.")
        }
        .accessibilityIdentifier("LibraryDownloads")
        .task {
            while !Task.isCancelled {
                if !working { await read() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func read() async {
        do {
            state = try await files.read()
            readFailed = false
        } catch {
            readFailed = true
        }
    }

    private func change(_ action: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await action()
                actionFailed = false
            } catch {
                actionFailed = true
            }
            await read()
        }
    }
}
