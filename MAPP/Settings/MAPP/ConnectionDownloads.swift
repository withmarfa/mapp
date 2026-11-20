import SwiftUI

/// The downloaded files of the open library: the space they use, the limit, the attachments kept offline, and Remove
/// Downloaded Files. What each step does is `DownloadedFiles`', unchanged.
struct ConnectionDownloads: View {
    let files: any DownloadedFiles
    @State private var state: DownloadedFileState?
    @State private var working = false
    @State private var readFailed = false
    @State private var actionFailure: String?

    private static let sizes: [UInt64] = [1, 5, 10, 25, 100].map { $0 * 1_000_000_000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection(
                "Downloaded files",
                footer: "Attachments stay offline and don’t count toward the limit. Removing downloads keeps attachments and files that are waiting to upload."
            ) {
                if let state {
                    SettingsRow("Space used") {
                        SettingsValue(verbatim: state.bytes.map(Self.size) ?? String(localized: "Unavailable"))
                    }
                    SettingsRow("Download limit") {
                        SettingsPopUp(
                            title: "Download limit",
                            selection: Binding(
                                get: { state.budget },
                                set: { budget in change { try await files.setBudget(budget) } })
                        ) {
                            Text("Automatic").tag(DownloadBudget.automatic)
                            ForEach(Self.sizes, id: \.self) { bytes in
                                Text(Self.size(bytes)).tag(DownloadBudget.bytes(bytes))
                            }
                            if case .bytes(let bytes) = state.budget, !Self.sizes.contains(bytes) {
                                Text(Self.size(bytes)).tag(state.budget)
                            }
                            Text("Keep all downloads").tag(DownloadBudget.keepAll)
                        }
                        .disabled(working)
                    }
                    if state.budget == .automatic, let limit = state.limit {
                        SettingsRow("Current limit") { SettingsValue(verbatim: Self.size(limit)) }
                    }
                    if let attachments = state.attachments {
                        SettingsRow("Attachments kept offline") { SettingsValue(verbatim: attachments.held.formatted()) }
                        if attachments.missing > 0 {
                            SettingsRow("Attachments not yet offline") { SettingsValue(verbatim: attachments.missing.formatted()) }
                            ForEach(attachments.reasons, id: \.reason) { missing in
                                SettingsRow(verbatim: DownloadWording.reason(missing), size: .compact, lines: nil)
                            }
                        }
                    } else {
                        SettingsRow("Attachment counts aren’t available.", size: .compact) {}
                    }
                } else if !readFailed {
                    SettingsRow("Reading downloaded files…") { ProgressView().controlSize(.small) }
                }
                if readFailed {
                    SettingsRow("Couldn’t read downloaded files. MAPP will try again.", size: .compact) {}
                }
                if let actionFailure {
                    SettingsRow(verbatim: actionFailure, size: .compact, lines: nil) {}
                }
            }
            if state != nil {
                SettingsButton("Remove Downloaded Files") { change { try await files.removeDownloadedFiles() } }
                    .disabled(working)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
            }
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
                actionFailure = nil
            } catch let failure as SourceFailure {
                actionFailure = failure.message
            } catch {
                actionFailure = String(localized: "Couldn’t change downloaded files. Check the current limit and try again.")
            }
            await read()
        }
    }
}
