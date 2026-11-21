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
        SettingsSection(
            "Downloaded Files",
            footer: "Attachments stay offline and don’t count toward the limit."
        ) {
            if let state {
                SettingsRow("Space Used") {
                    SettingsValue(verbatim: state.bytes.map(Self.size) ?? String(localized: "Unavailable"))
                }
                SettingsRow("Download Limit") {
                    SettingsPopUp(
                        title: "Download Limit",
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
                        Text("Keep All Downloads").tag(DownloadBudget.keepAll)
                    }
                    .disabled(working)
                }
                if state.budget == .automatic, let limit = state.limit {
                    SettingsRow("Current Limit") { SettingsValue(verbatim: Self.size(limit)) }
                }
                if let attachments = state.attachments {
                    SettingsRow("Attachments Kept Offline") { SettingsValue(verbatim: attachments.held.formatted()) }
                    if attachments.missing > 0 {
                        SettingsRow("Attachments Not Yet Offline") { SettingsValue(verbatim: attachments.missing.formatted()) }
                        ForEach(attachments.reasons, id: \.reason) { missing in
                            SettingsRow(verbatim: DownloadWording.reason(missing), size: .compact, lines: nil)
                        }
                    }
                } else {
                    SettingsRow("Attachment counts aren’t available.", size: .compact) {}
                }
                SettingsRow("Remove Downloaded Files", line: "Keeps attachments and files waiting to upload.") {
                    SettingsButton("Remove") { change { try await files.removeDownloadedFiles() } }
                        .disabled(working)
                }
            } else if !readFailed {
                SettingsRow("Reading Downloaded Files…") { ProgressView().controlSize(.small) }
            }
            if readFailed {
                SettingsProblemRow(title: Text("Couldn’t Read Downloaded Files"), line: Text("MAPP will try again."), actions: [])
            }
            if let actionFailure {
                SettingsRow(verbatim: actionFailure, size: .compact, lines: nil) {}
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
