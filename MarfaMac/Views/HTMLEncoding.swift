import Foundation

/// The encoding an HTML document shown in the sealed web page is read in. The page has to be told one
/// (`WebPage.load(_:mimeType:characterEncoding:baseURL:)`), and the one it is told overrides what the document declares,
/// so the declaration is found here as the HTML standard's prescan finds it: a byte order mark, or a `<meta charset>` or
/// `<meta http-equiv="Content-Type">` in the first 1024 bytes. `SealedPictureRewrite` reads the document's addresses in
/// the same encoding, so they name what the page would ask for.
nonisolated enum HTMLEncoding {
    /// UTF-8 where the bytes are UTF-8; otherwise what the document declares, and Windows-1252, the encoding standard's
    /// default for an undeclared document, where it declares none that is known.
    static func of(_ data: Data) -> String.Encoding {
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        var prescan = Prescan(bytes: Array(data.prefix(1024)))
        guard let label = prescan.declared() else { return .windowsCP1252 }
        return encoding(named: label)
    }

    /// The encoding a label names, read as the encoding standard reads the labels it treats differently from IANA's.
    static func encoding(named label: String) -> String.Encoding {
        let name = label.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\u{0C}\r")).lowercased()
        // A declaration of UTF-16 in the document's own bytes cannot be true, since those bytes are ASCII.
        if name.hasPrefix("utf-16") || name == "unicode" || name == "ucs-2" { return .utf8 }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return .windowsCP1252 }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        // The encoding standard reads ASCII and Latin-1 labels as Windows-1252, as browsers do.
        if encoding == .ascii || encoding == .isoLatin1 { return .windowsCP1252 }
        return encoding
    }

    /// The prescan of the HTML standard ("prescan a byte stream to determine its encoding"), up to the label it finds.
    private struct Prescan {
        let bytes: [UInt8]
        private var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func declared() -> String? {
            while index < bytes.count {
                if starts(with: "<!--") {
                    // The `-->` may share its dashes with the `<!--`.
                    index = find("-->", from: index + 2).map { $0 + 3 } ?? bytes.count
                } else if startsIgnoringCase(with: "<meta"), index + 5 < bytes.count, isSpace(bytes[index + 5]) || bytes[index + 5] == slash {
                    index += 6
                    if let label = meta() { return label }
                } else if bytes[index] == UInt8(ascii: "<"), index + 1 < bytes.count,
                          isLetter(bytes[index + 1]) || (bytes[index + 1] == slash && index + 2 < bytes.count && isLetter(bytes[index + 2])) {
                    index += 2
                    while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: ">") { index += 1 }
                    while attribute() != nil {}
                    index += 1
                } else if starts(with: "<!") || starts(with: "</") || starts(with: "<?") {
                    index = find(">", from: index + 2).map { $0 + 1 } ?? bytes.count
                } else {
                    index += 1
                }
            }
            return nil
        }

        /// Reads a `meta` tag's attributes, from after its name, and gives the label it declares, if it declares one.
        private mutating func meta() -> String? {
            var names: Set<String> = []
            var pragma = false
            var needsPragma: Bool?
            var charset: String?
            while let (name, value) = attribute() {
                guard names.insert(name).inserted else { continue }
                switch name {
                case "http-equiv":
                    if value == "content-type" { pragma = true }
                case "content":
                    if charset == nil, let label = Self.charset(inContent: value) {
                        charset = label
                        needsPragma = true
                    }
                case "charset":
                    charset = value
                    needsPragma = false
                default:
                    break
                }
            }
            guard let needsPragma, !needsPragma || pragma, let charset else { return nil }
            return charset
        }

        /// The standard's "get an attribute": the next attribute's name and value, lowercased, or nil at the tag's end.
        private mutating func attribute() -> (String, String)? {
            while index < bytes.count, isSpace(bytes[index]) || bytes[index] == slash { index += 1 }
            guard index < bytes.count, bytes[index] != UInt8(ascii: ">") else { return nil }
            var name: [UInt8] = []
            var value: [UInt8] = []
            nameLoop: while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "="), !name.isEmpty { break nameLoop }
                if isSpace(byte) {
                    while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                    guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { return (text(name), "") }
                    break nameLoop
                }
                if byte == slash || byte == UInt8(ascii: ">") { return (text(name), "") }
                name.append(lower(byte))
                index += 1
            }
            guard index < bytes.count else { return (text(name), "") }
            index += 1
            while index < bytes.count, isSpace(bytes[index]) { index += 1 }
            guard index < bytes.count else { return (text(name), "") }
            let first = bytes[index]
            if first == UInt8(ascii: "\"") || first == UInt8(ascii: "'") {
                index += 1
                while index < bytes.count, bytes[index] != first {
                    value.append(lower(bytes[index]))
                    index += 1
                }
                index += 1
                return (text(name), text(value))
            }
            if first == UInt8(ascii: ">") { return (text(name), "") }
            while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: ">") {
                value.append(lower(bytes[index]))
                index += 1
            }
            return (text(name), text(value))
        }

        /// The standard's "extract a character encoding from a meta element", on a value already lowercased.
        static func charset(inContent content: String) -> String? {
            var rest = Substring(content)
            while let found = rest.range(of: "charset") {
                rest = rest[found.upperBound...].drop { " \t\n\u{0C}\r".contains($0) }
                guard rest.first == "=" else { continue }
                rest = rest.dropFirst().drop { " \t\n\u{0C}\r".contains($0) }
                guard let first = rest.first else { return nil }
                if first == "\"" || first == "'" {
                    let quoted = rest.dropFirst()
                    guard let end = quoted.firstIndex(of: first) else { return nil }
                    return String(quoted[..<end])
                }
                let label = rest.prefix { !" \t\n\u{0C}\r;".contains($0) }
                return label.isEmpty ? nil : String(label)
            }
            return nil
        }

        private var slash: UInt8 { UInt8(ascii: "/") }
        private func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
        private func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D }
        private func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        private func lower(_ byte: UInt8) -> UInt8 { (0x41...0x5A).contains(byte) ? byte + 0x20 : byte }

        private func starts(with text: String) -> Bool {
            let pattern = Array(text.utf8)
            return index + pattern.count <= bytes.count && Array(bytes[index..<(index + pattern.count)]) == pattern
        }

        private func startsIgnoringCase(with text: String) -> Bool {
            let pattern = Array(text.utf8)
            return index + pattern.count <= bytes.count && zip(bytes[index..<(index + pattern.count)], pattern).allSatisfy { lower($0) == $1 }
        }

        private func find(_ text: String, from position: Int) -> Int? {
            let pattern = Array(text.utf8)
            var at = position
            while at + pattern.count <= bytes.count {
                if Array(bytes[at..<(at + pattern.count)]) == pattern { return at }
                at += 1
            }
            return nil
        }
    }
}
