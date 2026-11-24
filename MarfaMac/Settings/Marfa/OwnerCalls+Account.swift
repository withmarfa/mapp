import Foundation
import Marfa
import MarfaAPI

extension ClientOwnerCalls {
    // MARK: Account

    func profile() async throws(OwnerFailure) -> OwnerProfile {
        try await run { client in
            let profile = try await client.getProfile().ok.body.json
            return OwnerProfile(
                username: profile.username, emailIsReadable: profile.email != nil, email: profile.email?.value)
        }
    }

    func passkeys() async throws(OwnerFailure) -> [OwnerPasskey] {
        try await run { client in
            try await client.listOwnerPasskeys().ok.body.json.data.map {
                OwnerPasskey(id: $0.id, name: $0.name, added: Self.date($0.createdAt), lastUsed: Self.date($0.lastUsedAt))
            }
        }
    }

    func renamePasskey(_ id: String, to name: String) async throws(OwnerFailure) {
        try await run { client in
            _ = try await client.renameOwnerPasskey(path: .init(id: id), body: .json(.init(name: name))).ok
        }
    }

    func removePasskey(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.deleteOwnerPasskey(path: .init(id: id)).ok }
    }

    func passkeyAddAddress() async throws(OwnerFailure) -> URL {
        try await run { client in
            let link = try await client.getPasskeyAddUrl().ok.body.json
            guard let url = URL(string: link.url), url.scheme == "https" || url.scheme == "http" else {
                throw OwnerFailure.failed(String(localized: "The server’s link for adding a passkey couldn’t be read."))
            }
            return url
        }
    }

    func browserSignIns() async throws(OwnerFailure) -> [BrowserSignIn] {
        try await run { client in
            try await client.listSignIns().ok.body.json.data.filter { $0.kind == .browser }.map {
                BrowserSignIn(
                    id: $0.id, name: $0.name, userAgent: $0.userAgent, added: Self.date($0.createdAt),
                    lastUsed: Self.date($0.lastUsedAt))
            }
        }
    }

    func endSignIn(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.endSignIn(path: .init(id: id)).ok }
    }

    func changePassword(from current: String, to new: String) async throws(OwnerFailure) -> PasswordOutcome {
        let client = try make()
        do {
            switch try await client.changePassword(from: current, to: new) {
            case .changed: return .changed
            case .currentPasswordWrong: return .currentWrong
            case .newPasswordRefused(let message): return .newRefused(message)
            case .notPermitted(let scope, _): throw OwnerFailure.notPermitted(scope)
            case .tooManyAttempts(let seconds): return .tooManyAttempts(retryAfterSeconds: seconds)
            }
        } catch let failure as OwnerFailure {
            throw failure
        } catch {
            throw Self.failure(error)
        }
    }
}
