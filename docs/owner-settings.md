---
summary: The rules the Marfa's pages of Settings share, what each page is for, and what each cannot do.
paths:
  - MarfaMac/Settings/Marfa/*.swift
  - MarfaMac/Settings/App/CopyFolderCalls.swift
  - MarfaMac/Settings/App/ServerTypeCalls.swift
---

# The Marfa's pages of Settings

These pages show and change what the server holds for its owner. Every call goes to the server at once and none is queued. The contract's statement ids below are in the marfa repository.

## Pages

The page gate checks the connection and the sign-in’s permissions. A configured Marfa keeps its Account header and Sign Out above any connection state. Each section that needs additional access identifies the permission. Account links to the server settings pages, and Apps and Keys links to Apps.

| Page | Opens with | Its job |
| --- | --- | --- |
| Account | none | Profile, sign-out, sign-in controls and server settings. Problems and the release need `instance.read`. Updating needs `instance.maintain` |
| Passkeys | `sign_ins.manage` | Add a passkey in the browser, rename one or remove it |
| Browsers | `sign_ins.manage` | See and end browser sessions |
| Apps | `grants.manage` | Connected apps: access, owner permissions, keys they made, data they keep |
| Apps and Keys | `keys.manage` | The owner's keys and apps' keys. Making one needs `keys.mint` |
| Network | `config.manage` | Sign-in and other addresses, websites allowed, private addresses |
| Plugins | `schema.write` | Plugins installed, newer and available. One with a connector needs `connectors.manage` |
| Types | `schema.write` | Types, fields, status words, and rules |
| Links | `schema.write` | Link types. Opens from Types |
| Sources | `keys.manage` | Names and marks of sources. Both source rules need `config.manage` |
| Trash | `items.purge` | Restore items or empty Trash. Choose Select Items or Show All to permanently delete selected items. Changing how long items wait needs `config.manage` |
| Storage | `config.manage` | Where files are kept, copies, reading text, removing unused files, and item version retention |
| Connectors | `connectors.manage` | Each connector's health, machine, sign-in, settings and mapping |
| Webhooks | `webhooks.manage` | Webhooks by maker, their events and deliveries |
| Folders | type access to `system.folder` | Synced folders: patterns, limits, copies, Stop Syncing |
| Backups | `backups.manage` | Destination, backups, restore. Destination and interval need `config.manage` |
| Housekeeping | `instance.read` or `config.manage` | Jobs need `instance.read`. Confirming the clock needs `instance.maintain`. Log retention needs `config.manage` |
| Activity | `audit.read` | The audit log |
| Monitoring | `config.manage` | Heartbeat, error reports and telemetry |
| Limits | `config.manage` or `instance.read` | Changing limits needs `config.manage`. Either permission can read start-up setting names and whether each is set |

## Permissions

- **A page never shows content behind a missing permission.** It shows Needs a Permission in its own words, with Allow More, because a row that cannot load looks like a fault. `MarfaPageGate` decides.
- **A sign-in asks for every permission an app can hold**, and the owner grants what they choose. A page rereads the grants after approval and still says what is missing.
- **A `forbidden` answer rereads the grants** and offers Allow More… in the problem row (`OwnerProblemRow`).
- **Owner permissions are counted, never all or nothing**, and can only be turned off on a key's or an app's page (`OwnerPermissionsRow`).
- **Access is only ever narrowed.** It is sent with what was read, or with `narrow_only` for a key. A grant that holds only a write is sent a read in its place, never nothing.
- **Account asks at sign-in to read and change the profile**, and shows a value as read only where it may not change it.

## Asking first

- **Ask before anything that cannot be got back**, naming what goes and what stays: narrowing, revoking, disconnecting, emptying, shorter retention, less free disk, a raised folder limit, removing a type, plugin or data.
- **A question holds its version.** What is confirmed is sent on the version it named, whatever is read while the alert is open.
- **A typed safety number asks when the field is left**, because a person passes through other numbers while typing.
- **A shorter or unknown retention always asks.** With no value the app can read, any choice may be shorter. Keep Versions asks on every change.
- **Removing an app's data counts first and never half-tells.** It repeats until nothing is left, says how many went where it stops, and never says nothing changed once an item has gone.
- **The app's own data is never removed here.** Connection's Remove… stops `PreferencesSync` first; a purge from here would delete the item under it.
- **A disconnected app's keys still work** (`keys-and-oauth/grant-revoke-keeps-keys`); its webhooks go.

## Secrets and passwords

- **A secret is shown once**, in the sheet that follows making it, and the sheet's end drops it. It is never logged, stored, put in a draft or given to the accessibility tree.
- **A copied secret is concealed and leaves the clipboard after a minute** unless something else was copied (`OwnerClipboard`).
- **A stored secret is only Set or Not Set**, because the server never returns it.
- **Settings closing while a secret shows tells the owner** what was made, that it cannot be shown again and what to do.
- **A password lives in its sheet until the call ends.**
- **A connector's install link is never made into a command** where the shell would read it as more than one word, and an ended link is never shown or copied.

## What a person typed

- **A refusal keeps what was typed**, marks the field and says why under it. Clearing it loses work the person cannot see again.
- **A draft is handed back** at the end of the window or the app (`OwnerDrafts`, `Notices.notKept`). Where a call is in flight, its failure hands it back.
- **A pop-up or switch sends at once; a field sends on Return or when left.** Emptied, it removes the stored value.
- **A number out of range is never sent.** A separator the Mac's region does not use is refused, not guessed at.
- **A length is in Unicode code points**, the server's count, and hidden characters are found before trimming (`ProfileName`).

## Conflicts

- **A write names the instance that was read.** Where another Marfa answers, the page says so and adopts nothing from it.
- **Read before write.** A stored setting is read again, and a change made elsewhere is told, shown and never written over (`StoredSettings`).
- **The three enforcement levers have one writer** (`EnforcementSettings`), because `PATCH /config` replaces all three and an old reading would undo another page's change.
- **Changes to one type run one at a time** (`TypesModel`), each built from the type as read just before sending, because `PUT /types/{id}` replaces the whole type and has no version. Guidance goes back as it was.
- **A choice list changes by the word**, never as a whole list, so a change made elsewhere is kept.
- **A folder setting is sent on the version the person saw.** A newer reading keeps the typed value, which only Return sends again.
- **A webhook's events are read again just before sending**, which narrows the race and does not close it (withmarfa/marfa#3408).
- **Only what was read before is "changed somewhere else".** A `409` the server words itself shows those words, on the field they name.

## Health and updates

- **One reader of health** (`ServerHealthModel`) and one follower of an update (`UpdatesModel`) serve every page.
- **A part's word comes from its own status**, and unreadable is Couldn't Check, never Working.
- **A server that does not answer during an update is restarting**, not at fault. When the app stops waiting it offers Check Again, not Update, because the server may still be updating.
- **After a rollback,** a release the server can still install offers Try Again to a sign-in with `instance.maintain`. Other sign-ins see Allow More.
- **A connector's health is derived**, because the server gives no word for it (`ConnectorHealth.of`). Unreadable is never "waiting to start".
- **Pause, Resume and Run Now are stored choices** that the connector follows at its next run. The app never runs a connector.

## Words

- **The server's own error texts are never shown**, because they name settings by key and requests by path. Pages word a title and one line; details go to the app's log. A field may show the server's reason where it holds no key, code or route.
- **A setting with no name in the app is counted or described**, never shown by its key.
- **Problems and the Account badge share the server’s attention list.** Account refreshes it when opened. A problem opens the page that fixes it or offers a command to copy for settings the app cannot change. Without `instance.read`, Problems offers Allow More.
- **A problem row's title is a sentence.**

## Plugins, types and connectors

- **The app reads the plugins release itself** (`PluginRelease`), sends no credential, and uses a bundle only when its digest is the one a fresh index lists. A bundle is installed as its bytes.
- **An update to a plugin only adds.** Removing one keeps its types and their items and deletes its connector's mapping.
- **Guidance has no rule of the app's own.** The server's answer decides: a sign-in again, a refusal that gives the command-line command, or a missing permission.
- **A new type or link type is under `user.`**, with an id made from its name and checked against a fresh list. A field keeps its name when its label changes, because items hold values under it.
- **A type in use is moved before it is deleted.** The move is previewed again just before it starts, and the type is deleted unforced only when no item is left.
- **A mapping saves as it is made**, sending every other kind as stored, so one refused kind holds no other back. An older reading is never applied over a newer one.
- **Existing items change only when the owner applies a mapping**, after a dry run of the saved mapping counted them.
- **Trap:** a source rule's two halves differ. Who May Write applies when items are made and needs a credential that may write the type; Limit Sources applies to what is read and to events.

## Folders and backups

- **A folder's record is pinned by the working copy** (`CopyFolderCalls`), because the copy's slice leaves out `system.folder`. A pin goes only with Stop Syncing.
- **Stop Syncing cannot be undone**, and leaves items in Marfa and files on disk.
- **A restore adds what a backup holds and changes nothing that is there**, and says what it leaves out.

## What the server does not offer yet

- A webhook's version (withmarfa/marfa#3408), an enforcement precondition (withmarfa/marfa#3535) and a type move's (withmarfa/marfa#3536).
- Files in a mapping (withmarfa/marfa#3505), link counts by type (withmarfa/marfa#3533), a folder's contents (withmarfa/marfa#3534).
- How often a folder is read in full (withmarfa/marfa-swift#556), and a recent sign-in before a write (withmarfa/marfa-swift#557), so Private Addresses can write over a change made during that sign-in.
- A webhook's new secret, a secret of several lines, and an audit log's total.
