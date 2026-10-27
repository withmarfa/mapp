import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
@testable import MAPP

/// A stand-in for the internet, so a test of a picture fetch reaches no network. Each test uses hosts of its own, since
/// tests run at the same time, and the stand-in answers by host and path.
nonisolated final class PictureStub: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        /// An answer in pieces, with `Content-Length` only where `announce` says so.
        case body([Data], status: Int = 200, type: String = "image/png", announce: Bool = true)
        case redirect(String)
        /// The start of a body that never finishes.
        case stall(Data)
    }

    private struct State {
        var replies: [String: Reply] = [:]
        var requests: [String: [URLRequest]] = [:]
    }

    private static let state = Mutex(State())

    /// Answers `address` with `reply` from now on.
    static func answer(_ address: String, with reply: Reply) {
        let key = Self.key(URL(string: address)!)
        state.withLock { $0.replies[key] = reply }
    }

    /// The requests made to the host of `address`, in order.
    static func requests(to address: String) -> [URLRequest] {
        let host = URL(string: address)!.host()!
        return state.withLock { $0.requests.filter { $0.key.hasPrefix(host + "/") }.values.flatMap { $0 } }
    }

    static var configuration: @Sendable () -> URLSessionConfiguration {
        {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [PictureStub.self]
            return configuration
        }
    }

    /// A resolver that answers every name with one public address.
    static let resolver: PictureAddressPolicy.Resolver = { _ in [IPAddress(bytes: [93, 184, 216, 34])] }

    /// A host no other test uses.
    static func newHost() -> String { "h\(UUID().uuidString.lowercased().prefix(8)).example.com" }

    private static func key(_ url: URL) -> String { "\(url.host() ?? "")\(url.path())" }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = Self.key(url)
        let reply = Self.state.withLock { state in
            state.requests[key, default: []].append(request)
            return state.replies[key]
        }
        switch reply {
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        case .body(let pieces, let status, let type, let announce)?:
            var headers = ["Content-Type": type]
            if announce { headers["Content-Length"] = String(pieces.reduce(0) { $0 + $1.count }) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            for piece in pieces { client?.urlProtocol(self, didLoad: piece) }
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target)?:
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
        case .stall(let start)?:
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: start)
        }
    }

    override func stopLoading() {}
}

/// Pictures a test can serve.
nonisolated enum SamplePicture {
    /// A PNG `width` pixels wide and `height` high.
    static func png(width: Int = 8, height: Int = 8) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><script>alert(1)</script></svg>"#.utf8)
    static let page = Data("<!doctype html><html><body>Not a picture, and long enough to be told so by its first bytes.</body></html>".utf8)
}
