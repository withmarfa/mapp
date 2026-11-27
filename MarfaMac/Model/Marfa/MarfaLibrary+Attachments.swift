import AppKit
import Foundation

/// Where a file the item would not take ended up.
private enum KeptAside {
    case library
    case clipboard
    case left(String)
}

extension MarfaLibrary {
    /// Stages each file and attaches it to the item. A file the item will not take is added to the Library, attached
    /// to nothing, or put on the clipboard when that cannot be done. The staged file is removed only once one of
    /// those has succeeded.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async -> AttachReport {
        sendWaitingText()
        let directory = URL.temporaryDirectory.appending(path: "marfa-mac-attach-\(UUID().uuidString)", directoryHint: .isDirectory)
        let staged = await Self.stage(files, in: directory)
        var report = AttachReport()
        var removable: [URL] = []
        for (index, (file, staged)) in zip(files, staged).enumerated() {
            let url: URL
            do {
                url = try staged.get()
            } catch {
                report.failed.append((file.name, error.localizedDescription))
                try? FileManager.default.removeItem(at: directory.appending(path: String(index), directoryHint: .isDirectory))
                continue
            }
            do {
                report.embeds.append(try await source.embeds.attach(url, to: id))
                removable.append(url)
            } catch {
                switch await keptAside(url) {
                case .library:
                    report.kept.append((file.name, .library))
                    removable.append(url)
                case .clipboard:
                    report.kept.append((file.name, .clipboard))
                    removable.append(url)
                case .left(let reason):
                    report.failed.append((file.name, reason))
                }
            }
        }
        await Self.removeKept(removable, in: directory)
        return report
    }

    /// Adds the staged file as an item of its own, or puts it on the clipboard. Neither posts its own notice:
    /// the report says where it went, and the file stays put when neither can take it.
    private func keptAside(_ url: URL) async -> KeptAside {
        do {
            _ = try await source.embeds.addFile(url, title: nil, tier: .library, tags: [], parent: nil)
            return .library
        } catch {
            if copyImageToClipboard(url) { return .clipboard }
            // The temporary directory is a symlink, so the path told is the file itself.
            let path = url.resolvingSymlinksInPath().path
            return .left(String(localized: "It couldn’t be copied to the clipboard. The copy is still at \(path)."))
        }
    }

    /// Puts the image on the clipboard. False when it cannot, which leaves the staged file where it is.
    private func copyImageToClipboard(_ url: URL) -> Bool {
        #if DEBUG
        if let replacement = hooks.copyingToClipboard.current { return replacement() }
        #endif
        // The clipboard is holding text the person has not answered; nothing may write over it.
        guard !notices.holdsTextOnClipboard else { return false }
        let pasteboard = NSPasteboard.general
        let data = try? Data(contentsOf: url)
        let image = data.flatMap { NSImage(data: $0) }
        // A write leaves what is already there, so a paste can miss the image.
        pasteboard.clearContents()
        if let image, pasteboard.writeObjects([image]) { return true }
        return pasteboard.writeObjects([url as NSURL])
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

    /// Removes the staged copies that were attached or kept, and the directory once it holds nothing.
    @concurrent private static func removeKept(_ files: [URL], in directory: URL) async {
        for file in files {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        if (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.isEmpty == true {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func attach(file: URL, to id: ItemID) async throws -> Embed {
        sendWaitingText()
        return try await source.embeds.attach(file, to: id)
    }

    func addFile(_ file: URL, title: String?, parentID: ItemID?, tier: Tier, tags: [String]) async -> ItemID? {
        let cantAdd = String(localized: "Can’t Add File")
        do {
            return try await source.embeds.addFile(file, title: title, tier: tier, tags: tags, parent: parentID)
        } catch let failure as SourceFailure {
            notices.tell(cantAdd, failure.message)
        } catch {
            notices.tell(cantAdd, error.localizedDescription)
        }
        return nil
    }
}
