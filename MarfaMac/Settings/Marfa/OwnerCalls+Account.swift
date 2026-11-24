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

/// The owner's name, checked as the server checks it (`instance-claim/profile-input`): no control or hidden character
/// anywhere in what was typed, then trimmed, nonempty and at most 200 characters.
nonisolated enum ProfileName {
    static let longest = 200

    enum Problem: Error, Equatable {
        case empty, hidden, tooLong

        var line: String {
            switch self {
            case .empty: String(localized: "Enter a name.")
            case .hidden: String(localized: "Use letters, numbers and punctuation.")
            case .tooLong: String(localized: "Use at most 200 characters.")
            }
        }
    }

    static func checked(_ typed: String) -> Result<String, Problem> {
        if typed.unicodeScalars.contains(where: isHidden) { return .failure(.hidden) }
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.empty) }
        if name.unicodeScalars.count > longest { return .failure(.tooLong) }
        return .success(name)
    }

    /// The characters the server refuses in a name: controls, and those that change or hide how text runs.
    private static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xAD, 0x61C, 0x180E, 0xFEFF, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x206F: true
        default: scalar.properties.generalCategory == .control
        }
    }
}

/// A picture made ready for the owner's profile. A file the server takes as it is (`ProfilePicture.isTaken`) is sent byte
/// for byte; any other picture is drawn again as a PNG or JPEG within the contract's limits (`instance-claim/avatar-size`,
/// `avatar-dimensions`, `avatar-kind-refused`).
nonisolated enum ProfilePicture {
    static let largest = 2_097_152
    static let longestSide = 4096
    /// The longest side of the copy the Account page keeps to show.
    static let shownSide = 128

    /// The bytes to send, or nil where `data` is neither taken as it is nor a picture the Mac can read.
    static func prepared(_ data: Data) -> Data? {
        if isTaken(data) { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        var target = min(max(width, height), longestSide)
        while target >= 1 {
            if let drawn = drawn(source, longestSide: target), isTaken(drawn) { return drawn }
            target = target * 3 / 4
        }
        return nil
    }

    /// A small PNG of `data` for the page to show, so the picture's own bytes need not be kept.
    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let image = image(source, longestSide: shownSide)
        else { return nil }
        return encoded(image, as: .png)
    }

    /// The first frame, turned upright and no longer than `longestSide`, as a PNG where it has transparency and a JPEG where not.
    private static func drawn(_ source: CGImageSource, longestSide: Int) -> Data? {
        guard let image = image(source, longestSide: longestSide) else { return nil }
        let opaque: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
        return encoded(image, as: opaque.contains(image.alphaInfo) ? .jpeg : .png)
    }

    private static func image(_ source: CGImageSource, longestSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encoded(_ image: CGImage, as kind: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kind.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

nonisolated extension ProfilePicture {
    /// Whether the server would store `data` as it is: at most `largest` bytes, and a PNG, a baseline, extended or progressive
    /// JPEG, or a WebP (animated ones too) whose every image is 1 to `longestSide` pixels a side. The server reads only the
    /// files' marks, never their pixels, and so does this.
    static func isTaken(_ data: Data) -> Bool {
        guard data.count <= largest else { return false }
        let bytes = [UInt8](data)
        let sides: (Int, Int)?
        if bytes.starts(with: pngSignature) {
            sides = png(bytes)
        } else if bytes.starts(with: [0xFF, 0xD8]) {
            sides = jpeg(bytes)
        } else if bytes.starts(with: Array("RIFF".utf8)), bytes.count >= 12, Array(bytes[8..<12]) == Array("WEBP".utf8) {
            sides = webp(bytes)
        } else {
            sides = nil
        }
        return sides.map(fits) ?? false
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func fits(_ sides: (Int, Int)) -> Bool { (1...longestSide).contains(sides.0) && (1...longestSide).contains(sides.1) }

    private static func be(_ bytes: [UInt8], _ at: Int, _ count: Int) -> Int? {
        guard at >= 0, at + count <= bytes.count else { return nil }
        return bytes[at..<at + count].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func le(_ bytes: [UInt8], _ at: Int, _ count: Int) -> Int? {
        guard at >= 0, at + count <= bytes.count else { return nil }
        return bytes[at..<at + count].reversed().reduce(0) { $0 << 8 | Int($1) }
    }

    private static func name(_ bytes: [UInt8], _ at: Int) -> String? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        return String(decoding: bytes[at..<at + 4], as: UTF8.self)
    }

    /// A header first, at least one image chunk, and the end chunk as the file's last bytes.
    private static func png(_ bytes: [UInt8]) -> (Int, Int)? {
        var next = pngSignature.count
        var sides: (Int, Int)?
        var hasData = false
        while true {
            guard let length = be(bytes, next, 4), let chunk = name(bytes, next + 4) else { return nil }
            let end = next + 12 + length
            guard end <= bytes.count else { return nil }
            switch chunk {
            case "IHDR" where sides == nil && length == 13:
                guard let width = be(bytes, next + 8, 4), let height = be(bytes, next + 12, 4) else { return nil }
                sides = (width, height)
            case _ where sides == nil, "IHDR":
                return nil
            case "IDAT":
                hasData = true
            case "IEND":
                return length == 0 && end == bytes.count && hasData ? sides : nil
            default:
                break
            }
            next = end
        }
    }

    /// One baseline, extended or progressive frame, a scan, and the end marker as the file's last two bytes.
    private static func jpeg(_ bytes: [UInt8]) -> (Int, Int)? {
        var next = 2
        var sides: (Int, Int)?
        var scanned = false
        while true {
            guard next < bytes.count, bytes[next] == 0xFF else { return nil }
            while next + 1 < bytes.count, bytes[next + 1] == 0xFF { next += 1 }
            guard next + 1 < bytes.count else { return nil }
            let marker = bytes[next + 1]
            next += 2
            switch marker {
            case 0xD9: return scanned && next == bytes.count ? sides : nil
            case 0x01: continue
            case 0x00, 0xD0...0xD8: return nil
            default: break
            }
            guard let length = be(bytes, next, 2), length >= 2, next + length <= bytes.count else { return nil }
            let end = next + length
            switch marker {
            case 0xC0...0xCF where ![0xC4, 0xC8, 0xCC].contains(marker):
                guard sides == nil, (0xC0...0xC2).contains(marker), let height = be(bytes, next + 3, 2), let width = be(bytes, next + 5, 2),
                    next + 7 <= end
                else { return nil }
                sides = (width, height)
            case 0xDA:
                guard sides != nil, let after = afterScan(bytes, from: end) else { return nil }
                scanned = true
                next = after
                continue
            default:
                break
            }
            next = end
        }
    }

    private static func afterScan(_ bytes: [UInt8], from start: Int) -> Int? {
        var next = start
        while next + 1 < bytes.count {
            guard bytes[next] == 0xFF else {
                next += 1
                continue
            }
            switch bytes[next + 1] {
            case 0x00, 0xD0...0xD7: next += 2
            case 0xFF: next += 1
            default: return next
            }
        }
        return nil
    }

    /// The RIFF size matches the file, and the canvas and every image, animation frames included, agree and fit.
    private static func webp(_ bytes: [UInt8]) -> (Int, Int)? {
        guard le(bytes, 4, 4) == bytes.count - 8 else { return nil }
        var canvas: (Int, Int)?
        var extended = false
        var images = 0
        var first = true
        let walked = chunks(bytes, from: 12, to: bytes.count) { chunk, start, end in
            defer { first = false }
            switch chunk {
            case "VP8X" where first:
                guard let width = le(bytes, start + 4, 3), let height = le(bytes, start + 7, 3), start + 10 <= end else { return false }
                guard fits((width + 1, height + 1)) else { return false }
                canvas = (width + 1, height + 1)
                extended = true
            case "VP8 ", "VP8L":
                guard let sides = bitstream(bytes, chunk, start, end), fits(sides) else { return false }
                if let canvas, canvas != sides { return false }
                canvas = canvas ?? sides
                images += 1
            case "ANMF" where extended:
                guard let canvas, frame(bytes, start, end, in: canvas) else { return false }
                images += 1
            case _ where first, "VP8X", "ANMF":
                return false
            default:
                break
            }
            return true
        }
        guard walked, images > 0 else { return nil }
        return canvas
    }

    /// Walks sibling chunks from `from` to `to`; each with its padding byte must fit. `visit` gets the name and the data's range.
    private static func chunks(_ bytes: [UInt8], from: Int, to: Int, visit: (String, Int, Int) -> Bool) -> Bool {
        var next = from
        while next < to {
            guard let chunk = name(bytes, next), let size = le(bytes, next + 4, 4) else { return false }
            let start = next + 8
            let end = start + size
            let padded = end + (size & 1)
            guard padded <= to, visit(chunk, start, end) else { return false }
            next = padded
        }
        return true
    }

    private static func bitstream(_ bytes: [UInt8], _ chunk: String, _ start: Int, _ end: Int) -> (Int, Int)? {
        if chunk == "VP8L" {
            guard start < end, bytes[start] == 0x2F, start + 5 <= end, let bits = le(bytes, start + 1, 4) else { return nil }
            return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        }
        guard start + 10 <= end, bytes[start + 3] == 0x9D, bytes[start + 4] == 0x01, bytes[start + 5] == 0x2A,
            let width = le(bytes, start + 6, 2), let height = le(bytes, start + 8, 2)
        else { return nil }
        return (width & 0x3FFF, height & 0x3FFF)
    }

    /// An animation frame holds one image as large as the frame says, placed inside the canvas.
    private static func frame(_ bytes: [UInt8], _ start: Int, _ end: Int, in canvas: (Int, Int)) -> Bool {
        guard start + 16 <= end, let x = le(bytes, start, 3), let y = le(bytes, start + 3, 3), let width = le(bytes, start + 6, 3),
            let height = le(bytes, start + 9, 3)
        else { return false }
        let sides = (width + 1, height + 1)
        guard fits(sides) else { return false }
        var image: (Int, Int)?
        let walked = chunks(bytes, from: start + 16, to: end) { chunk, inner, innerEnd in
            guard chunk == "VP8 " || chunk == "VP8L" else { return true }
            guard image == nil, let found = bitstream(bytes, chunk, inner, innerEnd), fits(found) else { return false }
            image = found
            return true
        }
        guard walked, let image, image == sides else { return false }
        return x * 2 + sides.0 <= canvas.0 && y * 2 + sides.1 <= canvas.1
    }
}
