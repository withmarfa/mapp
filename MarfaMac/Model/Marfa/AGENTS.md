# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract is `conformance/spec/` in `withmarfa/marfa`. Check a rule there and in the package.

## Never lose a person's write

- **A write refused before it is queued is in no queue,** and neither is one that reaches a closed source. The typed text goes back through `Notices.notKept` (`MarfaLibrary.unqueuedText`).
- **Leaving a copy reads its queue in the step that closes it.** While writes wait, the person keeps or discards it. A discard names exactly the writes shown, so one that lands after keeps the copy.
- **A copy is removed only by `WorkingCopy.remove(store:confirming:)`,** against a fresh `unsentWrites(in:)`, all of it shown to the person (`MarfaHost.removeStore`). One that cannot be read stays.
- **A copy another version made opens with `ifRefused: .replace`,** which replaces it only with nothing unsent. Otherwise it is refused and the person sees what waits (`MarfaHost.unsentChanges(in:)`). Pass no `fileBudget` to `open`.
- **A copy is marked as discarded before it closes or anything waits** (`markBeforeLeaving`), on a disconnect and on a switch. A refused close takes the mark off again.
- **An ended sign-in parks the queue** until Settings signs in again, which hands the editors over and then gives the open copy the sign-in (`WorkingCopy.use(_:)`). The library stays, unless the store could not open again (`SourceUseFailure.closed`).
- **A switch that finds more writes after its sign-in keeps the approval** for the person's answer (`pendingSignIn`). A failed answer, a dropped question or a launch ends it.
- **An error the package classifies is never a fault** (`isOffline`, `isTransient`, `isKeyRefusal`): the package reports it through the connection and retries. A canceled call is not shown. Any other error shows the library unavailable, told once, with Refresh.
- **The copy drains its queue itself.** The sync drains once more when the connection follows again, never on a timer.
- **Answers are taken only by the queue's take-answered call** (`MarfaEngine+Answers.swift`), which clears what was answered and lists what was refused with its verdict, each told once.
- **Never clear the queue to recover from `copyExpired`.** Hydrate again, which keeps it.
- **A refused write that carried content stays listed** until the person discards it, and discarding it, or Undo Change on it, is confirmed.
- **A row the copy could not read is shown as damaged** (`Item.unreadableProperties`), never as an item the person emptied. An edit names only what it sets and clears (`Edit.clearProperties`), so the server keeps the rest.

## Text and versions

- **Every save names the version of the text it was typed on.** Only the first save sent on a version is merged against it (`BodyMerge.asRead`); later ones follow the person's own (`.following`). Never replace this with last-writer-wins, which overwrites text the person never saw.
- **Text read before the server answered this device's create is at version 0.** An edit on it goes on version 1 (`MarfaEngine.version(read:holding:)`), never the copy's version.
- **`MarfaLibrary` coalesces typing** (`TextPause`): held at once and until answered, sent after a pause or at a hand-over.
- **An Undo or Redo refused while the copy catches up is held** (`MarfaEngine+Holding`) and made only if what it touches is as it was when it was pressed. Otherwise no held write of the step is made, and the person is told. A held write never waits without end.
- **Where the server keeps its own text,** the page shows it and says the person's changes went to a copy.
- **A restore writes only the title and the text,** by the ordinary edit path, on the version the library holds.

## Edges and files

- **The core judges new links and moves** (`Edges.check`), including endpoint types, nesting, the bin, cycles, duplicates and cardinality. Either end can request the change.
- **`changeLinks` takes what the person changed** (`adding`, `removing`), never the screen's list. Changes run in call order, each after the source has taken (`SourceChange.taken`) or answered the one before.
- **Only `validation` and `notFound` refuse a check,** in the core's words, but for a `details.constraint` of `cardinality` or `duplicate`. A copy not yet whole is `.incomplete`, and any other error `.unknown`; neither is the core's refusal.
- **Check a new child's parent and every new link before writing any** (`newChildVerdict(under:)`).
- **An end that holds one link has it replaced by moving the other end,** in one `edges.update`. Never remove and add, which can leave the end with none or two.
- **Never take a link that a third item holds.** Tell the person which item holds it. A many-valued swap sends its new links first. A refusal leaves the old links in place.
- **The package writes what a text links or embeds as edges on save.** Change such a link in the text, never as a relationship, and answer a link only from the core (`ItemSource.linkAnswers`).
- **Attach through `attach(to:file:)`,** with a name unique on the item. Never use `embed(file:in:_:)`, which edits the body outside the editor's versioned saves.

## Structure

- **Every write goes to `MarfaSource`,** the `ItemSource` over the copy; `MarfaLibrary` changes nothing itself. Only `MarfaEngine` changes the source's contents.
- **The copy is the record.** The engine holds raw rows and edges, `MarfaHub` what readers were told, and `MarfaLibrary.records` the main actor's copy, which feeds `MarfaItemIndex`.
- **The engine reads what changed since its cursor** (`readChanged`), on one ordered stream. Do not use the package's live queries.
- **The package owns retries, fill progress, connection state and the last sync time.** `MarfaSync` hydrates on each move to `.needsHydration`. A fault stops it and offers Refresh.
- **A failed names call leaves an item the name it had,** and a new item shows a placeholder. It is told once, until a success.
- **A type's search is one call** (`SearchFilters.types`), so past its limit of types it is refused and said, never split.
- **Hidden rows (`system.*`, `app.*`) stay out of** items, counts, search and the bin (`MarfaMapping.isLibraryItem`), and their writes out of the problems (`MarfaEngine.libraryWrites`).
- **Properties, bodies and answers cross the package as values,** never as JSON text.
- **Tests step in only through the Debug-only `hooks`** (`TestTally`). Add no test setter or override to a shipping type.

## Connecting

- **`MarfaHost` owns the connection:** the address in defaults, the sign-in in the Keychain. Each Marfa has one copy, found by its origin (`MarfaStoreLocation`, `MarfaCopies`).
- **A Marfa is known by the instance it says it is,** read without a sign-in (`MarfaHost+Copies.swift`). Another origin opens a copy only then, with its own sign-in. Another instance at a known address gets a new copy.
- **Another copy of the open Marfa is sent from its own store,** never merged, and removed only once its queue is empty (`sendOtherCopies`).
- **Plain http to another machine is told once a run** (`Server.plainHTTPOrigin`). App Transport Security has no exception.
- **`SignIns` keeps the sign-in** (`ScriptedSignIns` in tests) and asks for what `SystemSignIns.scopes` lists. An `http_<n>` refusal means there is no Marfa server.

## Server calls

- **Make them through `MarfaServerCalls`** and the package's `Client` over its `Server`. Build no second client.
- **A type's field change is never queued,** and `PUT /types/{id}` has no version, so `TypeDefinitionEdit` rereads the type first.
- **This Marfa's settings change by `PATCH /config`** with only the changed fields, `null` to remove one, and the instance read in `X-Marfa-Instance-Id`. Never send `PUT`, `instance_id` in the body or an unchanged field.
- **Permanently Delete is `purge`,** offered only while the server answers, run after earlier writes, at the version the person was shown.
- **Saved views use** `createView`, `changeView` and `deleteView`, each on the version the window read.
- **A source's name, mark and count are the server's** (`MarfaLibrary.sources`): a code until it is named, then the last answer while offline.
- **Only Settings > Folders uses `CopyFolderCalls`,** whose pins stay until Stop Syncing.

## Wording

- **Tell a `MarfaHost.Problem` as what happened and what to do** (`Words.message(for:)`, `SignInOutcome`), never an error's text, with only the contract's actions (`MarfaProblems`). States and counts are worded in `SyncWording.swift`.

## Code Review Rules

- **Write dropped.** Flag a path that closes, discards or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge queued, offered offline or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code or allowed action that differs from `conformance/spec/` or the package.
