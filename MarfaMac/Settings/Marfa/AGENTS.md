# The Marfa's pages

These pages stand alone, so another app can take them without the app. They import nothing of the app's half: not its model, its views or its pages. They reach only `Settings/Parts/` and `MarfaSettingsHost`, the one protocol the app supplies (`AppSettingsHost`). `InstanceConfig` and `InstanceSettingsModel` live here because the pages own them; the app's library only reads `InstanceConfig`.

## The host

- `MarfaSettingsHost` gives the package's `Client` over the current server (as `MarfaServerCalls` builds it; build no second client), the server's name and address, the connection (`opening`, `connected`, `notConnected`, `signedOut`, `notAnswering`), the permissions the sign-in holds (`Credential.grants`), whether it lacks anything a sign-in asks for (`lacksAsked`), `allowMore(_:)`, Try Again, the way back to Connection, an optional `openInApp` that the app may leave out, This Marfa's draft model, `ownerDrafts` (where a page's model registers to hand back what was typed when Settings closes) and the bin. A page that needs more asks there, naming what it needs.
- `host.health` is the one `ServerHealthModel` that Overview, Backups and Housekeeping read; a page reads no health of its own and never shows a server's `error` text.
- A new page adds a case to `MarfaSettingsPage` and its view to `MarfaSettingsPageView`; what it needs from the app is added to the host first.

## Permissions and states

- Each page names the owner permission it needs (`MarfaSettingsPage.permission`) and says in one line, in its own words, what the app isn't allowed to do there without it (`permissionLine`; no two pages share a line, and a page's failed read says it too). `MarfaPageGate` shows the page, or a centered state: Needs a Permission with Allow More…, the server not answering with Try Again, no copy open or signed out with the way to Connection. A page never falls back to a library of its own, and never shows its content behind a state.
- A page may hold a setting of this Mac that needs no Marfa and no permission, which then stands above the state (`MarfaPageGate(above:)`, `SettingsStandingState`) as well as in the page. Apps' Open Marfa Links In (`OpenLinksSection`) is the one: it reads and sets only macOS's default for `marfa://`, and is never stored.
- Every sign-in asks for all app-grantable owner permissions (`SystemSignIns.askedAtSignIn`). Every Allow More… goes through `allowMore(_:)`. Its argument names the permissions the caller needs to proceed. After approval, each page checks the new sign-in's grants and still says what is missing. Account opens without an owner permission (`MarfaSettingsPage.permission` is nil). Change Password asks for access when the sign-in lacks `sign_ins.manage`.
- A call a page makes goes through `OwnerCalls` (`ClientOwnerCalls` over the host's `Client`), or `InstanceCalls` for Activity, Monitoring, Limits and Start-Up (`ClientInstanceCalls`; their stored settings are read and written through `StoredSettings`), so a model reads no generated type and a test scripts every answer. Types go through `TypeCalls`, which the host supplies (`ServerTypeCalls`, the app's half, since a type's replacement is built by `TypeDefinitionEdit`). A folder's settings go through `FolderCalls`, which the host supplies (`CopyFolderCalls`, the app's half, over the working copy, which owns the folder doors). A refusal names the permission the server says is missing and has the grants read again (`OwnerContext.learn`). A write refused keeps what was typed. See `docs/marfa-settings.md`.

## Code Review Rules

- **the app reached from the Marfa's half.** Flag a file here that names the app's model (`Browser`, `Libraries`, `ItemLibrary`, `MarfaHost`), its views or its pages instead of going through `MarfaSettingsHost` and the parts.
- **Page behind a missing state.** Flag a Marfa page that shows content while its permission is missing, the server does not answer, or no copy is open.
