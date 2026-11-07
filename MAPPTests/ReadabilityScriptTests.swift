@testable import MAPP
import CryptoKit
import Foundation
import Testing

/// The vendored scripts are Mozilla's, byte for byte. A change to them is an update, made with the notice
/// (`MAPP/Views/Reader/READABILITY-NOTICE.txt`) and these hashes together.
struct ReadabilityScriptTests {
    private func hash(of name: String) throws -> String {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "js"), "\(name).js is in the app")
        return SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func readabilityIsTheVersionTheNoticeNames() throws {
        #expect(try hash(of: "Readability") == "34dcab3d0832d0019f02990eed6b6124e029e8c32b9f0c6f2550544ff8dff174")
    }

    @Test func theReaderableCheckIsTheVersionTheNoticeNames() throws {
        #expect(try hash(of: "Readability-readerable") == "a98d28805804c1986ceed470678a3f409f150ee7f1d227f8c8239c005d21de65")
    }

    @Test func theScriptsAreLoadedForTheAnalysis() {
        #expect(PageAnalyzer.readability?.contains("function Readability(") == true)
        #expect(PageAnalyzer.readability?.contains("function isProbablyReaderable(") == true)
    }
}
