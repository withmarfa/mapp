# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract is `conformance/spec/` in `withmarfa/marfa`; check a rule there and in the package.

## Structure

- `MarfaSource` is the `ItemSource` over the copy. Views draw from the copy offline; a row count it cannot answer needs the server. `MarfaLibrary` changes nothing itself; every write goes to the source.
- Only `MarfaEngine` changes the source's contents. `MarfaSync` consumes `WorkingCopy.updates()`, waits for the engine's reads, sends queued writes and fetches kept files. The package owns retries, fill progress, connection state and the last sync time; a new one refreshes table row counts. Each transition to `.needsHydration`, including one from `.offline`, hydrates the copy. A fault stops hydration, offering Refresh.
- The copy is the record. The engine holds the raw rows and edges, `MarfaHub` what readers were told, and `MarfaLibrary.records` the main actor's copy, the source of `MarfaItemIndex`.
- Do not use the package's `LiveQuery`: the engine reads what the copy names as changed since its cursor (`readChanged`), on one ordered stream. An update says only what kind of read is wanted; the first of a stream is read from the cursor.
- Names and previews come from `items.displays` in batches. A failed call leaves an item its earlier name; a new item shows a placeholder. A publish asks its own items, then the earlier unnamed if that worked; a failure is told once until a success.
- A type's search follows Include Subtypes (`SearchScope.typeWithSubtypes`, one type through `SearchFilters.types`); `MarfaSource.search` is one call, so more than ten types is refused, shown as "Can’t Search".
- The engine keeps every hidden row (`system.*`, `app.*`) out of items, Recents, counts, search and the bin (`MarfaMapping.isLibraryItem`), and their writes out of the problems (`MarfaEngine.libraryWrites`). The slice takes this app's settings only where reached (`PreferencesReach`).
- Properties, bodies and answers cross the package as values, not JSON text. The package owns its types.
- Tests step into the engine, `MarfaSync` and `PictureCache` only through their Debug-only `hooks` (`TestTally`); add no test setter or override to a shipping type.
- `MarfaHost` owns the connection: the address in defaults, the sign-in in the Keychain, made on the server's own page. Each address has its own copy (`MarfaStoreLocation`). The library, the one subscriber to the source's states and reports, tells the host by callback.
- Plain http to another machine is told once a run (`Server.plainHTTPOrigin`); App Transport Security has no `Info.plist` exception.

## Never lose a person's write

- A write that reaches a closed source or is refused before queueing is in no queue: the typed text goes back through `Notices.notKept` (`MarfaLibrary.unqueuedText`).
- Leaving a copy (disconnecting or switching) reads its queue in the step closing it. While writes wait, the person keeps or discards it; a discard names exactly the writes shown, so one that lands after keeps it.
- A copy is removed only by `WorkingCopy.remove(store:confirming:)` against a fresh `unsentWrites(in:)`, all shown to the person (`MarfaHost.removeStore`); an unreadable one stays. A copy another version made opens with `ifRefused: .replace`, replaced only with none unsent, else refused (`MarfaError.wrongSchema`) with its count; leaving lists its writes (`MarfaHost.unsentChanges(in:)`). One for another server (`MarfaError.wrongServer`) is told with its unsent count (`Words.otherServer`). Pass no `fileBudget` to `open`.
- Disconnecting forgets the address and marks a discarded copy before it closes or anything waits (`markBeforeLeaving`); a refused close restores both; a switch marks the old copy first; the folder goes only when empty.
- An ended sign-in (`signedOut`, `credential_ended`) parks the queue until Settings signs in again, which hands the editors over, then gives the open copy the sign-in with `WorkingCopy.use(_:)`; library and queue stay unless the store could not open again (`SourceUseFailure.closed`); a reader copy is told `inUse`. A switch that finds more writes after its sign-in keeps the approval for the answer (`pendingSignIn`, in the defaults); a failed answer, a dropped question or a launch ends it.
- An error the package classifies (`isOffline`, `isTransient`, `isKeyRefusal`) is never a fault: the package reports it through the connection and retries. A canceled call is not shown. Any other error (`invalid`, `unknownType`, `validation`, the rest) shows the library unavailable, told once, with Refresh. A stop is told once per connection change, a drain failure until a success; the library stays stopped. One hydration runs whatever the progress says.
- `SignIns` keeps the sign-in (over the package's `Authorization`; `ScriptedSignIns` in tests), asking for `SystemSignIns.scopes(offered:)` (`OfferedScopes`; a failed read starts no sign-in). Only a sign-out's `.notConfirmed` is told, as the `marfa apps` steps that end it. An address is read as entered: `https://host` and `https://host:443` are two copies and two discard marks. `sameServer(as:)` (origin) only makes a same-origin address Sign In Again. An `http_<n>` refusal means no Marfa server; a thrown clean-up sign-out is told.
- The copy drains its queue itself when the server is back; the sync drains once more when the connection returns to following, never on a timer. The engine takes answers only with `Queue.takeAnswered()`, which clears the answered writes and lists a refused write that carried content, a blocked one and a dead one with their verdict, each told once.
- Never clear the queue to recover from `copyExpired`: hydrate again, which keeps it.
- A refused write that carried content stays listed until the person discards it; discarding it (if it carried text) or Undo Change on it is confirmed.
- A row the copy could not read (`Item.unreadableProperties`) is shown as damaged and never as an item the person emptied. An edit names only what it sets and clears (`Edit.clearProperties`), so the server keeps the rest.

## Text and versions

- Every save names the version of the text it was typed on. Only the first save sent on a version is merged against it (`BodyMerge.asRead`); later ones follow the person's own (`.following`), so saves never conflict with each other or overwrite text the person never saw. Never last-writer-wins.
- Text read before the server answered this device's create is at version 0; an edit on it goes on version 1 (`MarfaEngine.version(read:holding:)`), never the copy's version.
- `MarfaLibrary` coalesces typing (`TextPause`): held at once and until answered, as a raced read is older; sent after a pause or at a hand-over, leaving none waiting.
- An Undo or Redo the copy refuses while catching up is held (`MarfaEngine+Holding`) and made only if what it touches is as it was when it was pressed; otherwise none of the step is made and the person is told. A held write never overwrites newer text and never waits without end.
- Where the server keeps its text over the person's, the page shows the server's and says the person's changes went to a copy.
- A restore writes only the title and the text, through the ordinary edit path on the version the library holds.

## Server calls

- `MarfaServerCalls` makes Version History, type-icon and source calls through `Server`, and This Marfa's settings through the package's `Client` over that `Server`; build no second client.
- A type's field change (`MarfaServerCalls`) is never queued. `PUT /types/{id}` has no version, so `TypeDefinitionEdit` rereads the type first.
- Source names, marks and counts are server-only: `MarfaLibrary.sources` holds the last answer in memory (a source shows its code until the server has named it, and keeps the last answer offline). Its doc comment says when it is read and where the counts come from.
- This Marfa changes settings with `PATCH /config` carrying only the changed fields (`null` removes one) and the instance it read in `X-Marfa-Instance-Id`. Never send `PUT`, `instance_id` in the body, or an unchanged field.
- Permanently Delete is `purge`, never queued, offered only while the server can be reached, run after earlier writes, at the version the person was shown.
- Saved views (`system.view`) are written through the package's `createView`, `changeView` and `deleteView`, never queued or as items, each on the version the window read.
- A Marfa folder (`system.folder`) places no item. Do not use the package's folder calls.

## Edges and files

- A relationship is an edge written by the end that holds it; the core judges end types, nesting, the bin, cycles, duplicates and how many links an end may hold (`Edges.check(from:to:type:)`, and `Edges.check(_:moving:)` of a move); the app has no cardinality rule. `changeItemRelationship` takes what the person changed (`adding`, `removing`), never the screen's list, and works the links out from the copy. Changes run in call order, each after the source has taken (`SourceChange.taken`) or answered the previous one's writes; a closed source ends the wait, and `finish` waits for one in flight.
- `Edges.check` needs only the source held. Only `validation` and `notFound` refuse, in the core's words, but for `details.constraint` `cardinality` and `duplicate`; any other error is `.unknown`, which refuses nothing, and a picker row asks again. Check a new child's parent (`newChildVerdict(under:)`) and every new link of a change before writing any; a picker row asks as the change would be made.
- An end that holds one link of its type has it replaced by moving the edge's other end (one `edges.update`, asked of the core as a move). Never remove and add: that can leave the end holding none or two.
- Never take a link a third item holds as its own; tell the person which item holds it. A many-valued swap adds the new links first and removes the old ones once the source has taken them.
- The package writes what an item's text links or embeds as edges on save: change such a link in the text, never as a relationship. Answer a link only from the core (`ItemSource.linkAnswers`), never from the titles held.
- Attachments go through the package's `attach(to:file:)`, with a name unique among the item's attachments. Never use `embed(file:in:_:)`, which edits the body outside the editor's versioned saves.

## Wording

- `SyncWording.swift` words the model's states and counts. Tell a `MarfaHost.Problem` as what happened and what to do, never an error's text (`Words.message(for:)`, `SignInOutcome`), with only the contract's actions (`MarfaProblems`).

## Code Review Rules

- **Write dropped.** Flag any path that closes, discards, or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge that is queued, offered offline, or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single-valued link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code, or allowed action that differs from `conformance/spec/` or the package.
