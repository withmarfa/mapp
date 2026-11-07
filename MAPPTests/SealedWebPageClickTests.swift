@testable import MAPP
import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit

/// What a person does to a document once it has loaded, delivered to the web view as real events.
nonisolated enum Gesture: Sendable {
    /// Nothing: the document's own script does it all.
    case none
    case click
    case middleClick
    case commandClick
    case doubleClick
    /// Return on what has the focus.
    case pressReturn
    /// A click on the element, then Return.
    case clickThenReturn
}

/// A way a document can get a link activated. WebKit opens a connection to a link's address before the navigation
/// decider runs, so a route is closed only if the link never activates; each runs against a server that counts what
/// reaches it. `TARGET` in the document stands for that server's address, and `BOX` for a style with room to click.
nonisolated struct ActivationRoute: Sendable, CustomTestStringConvertible {
    let name: String
    var gesture: Gesture = .click
    var runsScripts = true
    let document: String

    var testDescription: String { name }

    func html(target: String) -> Data {
        let body = document
            .replacing("TARGET", with: target)
            .replacing("BOX", with: "display:block;width:300px;height:80px;background:#ccc")
        return Data("<!doctype html><html><body style=\"margin:0\">\(body)</body></html>".utf8)
    }

    /// A frame holding `content` at the top left of the document, where a click at the frame's center lands on it.
    static func frame(_ attributes: String = "", _ content: String) -> String {
        let source = "<body style=margin:0>\(content)".replacing("\"", with: "&quot;")
        return "<iframe id=t \(attributes) style='width:320px;height:100px;border:0' srcdoc=\"\(source)\"></iframe>"
    }

    static let newWindowLink = "<a target=_blank href='TARGET/x' style='BOX'>x</a>"
    static let closedLink = "<div id=t style='BOX'><template shadowrootmode=closed><a href='TARGET/x' style='BOX'>x</a></template></div>"
    static let enter = "new KeyboardEvent('keydown',{keyIdentifier:'Enter',key:'Enter',bubbles:true,cancelable:true})"
    static let click = "new MouseEvent('click',{bubbles:true,cancelable:true})"

    static let scripted: [ActivationRoute] = [
        .init(name: "click on a link in no document", gesture: .none, document: """
            <script>const a=document.createElement('a');a.href='TARGET/x';a.click()</script>
            """),
        .init(name: "event on a link in no document", gesture: .none, document: """
            <script>const a=document.createElement('a');a.href='TARGET/x';a.dispatchEvent(\(click))</script>
            """),
        .init(name: "click on a new-window link in no document", gesture: .none, document: """
            <script>const a=document.createElement('a');a.href='TARGET/x';a.target='_blank';a.click()</script>
            """),
        .init(name: "middle-button event on a link in no document", gesture: .none, document: """
            <script>const a=document.createElement('a');a.href='TARGET/x';
            a.dispatchEvent(new MouseEvent('auxclick',{bubbles:true,cancelable:true,button:1}))</script>
            """),
        .init(name: "middle-button event on a link", gesture: .none, document: """
            <a id=a href='TARGET/x'>x</a><script>
            a.dispatchEvent(new MouseEvent('auxclick',{bubbles:true,cancelable:true,button:1}))</script>
            """),
        .init(name: "click on a link in an open root", gesture: .none, document: """
            <div id=h></div><script>const r=h.attachShadow({mode:'open'});r.innerHTML="<a href='TARGET/x'>x</a>";r.firstChild.click()</script>
            """),
        .init(name: "click on a link in a closed root", gesture: .none, document: """
            <div id=h></div><script>const r=h.attachShadow({mode:'closed'});r.innerHTML="<a href='TARGET/x'>x</a>";r.firstChild.click()</script>
            """),
        .init(name: "event that stays inside a shadow root", gesture: .none, document: """
            <div id=h></div><script>const r=h.attachShadow({mode:'open'});r.innerHTML="<a href='TARGET/x'>x</a>";r.firstChild.dispatchEvent(\(click))</script>
            """),
        .init(name: "click borrowed from a frame", gesture: .none, document: """
            <script>const i=document.createElement('iframe');document.body.append(i);
            const a=document.createElement('a');a.href='TARGET/x';i.contentWindow.HTMLElement.prototype.click.call(a)</script>
            """),
        .init(name: "click borrowed from a removed frame", gesture: .none, document: """
            <script>const i=document.createElement('iframe');document.body.append(i);
            const c=i.contentWindow.HTMLElement.prototype.click;i.remove();
            const a=document.createElement('a');a.href='TARGET/x';c.call(a)</script>
            """),
        .init(name: "event sent through a removed frame", gesture: .none, document: """
            <script>const i=document.createElement('iframe');document.body.append(i);const w=i.contentWindow;
            const c=w.EventTarget.prototype.dispatchEvent;const e=new w.MouseEvent('click',{bubbles:true});i.remove();
            const a=document.createElement('a');a.href='TARGET/x';c.call(a,e)</script>
            """),
        .init(name: "event sent from a frame to a link here", gesture: .none, document: """
            <a id=a href='TARGET/x'>x</a><script>const i=document.createElement('iframe');document.body.append(i);
            i.contentWindow.EventTarget.prototype.dispatchEvent.call(a,new i.contentWindow.MouseEvent('click',{bubbles:true,cancelable:true}))</script>
            """),
        .init(name: "event whose class hides its type", gesture: .none, document: """
            <script>class E extends MouseEvent{get type(){return 'x'}};const a=document.createElement('a');a.href='TARGET/x';
            a.dispatchEvent(new E('click',{bubbles:true}))</script>
            """),
        .init(name: "event sent after the document replaces the type getter", gesture: .none, document: """
            <script>Object.defineProperty(Event.prototype,'type',{get(){return 'x'}});
            const a=document.createElement('a');a.href='TARGET/x';a.dispatchEvent(new MouseEvent('click',{bubbles:true}))</script>
            """),
        .init(name: "event sent through the window's method", gesture: .none, document: """
            <script>const a=document.createElement('a');a.href='TARGET/x';window.dispatchEvent.call(a,\(click))</script>
            """),
        .init(name: "Return sent to a focused link in a closed root", gesture: .none, document: """
            <div id=h></div><script>const r=h.attachShadow({mode:'closed'});r.innerHTML="<a href='TARGET/x'>x</a>";
            const a=r.firstChild;a.focus();a.dispatchEvent(\(enter))</script>
            """)
    ]

    static let real: [ActivationRoute] = [
        .init(name: "a link", runsScripts: false, document: "<a id=t href='TARGET/x' style='BOX'>x</a>"),
        .init(name: "an image map's area", runsScripts: false, document: """
            <img id=t usemap=#m width=300 height=80 src='data:image/gif;base64,R0lGODlhAQABAAAAACw='>
            <map name=m><area shape=rect coords=0,0,300,80 href='TARGET/x'></map>
            """),
        .init(name: "a control inside a link", runsScripts: false, document: "<a href='TARGET/x'><input id=t style='BOX'></a>"),
        .init(name: "a form whose controls are named after its methods, inside a link", document: """
            <a href='TARGET/x'><form id=t style='BOX'><input name=closest><input name=matches></form></a>
            """),
        .init(name: "a link in a closed declarative root", runsScripts: false, document: closedLink),
        .init(name: "a link in an open declarative root", runsScripts: false, document: """
            <div id=t style='BOX'><template shadowrootmode=open><a href='TARGET/x' style='BOX'>x</a></template></div>
            """),
        .init(name: "a closed root the byte scanner reads as a style", runsScripts: false, document: """
            <svg><style><div id=t style='BOX'><template shadowrootmode=closed><a href='TARGET/x' style='BOX'>x</a></template></div></style></svg>
            """),
        .init(name: "text slotted into a link in a closed root", runsScripts: false, document: """
            <div style='BOX'><template shadowrootmode=closed><a href='TARGET/x'><slot></slot></a></template><p id=t style='margin:0'>text</p></div>
            """),
        .init(name: "a closed root from setHTMLUnsafe", document: """
            <div id=h></div><script>h.setHTMLUnsafe("\(closedLink)")</script>
            """),
        .init(name: "a closed root from parseHTMLUnsafe", document: """
            <script>const d=Document.parseHTMLUnsafe("\(closedLink)");document.body.append(document.adoptNode(d.getElementById('t')))</script>
            """),
        .init(name: "a closed root from document.write", document: "<script>document.write(\"\(closedLink)\")</script>"),
        .init(name: "a closed root from attachShadow", document: """
            <div id=t style='BOX'></div><script>t.attachShadow({mode:'closed'}).innerHTML="<a href='TARGET/x' style='BOX'>x</a>"</script>
            """),
        .init(name: "a closed root in a custom element", document: """
            <x-y id=t style='BOX'></x-y><script>customElements.define('x-y',class extends HTMLElement{connectedCallback(){
            this.attachShadow({mode:'closed'}).innerHTML="<a href='TARGET/x' style='BOX'>x</a>"}})</script>
            """),
        .init(name: "a link, with the middle button", gesture: .middleClick, runsScripts: false, document: "<a id=t href='TARGET/x' style='BOX'>x</a>"),
        .init(name: "a link in a closed root, with the middle button", gesture: .middleClick, runsScripts: false, document: closedLink),
        .init(name: "a link in a closed root, with Command", gesture: .commandClick, runsScripts: false, document: closedLink),
        .init(name: "a link in a closed root, twice", gesture: .doubleClick, runsScripts: false, document: closedLink),
        .init(name: "a focused link, with Return", gesture: .pressReturn, runsScripts: false, document: "<a id=t autofocus href='TARGET/x' style='BOX'>x</a>"),
        .init(name: "a link, in a document that stops the event", document: """
            <a id=t href='TARGET/x' style='BOX'>x</a><script>window.addEventListener('click',e=>e.stopImmediatePropagation(),true);
            document.addEventListener('click',e=>{e.returnValue=true},true)</script>
            """),
        .init(name: "a link, in a document that replaces what the seal calls", document: """
            <a id=t href='TARGET/x' style='BOX'>x</a><script>window.Element=null;Function.prototype.call=function(){};
            Function.prototype.apply=function(){};Event.prototype.preventDefault=function(){}</script>
            """),
        .init(name: "a link after document.open", document: """
            <script>setTimeout(()=>{document.open();document.write("<a id=t href='TARGET/x' style='BOX'>x</a>");document.close()},0)</script>
            """),
        .init(name: "a link after a late document.write", document: """
            <script>setTimeout(()=>{document.write("<a id=t href='TARGET/x' style='BOX'>x</a>");document.close()},0)</script>
            """),
        .init(name: "a link after a removed frame's document.open", document: """
            <script>setTimeout(()=>{const i=document.createElement('iframe');document.body.append(i);const o=i.contentWindow.Document.prototype.open;
            i.remove();o.call(document);document.write("<a id=t href='TARGET/x' style='BOX'>x</a>");document.close()},0)</script>
            """),
        .init(name: "a link in a javascript: document", document: """
            <script>setTimeout(()=>{location.href="javascript:'<a id=t href=TARGET/x style=display:block;width:300px;height:80px>x</a>'"},0)</script>
            """),
        .init(name: "a new-window link in a frame", document: frame("", newWindowLink)),
        .init(name: "a new-window link in a blob frame", document: """
            <script>const b=URL.createObjectURL(new Blob(["<body style=margin:0>\(newWindowLink)"],{type:'text/html'}));
            const i=document.createElement('iframe');i.id='t';i.style='width:320px;height:100px;border:0';i.src=b;document.body.append(i)</script>
            """),
        .init(name: "a new-window link in a frame opened by its parent", document: """
            <iframe id=t style='width:320px;height:100px;border:0'></iframe><script>setTimeout(()=>{const d=t.contentDocument;
            d.open();d.write("<body style=margin:0>\(newWindowLink)");d.close()},0)</script>
            """)
    ]

    /// A sandbox without `allow-scripts` silently ends every listener in its frame, so these reach the frame's own
    /// lockdown only as a script that runs once.
    static let sandboxed: [ActivationRoute] = {
        let opaque = "sandbox=allow-popups"
        let sameOrigin = "sandbox='allow-popups allow-same-origin'"
        return [
            .init(name: "a link in a sandboxed frame", document: frame(opaque, newWindowLink)),
            .init(name: "a focused link in a sandboxed frame, with Return", gesture: .clickThenReturn, document: frame(opaque, "<a autofocus target=_blank href='TARGET/x' style='BOX'>x</a>")),
            .init(name: "a link in a closed root in a sandboxed frame", document: frame(opaque, "<div style='BOX'><template shadowrootmode=closed>\(newWindowLink)</template></div>")),
            .init(name: "a link in a frame inside a sandboxed frame", document: frame(opaque, """
                <iframe style='width:320px;height:100px;border:0' srcdoc='<body style=margin:0><a target=_blank href=TARGET/x style=display:block;width:300px;height:80px>x</a>'></iframe>
                """)),
            .init(name: "a sandboxed frame that loses its attribute", document: frame(opaque, newWindowLink) + """
                <script>setTimeout(()=>t.removeAttribute('sandbox'),50)</script>
                """),
            .init(name: "a link in a same-origin sandboxed frame", document: frame(sameOrigin, newWindowLink)),
            .init(name: "a link its parent writes into a same-origin sandboxed frame", document: """
                <iframe id=t \(sameOrigin) style='width:320px;height:100px;border:0'></iframe><script>setTimeout(()=>{const d=t.contentDocument;
                d.body.style.margin=0;d.body.innerHTML="\(newWindowLink)"},0)</script>
                """),
            .init(name: "a same-origin sandboxed frame its parent opens", document: """
                <iframe id=t \(sameOrigin) style='width:320px;height:100px;border:0'></iframe><script>setTimeout(()=>{const d=t.contentDocument;
                d.open();d.write("<body style=margin:0>\(newWindowLink)");d.close()},0)</script>
                """),
            .init(name: "a same-origin sandboxed frame its parent makes interactive", document: frame(sameOrigin, newWindowLink) + """
                <script>setTimeout(()=>{t.contentDocument.documentElement.inert=false},60)</script>
                """),
            .init(name: "a same-origin sandboxed frame whose root its parent replaces", document: frame(sameOrigin, "") + """
                <script>setTimeout(()=>{const d=t.contentDocument;const h=d.createElement('html');
                h.innerHTML="<body style=margin:0>\(newWindowLink)";d.documentElement.replaceWith(h)},60)</script>
                """),
            .init(name: "a same-origin sandboxed frame whose globals its parent replaces", document: frame(sameOrigin, newWindowLink) + """
                <script>setTimeout(()=>{const w=t.contentWindow;Object.defineProperty(w.HTMLElement.prototype,'inert',{set(){}});
                w.Element.prototype.setAttribute=function(){};w.Element.prototype.hasAttribute=()=>true;
                Object.defineProperty(w.Document.prototype,'documentElement',{get(){return null}});
                HTMLElement.prototype.__lookupSetter__('inert').call(t.contentDocument.documentElement,false)},60)</script>
                """),
            .init(name: "a sandboxed frame made by script", document: """
                <script>const i=document.createElement('iframe');i.id='t';i.style='width:320px;height:100px;border:0';
                i.setAttribute('sandbox','allow-popups allow-same-origin');document.body.append(i);const d=i.contentDocument;
                d.body.style.margin=0;d.body.innerHTML="\(newWindowLink)";d.documentElement.inert=false</script>
                """)
        ]
    }()

    static let all = scripted + real + sandboxed
}

/// Shows a page in a window no one can see, off every screen, and sends it real events.
@MainActor private final class Hosted {
    private let window = TestWindow(contentRect: NSRect(x: -4000, y: 200, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
    private var web: WKWebView? { Self.web(in: window.contentView) }

    init(_ page: WebPage) async throws {
        window.contentView = NSHostingView(rootView: WebView(page))
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -4000, y: 200))
        try #require(await eventually { self.web != nil })
    }

    deinit { MainActor.assumeIsolated { window.orderOut(nil) } }

    private static func web(in view: NSView?) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view?.subviews.lazy.compactMap { web(in: $0) }.first
    }

    func perform(_ gesture: Gesture, on page: WebPage) async throws {
        guard gesture != .none else { return }
        let web = try #require(web)
        let target = "document.getElementById('t')"
        try #require(try await eventuallyAsking {
            try await page.callJavaScript("return \(target) !== null", contentWorld: SealedWebPage.world) as? Bool == true
        })
        // Lets a frame load and a document's timers finish changing what the gesture lands on.
        try await Task.sleep(for: .milliseconds(250))
        let box = try #require(try await page.callJavaScript("""
            const r = \(target).getBoundingClientRect();
            return [r.x + Math.min(r.width / 2, 40), r.y + r.height / 2];
            """, contentWorld: SealedWebPage.world) as? [Double])
        let inView = NSPoint(x: box[0], y: web.isFlipped ? box[1] : web.bounds.height - box[1])
        let point = web.convert(inView, to: nil)
        switch gesture {
        case .none: break
        case .click: try await press(web, at: point)
        case .commandClick: try await press(web, at: point, flags: .command)
        case .doubleClick:
            try await press(web, at: point)
            try await press(web, at: point, clicks: 2)
        case .middleClick: try await press(web, at: point, down: .otherMouseDown, up: .otherMouseUp)
        case .pressReturn: try await pressReturn(in: web)
        case .clickThenReturn:
            try await press(web, at: point)
            try await pressReturn(in: web)
        }
    }

    private func press(
        _ web: WKWebView, at point: NSPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1,
        down: NSEvent.EventType = .leftMouseDown, up: NSEvent.EventType = .leftMouseUp
    ) async throws {
        for type in [down, up] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
            switch type {
            case .leftMouseDown: web.mouseDown(with: event)
            case .leftMouseUp: web.mouseUp(with: event)
            case .otherMouseDown: web.otherMouseDown(with: event)
            default: web.otherMouseUp(with: event)
            }
            // WebKit takes a mouse up that arrives with its mouse down for a stray one.
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private func pressReturn(in web: WKWebView) async throws {
        window.makeFirstResponder(web)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
            if type == .keyDown { web.keyDown(with: event) } else { web.keyUp(with: event) }
            // As for the mouse: a key up with its key down is dropped.
            try await Task.sleep(for: .milliseconds(60))
        }
    }
}

// One at a time: a web process that is slow to start under dozens of others could let a route pass by not running.
@Suite(.hangLimit, .serialized)
@MainActor struct SealedWebPageClickTests {
    private func shown(_ html: String, runsScripts: Bool, gesture: Gesture) async throws -> (SealedWebPage, Hosted) {
        let sealed = try await SealedWebPage.make(runsScripts: runsScripts)
        let host = try await Hosted(sealed.page)
        try await sealed.show(Data(html.utf8))
        try await host.perform(gesture, on: sealed.page)
        return (sealed, host)
    }

    @Test(arguments: ActivationRoute.all) func noRouteConnects(_ route: ActivationRoute) async throws {
        let probe = try await Probe()
        let sealed = try await SealedWebPage.make(runsScripts: route.runsScripts)
        let host = try await Hosted(sealed.page)
        try await sealed.show(route.html(target: "http://127.0.0.1:\(probe.port)"))
        try await host.perform(route.gesture, on: sealed.page)
        // The control below connects within milliseconds of the gesture; this gives a wrong connection the same chance.
        try await Task.sleep(for: .milliseconds(600))
        #expect(probe.count == 0)
    }

    @Test(arguments: ActivationRoute.all) func theSameRouteConnectsWithoutTheSeal(_ route: ActivationRoute) async throws {
        let probe = try await Probe()
        let page = WebPage()
        let host = try await Hosted(page)
        // The document navigates away from itself, so the load is not awaited.
        _ = page.load(route.html(target: "http://127.0.0.1:\(probe.port)"), mimeType: "text/html", characterEncoding: .utf8, baseURL: SealedWebPage.base)
        try await host.perform(route.gesture, on: page)
        #expect(await eventually { probe.count > 0 }, "the control connected to nothing, so the test above shows nothing")
    }

    @Test func aClickStillOpensADisclosure() async throws {
        let (sealed, host) = try await shown("""
            <!doctype html><body style="margin:0"><details id="d"><summary id="t" style="display:block;height:80px">More</summary>Text</details>
            """, runsScripts: false, gesture: .click)
        let open = try await sealed.page.callJavaScript("return document.getElementById('d').open", contentWorld: SealedWebPage.world)
        #expect(open as? Bool == true)
        withExtendedLifetime(host) {}
    }

    @Test func aDocumentsOwnHandlerStillHearsAClickButFindsItCancelled() async throws {
        let (sealed, host) = try await shown("""
            <!doctype html><body style="margin:0"><div id="t" style="height:80px"></div>
            <script>t.addEventListener('click', e => { window.heard = e.defaultPrevented; });</script>
            """, runsScripts: true, gesture: .click)
        #expect(try await sealed.page.callJavaScript("return window.heard") as? Bool == true)
        withExtendedLifetime(host) {}
    }

    @Test func aScriptedClickDoesNothing() async throws {
        let (sealed, host) = try await shown("""
            <!doctype html><button id="b" onclick="window.heard = true">Go</button>
            <script>b.click(); b.dispatchEvent(new MouseEvent('click', { bubbles: true }));</script>
            """, runsScripts: true, gesture: .none)
        #expect(try await sealed.page.callJavaScript("return window.heard === undefined") as? Bool == true)
        withExtendedLifetime(host) {}
    }

    @Test func aFrameWhoseScriptsMayRunIsNotMadeInert() async throws {
        let (sealed, host) = try await shown("""
            <!doctype html><iframe id="plain" srcdoc="<p>x"></iframe><iframe id="sandboxed" sandbox="allow-same-origin" srcdoc="<p>x"></iframe>
            """, runsScripts: true, gesture: .none)
        let inert = try await sealed.page.callJavaScript("""
            return ['plain', 'sandboxed'].map(id => document.getElementById(id).contentDocument.documentElement.inert)
                .concat(document.documentElement.inert);
            """) as? [Bool]
        #expect(inert == [false, true, false])
        withExtendedLifetime(host) {}
    }
}
