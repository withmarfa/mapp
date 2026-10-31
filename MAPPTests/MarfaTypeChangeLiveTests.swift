import Foundation
import Marfa
import struct MarfaCore.Item
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// Changing an item's type on the test instance, as Marfa's rules hold it: properties the new type does not
    /// declare stay, the text is read from the new type's key, and a missing required field is refused. Every item
    /// made has a title starting `MAPPTEST ` and is purged when the test ends, passed or not.
    @MainActor
    @Suite(.serialized)
    struct MarfaTypeChangeLiveTests {
        private static let note = TypeID("core.note"), task = TypeID("core.task"), event = TypeID("core.event")
        private static let entity = TypeID("core.entity")

        private func withLibrary(_ body: @MainActor (MarfaLibrary, MarfaSource, LiveMarfa.Made) async throws -> Void) async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaTypeChangeLiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]),
                location: MarfaStoreLocation(root: root))
            let library = MarfaLibrary(source: source, notices: Notices())
            func end() async {
                await source.flush()
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
            }
            do {
                source.refresh()
                try #require(await eventually {
                    library.isLoaded && library.connection == .online && LiveMarfa.isWhole(library.syncReport)
                })
                try await body(library, source, made)
            } catch {
                await end()
                throw error
            }
            await end()
        }

        /// A value of the field's kind, for a required field the test fills.
        private static func sample(for field: ItemTypeInfo.Field) -> PropertyValue? {
            switch field.kind {
            case .text: .string("MAPPTEST value")
            case .number: .number(field.minimum ?? 1)
            case .boolean: .bool(true)
            case .date: .string(ItemDate.day(Date()))
            case .choice, .status: field.options.first.map(PropertyValue.string)
            case .other, .list: nil
            }
        }

        private func make(_ type: TypeID, _ title: String, body: String, properties: [String: PropertyValue] = [:],
                          in library: MarfaLibrary, made: LiveMarfa.Made) throws -> ItemID {
            let id = library.createItem(
                typeID: type.rawValue, title: "MAPPTEST \(title) \(UUID().uuidString.prefix(8).lowercased())", body: body,
                properties: properties, parentID: nil, in: .allNotes, undoManager: nil)
            if let id { made.add(id) }
            return try #require(id)
        }

        private func row(_ id: ItemID, in source: MarfaSource) async throws -> MarfaCore.Item? {
            try await source.copy.items.get(id.rawValue)
        }

        @Test(.timeLimit(.minutes(2)))
        func theTextMovesToTheNewKeyAndUndoMovesItBack() async throws {
            try await withLibrary { library, source, made in
                let event = try #require(library.catalogue.itemTypes[Self.event])
                let noteBody = try #require(library.catalogue.itemTypes[Self.note]?.bodyKey)
                let eventBody = try #require(event.bodyKey)
                let text = "Agenda\n\n- [ ] book a room\n"
                let id = try make(Self.note, "retyped", body: text, in: library, made: made)
                try #require(await eventually { library.body(of: id)?.text == text })
                await source.flush()
                try #require(await eventually { library.syncReport.waiting == 0 })

                let plan = try #require(library.typeChange(of: id, to: Self.event))
                let filling = Dictionary(uniqueKeysWithValues: plan.missing.compactMap { field in Self.sample(for: field).map { (field.key, $0) } })
                let undo = UndoManager()
                library.changeType([id], to: Self.event, filling: filling, undoManager: undo)
                await source.flush()
                try #require(await eventually { library.item(id)?.type == Self.event && library.syncReport.waiting == 0 })
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                #expect(await eventually { library.body(of: id)?.text == text })
                let changed = try #require(try await row(id, in: source))
                #expect(changed.type == Self.event.rawValue)
                #expect(changed.properties[eventBody] == .string(text))
                if noteBody != eventBody { #expect(changed.properties[noteBody] == nil) }

                undo.undo()
                await source.flush()
                try #require(await eventually { library.item(id)?.type == Self.note && library.syncReport.waiting == 0 })
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                #expect(await eventually { library.body(of: id)?.text == text })
                let back = try #require(try await row(id, in: source))
                #expect(back.properties[noteBody] == .string(text))
                if noteBody != eventBody { #expect(back.properties[eventBody] == nil) }
                for key in filling.keys { #expect(back.properties[key] == nil, "\(key)") }
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func fieldsTheNewTypeDoesNotDeclareStay() async throws {
            try await withLibrary { library, source, made in
                let status = try #require(library.catalogue.itemTypes[Self.task]?.statusField)
                let value = try #require(status.options(including: nil).first)
                let id = try make(Self.task, "kept status", body: "Steps", properties: [status.key: .string(value)], in: library, made: made)
                try #require(await eventually { library.item(id) != nil && library.body(of: id) != nil })
                await source.flush()
                try #require(await eventually { library.syncReport.waiting == 0 })

                let plan = try #require(library.typeChange(of: id, to: Self.note))
                #expect(plan.unused.contains(status.key))
                library.changeType([id], to: Self.note, filling: [:], undoManager: nil)
                await source.flush()
                try #require(await eventually { library.item(id)?.type == Self.note && library.syncReport.waiting == 0 })
                #expect(library.notices.waiting.isEmpty, "\(library.notices.waiting)")
                #expect(library.item(id)?.value(of: status.key) == .string(value))
                #expect(try await row(id, in: source)?.properties[status.key] == .string(value))
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func aMissingRequiredFieldIsRefusedAndTheItemStaysAsItWas() async throws {
            try await withLibrary { library, source, made in
                let text = "Kept where it was"
                let id = try make(Self.note, "refused", body: text, in: library, made: made)
                try #require(await eventually { library.body(of: id)?.text == text })
                await source.flush()
                try #require(await eventually { library.syncReport.waiting == 0 })
                let entity = try #require(library.catalogue.itemTypes[Self.entity])
                let required = try #require(entity.fields.first { $0.required && $0.key != "title" })
                #expect(library.item(id)?.value(of: required.key) == nil)

                // The sheet never sends this, so it is sent as is to see the server refuse it: the entity's required
                // name is missing.
                let item = try #require(library.item(id))
                library.submit(.retype(id, Self.entity, [:], base: item.version), failing: String(localized: "Can’t Change Type"))
                await source.flush()
                #expect(await eventually { library.notices.waiting.contains { $0.title == String(localized: "Can’t Change Type") } })
                #expect(await eventually { library.item(id)?.type == Self.note })
                #expect(await eventually { library.body(of: id)?.text == text })
                #expect(try await row(id, in: source)?.type == Self.note.rawValue)
            }
        }
    }
}
