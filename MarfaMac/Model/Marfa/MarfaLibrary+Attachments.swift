import Foundation

extension MarfaLibrary {
    /// Stages each file and attaches it to the item. A file the item will not take is moved into Downloads under its
    /// own name, or the next free name. The staged file is removed only once that move has succeeded.
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
                do {
                    let saved = try saveRefused(url)
                    report.kept.append(KeptFile(name: file.name, file: saved))
                    removable.append(url)
                } catch {
                    // The temporary directory is a symlink, so the path told is the file itself.
                    let path = url.resolvingSymlinksInPath().path
                    report.failed.append((file.name, String(localized: "It couldn’t be saved to Downloads. The copy is still at \(path).")))
                }
            }
        }
        await Self.removeKept(removable, in: directory)
        return report
    }

    /// Moves the staged file into Downloads. A test can name the folder, or throw to leave the file where it is.
    private func saveRefused(_ url: URL) throws -> URL {
        let folder: URL
        #if DEBUG
        if let replacement = hooks.savingRefusedFile.current {
            folder = try replacement()
        } else {
            folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
        #else
        folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #endif
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try Self.move(url, into: folder)
    }

    /// How many names to try before the staged file is left where it is.
    private static let nameTries = 10_000

    /// The move is what finds a free name: looking first can lose it to a file that lands in between.
    private static func move(_ url: URL, into folder: URL) throws -> URL {
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        for number in 1...nameTries {
            let candidate = number == 1 ? name : (ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            do {
                let destination = folder.appending(path: candidate)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            } catch {
                guard alreadyThere(error) else { throw error }
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Whether the move lost the name to a file already there, including the one error underneath.
    private static func alreadyThere(_ error: any Error) -> Bool {
        func matches(_ error: NSError) -> Bool {
            error.domain == CocoaError.errorDomain && error.code == CocoaError.fileWriteFileExists.rawValue
                || error.domain == POSIXError.errorDomain && error.code == Int(POSIXError.EEXIST.rawValue)
        }
        let ns = error as NSError
        if matches(ns) { return true }
        guard let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return matches(underlying)
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
