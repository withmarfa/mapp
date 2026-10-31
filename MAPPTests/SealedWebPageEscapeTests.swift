@testable import MAPP
import Foundation
import Testing
import WebKit

/// Each way a script might still reach WebRTC from inside the sealed page, tried on its own against a UDP listener that
/// counts the datagrams that arrive.
@Suite(.serialized, .hangLimit) @MainActor struct SealedWebPageEscapeTests {
    enum Escape: String, CaseIterable, CustomTestStringConvertible {
        case blankFrameAtOnce, blankFrameEval, blankFrameSrcLater, srcdocFrame, dataFrame, blobFrame
        case blobWorker, blobSharedWorker, openedBlank, sandboxedSrcdocFrame, objectFrame, parserWrittenFrame

        var testDescription: String { rawValue }

        /// Whether an ordinary web page can send a datagram this way, which the control checks. WebKit exposes no peer
        /// connection in a worker, and a page with no window-creating delegate gets no window from `window.open`.
        var sendsWhenUnsealed: Bool { ![.blobWorker, .blobSharedWorker, .openedBlank].contains(self) }
    }

    /// The page script for one escape. `connect` tries a peer connection through the given constructor and says what
    /// happened, `report` records it, and `inner` is the document a frame holds, which does the same from its own realm.
    private func document(for escape: Escape, udpPort: UInt16) throws -> Data {
        let connect = #"""
            function connect(P) {
              if (!P) return 'absent';
              try {
                const pc = new P({ iceServers: [{ urls: 'stun:127.0.0.1:\#(udpPort)' }] });
                pc.createDataChannel('x');
                pc.createOffer().then(o => pc.setLocalDescription(o)).catch(() => {});
                return 'constructed';
              } catch (e) { return 'threw ' + e.name; }
            }
            """#
        let inner = "<script>\(connect)\nparent.postMessage({ name: '\(escape.rawValue)', outcome: connect(window.RTCPeerConnection || window.webkitRTCPeerConnection) }, '*');</script>"
        let worker = #"""
            \#(connect)
            const answer = { outcome: connect(self.RTCPeerConnection || self.webkitRTCPeerConnection), peer: typeof RTCPeerConnection, media: typeof navigator.mediaDevices };
            if (typeof postMessage === 'function') postMessage(answer); else onconnect = e => e.ports[0].postMessage(answer);
            """#
        func literal(_ text: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed), as: UTF8.self)
        }
        let body: String
        switch escape {
        case .blankFrameAtOnce:
            body = "const f = document.createElement('iframe'); document.body.append(f); report(connect(f.contentWindow.RTCPeerConnection));"
        case .blankFrameEval:
            body = "const f = document.createElement('iframe'); document.body.append(f); report(f.contentWindow.eval('(' + connect.toString() + ')(window.RTCPeerConnection)'));"
        case .blankFrameSrcLater:
            body = """
                const f = document.createElement('iframe'); document.body.append(f); f.src = 'about:blank';
                const early = connect(f.contentWindow.RTCPeerConnection);
                f.onload = () => report(early + ' then ' + connect(f.contentWindow.RTCPeerConnection) + ' then ' + f.contentWindow.eval('(' + connect.toString() + ')(window.RTCPeerConnection)'));
                """
        case .srcdocFrame:
            body = "const f = document.createElement('iframe'); f.srcdoc = \(try literal(inner)); document.body.append(f);"
        case .dataFrame:
            body = "const f = document.createElement('iframe'); f.src = 'data:text/html;base64,' + btoa(\(try literal(inner))); document.body.append(f);"
        case .blobFrame:
            body = "const f = document.createElement('iframe'); f.src = URL.createObjectURL(new Blob([\(try literal(inner))], { type: 'text/html' })); document.body.append(f);"
        case .blobWorker:
            body = """
                try { const w = new Worker(URL.createObjectURL(new Blob([\(try literal(worker))], { type: 'text/javascript' })));
                  w.onmessage = e => report(JSON.stringify(e.data)); w.onerror = e => report('worker error'); } catch (e) { report('threw ' + e.name); }
                """
        case .blobSharedWorker:
            body = """
                try { const w = new SharedWorker(URL.createObjectURL(new Blob([\(try literal(worker))], { type: 'text/javascript' })));
                  w.port.onmessage = e => report(JSON.stringify(e.data)); w.onerror = e => report('worker error'); } catch (e) { report('threw ' + e.name); }
                """
        case .sandboxedSrcdocFrame:
            body = "const f = document.createElement('iframe'); f.sandbox = 'allow-scripts'; f.srcdoc = \(try literal(inner)); document.body.append(f);"
        case .objectFrame:
            body = "const o = document.createElement('object'); o.data = 'about:blank'; document.body.append(o); report(connect(o.contentWindow && o.contentWindow.RTCPeerConnection));"
        case .parserWrittenFrame:
            body = "document.write('<iframe id=\"parsed\"></iframe>'); report(connect(document.getElementById('parsed').contentWindow.RTCPeerConnection));"
        case .openedBlank:
            body = "const w = window.open('about:blank'); report(w ? connect(w.RTCPeerConnection) : 'no window');"
        }
        return Data("""
            <!doctype html><html><body><script>
            window.results = {};
            function report(outcome) { results.outcome = outcome; }
            addEventListener('message', e => { if (e.data && e.data.outcome) results.outcome = e.data.outcome; });
            \(connect)
            try { \(body) } catch (e) { results.outcome = 'threw ' + e.name + ': ' + e.message; }
            setTimeout(() => { window.done = true; }, 2500);
            </script></body></html>
            """.utf8)
    }

    private func run(_ escape: Escape, sealed: Bool) async throws -> (outcome: String, probe: DatagramProbe) {
        let probe = try await DatagramProbe()
        let html = try document(for: escape, udpPort: probe.port)
        let page: WebPage
        if sealed {
            let made = try await SealedWebPage.make(runsScripts: true)
            try await made.show(html)
            page = made.page
        } else {
            page = WebPage()
            _ = page.load(html, mimeType: "text/html", characterEncoding: .utf8, baseURL: URL(string: "about:blank")!)
        }
        let finished = try await eventuallyAsking {
            (try? await page.callJavaScript("return window.done === true") as? Bool) == true
        }
        try #require(finished)
        let outcome = try await page.callJavaScript("return String(window.results.outcome)") as? String ?? "?"
        return (outcome, probe)
    }

    @Test(arguments: Escape.allCases) func noEscapeSendsADatagram(_ escape: Escape) async throws {
        let (outcome, probe) = try await run(escape, sealed: true)
        // The page ran its escape 2.5 s before it reported done; this gives a datagram that was wrongly sent the
        // last of its travel to the probe.
        try await Task.sleep(for: .milliseconds(300))
        let datagrams = probe.count
        #expect(datagrams == 0, "\(escape.rawValue) sent \(datagrams) datagrams (\(outcome))")
    }

    @Test(arguments: Escape.allCases) func theSameEscapeSendsWithoutTheSeal(_ escape: Escape) async throws {
        let (outcome, probe) = try await run(escape, sealed: false)
        if escape.sendsWhenUnsealed {
            let sent = await eventually(within: .seconds(20)) { probe.count > 0 }
            #expect(sent, "the control for \(escape.rawValue) sent nothing (\(outcome))")
        }
    }
}
