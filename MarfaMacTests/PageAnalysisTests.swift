@testable import MarfaMac
import Foundation
import Testing

struct PageAnalysisTests {
    private func answer(length: Int = 800, lang: Any? = "en", dir: Any? = nil, mail: Bool = false) -> [String: Any] {
        var article: [String: Any] = ["html": "<p>Text</p>", "length": length]
        article["lang"] = lang
        article["dir"] = dir
        return ["mail": mail, "article": article]
    }

    @Test func aLanguageThatCouldBreakOutOfAnAttributeIsDropped() throws {
        for lang in ["en\" onload=\"x", "", "x y", String(repeating: "a", count: 40), "<en>"] {
            #expect(try #require(PageAnalysis(javaScript: answer(lang: lang)).article).language == nil, "\(lang)")
        }
        #expect(try #require(PageAnalysis(javaScript: answer(lang: "zh-Hant-TW")).article).language == "zh-Hant-TW")
    }

    @Test func aDirectionThatIsNeitherIsDropped() throws {
        #expect(try #require(PageAnalysis(javaScript: answer(dir: "auto")).article).direction == nil)
    }

    @Test func anAnswerThatIsNotWhatTheScriptGivesIsNothing() {
        #expect(PageAnalysis(javaScript: nil) == .none)
        #expect(PageAnalysis(javaScript: "text") == .none)
        #expect(PageAnalysis(javaScript: ["article": ["html": 4]] as [String: Any]) == .none)
    }
}
