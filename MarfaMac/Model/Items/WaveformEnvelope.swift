import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// How loud a sound is along its length, worked out once for an open file and kept in memory only while its page is open.
/// It holds a fixed number of values from 0 to 1, however long the file is, and the page picks as many bars from them as
/// its width has room for.
nonisolated struct WaveformEnvelope: Sendable, Equatable {
    static let resolution = 800

    /// Loudness, 0 to 1, in equal parts of the file's length.
    let levels: [Float]

    /// `count` bars, each the loudest of its part of the file.
    func bars(_ count: Int) -> [Float] {
        guard count > 0, !levels.isEmpty else { return [] }
        return (0..<count).map { bar in
            let start = bar * levels.count / count
            let end = max(start + 1, (bar + 1) * levels.count / count)
            return levels[start..<min(end, levels.count)].max() ?? 0
        }
    }

    /// Decodes the file in chunks and keeps the peaks, or nil where it has no sound or cannot be read. It reads through
    /// the audio file reader, which decodes in this process and needs no audio device, and stops when the page goes. A
    /// two-hour file takes the time its decoding takes, and nothing waits for it.
    @concurrent static func read(_ url: URL, type: UTType?) async -> WaveformEnvelope? {
        // A Marfa file has no extension, which the reader may need to tell its format: a copy that has one is read.
        let copy = type.flatMap { QuickLookFile.copy(of: url, titled: "Sound", as: $0, in: "Waveforms") }
        defer { copy?.remove() }
        guard let file = try? AVAudioFile(forReading: copy?.url ?? url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536) else { return nil }
        let total = Double(file.length)
        let channels = Int(file.processingFormat.channelCount)
        var peaks = [Float](repeating: 0, count: resolution)
        var index = 0.0
        while file.framePosition < file.length {
            if Task.isCancelled { return nil }
            do { try file.read(into: buffer) } catch { return nil }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let bucket = min(Int((index + Double(frame)) / total * Double(resolution)), resolution - 1)
                var level: Float = 0
                for channel in 0..<channels { level = max(level, abs(data[channel][frame])) }
                if level > peaks[bucket] { peaks[bucket] = level }
            }
            index += Double(buffer.frameLength)
        }
        guard let loudest = peaks.max(), loudest > 0 else { return nil }
        // Quiet parts stay visible beside loud ones.
        return WaveformEnvelope(levels: peaks.map { pow($0 / loudest, 0.7) })
    }
}
