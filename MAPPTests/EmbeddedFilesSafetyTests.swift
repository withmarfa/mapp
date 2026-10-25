import AppKit
import Darwin
import Foundation
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import MAPP

/// A scheme task that, like WebKit's own, must hear nothing once it has been stopped.
final class StrictSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var stopped = false
    var callsAfterStop: [String] = []
    var status: Int?
    var data = Data()
    var finished = false
    var failed = false
    var onPiece: () -> Void = {}

    init(_ url: URL) { request = URLRequest(url: url) }

    private func note(_ call: String) { if stopped { callsAfterStop.append(call) } }
    func didReceive(_ response: URLResponse) { note("response"); status = (response as? HTTPURLResponse)?.statusCode }
    func didReceive(_ data: Data) { note("data"); self.data.append(data); onPiece() }
    func didFinish() { note("finish"); finished = true }
    func didFailWithError(_ error: any Error) { note("fail"); failed = true }
}

/// What a scheme task hears once WebKit has stopped it or a folder has changed under it, and what Open hands
/// to other apps.
@Suite(.serialized)
struct EmbeddedFilesSafetyTests {
    @Test func aFileRequestStoppedAtOnceHearsNothing() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let files = EmbeddedFiles()
        files.open = { reference, item in await folder.open(reference, in: item) }
        let webView = WKWebView()
        let task = StrictSchemeTask(EmbeddedFiles.url(for: .name("Photo.png"), in: folder.note, version: 1))
        files.webView(webView, start: task)
        task.stopped = true
        files.webView(webView, stop: task)
        try await Task.sleep(for: .milliseconds(300))
        #expect(task.callsAfterStop.isEmpty, "\(task.callsAfterStop)")
    }

    @Test func anIconRequestStoppedAtOnceHearsNothing() async throws {
        let files = EmbeddedFiles()
        let webView = WKWebView()
        let task = StrictSchemeTask(EmbeddedFiles.iconURL(for: .commaSeparatedText))
        files.webView(webView, start: task)
        task.stopped = true
        files.webView(webView, stop: task)
        try await Task.sleep(for: .milliseconds(300))
        #expect(task.callsAfterStop.isEmpty, "WebKit raises on these: \(task.callsAfterStop)")
    }

    @Test func aFolderSwappedForALinkAfterResolvingIsNotServed() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let secret = Data("outside the directory".utf8)
        let outside = folder.outside.url.appending(path: "Attachments")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try secret.write(to: outside.appending(path: "Photo.png"))
        let files = EmbeddedFiles()
        files.open = { reference, item in
            guard let url = folder.resolve(reference, in: item) else { return .missing }
            // What another writer to the folder could do between finding the file and opening it.
            let attachments = folder.root.url.appending(path: "Attachments")
            try? FileManager.default.moveItem(at: attachments, to: folder.root.url.appending(path: "Moved"))
            try? FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: outside)
            return EmbedResolution(await OpenFile.open(url, inside: folder.root.url))
        }
        let task = StrictSchemeTask(EmbeddedFiles.url(for: .path("../Attachments/Photo.png"), in: folder.note, version: 1))
        files.webView(WKWebView(), start: task)
        for _ in 0..<200 where !task.finished && !task.failed { try await Task.sleep(for: .milliseconds(5)) }
        #expect(task.status == 404)
        #expect(task.data != secret, "served \(task.status ?? 0): a file outside the folder through a folder swapped for a link")
    }

    @Test func aPipeSwappedInAfterResolvingDoesNotHang() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let file = folder.root.url.appending(path: "Attachments/Photo.png")
        let files = EmbeddedFiles()
        files.open = { reference, item in
            guard let url = folder.resolve(reference, in: item) else { return .missing }
            try? FileManager.default.removeItem(at: file)
            mkfifo(file.path, 0o644)
            return EmbedResolution(await OpenFile.open(url, inside: folder.root.url))
        }
        let task = StrictSchemeTask(EmbeddedFiles.url(for: .name("Photo.png"), in: folder.note, version: 1))
        files.webView(WKWebView(), start: task)
        for _ in 0..<200 where !task.finished && !task.failed && task.status == nil { try await Task.sleep(for: .milliseconds(5)) }
        let answered = task.finished || task.failed || task.status != nil
        // Releases the reader so the rest of the suite keeps its thread.
        let writer = open(file.path, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        #expect(answered, "a reading thread is blocked opening a pipe")
    }

    @Test func openNeverHandsOverAFileThatMightRun() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let script = "#!/bin/sh\nexit 0\n"
        let refused = [
            "Report", "Invoice.command", "Run.tool", "Setup.sh", "tool.py", "Settings.terminal", "Site.fileloc",
            "Site.webloc", "Site.inetloc", "App.jar", "Bundle.zip", "Page.html", "Page.webarchive", "Drawing.svg", "Data.json",
            "Mystery.xyz",
        ]
        for name in refused {
            try folder.root.write(script, to: "Attachments/\(name)")
            chmod(folder.root.url.appending(path: "Attachments/\(name)").path, 0o755)
            let url = try #require(folder.resolve(.name(name), in: folder.note))
            #expect(!EmbeddedFiles.opens(url), "Open would hand \(name), marked executable, to an app")
            chmod(url.path, 0o644)
            #expect(!EmbeddedFiles.opens(url), "Open would hand \(name) to an app that runs or follows it, or is of no kind it can tell")
        }
        let opened = ["Photo.png", "Song.mp3", "Clip.mov", "Plan.pdf", "Table.tsv", "Sheet.csv", "Letter.docx", "Sums.xlsx", "Deck.pptx", "Essay.rtf", "Book.epub", "Report.pages"]
        for name in opened {
            try folder.write(Data("x".utf8), to: "Attachments/\(name)")
            let url = try #require(OpenFile.realPath(of: folder.root.url)).appending(path: "Attachments/\(name)")
            #expect(EmbeddedFiles.opens(url), "\(name) is a document to open")
        }
        let marked = folder.root.url.appending(path: "Attachments/Photo.png")
        chmod(marked.path, 0o744)
        #expect(!EmbeddedFiles.opens(marked), "a document marked executable may be something else")
    }

    @Test func aFileIsOpenedThroughNoLinkAnywhereInItsPath() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let real = try #require(OpenFile.realPath(of: folder.root.url))
        let root = folder.root.url
        #expect(await OpenFile.open(real.appending(path: "Attachments/Photo.png"), inside: root) != nil)
        // `Linked` is a link to a folder outside, which holds `secret.png`.
        #expect(await OpenFile.open(real.appending(path: "Linked/secret.png"), inside: root) == nil)
        #expect(await OpenFile.open(real.appending(path: "Attachments/link.png"), inside: root) == nil)
    }

    /// Whatever path a file was found at, only what the descriptor opened is trusted.
    @Test func onlyAFileOpenedInsideTheFolderIsKept() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let root = folder.root.url
        let outside = try #require(OpenFile.realPath(of: folder.outside.url)).appending(path: "secret.png")
        #expect(await OpenFile.open(outside, inside: root) == nil, "a file outside the folder, reached by no link")
        let real = try #require(OpenFile.realPath(of: root))
        #expect(await OpenFile.open(real.appending(path: ".marfa/Secret.png"), inside: root) == nil, "a hidden folder")
        #expect(await OpenFile.open(real.appending(path: "Attachments"), inside: root) == nil, "a folder")
        let opened = try #require(await OpenFile.open(real.appending(path: "Attachments/Photo.png"), inside: root))
        #expect(opened.url.lastPathComponent == "Photo.png")
        #expect(opened.length == UInt64(try EmbedFixtures.png().count))

    }

    @Test func aPipeIsNeverOpenedForReading() async throws {
        let folder = try EmbeddedFilesTests.Folder()
        let real = try #require(OpenFile.realPath(of: folder.root.url))
        let pipe = real.appending(path: "Attachments/Pipe.png")
        try #require(mkfifo(pipe.path, 0o644) == 0)
        let started = ContinuousClock.now
        #expect(await OpenFile.open(pipe, inside: folder.root.url) == nil)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}
