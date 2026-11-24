import Foundation
import ImageIO
import Marfa
import MarfaAPI
import OpenAPIRuntime
import UniformTypeIdentifiers

extension ClientOwnerCalls {
    // MARK: Account

    func profile() async throws(OwnerFailure) -> OwnerProfile {
        try await run { client in Self.profile(try await client.getProfile().ok.body.json) }
    }

    private static func profile(_ profile: Components.Schemas.Profile) -> OwnerProfile {
        OwnerProfile(
            name: profile.name, username: profile.username, emailIsReadable: profile.email != nil, email: profile.email?.value,
            pictureIsReadable: profile.avatar != nil, hasPicture: profile.avatar?.value != nil)
    }

    func changeableProfile() -> Set<ProfileField> {
        guard let server, let scopes = (try? server())?.credential?.scopes else { return Set(ProfileField.allCases) }
        return Set(ProfileField.allCases.filter { scopes.contains("profile.\($0.rawValue):write") || scopes.contains("profile:write") })
    }

    func setProfileName(_ name: String) async throws(OwnerFailure) -> OwnerProfile {
        try await run { client in
            Self.profile(try await client.updateProfile(body: .json(.init(name: name))).ok.body.json)
        }
    }

    func profilePicture() async throws(OwnerFailure) -> Data? {
        do {
            return try await run { client -> Data? in
                let body: HTTPBody
                switch try await client.getProfileAvatar().ok.body {
                case .png(let bytes), .jpeg(let bytes), .imageWebp(let bytes): body = bytes
                }
                return try await Data(collecting: body, upTo: ProfilePicture.largest)
            }
        } catch .notFound {
            return nil
        }
    }

    func setProfilePicture(_ picture: Data) async throws(OwnerFailure) -> OwnerProfile {
        try await run { client in
            Self.profile(try await client.replaceProfileAvatar(body: .binary(HTTPBody(picture))).ok.body.json)
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

/// A picture made ready for the owner's profile, within what the contract stores (`instance-claim/avatar-kind-refused`,
/// `avatar-dimensions`, `avatar-size`): a PNG, JPEG or WebP is sent as it is when it fits, and any other picture, or one too
/// large, is drawn again at a size that fits.
nonisolated enum ProfilePicture {
    static let largest = 2_097_152
    static let longestSide = 4096
    private static let kept: Set<String> = [UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier]

    /// The bytes to send, or nil where `data` holds no picture the Mac can read.
    static func prepared(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        let kind = CGImageSourceGetType(source) as String?
        let side = max(width, height)
        if let kind, kept.contains(kind), side <= longestSide, data.count <= largest, CGImageSourceGetCount(source) == 1 { return data }
        var target = min(side, longestSide)
        while target >= 1 {
            if let drawn = drawn(source, longestSide: target), drawn.count <= largest { return drawn }
            target = target * 3 / 4
        }
        return nil
    }

    /// The first frame, turned upright and no longer than `longestSide`, as a PNG where it has transparency and a JPEG where not.
    private static func drawn(_ source: CGImageSource, longestSide: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let opaque: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
        let kind = opaque.contains(image.alphaInfo) ? UTType.jpeg : UTType.png
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kind.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
