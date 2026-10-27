import Foundation
import Testing
@testable import MAPP

@MainActor struct PictureDisconnectTests {
    /// The pictures kept for a library's notes go with the library. The cache is the app's own folder in the caches
    /// folder of the test host, which has a bundle identifier of its own, never the installed app's.
    @Test func disconnectingRemovesThePicturesKept() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let marker = PictureCache.standardFolder.appending(path: "marker-\(UUID().uuidString)/picture.png")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SamplePicture.png().write(to: marker)

        try await host.disconnect(.keepCopy)

        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
