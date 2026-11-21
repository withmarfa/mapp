import Foundation
import Testing
@testable import MAPP

@Suite struct EditorOptionsTests {
    @Test func theDefaultsAreInkkitsOwnWherePageSaysNothing() {
        let options = EditorOptions(PageStyle())
        #expect(options.textInput == .init(
            spellcheck: true, smartPunctuation: false, pairBrackets: false, continueLists: true, indent: "tab", indentWidth: 4,
            paste: "formatted"))
        #expect(options.display == .init(foldHeadings: false, codeLineNumbers: false))
    }

    @Test func everyChoiceReachesTheSetInkkitTakes() throws {
        var style = PageStyle()
        style.checksSpelling = false
        style.smartPunctuation = true
        style.pairsBrackets = true
        style.continuesLists = false
        style.indentWith = .twoSpaces
        style.pasteAs = .plainText
        style.foldsHeadings = true
        style.showsCodeLineNumbers = true
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EditorOptions(style))) as? [String: [String: Any]]
        let input = try #require(sent?["textInput"])
        #expect(input["spellcheck"] as? Bool == false)
        #expect(input["smartPunctuation"] as? Bool == true)
        #expect(input["pairBrackets"] as? Bool == true)
        #expect(input["continueLists"] as? Bool == false)
        #expect(input["indent"] as? String == "spaces")
        #expect(input["indentWidth"] as? Int == 2)
        #expect(input["paste"] as? String == "plainText")
        let display = try #require(sent?["display"])
        #expect(display["foldHeadings"] as? Bool == true)
        #expect(display["codeLineNumbers"] as? Bool == true)
    }

    @Test func indentWithAlwaysSendsAKindAndAWidthInkkitAccepts() {
        for choice in IndentWith.allCases {
            #expect((1...8).contains(choice.width))
        }
        #expect(EditorOptions(PageStyle()).textInput.indent == "tab")
    }

    @Test func everyNewEditorSettingIsResetWithTheOthers() {
        for key in [LineSpacing.key, ParagraphSpacing.key, IndentWith.key, PasteAs.key, EditingMode.key, PageKey.smartPunctuation,
                    PageKey.pairsBrackets, PageKey.continuesLists, PageKey.foldsHeadings, PageKey.showsCodeLineNumbers] {
            #expect(MacSettings.keys.contains(key), "\(key)")
        }
    }

    @Test func standardSpacingIsThePagesOwn() {
        #expect(LineSpacing.standard.multiple == 1.55)
        #expect(ParagraphSpacing.standard.multiple == 0.667)
    }
}
