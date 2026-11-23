import Foundation

/// Why a looks file was not written or kept.
nonisolated enum LooksFileError: Error, Equatable, Sendable {
    /// The file could not be written.
    case unwritable
    /// The file could not be read.
    case unreadable
    /// The file is not a looks file this version reads. Nothing was kept.
    case notALooksFile
    /// The library's types have not loaded, so there is nothing to measure the file against. Nothing was kept.
    case notLoaded
}

extension TypeLooks {
    /// The most a looks file may hold: a server with thousands of types writes well under this.
    static let largestFile = 8_000_000

    /// Writes every look of the catalogue's types on `library` to `url` (`file(in:library:)`).
    func exportLooks(to url: URL, in catalogue: Catalogue, library: String) throws(LooksFileError) {
        do {
            try file(in: catalogue, library: library).encoded().write(to: url, options: .atomic)
        } catch {
            throw .unwritable
        }
    }

    /// Keeps what differs in the file at `url` on `library` (`importLooks(_:into:in:)`). A catalogue that has not loaded, a
    /// file that cannot be read and one that is not a looks file are refused and nothing is kept.
    func importLooks(from url: URL, into library: String, in catalogue: Catalogue) throws(LooksFileError) {
        guard !catalogue.itemTypes.isEmpty else { throw .notLoaded }
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.largestFile else { throw LooksFileError.notALooksFile }
            data = try Data(contentsOf: url)
        } catch let error as LooksFileError {
            throw error
        } catch {
            throw .unreadable
        }
        guard let file = LooksFile.read(data) else { throw .notALooksFile }
        importLooks(file, into: library, in: catalogue)
    }
}
