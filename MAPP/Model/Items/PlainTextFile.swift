import Foundation

/// A bounded, read-only preview. Unrecognized encodings and binary data stay with the system file preview.
nonisolated enum PlainTextFile {
    static let byteLimit = 4 * 1024 * 1024

    enum Preview: Equatable, Sendable {
        case text(String)
        case unsupported
        case unavailable
    }

    static func read(_ url: URL) -> Preview {
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var data = Data()
            while data.count <= byteLimit {
                let next = try file.read(upToCount: min(64 * 1024, byteLimit + 1 - data.count)) ?? Data()
                if next.isEmpty { return decode(data) }
                data.append(next)
            }
            return .unsupported
        } catch {
            return .unavailable
        }
    }

    static func decode(_ data: Data) -> Preview {
        guard data.count <= byteLimit else { return .unsupported }
        let payload: Data
        let encoding: String.Encoding
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            payload = data.dropFirst(4)
            encoding = .utf32BigEndian
        } else if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            payload = data.dropFirst(4)
            encoding = .utf32LittleEndian
        } else if data.starts(with: [0xFE, 0xFF]) {
            payload = data.dropFirst(2)
            encoding = .utf16BigEndian
        } else if data.starts(with: [0xFF, 0xFE]) {
            payload = data.dropFirst(2)
            encoding = .utf16LittleEndian
        } else {
            payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
            encoding = .utf8
        }
        // Foundation can drop an incomplete UTF-16 code unit. A preview must not silently omit source bytes.
        guard let text = String(data: payload, encoding: encoding), text.data(using: encoding) == payload,
              !text.unicodeScalars.contains(where: {
            ($0.value < 0x20 && ![9, 10, 13].contains($0.value)) || $0.value == 0x7F
        }) else { return .unsupported }
        return .text(text)
    }
}
