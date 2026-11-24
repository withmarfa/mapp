import Foundation
import Testing
@testable import MarfaMac

@Suite struct EditorOptionsTests {
    @Test func everyNewEditorSettingIsResetWithTheOthers() {
        for key in [LineSpacing.key, ParagraphSpacing.key, IndentWith.key, PasteAs.key, EditingMode.key, PageKey.smartPunctuation,
                    PageKey.pairsBrackets, PageKey.continuesLists, PageKey.foldsHeadings, PageKey.showsCodeLineNumbers] {
            #expect(MacSettings.keys.contains(key), "\(key)")
        }
    }
}
