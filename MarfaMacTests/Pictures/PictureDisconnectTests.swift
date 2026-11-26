import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit)
@MainActor struct PictureDisconnectTests {
    /// The pictures and opened files kept for a library's items go with that library, and another Marfa's stay. The
    /// folders are the test host's own, under its bundle identifier, never the installed app's.
    @Test func disconnectingRemovesOnlyThatMarfasPicturesAndFiles() async throws {
        let bench = HostBench()
        let first = try MarfaConnection(address: "http://first.test:8210")
        let second = try MarfaConnection(address: "http://second.test:8210")
        bench.servers.instances.withLock { $0 = [first: "instance-a", second: "instance-b"] }
        let host = bench.host(cleaner: MarfaHost.standardCleaner)
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")
        let firstFolder = bench.location.directory(for: first).lastPathComponent
        let secondFolder = bench.location.directory(for: second).lastPathComponent
        #expect(firstFolder != secondFolder)
        let markers = try [firstFolder, secondFolder].map { folder in
            let picture = PictureCache.folder(for: folder).appending(path: "marker/picture.png")
            let file = MarfaSource.keptFiles(for: folder).appending(path: "marker/file.txt")
            for url in [picture, file] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("kept".utf8).write(to: url)
            }
            return (picture, file)
        }
        defer {
            for folder in [firstFolder, secondFolder] {
                try? FileManager.default.removeItem(at: PictureCache.folder(for: folder))
                try? FileManager.default.removeItem(at: MarfaSource.keptFiles(for: folder))
            }
        }

        try await host.disconnect(.keepCopy)

        #expect(!FileManager.default.fileExists(atPath: markers[1].0.path))
        #expect(!FileManager.default.fileExists(atPath: markers[1].1.path))
        #expect(FileManager.default.fileExists(atPath: markers[0].0.path), "the other Marfa's pictures stay")
        #expect(FileManager.default.fileExists(atPath: markers[0].1.path), "the other Marfa's opened files stay")
    }

    /// A picture whose fetch began for one Marfa is kept in that Marfa's cache, and one whose Marfa was disconnected
    /// meanwhile is not kept at all; another Marfa's cache is untouched either way.
    @Test func aLatePictureStaysWithItsOwnMarfa() async throws {
        let left = WebPictures.kept(for: "late-\(UUID().uuidString)")
        let other = WebPictures.kept(for: "other-\(UUID().uuidString)")
        defer {
            for cache in [left.cache, other.cache] { try? FileManager.default.removeItem(at: cache.folder) }
        }
        #expect(left.cache.folder != other.cache.folder)
        #expect(WebPictures.kept(for: left.cache.folder.lastPathComponent) === left)
        let leftBefore = left.cache.generation
        let otherBefore = other.cache.generation

        await PictureCache.removeAll(in: left.cache.folder)

        #expect(left.cache.generation != leftBefore)
        #expect(other.cache.generation == otherBefore, "removing one Marfa's pictures never stops another's fetches")
    }
}
