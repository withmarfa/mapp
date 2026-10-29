import Foundation
import Testing
@testable import MAPP

/// A document that is not UTF-8 is read in the encoding it declares, found as the HTML prescan finds it, and in
/// Windows-1252 only where it declares none that is known.
struct HTMLEncodingTests {
    private func encoding(_ html: String, prefix: [UInt8] = []) -> String.Encoding {
        // A byte that is not UTF-8, so the declaration is what decides.
        HTMLEncoding.of(Data(prefix + Array(html.utf8) + [0xE9]))
    }

    /// The encoding Core Foundation gives the IANA name, which for Shift_JIS is not Foundation's `.shiftJIS`
    /// (code page 932).
    private func iana(_ name: String) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(name as CFString)))
    }

    private var shiftJIS: String.Encoding { iana("shift_jis") }

    @Test func aDocumentThatIsUTF8IsReadAsUTF8WhateverItDeclares() {
        #expect(HTMLEncoding.of(Data(#"<meta charset="shift_jis"><p>café</p>"#.utf8)) == .utf8)
    }

    @Test func aMetaCharsetIsRead() {
        #expect(encoding(#"<!doctype html><html><head><meta charset="shift_jis">"#) == shiftJIS)
        #expect(encoding("<META CHARSET=EUC-JP>") == iana("euc-jp"))
        #expect(encoding("<meta charset='windows-1251'>") == String.Encoding.windowsCP1251)
        #expect(encoding("<meta/charset=koi8-r>") == iana("koi8-r"))
    }

    @Test func aContentTypePragmaIsRead() {
        #expect(encoding(#"<meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">"#) == shiftJIS)
        #expect(encoding(#"<meta content='text/html; charset="windows-1251"' http-equiv=content-type>"#) == .windowsCP1251)
        #expect(encoding(#"<meta content="text/html; charset=shift_jis">"#) == .windowsCP1252, "a content charset counts only with the pragma")
    }

    @Test func aByteOrderMarkComesFirst() {
        #expect(HTMLEncoding.of(Data([0xFF, 0xFE] + Array("<".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })) == .utf16LittleEndian)
        #expect(HTMLEncoding.of(Data([0xFE, 0xFF, 0x00, 0x3C])) == .utf16BigEndian)
    }

    @Test func whatThePrescanSkipsIsNotADeclaration() {
        #expect(encoding(#"<!-- <meta charset="shift_jis"> -->"#) == .windowsCP1252)
        #expect(encoding(#"<div title='<meta charset="shift_jis">'>"#) == .windowsCP1252)
        #expect(encoding(#"<!-- a --><div title=">"><meta charset="shift_jis">"#) == shiftJIS)
        #expect(encoding(String(repeating: " ", count: 1024) + #"<meta charset="shift_jis">"#) == .windowsCP1252, "past the first 1024 bytes")
    }

    @Test func whatTheEncodingStandardReadsOtherwiseIsReadItsWay() {
        #expect(encoding("<meta charset=iso-8859-1>") == .windowsCP1252)
        #expect(encoding("<meta charset=us-ascii>") == .windowsCP1252)
        #expect(encoding("<meta charset=utf-16>") == .utf8)
        #expect(encoding("<meta charset=no-such-encoding>") == .windowsCP1252)
        #expect(encoding("<p>no declaration</p>") == .windowsCP1252)
    }
}
