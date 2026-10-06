import AppKit
import AVFoundation
import Darwin
import Foundation
import Testing
import WebKit
@testable import MAPP

/// Small real files of each kind, made by code so the tests carry no binaries.
enum EmbedFixtures {
    static func png(width: Int = 4, height: Int = 3) throws -> Data {
        try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.representation(using: .png, properties: [:]))
    }

    /// Half a second of a tone, as 16-bit mono PCM.
    static func wav(seconds: Double = 0.5, rate: Int = 8000) -> Data {
        let samples = Int(Double(rate) * seconds)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples * 2))
        for index in 0..<samples {
            append(Int16(sin(Double(index) * 2 * .pi * 440 / Double(rate)) * 8000))
        }
        return data
    }

    /// A second of 64 by 64 H.264 video in a QuickTime movie.
    static func movie(to url: URL) async throws {
        let size = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed, "\(String(describing: writer.error))")
    }

    /// One page filled red, so a frame showing it can be told from an empty one.
    static func pdf(to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
    }
}

/// A request WebKit would make of the scheme, keeping what the app answers.
final class RecordingSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: HTTPURLResponse?
    var data = Data()
    var received = 0
    var largestPiece = 0
    var finished = false
    var failure: (any Error)?
    /// Bytes are only counted, so the test itself holds nothing of a large file.
    var keepsData = true
    var onPiece: () -> Void = {}

    init(_ url: URL, range: String? = nil) {
        var request = URLRequest(url: url)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        self.request = request
    }

    func didReceive(_ response: URLResponse) { self.response = response as? HTTPURLResponse }

    func didReceive(_ data: Data) {
        received += data.count
        largestPiece = max(largestPiece, data.count)
        if keepsData { self.data.append(data) }
        onPiece()
    }

    func didFinish() { finished = true }
    func didFailWithError(_ error: any Error) { failure = error }
}

@Suite(.serialized)
struct EmbeddedFilesTests {
    /// A notes folder with a note in `Projects/` and files around it, and a folder outside it.
    final class Folder {
        let root: TemporaryFolder
        let outside: TemporaryFolder
        let bin: TemporaryFolder
        let note: Note
        let library: NoteLibrary

        init(body: String = "") throws {
            root = try TemporaryFolder()
            outside = try TemporaryFolder()
            bin = try TemporaryFolder()
            let png = try EmbedFixtures.png()
            for path in ["Attachments/Photo.png", "Projects/Beside.png", "Other/Beside.png", "a/z/pic.png", "bz/pic.png", "Top.png", "Deep/er/Top.png"] {
                try Self.put(png, at: path, in: root)
            }
            try root.write("Plan\n", to: "Projects/Plan.md")
            try root.write("Hidden\n", to: ".marfa/Secret.png")
            try png.write(to: outside.url.appending(path: "secret.png"))
            let manager = FileManager.default
            try manager.createSymbolicLink(at: root.url.appending(path: "Attachments/link.png"), withDestinationURL: outside.url.appending(path: "secret.png"))
            try manager.createSymbolicLink(at: root.url.appending(path: "Linked"), withDestinationURL: outside.url)
            note = Note(path: "Projects/Embeds.md", text: body, created: .now)
            library = NoteLibrary(notes: [note], store: FolderStore(root: root.url, bin: bin.url))
        }

        func write(_ data: Data, to path: String) throws {
            try Self.put(data, at: path, in: root)
        }

        static func put(_ data: Data, at path: String, in root: TemporaryFolder) throws {
            let file = root.url.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }

        func file(_ reference: EmbedReference) async -> String? {
            let base = root.url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count
            return await library.embeddedFile(reference, in: note.id)?.pathComponents.dropFirst(base).joined(separator: "/")
        }
    }

    @Test func aPathIsReadFromTheNoteAndAFolderRootAsMarfaReadsIt() async throws {
        let folder = try Folder()
        #expect(await folder.file(.path("../Attachments/Photo.png")) == "Attachments/Photo.png")
        #expect(await folder.file(.path("/Attachments/Photo.png")) == "Attachments/Photo.png")
        #expect(await folder.file(.path("Beside.png")) == "Projects/Beside.png")
        #expect(await folder.file(.path("./Beside.png?size=2#top")) == "Projects/Beside.png")
        #expect(await folder.file(.path("..%2FAttachments%2FPhoto.png")) == "Attachments/Photo.png")
        #expect(await folder.file(.path("../attachments/PHOTO.PNG")) != nil, "a path names a file whatever its case")
    }

    @Test func nothingOutsideTheFolderIsReached() async throws {
        let folder = try Folder()
        #expect(await folder.file(.path("../../secret.png")) == nil, "a path leading out of the folder")
        #expect(await folder.file(.path("../../../../../../../../etc/hosts")) == nil)
        #expect(await folder.file(.path(folder.outside.url.appending(path: "secret.png").path)) == nil, "an absolute path is read from the folder's root")
        #expect(await folder.file(.path("/etc/hosts")) == nil)
        #expect(await folder.file(.path("../Attachments/link.png")) == nil, "a symbolic link to a file")
        #expect(await folder.file(.path("../Linked/secret.png")) == nil, "a symbolic link to a folder")
        #expect(await folder.file(.name("secret.png")) == nil, "a name never reaches through a link")
        #expect(await folder.file(.path("../.marfa/Secret.png")) == nil, "a hidden file")
        #expect(await folder.file(.path("../Attachments")) == nil, "a folder")
        #expect(await folder.file(.path("https://example.com/Photo.png")) == nil)
        #expect(await folder.file(.path("//example.com/Photo.png")) == nil)
        let stranger = ItemID.mint()
        #expect(await folder.library.embeddedFile(.path("../Attachments/Photo.png"), in: stranger) == nil, "an item the library does not hold")
    }

    @Test func aDocumentEmbeddedIsANoteNotAFile() async throws {
        let folder = try Folder()
        #expect(await folder.file(.path("Plan.md")) == nil)
        #expect(await folder.file(.name("Plan.md")) == nil)
        #expect(await folder.file(.name("Plan")) == nil)
    }

    @Test func aNameIsResolvedAsObsidianAndMarfaResolveIt() async throws {
        let folder = try Folder()
        #expect(await folder.file(.name("Photo.png")) == "Attachments/Photo.png")
        #expect(await folder.file(.name("photo.PNG")) == "Attachments/Photo.png")
        #expect(await folder.file(.name("Beside.png")) == "Projects/Beside.png", "the note's own directory first")
        #expect(await folder.file(.name("Top.png")) == "Top.png", "the path from the root")
        #expect(await folder.file(.name("z/pic.png")) == "a/z/pic.png", "at a directory's edge, never inside a name")
        #expect(await folder.file(.name("/Attachments/Photo.png")) == "Attachments/Photo.png")
        #expect(await folder.file(.name("../Attachments/Photo.png")) == "Attachments/Photo.png", "`../` is a path")
        #expect(await folder.file(.name("./Beside.png")) == "Projects/Beside.png")
        #expect(await folder.file(.name("Gone.png")) == nil)
        #expect(EmbedPaths.named("pic.png", from: "", among: ["x/y/pic.png", "x/pic.png", "w/pic.png"]) == "w/pic.png", "the shallowest, then path order")
    }

    // MARK: Serving

    func serve(_ folder: Folder, _ reference: EmbedReference, range: String? = nil, keepingData: Bool = true) async throws -> RecordingSchemeTask {
        let files = EmbeddedFiles()
        files.resolve = { reference, item in await folder.library.embeddedFile(reference, in: item) }
        let task = RecordingSchemeTask(EmbeddedFiles.url(for: reference, in: folder.note.id, version: 1), range: range)
        task.keepsData = keepingData
        files.webView(WKWebView(), start: task)
        for _ in 0..<2000 where !task.finished && task.failure == nil { try await Task.sleep(for: .milliseconds(5)) }
        try #require(task.finished)
        return task
    }

    @Test func aFileIsServedWholeOrByRange() async throws {
        let folder = try Folder()
        let bytes = Data((0..<3000).map { UInt8($0 % 251) })
        try folder.write(bytes, to: "Attachments/Tone.wav")
        let reference = EmbedReference.name("Tone.wav")

        let whole = try await serve(folder, reference)
        #expect(whole.response?.statusCode == 200)
        #expect(whole.response?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("audio/") == true)
        #expect(whole.response?.value(forHTTPHeaderField: "Content-Length") == "3000")
        #expect(whole.response?.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(whole.data == bytes)

        let start = try await serve(folder, reference, range: "bytes=0-1")
        #expect(start.response?.statusCode == 206)
        #expect(start.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 0-1/3000")
        #expect(start.data == bytes[0...1])

        let middle = try await serve(folder, reference, range: "bytes=1000-2999")
        #expect(middle.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 1000-2999/3000")
        #expect(middle.response?.value(forHTTPHeaderField: "Content-Length") == "2000")
        #expect(middle.data == bytes[1000...2999])

        let open = try await serve(folder, reference, range: "bytes=2990-")
        #expect(open.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 2990-2999/3000")
        #expect(open.data == bytes[2990...])

        let suffix = try await serve(folder, reference, range: "bytes=-10")
        #expect(suffix.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 2990-2999/3000")

        let past = try await serve(folder, reference, range: "bytes=5000-")
        #expect(past.response?.statusCode == 416)
        #expect(past.response?.value(forHTTPHeaderField: "Content-Range") == "bytes */3000")
        #expect(past.received == 0)

        let missing = try await serve(folder, .name("Gone.wav"))
        #expect(missing.response?.statusCode == 404)
        let linked = try await serve(folder, .path("../Attachments/link.png"))
        #expect(linked.response?.statusCode == 404)
    }

    @Test func aRangeHeaderIsReadAsHTTPReadsIt() {
        #expect(EmbeddedFiles.span(nil, length: 10) == .whole)
        #expect(EmbeddedFiles.span("bytes=0-", length: 10) == .part(0, 9))
        #expect(EmbeddedFiles.span("bytes=2-4", length: 10) == .part(2, 4))
        #expect(EmbeddedFiles.span("bytes=8-100", length: 10) == .part(8, 9))
        #expect(EmbeddedFiles.span("bytes=-3", length: 10) == .part(7, 9))
        #expect(EmbeddedFiles.span("bytes=-30", length: 10) == .part(0, 9))
        #expect(EmbeddedFiles.span("bytes=10-", length: 10) == .unsatisfiable)
        #expect(EmbeddedFiles.span("bytes=0-1,4-5", length: 10) == .whole)
        #expect(EmbeddedFiles.span("bytes=5-2", length: 10) == .whole)
        #expect(EmbeddedFiles.span("items=0-1", length: 10) == .whole)
    }

    @Test func aNameWithCharactersAQueryUsesIsCarriedWhole() throws {
        let item = ItemID.mint()
        for reference in [EmbedReference.name("R&D = 100% + more?#.png"), .path("../A%20b/c&d.png#page=2")] {
            let url = EmbeddedFiles.url(for: reference, in: item, version: 3)
            let request = try #require(EmbeddedFiles.request(in: url))
            #expect(request.item == item)
            #expect(request.reference == reference)
        }
    }

    /// The memory the process holds, as the system counts it against the app.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @Test func aLargeFileIsStreamedInPiecesWithoutBeingHeldInMemory() async throws {
        let folder = try Folder()
        let size: UInt64 = 200 * 1024 * 1024
        let file = folder.root.url.appending(path: "Attachments/Large.mov")
        try #require(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: size)
        try handle.close()

        let before = Self.footprint()
        try #require(before > 0)
        var peak = before
        let files = EmbeddedFiles()
        files.resolve = { reference, item in await folder.library.embeddedFile(reference, in: item) }
        let task = RecordingSchemeTask(EmbeddedFiles.url(for: .name("Large.mov"), in: folder.note.id, version: 1))
        task.keepsData = false
        task.onPiece = { peak = max(peak, Self.footprint()) }
        files.webView(WKWebView(), start: task)
        for _ in 0..<6000 where !task.finished && task.failure == nil { try await Task.sleep(for: .milliseconds(5)) }
        try #require(task.finished)
        #expect(UInt64(task.received) == size)
        #expect(task.largestPiece <= EmbeddedFiles.piece)
        #expect(peak - before < 48 * 1024 * 1024, "the footprint grew by \(peak - before) bytes")
    }

    @Test func aStoppedRequestHearsNothingMore() async throws {
        let folder = try Folder()
        try folder.write(Data(count: 8 * EmbeddedFiles.piece), to: "Attachments/Long.wav")
        let files = EmbeddedFiles()
        files.resolve = { reference, item in await folder.library.embeddedFile(reference, in: item) }
        let webView = WKWebView()
        let task = RecordingSchemeTask(EmbeddedFiles.url(for: .name("Long.wav"), in: folder.note.id, version: 1))
        task.keepsData = false
        task.onPiece = { files.webView(webView, stop: task) }
        files.webView(webView, start: task)
        try await Task.sleep(for: .milliseconds(300))
        #expect(task.received == EmbeddedFiles.piece, "WebKit throws on a task it has stopped")
        #expect(!task.finished)
    }

    @Test func eachKindOfFileIsToldAsThePageShowsIt() {
        #expect(EmbeddedFiles.kind(of: .png) == "image")
        #expect(EmbeddedFiles.kind(of: .mp3) == "audio")
        #expect(EmbeddedFiles.kind(of: .wav) == "audio")
        #expect(EmbeddedFiles.kind(of: .quickTimeMovie) == "video")
        #expect(EmbeddedFiles.kind(of: .mpeg4Movie) == "video")
        #expect(EmbeddedFiles.kind(of: .pdf) == "pdf")
        #expect(EmbeddedFiles.kind(of: .commaSeparatedText) == "file")
        #expect(EmbeddedFiles.kind(of: .zip) == "file")
        #expect(EmbeddedFiles.kind(of: nil) == "file")
    }
}
