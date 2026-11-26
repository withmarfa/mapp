import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// An item's place in its audio or video is kept on this Mac, written when playback pauses and when the item is left,
/// and never taken past the file's end.
@MainActor
@Suite(.serialized, .hangLimit)
struct PlaybackPlaceTests {
    private func defaults() -> UserDefaults { ThrowawayDefaults.make("MarfaMacTests.PlaybackPlaces") }

    /// Two seconds of a tone, kept under a hash with no extension as a Marfa file is.
    private func sound() throws -> URL {
        let rate: UInt32 = 8000
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let samples = (0..<Int(rate) * 2).map { Int16(sin(Double($0) * 0.2) * 12_000) }
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + samples.count * 2)); data.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
        for sample in samples { put(sample) }
        let folder = FileManager.default.temporaryDirectory.appending(path: "PlaybackPlaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: String(repeating: "cd", count: 32))
        try data.write(to: url)
        return url
    }

    @Test func aPlaceOutsideTheFileOpensAtTheStart() {
        #expect(PlaybackPlaces.opening(kept: nil, duration: 100) == 0)
        #expect(PlaybackPlaces.opening(kept: 40, duration: 100) == 40)
        #expect(PlaybackPlaces.opening(kept: 100, duration: 100) == 0)
        #expect(PlaybackPlaces.opening(kept: 250, duration: 100) == 0)
        #expect(PlaybackPlaces.opening(kept: -3, duration: 100) == 0)
        #expect(PlaybackPlaces.opening(kept: .nan, duration: 100) == 0)
    }

    @Test func theNewestPlacesAreKeptAndAnUnreadableStoreIsSetAside() {
        let defaults = defaults()
        let first = ItemID.mint()
        PlaybackPlaces.keep(30, of: first, in: defaults)
        for _ in 0..<PlaybackPlaces.limit { PlaybackPlaces.keep(30, of: .mint(), in: defaults) }
        #expect(PlaybackPlaces.place(of: first, in: defaults) == nil)
        let other = ItemID.mint()
        PlaybackPlaces.keep(12, of: other, in: defaults)
        PlaybackPlaces.keep(0.4, of: other, in: defaults)
        #expect(PlaybackPlaces.place(of: other, in: defaults) == nil)
        defaults.set(Data("not a list".utf8), forKey: PlaybackPlaces.key)
        #expect(PlaybackPlaces.place(of: other, in: defaults) == nil)
        #expect((defaults.array(forKey: PlaybackPlaces.setAsideKey) as? [Data])?.count == 1)
    }

    @Test func thePlaceIsWrittenOnPauseAndOnLeavingAndNeverPastTheEnd() async throws {
        let defaults = defaults()
        let url = try sound()
        let id = ItemID.mint()
        let playback = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        await playback.load()
        #expect(playback.state == .ready)
        // Opening plays nothing, and the file's length is the model's.
        #expect(!playback.isPlaying)
        #expect(abs(playback.duration - 2) < 0.1)

        playback.seek(to: 1.2)
        #expect(PlaybackPlaces.place(of: id, in: defaults) == nil, "a move alone writes nothing")
        playback.pause()
        #expect(abs((PlaybackPlaces.place(of: id, in: defaults) ?? 0) - 1.2) < 0.05)

        playback.seek(to: 99)
        #expect(playback.position <= playback.duration)
        playback.seek(to: 1.0)
        playback.leave()
        #expect(abs((PlaybackPlaces.place(of: id, in: defaults) ?? 0) - 1.0) < 0.05)

        let again = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        await again.load()
        #expect(abs(again.position - 1.0) < 0.05)
        #expect(!again.isPlaying, "a kept place is shown paused")
        again.leave()

        PlaybackPlaces.keep(500, of: id, in: defaults)
        let past = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        await past.load()
        #expect(past.position == 0)
        past.leave()
    }

    /// Two windows on one item: a window never writes a place it already kept, or its opening place, over the other's newer one.
    @Test func aPageLeftUntouchedKeepsAnotherPagesNewerPlace() async throws {
        let defaults = defaults()
        let url = try sound()
        let id = ItemID.mint()
        PlaybackPlaces.keep(0.6, of: id, in: defaults)
        let untouched = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        let played = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        await untouched.load()
        await played.load()
        played.seek(to: 1.2)
        played.pause()
        untouched.leave()
        #expect(abs((PlaybackPlaces.place(of: id, in: defaults) ?? 0) - 1.2) < 0.05)
        played.leave()

        // Once each window has kept its place, closing the one kept earlier leaves the newer place.
        let first = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        let second = MediaPlayback(item: id, url: url, type: .wav, defaults: defaults)
        await first.load()
        await second.load()
        first.seek(to: 1.05)
        first.pause()
        second.seek(to: 1.40)
        second.pause()
        first.leave()
        #expect(abs((PlaybackPlaces.place(of: id, in: defaults) ?? 0) - 1.40) < 0.05)
        second.leave()
    }

    @Test func aFileAVFoundationCannotPlayIsSaidToBeUnplayable() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PlaybackPlaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "broken.m4a")
        try Data("not audio".utf8).write(to: url)
        let playback = MediaPlayback(item: .mint(), url: url, type: .mpeg4Audio, defaults: defaults())
        await playback.load()
        #expect(playback.state == .unplayable)
        playback.leave()
    }

    @Test func aSoundsWaveformIsWorkedOutFromItsLoudness() async throws {
        let url = try sound()
        let envelope = try #require(await WaveformEnvelope.read(url, type: .wav))
        #expect(envelope.levels.count == WaveformEnvelope.resolution)
        #expect(envelope.levels.max() == 1)
        #expect(envelope.bars(40).count == 40)
    }
}
