# The Marfa's pages

These pages stand alone, so another app can take them without MAPP. They import nothing of MAPP's half: not its model, its views or its pages. They reach only `Settings/Parts/` and `MarfaSettingsHost`, the one protocol MAPP supplies (`MAPPMarfaSettingsHost`). `InstanceConfig` and `InstanceSettingsModel` live here because the pages own them; MAPP's library only reads `InstanceConfig`.

## The host

- `MarfaSettingsHost` gives the package's `Client` over the current server (as `MarfaServerCalls` builds it; build no second client), the server's name and address, the connection (`opening`, `connected`, `notConnected`, `signedOut`, `notAnswering`), the permissions the sign-in holds (`Credential.grants`), `allowMore(_:)`, Try Again, the way back to Connection, an optional `openInApp` that MAPP may leave out, This Marfa's draft model and the bin. A page that needs more asks for it there, in terms of its own.
- A new page adds a case to `MarfaSettingsPage` and its view to `MarfaSettingsPageView`; what it needs from the app is added to the host first.

## Permissions and states

- Each page names the owner permission it needs (`MarfaSettingsPage.permission`) and says in one line what MAPP isn't allowed to do without it. `MarfaPageGate` shows the page, or a centered state: Needs a Permission with Allow More…, the server not answering with Try Again, no copy open or signed out with the way to Connection. A page never falls back to a library of its own, and never shows its content behind a state.
- Allow More… asks again for what is held and the page's own permission; cancelled or approved with fewer, nothing changes and the page still says what is missing. `sign_ins.manage` is asked for only from Account, never at sign-in.

## Code Review Rules

- **MAPP reached from the Marfa's half.** Flag a file here that names MAPP's model (`Browser`, `Libraries`, `ItemLibrary`, `MarfaHost`), its views or its pages instead of going through `MarfaSettingsHost` and the parts.
- **Page behind a missing state.** Flag a Marfa page that shows content while its permission is missing, the server does not answer, or no copy is open.
