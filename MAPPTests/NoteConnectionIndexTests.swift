import Foundation
import Testing
@testable import MAPP

struct NoteConnectionIndexTests {
    private func record(_ title: String, type: String = "custom.task", header: String = "", body: String = "") -> NoteProjection {
        NoteProjection(id: UUID(), file: NoteFile(text: "---\ntype: \(type)\ntitle: \"\(title)\"\n\(header)---\n\(body)"), fallbackTitle: title)
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
        #expect(index.references.filter { $0.sourceID == ordinary.id }.allSatisfy { $0.resolution == .missing })
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
}
