@testable import MAPP
import Foundation
import Testing

struct PageAnalysisTests {
    private func answer(length: Int = 800, lang: Any? = "en", dir: Any? = nil, mail: Bool = false) -> [String: Any] {
        var article: [String: Any] = ["html": "<p>Text</p>", "length": length]
        article["lang"] = lang
        article["dir"] = dir
        return ["mail": mail, "article": article]
    }

    @Test func anArticleOfEnoughTextIsKept() throws {
        let analysis = PageAnalysis(javaScript: answer())
        let article = try #require(analysis.article)
        #expect(article.html == "<p>Text</p>" && article.language == "en" && article.direction == nil)
        #expect(analysis.offersReader)
    }

    @Test func anArticleThatIsTooShortIsNoArticle() {
        #expect(PageAnalysis(javaScript: answer(length: PageAnalysis.shortestArticle - 1)).article == nil)
        #expect(PageAnalysis(javaScript: answer(length: PageAnalysis.shortestArticle)).article != nil)
    }

    @Test func aPageWithNoArticleOffersNoReader() {
        let analysis = PageAnalysis(javaScript: ["mail": false, "article": NSNull()] as [String: Any])
        #expect(analysis.article == nil && !analysis.offersReader)
    }

    @Test func theDirectionAndLanguageAreWhatTheDocumentSaid() throws {
        let article = try #require(PageAnalysis(javaScript: answer(lang: "ar-EG", dir: "RTL")).article)
        #expect(article.direction == .rtl && article.language == "ar-EG")
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

    @Test func theMailFlagIsKeptWithOrWithoutAnArticle() {
        #expect(PageAnalysis(javaScript: answer(mail: true)).isMail)
        #expect(PageAnalysis(javaScript: ["mail": true] as [String: Any]).isMail)
    }

    @Test func anAnswerThatIsNotWhatTheScriptGivesIsNothing() {
        #expect(PageAnalysis(javaScript: nil) == .none)
        #expect(PageAnalysis(javaScript: "text") == .none)
        #expect(PageAnalysis(javaScript: ["article": ["html": 4]] as [String: Any]) == .none)
    }

    @Test func aPageWithNoArticleIsAlwaysShownAsItIs() {
        let none = PageAnalysis.none
        #expect(none.mode(choosing: .reader) == .original && none.mode(choosing: .original) == .original)
        let article = PageAnalysis(javaScript: answer())
        #expect(article.mode(choosing: .reader) == .reader && article.mode(choosing: .original) == .original)
    }
}
