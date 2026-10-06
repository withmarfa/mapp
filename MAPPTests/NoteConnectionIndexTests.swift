import Foundation
import Testing
@testable import MAPP

struct NoteConnectionIndexTests {
    private func record(_ title: String, type: String = "custom.task", header: String = "", body: String = "") -> NoteProjection {
        NoteProjection(id: .mint(), file: NoteFile(text: "---\ntype: \(type)\ntitle: \"\(title)\"\n\(header)---\n\(body)"), fallbackTitle: title)
    }

    private var rules: [String: [NoteConnectionRule]] {
        ["custom.task": [
            .init(field: "child-of", name: "parent-of", reverseName: "child-of", direction: .reverse),
            .init(field: "about", name: "about", reverseName: nil, direction: .forward),
        ]]
    }

    @Test func configuredReverseAndArrayConnectionsBecomeDirectedEdges() {
        let parent = record("Project", type: "custom.project")
        let first = record("First")
        let second = record("Second")
        let child = record("Task", header: "child-of: ' [[ Project ]] '\nabout:\n  - '[[First]]'\n  - ' [[Second]] '\n", body: "See [[Project]] and [[First]].")
        let index = NoteConnectionIndex(records: [parent, first, second, child], rulesByType: rules)
        #expect(index.edges.contains(.init(name: "parent-of", reverseName: "child-of", sourceID: parent.id, targetID: child.id)))
        #expect(index.edges.contains(.init(name: "about", reverseName: nil, sourceID: child.id, targetID: first.id)))
        #expect(index.edges.contains(.init(name: "about", reverseName: nil, sourceID: child.id, targetID: second.id)))
        #expect(index.edges.count == 3)
        #expect(index.references.filter { $0.origin == .body }.count == 2)
        #expect(index.issues.isEmpty)
    }

    @Test func unknownTypesAndUnconfiguredHeadersDoNotInventSemanticEdges() {
        let target = record("Target")
        let unknown = record("Unknown", type: "future.item", header: "child-of: '[[Target]]'\n", body: "[[Target]]")
        let ordinary = record("Ordinary", header: "random: '[[Target]]'\n", body: "[[Target|Alias]] [[Target#Heading]]")
        let index = NoteConnectionIndex(records: [target, unknown, ordinary], rulesByType: rules)
        #expect(index.edges.isEmpty)
        #expect(index.references.contains { $0.sourceID == unknown.id && $0.origin == .body && $0.resolution == .resolved(target.id) })
        #expect(index.references.filter { $0.sourceID == ordinary.id }.allSatisfy { $0.resolution == .resolved(target.id) })
    }

    @Test func missingAndCaseInsensitiveDuplicateTitlesStayUnresolved() {
        let first = record("Same")
        let second = record("same")
        let source = record("Source", header: "about: ['[[SAME]]', '[[Missing]]']\n", body: "[[ Same ]] [[Missing]]")
        let index = NoteConnectionIndex(records: [first, second, source], rulesByType: rules)
        #expect(index.edges.isEmpty)
        #expect(index.references.filter { $0.targetTitle == "SAME" || $0.targetTitle == "Same" }.allSatisfy { $0.resolution == .ambiguous([first.id, second.id]) })
        #expect(index.references.filter { $0.targetTitle == "Missing" }.allSatisfy { $0.resolution == .missing })
    }

    @Test func malformedConfiguredValuesAreReportedAndValidValuesStillResolve() {
        let target = record("Target")
        let source = record("Source", header: "about: ['[[Target]]', false, 'plain text']\nchild-of: {nested: '[[Target]]'}\n")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.edges.count == 1)
        #expect(index.issues.count == 3)
        #expect(index.issues.allSatisfy { $0.sourceID == source.id })
    }

    @Test func aliasesAndHeadingsResolveTheirBaseWithoutChangingTypedText() {
        let target = record("Café")
        let source = record("Source", header: "about: ['[[CAFÉ|shown]]', '[[Cafe\u{301}#part]]']\n", body: "[[Café|shown]] [[CAFÉ#part|shown]]")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.count == 4)
        #expect(index.references.allSatisfy { $0.resolution == .resolved(target.id) })
        #expect(index.references.map(\.targetTitle) == ["Café|shown", "CAFÉ#part|shown", "CAFÉ|shown", "Cafe\u{301}#part"])
        #expect(index.edges.count == 1)
        #expect(source.file.text.contains("[[CAFÉ|shown]]"))
        #expect(index.issues.isEmpty)
    }

    @Test(arguments: ["C# notes", "C|shown"])
    func wholeTextNamingAnotherRecordIsAmbiguous(typed: String) {
        let base = record("C")
        let whole = record(typed)
        let source = record("Source", header: "about: '[[\(typed)]]'\n", body: "[[\(typed)]]")
        let index = NoteConnectionIndex(records: [base, whole, source], rulesByType: rules)
        #expect(index.references.count == 2)
        #expect(index.references.allSatisfy { $0.resolution == .ambiguous([base.id, whole.id]) })
        #expect(index.edges.isEmpty)
    }

    @Test func wholeAndBaseNamesOfTheSameRecordAreOneTarget() {
        let target = NoteProjection(note: Note(path: "C.md", text: "---\ntitle: 'C# notes'\n---", created: .now))
        let source = record("Source", header: "about: ['[[C# notes]]', '[[C|shown]]']\n")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.count == 2)
        #expect(index.references.allSatisfy { $0.resolution == .resolved(target.id) })
        #expect(index.edges.count == 1)
    }

    @Test func filePathAndNameResolveWithAndWithoutTheirExtension() {
        let target = NoteProjection(note: Note(path: "Projects/Café.md", text: "---\ntitle: Project\n---", created: .now))
        let source = record("Source", header: "about: ['[[Cafe\u{301}]]', '[[CAFÉ.MD]]', '[[projects/café]]', '[[PROJECTS/CAFÉ.MD]]']\n")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.count == 4)
        #expect(index.references.allSatisfy { $0.resolution == .resolved(target.id) })
        #expect(index.edges.count == 1)
    }

    @Test func titleAndFileAliasesDoNotMakeOneRecordAmbiguousButCollisionsDo() {
        let first = NoteProjection(note: Note(path: "Same.md", text: "---\ntitle: same\n---", created: .now))
        let source = record("Source", header: "about: '[[SAME]]'\n")
        let single = NoteConnectionIndex(records: [first, source], rulesByType: rules)
        #expect(single.references.first?.resolution == .resolved(first.id))
        let second = record("SAME")
        let collision = NoteConnectionIndex(records: [first, second, source], rulesByType: rules)
        #expect(collision.references.first?.resolution == .ambiguous([first.id, second.id]))
        #expect(collision.edges.isEmpty)
    }

    @Test func knownDeclaredIDsResolveWithoutTreatingLocalOrUnknownIDsAsNames() {
        let declaredID = UUID()
        let unknownID = UUID()
        let target = record("Target", header: "marfa_id: '\(declaredID.uuidString)'\n")
        let numericName = record(unknownID.uuidString)
        let source = record("Source", header: "about: ['[[\(declaredID.uuidString.lowercased())]]', '[[\(unknownID.uuidString)]]', '[[\(target.id.rawValue)]]']\n")
        let index = NoteConnectionIndex(records: [target, numericName, source], rulesByType: rules)
        #expect(index.references.map(\.resolution) == [.resolved(target.id), .missing, .missing])
        #expect(index.edges.count == 1)
        #expect(target.fields?["marfa_id"] == .string(declaredID.uuidString))
    }

    @Test func repeatedDeclaredIDsAreAmbiguousAndInvalidIDsStayOrdinaryFields() {
        let declaredID = UUID()
        let first = record("First", header: "marfa_id: '\(declaredID)'\n")
        let second = record("Second", header: "marfa_id: '\(declaredID)'\n")
        let invalid = record("Invalid", header: "marfa_id: 'opaque-id'\n")
        let source = record("Source", header: "about: ['[[\(declaredID)]]', '[[opaque-id]]']\n")
        let index = NoteConnectionIndex(records: [first, second, invalid, source], rulesByType: rules)
        #expect(index.references.map(\.resolution) == [.ambiguous([first.id, second.id]), .missing])
        #expect(index.edges.isEmpty)
    }

    @Test func emptyBaseNamesRemainMalformedAndMissingAliasesRemainMissing() {
        let source = record("Source", header: "about: ['[[|shown]]', '[[#part]]', '[[Absent|shown]]']\n")
        let index = NoteConnectionIndex(records: [source], rulesByType: rules)
        #expect(index.issues.count == 2)
        #expect(index.references.map(\.resolution) == [.missing])
        #expect(index.references.first?.targetTitle == "Absent|shown")
        #expect(index.edges.isEmpty)
    }

    @Test func fileNameWhitespaceIsSignificantWhileTitleWhitespaceIsTrimmed() {
        let spacedFile = NoteProjection(note: Note(path: " Leading.md", text: "---\ntitle: Unrelated\n---", created: .now))
        let source = record("Source", header: "about: '[[Leading]]'\n")
        let unmatched = NoteConnectionIndex(records: [spacedFile, source], rulesByType: rules)
        #expect(unmatched.references.first?.resolution == .missing)
        #expect(unmatched.edges.isEmpty)

        let genuine = NoteProjection(note: Note(path: "Leading.md", text: "---\ntitle: Another\n---", created: .now))
        let matched = NoteConnectionIndex(records: [spacedFile, genuine, source], rulesByType: rules)
        #expect(matched.references.first?.resolution == .resolved(genuine.id))
        #expect(matched.edges.count == 1)

        let spacedTitle = record(" Leading ")
        let titleMatched = NoteConnectionIndex(records: [spacedFile, spacedTitle, source], rulesByType: rules)
        #expect(titleMatched.references.first?.resolution == .resolved(spacedTitle.id))
    }

    @Test(arguments: ["C|\u{301}shown", "C#\u{301}part"])
    func combiningMarksAfterAliasAndHeadingDelimitersDoNotHideTheBase(typed: String) {
        let target = record("C")
        let source = record("Source", header: "about: '[[\(typed)]]'\n", body: "[[\(typed)]]")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.count == 2)
        #expect(index.references.allSatisfy { $0.resolution == .resolved(target.id) })
        #expect(index.references.allSatisfy { $0.targetTitle == typed })
        #expect(index.edges.count == 1)
    }


    @Test func structuralMarkersAreScalarsEvenBesideCombiningMarks() {
        let title = "\u{301}C"
        let target = record(title)
        let source = record("Source", header: "about: '[[\(title)]]'\n", body: "[[\(title)]]\u{301}")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.count == 2)
        #expect(index.references.allSatisfy { $0.resolution == .resolved(target.id) })
        #expect(index.references.allSatisfy { $0.targetTitle == title })
        #expect(index.edges.count == 1)
        #expect(index.issues.isEmpty)
    }

    @Test func combiningMarksDoNotHideMalformedInnerBrackets() {
        let source = record("Source", header: "about: ['[[C[\u{301}part]]', '[[C]\u{301}part]]']\n")
        let index = NoteConnectionIndex(records: [source], rulesByType: rules)
        #expect(index.issues.count == 2)
        #expect(index.references.isEmpty)
        #expect(index.edges.isEmpty)
    }


    @Test func zeroWidthSpaceIsSignificantInTitlesAndTypedNames() {
        let significant = record("\u{200B}Leading")
        let plain = record("Leading")
        let source = record("Source", header: "about: ['[[Leading]]', '[[\u{200B}Leading]]', '[[\u{200B}Leading|shown]]', '\u{200B}[[Leading]]']\n")
        let index = NoteConnectionIndex(records: [significant, plain, source], rulesByType: rules)
        #expect(index.references.map(\.resolution) == [.resolved(plain.id), .resolved(significant.id), .resolved(significant.id)])
        #expect(index.references.map(\.targetTitle) == ["Leading", "\u{200B}Leading", "\u{200B}Leading|shown"])
        #expect(index.issues.count == 1)
        let missing = NoteConnectionIndex(records: [plain, source], rulesByType: rules)
        #expect(missing.references.map(\.resolution) == [.resolved(plain.id), .missing, .missing])
    }

    @Test(arguments: [" ", "\t", "\u{A0}"])
    func unicodeWhitespaceAroundTitlesAndTypedNamesIsTrimmed(space: String) {
        let target = record("\(space)Leading\(space)")
        let source = record("Source", header: "about: '\(space)[[\(space)Leading\(space)]]\(space)'\n")
        let index = NoteConnectionIndex(records: [target, source], rulesByType: rules)
        #expect(index.references.first?.resolution == .resolved(target.id))
        #expect(index.references.first?.targetTitle == "Leading")
        #expect(index.issues.isEmpty)
    }

}
