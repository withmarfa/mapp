import Foundation
@testable import Marfa
@testable import MarfaMac
import Network
import Testing

@Suite(.hangLimit)
struct ClientRegistrationTests {
    @Test(arguments: [false, true])
    func aNewSignInSendsTheMacName(device: Bool) async throws {
        let probe = try await RegistrationProbe()
        let connection = try MarfaConnection(address: probe.origin)
        let signIns = SystemSignIns(computerName: { "Étage 🖥️" }, anchor: { nil })
        do {
            if device {
                _ = try await signIns.startCodeSignIn(to: connection)
            } else {
                _ = try await signIns.authorization(for: connection).signIn { _, _ in
                    Issue.record("The browser opened before registration succeeded.")
                    throw CancellationError()
                }
            }
            Issue.record("Registration unexpectedly succeeded.")
        } catch SignInError.refused(let code, let message) {
            #expect(code == "registration_observed")
            #expect(message == "Marfa for Mac on Étage 🖥️")
        }
    }
}

private nonisolated final class RegistrationProbe: Sendable {
    let origin: String
    private let listener: NWListener

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let (states, report) = AsyncStream<NWListener.State>.makeStream()
        listener.stateUpdateHandler = { report.yield($0) }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Self.read(connection, bytes: Data())
        }
        listener.start(queue: .global())
        var readyPort: NWEndpoint.Port?
        for await state in states {
            if case .failed(let error) = state { throw error }
            if case .ready = state {
                readyPort = listener.port
                break
            }
        }
        let port = try #require(readyPort)
        self.listener = listener
        origin = "http://127.0.0.1:\(port.rawValue)"
    }

    deinit { listener.cancel() }

    private static func read(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, complete, error in
            let request = bytes + (chunk ?? Data())
            if !respond(to: request, on: connection) {
                if complete || error != nil {
                    connection.cancel()
                } else {
                    read(connection, bytes: request)
                }
            }
        }
    }

    private static func respond(to request: Data, on connection: NWConnection) -> Bool {
        guard let boundary = request.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let lines = String(decoding: request[..<boundary.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let headers = lines.dropFirst().compactMap { line -> (String, String)? in
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { return nil }
            return (pair[0].lowercased(), pair[1].trimmingCharacters(in: .whitespaces))
        }
        let count = headers.first { $0.0 == "content-length" }.flatMap { Int($0.1) } ?? 0
        let body = request[boundary.upperBound...]
        guard body.count >= count else { return false }
        if lines.first?.hasPrefix("GET /.well-known/oauth-authorization-server ") == true,
           let host = headers.first(where: { $0.0 == "host" })?.1 {
            let origin = "http://\(host)"
            answer(connection, status: "200 OK", fields: [
                "issuer": origin, "authorization_endpoint": origin + "/authorize",
                "token_endpoint": origin + "/token", "device_authorization_endpoint": origin + "/device",
                "registration_endpoint": origin + "/register",
            ])
        } else if lines.first?.hasPrefix("POST /register ") == true,
                  let metadata = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                  let name = metadata["client_name"] as? String {
            answer(connection, status: "400 Bad Request", fields: [
                "error": "registration_observed", "error_description": name,
            ])
        } else {
            answer(connection, status: "404 Not Found", fields: [:])
        }
        return true
    }

    private static func answer(_ connection: NWConnection, status: String, fields: [String: String]) {
        let body = (try? JSONEncoder().encode(fields)) ?? Data()
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
