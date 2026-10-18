# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract it follows is `conformance/spec/` in `withmarfa/marfa`; check a Marfa rule there and in the package, not from memory. The rules in `MAPP/Model/AGENTS.md` apply here too.

## Structure

- `MarfaSource` is the `ItemSource` over the copy. The copy answers every read, so the app paints before and without the network, and writes go to the copy's queue at once.
- `MarfaEngine` is the one place the source changes what it holds. `MarfaSync` does all the server work beside it: hydrate, catch up, drain, read the bin, change the key.
- `MarfaFollow` keeps the engine hearing the copy's `changes()`. The core finishes a stream it ended on a fault, after telling it `.stopped`, and one it refused a place in its watch, so `MarfaFollow` asks for a new stream at a falling rate and has the engine read the copy again, since neither stream heard what changed between them. A stream that finishes without `.stopped` last is the copy closing, so the follow ends. A failed follow of the server is different: its stream stays open and `MarfaSync` restarts the follow. After a new stream the engine also asks `MarfaSync` to refresh, which sets the library right again once the server answers. `MarfaSync` tells the person of a stop once until something succeeds, so a core that faults again and again is not an alert at every retry.
- `MarfaLibrary` changes nothing itself. Every write goes to the source.
- The package's `LiveQuery` is not used here. It reads a whole result again after each change and does not say what changed, and the engine reads again only the items and edges a change names, orders every write, answer and change on one stream, and reflects a write at once. `LiveQuery` suits a view that shows one read of a copy; MAPP's views read through `ItemLibrary`, never the package.
- The copy holds both tiers (`hydrate(types:tier: .all)`), so the Inbox and the rest of the library read from one copy, offline too.
- An item's properties keep the order the server gives them (`JSONObject`). Properties, bodies and answers cross the package as values, never as JSON text; the app parses none.
- The package's `Item`, `Edge`, `Edit`, `Draft`, `ListFilters`, `SearchFilters`, `SearchHit`, `BinPage`, `ItemState`, `Tier` and `JSONValue` are the core's own types. `MemberImportVisibility` is on, so a file that reads their members imports each one by name (`import struct MarfaCore.Item`). Never `import MarfaCore` whole: it makes `QueuedWrite`, `MarfaError`, `DrainReport` and other names the package declares itself ambiguous.
- Each server address has its own copy in the app's own storage (`MarfaStoreLocation`), never inside a notes folder.
- `MarfaHost` owns the connection: the address in defaults and the key in the Keychain (`KeychainKeyStore`). The key is never shown again once entered. Tests use `MemoryKeyStore` and a temporary store location.

## Never lose a person's write

- A write that reaches a source after it closed is refused and the person is told (`MarfaEngine.notKept`). The app shows it in the front window and puts its text on the clipboard (`Libraries.unkept`).
- Leaving a copy, by disconnecting or switching server, reads the copy's own queue in the same step as it closes, after the submitted writes are queued. While any writes wait, the person chooses to keep the copy or discard it. A discard names exactly the writes the person was shown; a write that lands after keeps the copy, and the person is asked again.
- A discarded copy is marked before anything is removed and is never opened again as it was.
- Disconnecting forgets the address before it removes the key and the copy, so a quit partway through never reopens that server. Switching server shows the new server's library before the old key and copy are removed.
- A refused key parks the queue until Settings gives another key; the parked writes go with the next drain. Writes made while the key changes wait for the copy rather than fail. A key that works is kept until the server has taken the new one.
- `MarfaHost.handOverEdits` has the pages hand over their edits as a step starts and again right before it reads or closes a copy.
- When the server is back, the copy's held stream drains the queue itself, once, and tells `queueDrained` with the report or `queueNotDrained` with the error. The engine takes those answers as it takes a drain of `MarfaSync`'s own, and `MarfaSync` starts no drain on `serverReachable`. Never start a second drain there.
- A drain the copy runs itself can record answers while the engine is still taking an earlier report. The engine forgets only the answers it has taken (`forgetAnswered(ids:)` with `MarfaEngine.takenAnswers`), never all of them at once. A blocked or dead answer is applied but not marked taken: the copy keeps it for a release, which gives the write the same id and a new answer. A drain that stops on any error loses its report, so the engine reads the answers from the queue before anything forgets them (`MarfaEngine.takeAnswers`).
- When a drain answer expires the copy (`copyExpired`, for example after a retype), `MarfaSync` hydrates again, which keeps the queue, and only then reads the answers from the queue. Never clear the queue to recover from an expired copy.
- A refused write that carried content stays listed until the person discards it, and discarding one that carried text is confirmed, since the write holds the only copy.

## Rows the copy cannot read

- A row whose stored properties the copy could not read comes back with no properties and `Item.unreadableProperties` set. It is shown as damaged: the item carries a problem that keeps it from being edited, the list row and the page say why, and it is never shown as an item the person emptied. `MarfaEngine.propertyEdit` refuses to build a replacement from such a row, since the properties it shows are not what it holds. The package refuses any write to the row until a hydration replaces it from the server, so a read that finds such a row has `MarfaSync` hydrate (`MarfaSync.unreadable`), once for each row while the copy is open. A row still unreadable after that stays damaged, and the message says to disconnect the library and connect it again. A save that arrives for an item that can no longer be written, or that the package refused before queueing it (`SyncProblem.notQueued`), is in no queue, so the text goes to the person through `MarfaLibrary.notKept` like a write after the source closed.
- An edge with `unreadableProperties` is read as its ends alone; a move of it is refused by the package in its own words.

## Text and versions

- Every save names the version of the text it was typed on. Only the first save typed on a version is merged against it (`BodyMerge.asRead`); later saves follow the person's own (`.following`). So a person's saves never conflict with each other and never overwrite text they did not see. Do not replace this with last-writer-wins.
- An answer counts toward that version only once the version it needs can be read; until then it stays in the queue.
- `MarfaLibrary` holds the text the person typed until the source answers it, since a read that raced the write would be older.
- Undo registers the writes that put back what changed, made at the version current when Undo runs.
- Where the server keeps its own text over the person's, the page shows the server's text and says the person's changes went to a copy.

## Edges

- A relationship is an edge, named as the end that holds it writes it (`child-of`), with the other end as `inverse:` and the edge type. Check links against the catalogue's types, roles, how many each end may hold, and the contract's cycle rule (`conformance/spec/edges.md`) before sending.
- An end that holds one link of its type has it replaced by moving the edge's other end: one queued `edges.update` with an `EdgeEdit`, which keeps the edge's ID. Never remove and add, which leaves the end holding none or two for a moment and loses the link on a refusal.
- A move to the end the edge already holds queues nothing: the package returns `nil` from `edges.update`, since the server refuses an update that changes nothing.
- Never take a link that a third item holds as its own; tell the person which item holds it. A change that would need two edges to move is told and not sent.
- Where a field that holds many swaps one item for another, add the new links first and remove the old ones only once the source has taken them.
- What an item's text links or embeds is written as edges by the package when the text is saved. Change a link in the text, never as a relationship. What each link was bound to, including a name that names no item or more than one, is kept on the item in order (`Item.boundLinks`, one per spelling), and `resolveLink` answers each link from its own binding, so the app opens what Marfa's core bound it to. Never answer a link the copy has not bound from the titles held.
- Attachments go through the package's `attach(to:file:)`, and the editor inserts the returned name into the text. Do not use the package's `embed(file:in:_:)`, which edits the body itself, outside the editor's versioned saves. Make a file's name unique among the item's attachments first, since an embed must name one file.

## Server-only actions

- Delete Permanently is `purge`, which is never queued. Offer it only while the server can be reached. It runs after the writes submitted before it have been sent, at the version the person was shown, and the server's answer is its verdict.
- The bin is the server's. The engine keeps a deleted item's last row for Recently Deleted until `MarfaSync` reads the bin.
- A Marfa folder (`system.folder`) is not a MAPP folder: it holds a device's sync settings and places no item. Do not use the package's folder calls, keep `.folders` out of a Marfa source's capabilities, and show no folders.

## Wording

- The model gives states and counts; `SyncWording.swift` turns them into words, so each sentence is tested without a window.
- Show a `MarfaHost.Problem` as what happened and what to do (`MarfaSettingsModel.notice(for:)`), never as the error.
- A problem offers only the actions the contract allows for it (`MarfaProblems`).

## Code Review Rules

- **Write dropped.** Flag any path that closes, discards, or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge that is queued, offered offline, or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single-valued link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code, or allowed action that differs from `conformance/spec/` or the package.
