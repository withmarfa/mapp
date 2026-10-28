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

/// The same for UDP, which a content rule never sees: counts the datagrams that arrive.
nonisolated final class DatagramProbe: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var datagrams = 0
    private(set) var port: UInt16 = 0

    var count: Int { lock.withLock { datagrams } }

    init() async throws {
        listener = try NWListener(using: .udp, on: .any)
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: .global())
            receive(on: connection)
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

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [self] data, _, _, error in
            if data != nil { lock.withLock { datagrams += 1 } }
            if error == nil { receive(on: connection) }
        }
    }

    deinit { listener.cancel() }
}

@MainActor struct SealedWebPageTests {
    /// A document that tries every way to reach out, then reports what happened.
    private func hostile(port: UInt16) -> Data {
        let target = "http://127.0.0.1:\(port)"
        return Data("""
            <!doctype html><html><head><meta http-equiv="refresh" content="0;url=\(target)/meta"></head><body>
            <form id="f" method="post" action="\(target)/form"><input name="a" value="1"></form>
            <a id="link" href="\(target)/link">link</a>
            <a id="blank" href="\(target)/blank" target="_blank">blank</a>
            <style>
              @import url("\(target)/import.css");
              body { background: url("\(target)/background.png"); }
              p { list-style-image: url("\(target)/list.png"); cursor: url("\(target)/cursor.png"), auto; }
            </style>
            <p>styled</p>
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
            document.getElementById('blank').click();
            results.beacon = String(navigator.sendBeacon('\(target)/beacon', 'x'));
            const refresh = document.createElement('meta'); refresh.httpEquiv = 'refresh'; refresh.content = '0;url=\(target)/refresh';
            document.head.append(refresh);
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
        #expect(results["href"] == "about:blank", "the form, the links, a refresh, location and window.open went nowhere")
        // A fixed wait, to give a request that was wrongly let through time to arrive.
        try await Task.sleep(for: .milliseconds(500))
        #expect(probe.count == 0, "nothing reached the server, but \(probe.seen) did")
    }

    /// A document that tries to open a WebRTC connection that gathers candidates through a STUN server it names, from
    /// its own realm and from every kind of frame it can build, then reports which of them could.
    private func peerConnecting(udpPort: UInt16) -> Data {
        Data("""
            <!doctype html><html><body><script>
            window.results = {};
            const stun = { iceServers: [{ urls: 'stun:127.0.0.1:\(udpPort)' }] };
            function attempt(name, scope) {
              const names = ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCSessionDescription', 'RTCIceCandidate'];
              const present = names.filter(n => typeof scope[n] !== 'undefined');
              const media = typeof scope.navigator.mediaDevices !== 'undefined';
              results[name] = present.length === 0 && !media ? 'absent' : 'present: ' + present.join(',') + (media ? ',mediaDevices' : '');
              const Peer = scope.RTCPeerConnection || scope.webkitRTCPeerConnection;
              if (!Peer) return;
              try {
                const pc = new Peer(stun);
                pc.createDataChannel('x');
                pc.createOffer().then(o => pc.setLocalDescription(o)).catch(() => {});
              } catch (e) {}
            }
            attempt('main', window);
            const blank = document.createElement('iframe');
            document.body.append(blank);
            attempt('blankFrame', blank.contentWindow);
            const srcdoc = document.createElement('iframe');
            srcdoc.srcdoc = '<p>x</p>';
            document.body.append(srcdoc);
            srcdoc.onload = () => attempt('srcdocFrame', srcdoc.contentWindow);
            const written = document.createElement('iframe');
            document.body.append(written);
            written.contentDocument.open(); written.contentDocument.write('<p>x</p>'); written.contentDocument.close();
            attempt('writtenFrame', written.contentWindow);
            const nested = document.createElement('iframe');
            document.body.append(nested);
            const inner = nested.contentDocument.createElement('iframe');
            nested.contentDocument.body.append(inner);
            attempt('nestedFrame', inner.contentWindow);
            // A frame taken from a window opened by the document.
            const opened = window.open('about:blank');
            if (opened) attempt('openedWindow', opened); else results.openedWindow = 'absent';
            setTimeout(() => { window.done = true; }, 1000);
            </script></body></html>
            """.utf8)
    }

    @Test func aPageCannotOpenAPeerConnection() async throws {
        let probe = try await DatagramProbe()
        let page = try await SealedWebPage.make()
        try await page.show(peerConnecting(udpPort: probe.port))
        let results = try await results(of: page)
        for frame in ["main", "blankFrame", "srcdocFrame", "writtenFrame", "nestedFrame", "openedWindow"] {
            #expect(results[frame] == "absent", "\(frame) has no WebRTC: \(results[frame] ?? "never ran")")
        }
        // A fixed wait, to give a datagram that was wrongly sent time to arrive.
        try await Task.sleep(for: .seconds(2))
        #expect(probe.count == 0, "\(probe.count) datagrams reached the server")
    }

    @Test func theSamePeerConnectionSendsDatagramsWithoutTheSeal() async throws {
        // The control: an ordinary web page does send the datagram, so the test above can tell.
        let probe = try await DatagramProbe()
        let page = WebPage()
        _ = page.load(peerConnecting(udpPort: probe.port), mimeType: "text/html", characterEncoding: .utf8, baseURL: URL(string: "about:blank")!)
        let sent = await eventually(within: .seconds(20)) { probe.count > 0 }
        #expect(sent, "the control sent no datagram, so the test above shows nothing")
    }

    @Test func theGateLetsThroughOnlyTheLoadItWasToldAbout() {
        let gate = SealedWebPage.NavigationGate()
        let elsewhere = URL(string: "http://127.0.0.1:9/")
        #expect(gate.decide(url: SealedWebPage.base, inMainFrame: true) == .cancel, "nothing is allowed until a load is started")
        gate.allow(SealedWebPage.base)
        #expect(gate.decide(url: elsewhere, inMainFrame: true) == .cancel, "another request cannot take the allowance")
        #expect(gate.decide(url: nil, inMainFrame: true) == .cancel)
        #expect(gate.decide(url: SealedWebPage.base, inMainFrame: true) == .allow, "the load's own request passes")
        #expect(gate.decide(url: SealedWebPage.base, inMainFrame: true) == .cancel, "once")
        gate.allow(SealedWebPage.base)
        gate.disallow()
        #expect(gate.decide(url: SealedWebPage.base, inMainFrame: true) == .cancel, "the allowance ends with the load")
    }

    @Test func theGateAllowsOnlyFramesTheDocumentBuildsForItself() {
        let gate = SealedWebPage.NavigationGate()
        for allowed in ["about:blank", "data:text/html,x", "blob:null/1", "DATA:text/html,x"] {
            #expect(gate.decide(url: URL(string: allowed), inMainFrame: false) == .allow, "\(allowed)")
        }
        for refused in ["http://127.0.0.1:9/", "https://example.com/", "file:///etc/hosts"] {
            #expect(gate.decide(url: URL(string: refused), inMainFrame: false) == .cancel, "\(refused)")
        }
    }

    /// When one page held every document, a navigation the shown document started while the next document's load waited
    /// for its policy decision replaced that load, which WebKit then dropped without finishing or failing it, so `show`
    /// never returned. The time limit makes that a failure rather than a run that never ends.
    @Test(.timeLimit(.minutes(1))) func aNavigationTheLastDocumentLeftPendingGoesNowhere() async throws {
        let probe = try await Probe()
        let page = try await SealedWebPage.make()
        // A message loop, which no timer throttling slows, starts a navigation at every turn of the page's event loop,
        // so one is always starting while the next load waits for its policy decision.
        try await page.show(Data("""
            <html><body><script>
            const channel = new MessageChannel();
            channel.port1.onmessage = () => { location.href = 'http://127.0.0.1:\(probe.port)/pending'; channel.port2.postMessage(0); };
            channel.port2.postMessage(0);
            </script></body></html>
            """.utf8))
        weak var navigating = page.page
        for n in 1...5 {
            try await page.show(Data("<html><body><script>window.results = {n: '\(n)'}; window.done = true;</script></body></html>".utf8))
        }
        #expect(try await results(of: page) == ["n": "5"])
        #expect(await eventually { navigating == nil }, "the page that held the navigating document is let go, which ends its scripts")
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
        #expect(await eventually { probe.count > 0 })
    }

    @Test func aLaterDocumentReplacesTheFirst() async throws {
        let page = try await SealedWebPage.make()
        try await page.show(Data("<html><body><script>window.results = {n: '1'}; window.done = true;</script></body></html>".utf8))
        try await page.show(Data("<html><body><script>window.results = {n: '2'}; window.done = true;</script></body></html>".utf8))
        #expect(try await results(of: page) == ["n": "2"])
    }

    @Test func aCancelledShowLeavesTheEarlierDocumentShowing() async throws {
        let page = try await SealedWebPage.make()
        try await page.show(Data("<html><body><script>window.results = {n: '1'}; window.done = true;</script></body></html>".utf8))
        let shown = page.page
        let later = Task { try await page.show(Data("<html><body><script>window.results = {n: '2'}; window.done = true;</script></body></html>".utf8)) }
        later.cancel()
        await #expect(throws: (any Error).self) { try await later.value }
        #expect(page.page === shown)
        #expect(try await results(of: page) == ["n": "1"])
    }

    @Test func aShowThatAnotherStartedBeforeItFinishedThrowsAndLeavesTheNewerDocument() async throws {
        let page = try await SealedWebPage.make()
        // Both start before either load can finish, since the first reaches its load and waits for WebKit before the
        // second runs, so the first is the older whichever load ends first.
        let older = Task { try await page.show(Data("<html><body><script>window.results = {n: '1'}; window.done = true;</script></body></html>".utf8)) }
        let newer = Task { try await page.show(Data("<html><body><script>window.results = {n: '2'}; window.done = true;</script></body></html>".utf8)) }
        await #expect(throws: CancellationError.self) { try await older.value }
        try await newer.value
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
