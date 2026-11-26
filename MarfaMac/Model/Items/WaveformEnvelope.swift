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

    /// Reads the file's sound at a low rate and keeps its peaks, or nil where it has none or cannot be read. A two-hour
    /// file reads in the time it takes to decode it, in a task that stops when the page goes.
    @concurrent static func read(_ url: URL, type: UTType?, duration: Double) async -> WaveformEnvelope? {
        guard duration > 0 else { return nil }
        let asset = FileMedia.asset(at: url, type: type)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 8000,
        ])
        guard reader.canAdd(output) else { return nil }
        let provider = reader.outputProvider(for: output)
        guard (try? reader.start()) != nil else { return nil }
        let rate = 8000.0
        let total = duration * rate
        var peaks = [Float](repeating: 0, count: resolution)
        var index = 0.0
        while let buffer = try? await provider.next() {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            buffer.withUnsafeSampleBuffer { sampleBuffer in
                guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
                let count = CMBlockBufferGetDataLength(block) / 2
                var samples = [Int16](repeating: 0, count: count)
                let copied = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 2, destination: $0.baseAddress!) }
                guard copied == kCMBlockBufferNoErr else { return }
                for sample in samples {
                    let bucket = min(Int(index / total * Double(resolution)), resolution - 1)
                    let level = Float(abs(Int32(sample))) / 32768
                    if level > peaks[bucket] { peaks[bucket] = level }
                    index += 1
                }
            }
        }
        guard reader.status == .completed, let loudest = peaks.max(), loudest > 0 else { return nil }
        // Quiet parts stay visible beside loud ones.
        return WaveformEnvelope(levels: peaks.map { pow($0 / loudest, 0.7) })
    }
}
