# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract it follows is `conformance/spec/` in `withmarfa/marfa`; check a Marfa rule there and in the package. The rules in `MAPP/Model/AGENTS.md` apply here too.

## Structure

- `MarfaSource` is the `ItemSource` over the copy. The copy answers every read, so the app paints offline; writes go to its queue at once. `MarfaLibrary` changes nothing itself; every write goes to the source.
- `MarfaEngine` (one actor, split by file) is the one place the source changes what it holds. `MarfaSync` does the server work the package does not: it consumes `WorkingCopy.updates()`, shows the connection the package reports and the fill, hands each update to the engine and waits for it to be read, sends what waits and fetches kept files. MAPP keeps no retry timer, progress poll, last-synced stamp or connection state. Each turn of the connection to `.needsHydration`, also after an `.offline` wait, hydrates the copy; a fault shows stopped with Refresh offered.
- The copy is the record. The engine holds the raw rows and edges, `MarfaHub` what readers were told, and `MarfaLibrary.records` the main actor's observable copy, from which `MarfaItemIndex` is derived.
- Do not use the package's `LiveQuery`: the engine reads again only what the copy names as changed since its own cursor (`readChanged`), on one ordered stream. An update only says what kind of read is wanted; the first of a stream is read from the cursor. Views read through `ItemLibrary`, never the package.
- The engine keeps every `system.*` row out of items, Recents, counts, search and the bin (`MarfaMapping.isLibraryItem`).
- Properties, bodies and answers cross the package as values, not JSON text. The package owns its types (`Item`, `Edge`, `Draft`, `Edit`, `JSONValue`); `import Marfa` is its only import.
- Tests step into the engine, `MarfaSync`, `MarfaDownloads` and `PictureCache` only through their `hooks`, counting through `TestTally` (`TestHooks.swift`, Debug only). Never add a setter or an override for tests to a shipping type.
- `MarfaHost` owns the connection: the address in defaults, the sign-in in the Keychain, made on the server's own page. Each address has its own copy (`MarfaStoreLocation`). The library is the one subscriber to the source's states and reports and tells the host by callback.
- An address that sends the sign-in over plain http to another machine is told once a run (`Server.plainHTTPOrigin`). `Server` calls go over `URLSession`, so App Transport Security applies; `Info.plist` has no exception.

## Never lose a person's write

- A write that reaches a closed source, or that the package refuses before queueing it, is in no queue: what the person typed goes back through `Notices.notKept` (`MarfaLibrary.unqueuedText`).
- Leaving a copy (disconnecting or switching server) reads its queue in the same step as it closes. While any writes wait, the person chooses to keep the copy or discard it, and a discard names exactly the writes the person was shown; a write that lands after keeps the copy.
- A copy is removed only by `WorkingCopy.remove(store:unsent:)`, with the count of changes the person was shown; one that could not be counted is never discarded. A copy another version made opens with `ifRefused: .replace`, replaced only when it counts no unsent changes; with any, it refuses (`MarfaError.wrongSchema`) and the person is told the count. A copy whose server is another one (`MarfaError.wrongServer`) is told with its unsent count (`Words.otherServer`). Never pass a `fileBudget` to `open`.
- Disconnecting forgets the address before ending the sign-in and removing the copy, so a quit partway never reopens that server.
- An ended sign-in (`signedOut`, `credential_ended`) parks the queue until Settings signs in again, which closes the copy and opens it on the new sign-in; nothing in the queue is discarded. A canceled sign-in changes nothing; Cancel shows only while `isSigningIn`. A switch that finds more writes after its sign-in keeps the approval for the answer (`pendingSignIn`, recorded in the defaults): the answer takes it; a failed answer, a dropped question or the next launch ends it.
- An error the package classifies (`isOffline`, `isTransient`, `isKeyRefusal`) is never a fault to show: the package reports it through the connection and tries again. A canceled call is not shown. What remains (another error, or `invalid`, `unknownType`, `validation`) shows the library unavailable, told once, with Refresh offered. Hydration errors are `isHydrationNeeded`. `MarfaEngine.asking` waits out `keyChanging`. A stop is told once per change of connection and a drain failure until one succeeds; the library stays stopped until then (not `.noServer`). One hydration runs whatever the progress updates.
- `SignIns` keeps the sign-in (`SystemSignIns` over the package's `Authorization`; `MemorySignIns` in tests), asking for item and `edge.*` scopes. One it cannot read (a throw) is shown as that (`Words.signInUnreadable`), never as missing or ended, and nothing is replaced.
- The copy drains its queue itself when the server is back; the sync drains once more when the connection returns to following, never on a timer. The engine takes answers only with `Queue.takeAnswered()`: it clears the answered writes and lists a refused write that carried content, a blocked one and a dead one with their verdict, each told once.
- Never clear the queue to recover from `copyExpired`: hydrate again, which keeps it.
- A refused write that carried content stays listed until the person discards it; discarding it, if it carried text, or Undo Change on it, is confirmed.
- A row the copy could not read (`Item.unreadableProperties`) is shown as damaged and never as an item the person emptied, and no edit is built from it (`MarfaEngine.propertyEdit`).

## Text and versions

- Every save names the version of the text it was typed on. Only the first save typed on a version is merged against it (`BodyMerge.asRead`); later saves follow the person's own (`.following`). So a person's saves never conflict with each other and never overwrite text they did not see. Do not replace this with last-writer-wins.
- Text read before the server answered this device's own create is at version 0; an edit typed on it is sent on version 1 (`MarfaEngine.version(read:holding:)`), never on the version the copy holds.
- `MarfaLibrary` holds the text the person typed until the source answers it, as a read that raced the write would be older.
- An Undo or Redo the copy refuses while catching up is held (`MarfaEngine+Holding`) and made only if what it touches is as it was when it was pressed; otherwise none of the step is made and the person is told. A held write never overwrites newer text and never waits without end.
- Where the server keeps its text over the person's, the page shows the server's and says the person's changes went to a copy.
- A restore writes only the title and the text, through the ordinary edit path on the version the library holds.

## Server calls

- `MarfaServerCalls` makes Version History, This Marfa and type-icon calls through `Server`; build no second client.
- This Marfa changes settings with `PATCH /config` carrying only the changed fields (`null` removes one) and the instance it read in `X-Marfa-Instance-Id`. Never send `PUT`, `instance_id` in the body, or a field the person did not change.
- Delete Permanently is `purge`, never queued, offered only while the server can be reached, and run after the writes submitted before it, at the version the person was shown.
- Saved views (`system.view`) are written through the package's `createView`, `changeView` and `deleteView`, never queued and never as items, each based on the version the window read.
- A Marfa folder (`system.folder`) places no item. Do not use the package's folder calls.

## Edges and files

- A relationship is an edge written by the end that holds it. The core judges end types, nesting, the bin and cycles (`Edges.check`), but **not cardinality yet**, so MAPP checks how many links an end holds. `changeItemRelationship` takes what the person changed (`adding`, `removing`), never the list the screen showed, and works the links out from the copy after the core's check. Changes run in call order, each after the source has taken (`SourceChange.taken`) or answered the writes of the one before; a closed source ends the wait. `finish` waits for one in flight.
- `Edges.check` needs only the source held, and skips the target's type for a target not held. Only `validation` and `notFound` are its refusal (`EdgeVerdict.refused`); any other error is `.unknown`, which refuses nothing, and a picker row asks again. Check a new child's parent (`newChildVerdict(under:)`) and every new link of a change before writing any.
- An end that holds one link of its type has it replaced by moving the edge's other end (one `edges.update` with an `EdgeEdit`). Never remove and add: that can leave the end holding none or two.
- Never take a link that a third item holds as its own; tell the person which item holds it. A many-valued swap adds the new links first and removes the old ones once the source has taken them.
- What an item's text links or embeds is written as edges by the package when the text is saved: change a link in the text, never as a relationship. Answer a link only from the core (`ItemSource.linkAnswers`), never from the titles held.
- Attachments go through the package's `attach(to:file:)`, with a name unique among the item's attachments. Never use `embed(file:in:_:)`, which edits the body outside the editor's versioned saves.

## Wording

- `SyncWording.swift` words the model's states and counts. Show a `MarfaHost.Problem` as what happened and what to do, never the error, with only the contract's actions (`MarfaProblems`).

## Code Review Rules

- **Write dropped.** Flag any path that closes, discards, or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge that is queued, offered offline, or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single-valued link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code, or allowed action that differs from `conformance/spec/` or the package.
