@testable import MAPP
import Foundation
import Network
import Testing
import WebKit

/// A server on this Mac that counts what reaches it, so a test can show that a blocked request never left the page
/// rather than only that it failed.
nonisolated final class Probe: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections = 0
    private var requests: [String] = []
    private(set) var port: UInt16 = 0

    var count: Int { lock.withLock { connections } }
    /// The request lines that arrived, for a failure message that says what got through.
    var seen: [String] { lock.withLock { requests } }

    init() async throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [self] connection in
            lock.withLock { connections += 1 }
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, _ in
                let line = data.flatMap { String(decoding: $0, as: UTF8.self).split(separator: "\r\n").first.map(String.init) } ?? ""
                self.lock.withLock { self.requests.append(line) }
            }
            // Answers anything, so a request that got through would load.
            let body = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\nok".utf8)
            connection.send(content: body, completion: .contentProcessed { _ in connection.cancel() })
        }
        let (states, report) = AsyncStream<NWListener.State>.makeStream()
        listener.stateUpdateHandler = { report.yield($0) }
        listener.start(queue: .global())
        for await state in states {
            if case .failed(let error) = state { throw error }
            if case .ready = state { break }
        }
        port = listener.port?.rawValue ?? 0
    }

    deinit { listener.cancel() }
}

@MainActor struct SealedWebPageTests {
    /// A document that tries every way to reach out, then reports what happened.
    private func hostile(port: UInt16) -> Data {
        let target = "http://127.0.0.1:\(port)"
        return Data("""
            <!doctype html><html><body>
            <form id="f" method="post" action="\(target)/form"><input name="a" value="1"></form>
            <a id="link" href="\(target)/link">link</a>
            <script>
            window.results = { ran: 'yes' };
            const pending = [];
            function track(name, promise) {
              const timeout = new Promise(res => setTimeout(() => res('pending'), 4000));
              pending.push(Promise.race([promise, timeout]).then(v => results[name] = v, () => results[name] = 'blocked'));
            }
            function load(make) {
              return new Promise((resolve, reject) => { const e = make(resolve, reject); document.body.append(e); });
            }
            track('fetch', fetch('\(target)/fetch', { mode: 'no-cors' }).then(() => 'loaded'));
            track('xhr', new Promise((res, rej) => {
              const x = new XMLHttpRequest(); x.open('GET', '\(target)/xhr'); x.onload = () => res('loaded'); x.onerror = () => rej(); x.send();
            }));
            track('image', load((res, rej) => { const i = new Image(); i.onload = () => res('loaded'); i.onerror = () => rej(); i.src = '\(target)/img.png'; return i; }));
            track('script', load((res, rej) => { const s = document.createElement('script'); s.onload = () => res('loaded'); s.onerror = () => rej(); s.src = '\(target)/s.js'; return s; }));
            track('frame', load((res, rej) => { const f = document.createElement('iframe'); f.onload = () => res(f.contentDocument === null ? 'blocked' : 'loaded'); f.onerror = () => rej(); f.src = '\(target)/frame'; return f; }));
            track('socket', new Promise((res, rej) => { const s = new WebSocket('ws://127.0.0.1:\(port)/socket'); s.onopen = () => res('loaded'); s.onerror = () => rej(); }));
            document.getElementById('f').submit();
            document.getElementById('link').click();
            location.href = '\(target)/navigate';
            window.open('\(target)/popup');
            Promise.all(pending).then(() => setTimeout(() => { results.href = location.href; window.done = true; }, 500));
            </script></body></html>
            """.utf8)
    }

    private func results(of page: SealedWebPage) async throws -> [String: String] {
        let finished = try await eventuallyAsking {
            (try await page.page.callJavaScript("return window.done === true") as? Bool) == true
        }
        try #require(finished)
        let json = try await page.page.callJavaScript("return JSON.stringify(window.results)") as? String
        return try JSONDecoder().decode([String: String].self, from: Data(try #require(json).utf8))
    }

    @Test func aPageThatReachesOutReachesNothing() async throws {
        let probe = try await Probe()
        let page = try await SealedWebPage.make()
        try await page.show(hostile(port: probe.port))
        let results = try await results(of: page)
        #expect(results["ran"] == "yes", "JavaScript runs")
        for attempt in ["fetch", "xhr", "image", "script", "frame", "socket"] {
            // A blocked load answers with an error; one that never answers is still no load.
            #expect(results[attempt] == "blocked" || results[attempt] == "pending", "\(attempt) did not load")
        }
        #expect(results["href"] == "about:blank", "the form, the link, location and window.open went nowhere")
        // A fixed wait, to give a request that was wrongly let through time to arrive.
        try await Task.sleep(for: .milliseconds(500))
        #expect(probe.count == 0, "nothing reached the server, but \(probe.seen) did")
    }

    @Test func whatTheDocumentHoldsItselfStillLoads() async throws {
        let gif = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        let page = try await SealedWebPage.make()
        try await page.show(Data("""
            <html><body><script>
            window.results = {};
            const i = new Image();
            i.onload = () => { results.image = 'loaded'; window.done = true; };
            i.onerror = () => { results.image = 'blocked'; window.done = true; };
            i.src = '\(gif)';
            </script></body></html>
            """.utf8))
        #expect(try await results(of: page) == ["image": "loaded"])
    }

    @Test func theSameDocumentReachesTheServerWithoutTheSeal() async throws {
        // The control: the same page in an ordinary web page does reach the probe, so the test above can tell.
        let probe = try await Probe()
        let page = WebPage()
        // The document navigates away from itself, so the load is not awaited.
        _ = page.load(hostile(port: probe.port), mimeType: "text/html", characterEncoding: .utf8, baseURL: URL(string: "about:blank")!)
        try await Task.sleep(for: .seconds(2))
        #expect(probe.count > 0)
    }

    @Test func aLaterDocumentReplacesTheFirst() async throws {
        let page = try await SealedWebPage.make()
        try await page.show(Data("<html><body><script>window.results = {n: '1'}; window.done = true;</script></body></html>".utf8))
        try await page.show(Data("<html><body><script>window.results = {n: '2'}; window.done = true;</script></body></html>".utf8))
        #expect(try await results(of: page) == ["n": "2"])
    }

    @Test func aPageKeepsNothingBetweenOpens() async throws {
        let write = "try { localStorage.setItem('k', 'v') } catch (e) {} document.cookie = 'a=b'; window.results = {}; window.done = true;"
        let read = "let k = 'denied'; try { k = String(localStorage.getItem('k')) } catch (e) {} window.results = {k: k, c: document.cookie}; window.done = true;"
        let first = try await SealedWebPage.make()
        try await first.show(Data("<html><body><script>\(write)</script></body></html>".utf8))
        _ = try await results(of: first)
        let second = try await SealedWebPage.make()
        try await second.show(Data("<html><body><script>\(read)</script></body></html>".utf8))
        let kept = try await results(of: second)
        #expect(kept["c"] == "")
        #expect(kept["k"] == "denied" || kept["k"] == "null")
    }
}
