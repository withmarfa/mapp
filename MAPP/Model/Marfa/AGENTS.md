# Marfa library

`MarfaLibrary` is the `ItemLibrary` over a Marfa server, read through the `marfa-swift` package's working copy. The contract it follows is `conformance/spec/` in `withmarfa/marfa`; check a Marfa rule there and in the package, not from memory. The rules in `MAPP/Model/AGENTS.md` apply here too.

## Structure

- `MarfaSource` is the `ItemSource` over the copy. The copy answers every read, so the app paints before and without the network, and writes go to the copy's queue at once.
- `MarfaEngine` is the one place the source changes what it holds. `MarfaSync` does all the server work beside it: hydrate, catch up, drain, read the bin, change the key.
- `MarfaFollow` keeps the engine hearing the copy's `changes()`. The core finishes a stream it ended on a fault, after telling it `.stopped`, and one it refused a place in its watch, so `MarfaFollow` asks for a new stream at a falling rate and has the engine read the copy again, since neither stream heard what changed between them. A stream that finishes without `.stopped` last is the copy closing, so the follow ends. A failed follow of the server is different: its stream stays open and `MarfaSync` restarts the follow. After a new stream the engine also asks `MarfaSync` to refresh, which sets the library right again once the server answers. `MarfaSync` tells the person of a stop once until something succeeds, so a core that faults again and again is not an alert at every retry.
- `MarfaLibrary` changes nothing itself. Every write goes to the source.
- Do not use the package's `LiveQuery`: it reads a whole result again after each change without saying what changed, while the engine reads again only what a change names, on one ordered stream, and reflects a write at once. MAPP's views read through `ItemLibrary`, never the package.
- The copy holds both tiers (`hydrate(types:tier:edgeTypes:)` with `MarfaSync.slice`, `["*", "system.view"]`, and tier `.all`), so the Inbox and the rest of the library read from one copy, offline too. The slice holds `parent-of` whole (`MarfaSync.sliceEdgeTypes`), which a view's `beneath` filter needs. `system.view` is in the slice only so the copy can list the saved views and their items (`MarfaReading.views()`, `items(inView:)`); the engine keeps every `system.*` row out of the items, Recents, counts, search and the bin (`MarfaMapping.isLibraryItem`). A hydration under way answers only the views that have arrived (`.partial`), so the engine adds those to the views it last read and removes none until the answer is whole. A view whose version changes, as when its query changes, drops its last list (`LibraryView.version`). A copy whose slice differs hydrates again, keeping its queued writes.
- An item's properties keep the order the server gives them (`JSONObject`). Properties, bodies and answers cross the package as values, never as JSON text; the app parses none.
- The package's `Item`, `Edge`, `Edit`, `Draft`, `ListFilters`, `SearchFilters`, `SearchHit`, `BinPage`, `ItemState`, `Tier` and `JSONValue` are the core's own types. `MemberImportVisibility` is on, so a file that reads their members imports each one by name (`import struct MarfaCore.Item`). Never `import MarfaCore` whole: it makes `QueuedWrite`, `MarfaError`, `DrainReport` and other names the package declares itself ambiguous.
- Each server address has its own copy in the app's own storage (`MarfaStoreLocation`).
- `MarfaHost` owns the connection: the address in defaults and the key in the Keychain (`KeychainKeyStore`). The key is never shown again once entered. Tests use `MemoryKeyStore` and a temporary store location.
- `MarfaHost` makes the one `MarfaLibrary` for the copy it opens (`MarfaHost.library`). While a copy is open, how the server stands and what the copy last reported are the library's (`connection`, `syncReport`); the host reads them from it and holds its own state only while no copy is open. Never subscribe to a source's states or reports a second time to keep a copy of them.
- An address that sends the key over plain http to another machine is told once in each run, when its copy is first attached (`Server.takePlainHTTPNotice()`), in the app's own words, through the host's `notices`. `localhost`, `127.0.0.0/8` and `::1` are not. MAPP reaches the server only through the package's core, not `URLSession`, so App Transport Security does not apply and `Info.plist` has no exception.
- `MarfaHost` also reads the server's own name (`Server.instanceDescription()`, which sends no key) when a copy is attached and each time the connection returns online, off the main actor, and keeps the last name for each address in defaults. A failed read changes nothing. `LibraryDescription.name` shows the name, or the address's host until one has been read. Disconnecting or switching away forgets that address's name.

## Never lose a person's write

- A write that reaches a source after it closed is refused (`MarfaEngine.closedCode`), and the library tells the person through `Notices.notKept`, which puts its text on the clipboard as a window first shows it.
- Leaving a copy, by disconnecting or switching server, reads the copy's own queue in the same step as it closes, after the submitted writes are queued. While any writes wait, the person chooses to keep the copy or discard it. A discard names exactly the writes the person was shown; a write that lands after keeps the copy, and the person is asked again.
- A discarded copy is marked before anything is removed and is never opened again as it was.
- Disconnecting forgets the address before it removes the key and the copy, so a quit partway through never reopens that server. Switching server shows the new server's library before the old key and copy are removed.
- A refused key parks the queue until Settings gives another key; the parked writes go with the next drain. Writes made while the key changes wait for the copy rather than fail. A key that works is kept until the server has taken the new one.
- `MarfaHost.handOverEdits` has the pages hand over their edits as a step starts and again right before it reads or closes a copy.
- When the server is back, the copy's held stream drains the queue itself, once, and tells `queueDrained` with the report or `queueNotDrained` with the error. The engine takes those answers as it takes a drain of `MarfaSync`'s own, and `MarfaSync` starts no drain on `serverReachable`. Never start a second drain there.
- A drain the copy runs itself can record answers while the engine is still taking an earlier report. The engine forgets only the answers it has taken (`forgetAnswered(ids:)` with `MarfaEngine.takenAnswers`), never all of them at once. A blocked or dead answer is applied but not marked taken: the copy keeps it for a release, which gives the write the same id and a new answer. A drain that stops on any error loses its report, so the engine reads the answers from the queue before anything forgets them (`MarfaEngine.takeAnswers`).
- When a drain answer expires the copy (`copyExpired`, for example after a retype), `MarfaSync` hydrates again, which keeps the queue, and only then reads the answers from the queue. Never clear the queue to recover from an expired copy. While that hydration runs, the copy refuses reads (`hydrationIncomplete`); the engine keeps what it last read and tells the person nothing, since the copy reports `.refreshed` when the hydration ends and the engine reads it again then.
- A copy another version of the app made is refused by the package with `MarfaError.wrongSchema`, which removes nothing and counts the copy's unsent changes.
  - With none, `MarfaSource.open` has the package replace it (`WorkingCopy.replaceRefused`) with an empty copy, which hydrates from the server like a new one. The files the copy downloaded stay, and so does the download budget the person chose: MAPP passes no `fileBudget`, so the package keeps the old store's. Never pass one to `open` or `replaceRefused`; the person sets it in Settings (`MarfaDownloads.setBudget`).
  - The package replaces nothing while another process writes the copy (`readingHandle`), and the host is `.inUse`: the person quits the other copy of MAPP.
  - With changes, the copy stays and the host is `.otherVersion(unsent:)`: only the version that made it can send them, and Disconnect asks to keep the copy or discard the changes they were shown. With a count that cannot be read, the copy stays the same way, and Disconnect can only keep it.
  - Never remove a copy except through `WorkingCopy.remove`, and never replace one whose count the package did not give as none.
- A refused write that carried content stays listed until the person discards it, and discarding one that carried text is confirmed, since the write holds the only copy. Undo Change on a write that carried text is confirmed too, and puts the text on the clipboard (`ProblemWording.confirmation(for:)`).
- A refused text save is also given back through `Notices.notKept`, since the page then shows the library's text; the message says the change is listed in Settings.
- A copy is removed only by the package's `WorkingCopy.remove(store:unsent:)` (`MarfaHost.removeCopy`), which holds the copy's writer lock from counting its unsent changes to removing it. So a discard never takes a copy from another copy of the app still writing it, and never loses a change the person was not shown. MAPP passes the number they were shown (`MarfaHost.agreedLoss`): the count of the writes the sheet listed, the count a copy another version made reported (`State.otherVersion`), or 0 where nothing waited. The package removes the store of any schema, its log and the files it fetched, and MAPP then removes the empty folder. The package's errors are told as follows:
  - `readingHandle`: another process writes the copy. It stays, marked to go, and the person is told another copy of MAPP is using it (`.notRemoved`).
  - `unsentDiffers` with a count no higher than the person agreed to (a shown write was sent while the sheet was open, or the store is already gone from an earlier part-way removal): nothing is lost beyond what they agreed, so the removal is asked again once with that count, 0 included, which also takes a lock or fetched files left behind, and the folder is then removed.
  - `unsentDiffers` with a higher count: the copy holds other changes than the person was shown, and none is lost. It stays, is not marked to go, and the person is told the count it holds (`.copyKept(.changed)`); connecting to the address again, with its key since the key is already deleted, opens it and sends them. A copy not yet gone when its address is opened again is checked the same way.
  - `unsentDiffers` with no count: the package never removes a copy it cannot count, so a damaged store, or a copy another version made whose count could not be read, stays (`.copyKept(.unreadable)`).
  - `invalid`: the store is a folder's, which is not MAPP's to remove (`.copyKept(.notMapps)`).
- A copy whose changes were not counted for the person (a damaged store, a copy another version made without a count, a queue that could not be read) cannot be discarded. The departure sheet offers only Keep Copy and Disconnect, with where the copy is so the person can move its folder to the Trash after quitting MAPP, and `MarfaHost` refuses `.discardCopy(nil)` for such a copy before it leaves anything (`.cannotDiscard`). A copy that is still on disk is not opened as it is: a damaged one is refused again at every connect until the person removes its folder.
- The address and agreed count of a discarded copy that could not be removed are kept in defaults (`MarfaDiscardedCopies`), so the removal is tried again, against the same count, before the address is opened.

## Rows the copy cannot read

- A row whose stored properties the copy could not read comes back with no properties and `Item.unreadableProperties` set. It is shown as damaged: the item carries a problem that keeps it from being edited, the list row and the page say why, and it is never shown as an item the person emptied. `MarfaEngine.propertyEdit` refuses to build a replacement from such a row, since the properties it shows are not what it holds. The package refuses any write to the row until a hydration replaces it from the server, so a read that finds such a row has `MarfaSync` hydrate (`MarfaSync.unreadable`), once for each row while the copy is open. A row still unreadable after that stays damaged, and the message says to disconnect the library and connect it again. A save that arrives for an item that can no longer be written or that the copy no longer holds (purged on another device), or that the package refused before queueing it (`SyncProblem.notQueued`), is in no queue, so the text goes to the person through `Notices.notKept` like a write after the source closed. The same holds for any write the package refuses before queueing: what the person typed into it (text, a title or another text property, or a new item's title with its text) is given back the same way (`MarfaLibrary.unqueuedText`).
- An edge with `unreadableProperties` is read as its ends alone; a move of it is refused by the package in its own words.

## Text and versions

- Every save names the version of the text it was typed on. Only the first save typed on a version is merged against it (`BodyMerge.asRead`); later saves follow the person's own (`.following`). So a person's saves never conflict with each other and never overwrite text they did not see. Do not replace this with last-writer-wins.
- Text read on this device's own create before the server answered it is at version 0, which no server holds. Once the copy holds the answer, an edit typed on that text is sent on version 1 (`MarfaEngine.version(read:holding:)`), never on the version the copy holds, so a change another device made since is merged or kept apart as a conflicted copy, never overwritten.
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
- A Marfa folder (`system.folder`) holds a device's sync settings and places no item. MAPP syncs no folders: do not use the package's folder calls, and show a folder only as a fact on an item.

## Wording

- The model gives states and counts; `SyncWording.swift` turns them into words, so each sentence is tested without a window.
- Show a `MarfaHost.Problem` as what happened and what to do (`MarfaSettingsModel.notice(for:)`), never as the error.
- A problem offers only the actions the contract allows for it (`MarfaProblems`). A write set aside `failing_alone` is offered both Try Again and Undo Change, since its failures were no answer to it.

## Code Review Rules

- **Write dropped.** Flag any path that closes, discards, or replaces a copy without reading its queue in the same step, or discards writes the person was not shown.
- **Queued purge.** Flag a purge that is queued, offered offline, or sent before earlier writes.
- **Edge left empty or doubled.** Flag a single-valued link replaced by remove and add, or a many-valued swap that removes before the new link is taken.
- **Merge bypassed.** Flag a body write without a base version, or one that overwrites text the person did not see.
- **Contract drift.** Flag a pre-check, error code, or allowed action that differs from `conformance/spec/` or the package.
