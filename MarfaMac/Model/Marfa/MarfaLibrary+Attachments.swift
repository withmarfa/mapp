import Foundation

extension MarfaLibrary {
    /// The files go to the source as files of their own, which this removes once it has taken them. Each is
    /// attached to the item by the package, which says what the page writes in the text to embed it.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async -> AttachReport {
        sendWaitingText()
        let directory = URL.temporaryDirectory.appending(path: "marfa-mac-attach-\(UUID().uuidString)", directoryHint: .isDirectory)
        let staged = await Self.stage(files, in: directory)
        var report = AttachReport()
        for (file, staged) in zip(files, staged) {
            do {
                report.embeds.append(try await source.embeds.attach(try staged.get(), to: id))
            } catch {
                report.failed.append((file.name, error.localizedDescription))
            }
        }
        await Self.removeStaged(directory)
        return report
    }

    /// Writes each file where the package can read it, in a folder of its own, so two files with one name each
    /// keep their bytes.
    @concurrent private static func stage(_ files: [(name: String, data: Data)], in directory: URL) async -> [Result<URL, any Error>] {
        files.enumerated().map { index, file in
            Result {
                let folder = directory.appending(path: String(index), directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: FileName.attachmentName(file.name))
                try file.data.write(to: url)
                return url
            }
        }
    }

    @concurrent private static func removeStaged(_ directory: URL) async {
        try? FileManager.default.removeItem(at: directory)
    }

    func attach(file: URL, to id: ItemID) async throws -> Embed {
        sendWaitingText()
        return try await source.embeds.attach(file, to: id)
    }

    func addFile(_ file: URL, title: String?, parentID: ItemID?, in place: Place) async -> ItemID? {
        let cantAdd = String(localized: "Can’t Add File")
        do {
            // The Feed is the feed tier, so a file added there stays where it was added.
            return try await source.embeds.addFile(file, title: title, tier: place == .feed ? .feed : nil, parent: parentID)
        } catch let failure as SourceFailure {
            notices.tell(cantAdd, failure.message)
        } catch {
            notices.tell(cantAdd, error.localizedDescription)
        }
        return nil
    }
}
