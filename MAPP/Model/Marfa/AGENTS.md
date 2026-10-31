# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract it follows is `conformance/spec/` in `withmarfa/marfa`; check a Marfa rule there and in the package, not from memory. The rules in `MAPP/Model/AGENTS.md` apply here too. The engine's types say in their doc comments how they read, coalesce and hold.

## Structure

- `MarfaSource` is the `ItemSource` over the copy. The copy answers every read, so the app paints before and without the network, and writes go to the copy's queue at once. `MarfaLibrary` changes nothing itself; every write goes to the source.
- `MarfaEngine` (one actor, split by file) is the one place the source changes what it holds. `MarfaSync` does all the server work beside it: hydrate, catch up, drain, read the bin, change the key. `MarfaFollow` keeps the engine hearing the copy's `changes()`.
- The copy is the record. The engine holds the raw rows and edges, `MarfaHub` what readers were told, and `MarfaLibrary.records` the main actor's observable copy, from which `MarfaItemIndex` is derived. Add no other copy.
- Do not use the package's `LiveQuery`: the engine reads again only what a change names, on one ordered stream. MAPP's views read through `ItemLibrary`, never the package.
- The engine keeps every `system.*` row out of the items, Recents, counts, search and the bin (`MarfaMapping.isLibraryItem`).
- Properties, bodies and answers cross the package as values, never as JSON text; the app parses none. Never `import MarfaCore` whole: import each core type by name (`import struct MarfaCore.Item`), since `MemberImportVisibility` is on and a whole import makes the package's own names ambiguous.
- Tests step into the engine, `MarfaSync`, `MarfaDownloads` and `PictureCache` only through their `hooks` and count through `TestTally` (`MAPP/Model/TestHooks.swift`, Debug only). Never add a setter for tests to a shipping type.
- `MarfaHost` owns the connection: the address in defaults and the key in the Keychain (`KeychainKeyStore`); the key is never shown again once entered. Each address has its own copy (`MarfaStoreLocation`). The library is the one subscriber to the source's states and reports and tells the host through callbacks; never subscribe a second time.
- An address that sends the key over plain http to another machine is told once a run. Only Version History (`MarfaServerVersions`) and This Marfa (`MarfaServerConfig`) go over `URLSession`, so App Transport Security applies to them alone; `Info.plist` has no exception.

## Never lose a person's write

- A write that reaches a source after it closed, or that the package refuses before queueing it, is in no queue: what the person typed into it goes back through `Notices.notKept` (`MarfaLibrary.unqueuedText`). A refused text save is given back the same way.
- Leaving a copy, by disconnecting or switching server, reads the copy's own queue in the same step as it closes. While any writes wait, the person chooses to keep the copy or discard it, and a discard names exactly the writes the person was shown; a write that lands after keeps the copy.
- A copy is removed only by the package's `WorkingCopy.remove(store:unsent:)` (`MarfaHost.removeCopy`), with the count of changes the person was shown. A copy whose changes could not be counted is never discarded. A copy another version made (`MarfaError.wrongSchema`) is replaced only when the package counts no unsent changes. Never pass a `fileBudget` to `open` or `replaceRefused`.
- Disconnecting forgets the address before it removes the key and the copy, so a quit partway through never reopens that server.
- A refused key parks the queue until Settings gives another key. A key that works is kept until the server has taken the new one.
- The copy drains its queue itself when the server is back; never start a second drain on `serverReachable`. The engine forgets only the answers it has taken, never all at once, and reads answers from the queue before anything forgets them.
- Never clear the queue to recover from an expired copy (`copyExpired`): hydrate again, which keeps it.
- A refused write that carried content stays listed until the person discards it; discarding one that carried text, or Undo Change on it, is confirmed.
- A row the copy could not read (`Item.unreadableProperties`) is shown as damaged and never as an item the person emptied, and no edit is built from it (`MarfaEngine.propertyEdit`).

## Text and versions

- Every save names the version of the text it was typed on. Only the first save typed on a version is merged against it (`BodyMerge.asRead`); later saves follow the person's own (`.following`). So a person's saves never conflict with each other and never overwrite text they did not see. Do not replace this with last-writer-wins.
- Text read before the server answered this device's own create is at version 0; an edit typed on it is sent on version 1 (`MarfaEngine.version(read:holding:)`), never on the version the copy holds.
- `MarfaLibrary` holds the text the person typed until the source answers it, since a read that raced the write would be older.
- An Undo or Redo the copy refuses while it is brought up to date is held (`MarfaEngine+Holding`) and made only if what it touches is as it was when it was pressed; otherwise none of the step is made and the person is told. A held write never overwrites newer text and never waits without end.
- Where the server keeps its own text over the person's, the page shows the server's text and says the person's changes went to a copy.
- A restore writes only the title and the text, through the ordinary edit path on the version the library holds.

## Server calls

- This Marfa changes settings with `PATCH /config` carrying only the changed fields (`null` removes one) and the instance it read in `X-Marfa-Instance-Id`. Never send `PUT`, `instance_id` in the body, or a field the person did not change.
- Delete Permanently is `purge`, never queued, offered only while the server can be reached, and run after the writes submitted before it, at the version the person was shown.
- Saved views (`system.view`) are written through the package's `createView`, `changeView` and `deleteView`, never queued and never as items, each based on the version the window read.
- A Marfa folder (`system.folder`) places no item. Do not use the package's folder calls.

## Edges and files

- A relationship is an edge written by the end that holds it. Check links against the catalogue's types, roles, how many each end may hold, and the contract's cycle rule (`conformance/spec/edges.md`) before sending.
- An end that holds one link of its type has it replaced by moving the edge's other end (one `edges.update` with an `EdgeEdit`). Never remove and add, which leaves the end holding none or two and loses the link on a refusal.
- Never take a link that a third item holds as its own; tell the person which item holds it. Where a field that holds many swaps one item for another, add the new links first and remove the old ones only once the source has taken them.
- What an item's text links or embeds is written as edges by the package when the text is saved: change a link in the text, never as a relationship. Answer a link only from the copy's binding (`Item.boundLinks`), never from the titles held.
- Attachments go through the package's `attach(to:file:)`, with a name unique among the item's attachments. Never use `embed(file:in:_:)`, which edits the body outside the editor's versioned saves.

## Wording

- `SyncWording.swift` turns the model's states and counts into words. Show a `MarfaHost.Problem` as what happened and what to do, never as the error, with only the actions the contract allows (`MarfaProblems`).

## Code Review Rules

- **Write dropped.** Flag any path that closes, discards, or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge that is queued, offered offline, or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single-valued link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code, or allowed action that differs from `conformance/spec/` or the package.
