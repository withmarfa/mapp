import Foundation

/// Points every picture of an HTML document at the app (`SealedPictures`) before the document is shown in the sealed web
/// page, so a picture at a web address is drawn only from what the app gives it and the document never names a website
/// to the page.
///
/// Each `img` is drawn from its `src`, or its `data-src` where it has no `src`, as the connectors read a document's
/// pictures. An `http` or `https` address becomes a `SealedPictures` URL for the item; any other `src` (a `data:` picture
/// the document holds, or a relative address, which resolves against nothing) is left as written. Every `srcset`, on an
/// `img` or on a `<picture>`'s `<source>`, is dropped, so only `src` is drawn. The seal blocks whatever this misses, so a
/// picture it does not reach is a missing picture, never a request.
///
/// The scan follows the HTML tokenizer's rules for what matters here: comments, the text of `script`, `style` and the
/// other raw-text elements, quoted and unquoted attribute values and character references. Everything else is copied
/// byte for byte.
nonisolated enum SealedPictureRewrite {
    struct Result: Sendable {
        /// The document as UTF-8.
        let html: Data
        /// The web addresses of its pictures, each once, in the order they first appear.
        let addresses: [URL]
    }

    static func rewrite(_ data: Data, item: ItemID, version: Int) -> Result {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
        var scanner = Scanner(bytes: Array(text.utf8), item: item, version: version)
        scanner.run()
        return Result(html: Data(scanner.output), addresses: scanner.addresses)
    }

    /// Elements whose content the tokenizer reads as text up to their end tag, so a tag-like string inside them is not
    /// a tag. `noscript` is not among them: with scripts off its content is markup, and with scripts on it is text that
    /// a rewrite inside cannot harm.
    private static let rawText: Set<String> = ["script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes"]

    private struct Attribute {
        let name: String
        /// The attribute as written, from its name to the end of its value.
        let written: Range<Int>
        let value: String?
    }

    private struct Scanner {
        let bytes: [UInt8]
        let item: ItemID
        let version: Int
        var output: [UInt8] = []
        var addresses: [URL] = []
        private var seen: Set<URL> = []
        private var index = 0

        init(bytes: [UInt8], item: ItemID, version: Int) {
            self.bytes = bytes
            self.item = item
            self.version = version
            output.reserveCapacity(bytes.count + bytes.count / 8)
        }

        mutating func run() {
            while index < bytes.count {
                guard bytes[index] == UInt8(ascii: "<"), index + 1 < bytes.count else {
                    output.append(bytes[index])
                    index += 1
                    continue
                }
                let next = bytes[index + 1]
                if starts(with: "<!--", at: index) {
                    copy(through: find("-->", from: index + 4).map { $0 + 3 } ?? bytes.count)
                } else if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") || next == UInt8(ascii: "/") {
                    copy(through: find(">", from: index + 2).map { $0 + 1 } ?? bytes.count)
                } else if isLetter(next) {
                    startTag()
                } else {
                    output.append(bytes[index])
                    index += 1
                }
            }
        }

        private mutating func startTag() {
            let start = index
            var position = index + 1
            while position < bytes.count, !isSpace(bytes[position]), bytes[position] != UInt8(ascii: "/"), bytes[position] != UInt8(ascii: ">") {
                position += 1
            }
            let nameEnd = position
            let name = String(decoding: bytes[(start + 1)..<nameEnd], as: UTF8.self).lowercased()
            var attributes: [Attribute] = []
            while true {
                while position < bytes.count, isSpace(bytes[position]) || bytes[position] == UInt8(ascii: "/") { position += 1 }
                guard position < bytes.count, bytes[position] != UInt8(ascii: ">") else { break }
                let attributeStart = position
                // A first `=` is part of the name, as the tokenizer reads it.
                position += 1
                while position < bytes.count, !isSpace(bytes[position]), !"/>=".utf8.contains(bytes[position]) { position += 1 }
                let attributeName = String(decoding: bytes[attributeStart..<position], as: UTF8.self).lowercased()
                var after = position
                while after < bytes.count, isSpace(bytes[after]) { after += 1 }
                var value: String?
                if after < bytes.count, bytes[after] == UInt8(ascii: "=") {
                    after += 1
                    while after < bytes.count, isSpace(bytes[after]) { after += 1 }
                    if after < bytes.count, bytes[after] == UInt8(ascii: "\"") || bytes[after] == UInt8(ascii: "'") {
                        let quote = bytes[after]
                        let valueStart = after + 1
                        var valueEnd = valueStart
                        while valueEnd < bytes.count, bytes[valueEnd] != quote { valueEnd += 1 }
                        value = Self.decode(bytes[valueStart..<valueEnd])
                        position = min(valueEnd + 1, bytes.count)
                    } else {
                        let valueStart = after
                        var valueEnd = valueStart
                        while valueEnd < bytes.count, !isSpace(bytes[valueEnd]), bytes[valueEnd] != UInt8(ascii: ">") { valueEnd += 1 }
                        value = Self.decode(bytes[valueStart..<valueEnd])
                        position = valueEnd
                    }
                }
                attributes.append(Attribute(name: attributeName, written: attributeStart..<position, value: value))
            }
            let end = min(position + 1, bytes.count)
            index = end
            switch name {
            case "img": writeImage(name: start..<nameEnd, attributes: attributes)
            case "source": writeSource(name: start..<nameEnd, attributes: attributes)
            default: output.append(contentsOf: bytes[start..<end])
            }
            if SealedPictureRewrite.rawText.contains(name) {
                copy(through: findEndTag(name, from: end) ?? bytes.count)
            }
        }

        private mutating func writeImage(name: Range<Int>, attributes: [Attribute]) {
            // The first of a repeated attribute is the one the parser keeps.
            let source = attributes.first { $0.name == "src" }?.value.map(Self.trimmed)
            let lazy = attributes.first { $0.name == "data-src" }?.value.map(Self.trimmed)
            let chosen = source.flatMap { $0.isEmpty ? nil : $0 } ?? lazy
            let address = chosen.flatMap(Self.webAddress)
            var kept = attributes.filter { $0.name != "srcset" }
            if address != nil { kept.removeAll { $0.name == "src" } }
            output.append(contentsOf: bytes[name])
            for attribute in kept {
                output.append(UInt8(ascii: " "))
                output.append(contentsOf: bytes[attribute.written])
            }
            if let address {
                if seen.insert(address).inserted { addresses.append(address) }
                let url = SealedPictures.url(for: address, in: item, version: version).absoluteString
                output.append(contentsOf: " src=\"\(url.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"))\"".utf8)
            }
            output.append(UInt8(ascii: ">"))
        }

        private mutating func writeSource(name: Range<Int>, attributes: [Attribute]) {
            output.append(contentsOf: bytes[name])
            for attribute in attributes where attribute.name != "srcset" {
                output.append(UInt8(ascii: " "))
                output.append(contentsOf: bytes[attribute.written])
            }
            output.append(UInt8(ascii: ">"))
        }

        private mutating func copy(through end: Int) {
            output.append(contentsOf: bytes[index..<end])
            index = end
        }

        private func starts(with text: String, at position: Int) -> Bool {
            let pattern = Array(text.utf8)
            guard position + pattern.count <= bytes.count else { return false }
            return Array(bytes[position..<(position + pattern.count)]) == pattern
        }

        private func find(_ text: String, from position: Int) -> Int? {
            let pattern = Array(text.utf8)
            var at = position
            while at + pattern.count <= bytes.count {
                if bytes[at] == pattern[0], starts(with: text, at: at) { return at }
                at += 1
            }
            return nil
        }

        /// Where `</name` starts, in any case, followed by what ends a tag name.
        private func findEndTag(_ name: String, from position: Int) -> Int? {
            let pattern = Array(("</" + name).utf8)
            var at = position
            while at + pattern.count <= bytes.count {
                if bytes[at] == UInt8(ascii: "<"),
                   zip(bytes[at..<(at + pattern.count)], pattern).allSatisfy({ lower($0) == $1 }) {
                    let following = at + pattern.count
                    if following == bytes.count || isSpace(bytes[following]) || bytes[following] == UInt8(ascii: "/") || bytes[following] == UInt8(ascii: ">") {
                        return at
                    }
                }
                at += 1
            }
            return nil
        }

        private func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D }
        private func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        private func lower(_ byte: UInt8) -> UInt8 { (0x41...0x5A).contains(byte) ? byte + 0x20 : byte }

        /// The address a picture is drawn from, where it names a website.
        static func webAddress(_ text: String) -> URL? {
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  url.host(percentEncoded: true)?.isEmpty == false
            else { return nil }
            return url
        }

        /// A URL attribute is read without the ASCII whitespace around it.
        static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\u{0C}\r"))
        }

        private static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"]

        /// An attribute value with its character references read. Only the named references an address can hold are
        /// known; any other is left as written.
        static func decode(_ raw: ArraySlice<UInt8>) -> String {
            let text = String(decoding: raw, as: UTF8.self)
            guard text.contains("&") else { return text }
            var result = ""
            var rest = Substring(text)
            while let amp = rest.firstIndex(of: "&") {
                result += rest[..<amp]
                rest = rest[amp...]
                if let semicolon = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semicolon) <= 10 {
                    let body = rest[rest.index(after: rest.startIndex)..<semicolon]
                    var replacement: String?
                    if body.hasPrefix("#x") || body.hasPrefix("#X") {
                        replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                    } else if body.hasPrefix("#") {
                        replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                    } else {
                        replacement = named[String(body)]
                    }
                    if let replacement {
                        result += replacement
                        rest = rest[rest.index(after: semicolon)...]
                        continue
                    }
                }
                // `&amp` with no semicolon is still read in a value, unless a letter, digit or `=` follows.
                if rest.hasPrefix("&amp"), !(rest.dropFirst(4).first.map { $0.isLetter || $0.isNumber || $0 == "=" } ?? false) {
                    result += "&"
                    rest = rest.dropFirst(4)
                    continue
                }
                result += "&"
                rest = rest.dropFirst()
            }
            return result + rest
        }
    }
}
