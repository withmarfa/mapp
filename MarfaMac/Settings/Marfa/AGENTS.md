# The Marfa's pages

These pages stand alone, so another app can take them. They import nothing of the app's half. They reach only `Settings/Parts/` and `MarfaSettingsHost`, the one protocol the app supplies (`AppSettingsHost`). `docs/owner-settings.md` has the rules of what they do.

## The host

- **A page that needs more asks through the host, by naming what it needs.** Add that to `MarfaSettingsHost` first, then the case in `MarfaSettingsPage` and the view in `MarfaSettingsPageView`.
- **The host gives the package's `Client` over the current server.** Build no second client.
- **Marfa pages remain listed in every connection state.** A route outside the sidebar names its entry with `MarfaSettingsPage.sidebarEntry`.
- **A page reads health and updates only from the host's one model of each** (`host.health`, `host.updates`).
- **`openInApp` is optional,** because another app may have nothing to open.
- **`InstanceConfig` and `InstanceSettingsModel` live here** because the pages own them. The app's library only reads `InstanceConfig`.

## Calls

- **A page calls through `OwnerCalls`,** or `InstanceCalls` for Activity, Monitoring, Limits and Start-Up, so a model reads no generated type and a test scripts every answer.
- **Types and folders go through calls the app's half supplies** (`TypeCalls`, `FolderCalls`), because `TypeDefinitionEdit` and the working copy are there.
- **A refusal names the missing permission and has the grants read again** (`OwnerContext.learn`).

## Permissions and states

- **Each page names its permission and the one line that says what the app may not do** (`MarfaSettingsPage.permission`, `permissionLine`). No two pages share a line.
- **`MarfaPageGate` shows the page or a centered state.** A page never falls back to a library of its own.
- **A setting that needs no Marfa stands above the state** (`MarfaPageGate(above:)`, `SettingsStandingState`).
- **Every permission request goes through `allowMore(_:)`,** whose argument names the permissions that the caller needs.
- **Account has no page permission.** Change Password asks for access where the sign-in lacks `sign_ins.manage`.

## Code Review Rules

- **The app reached from the Marfa's half.** Flag a file here that names the app's model (`Browser`, `Libraries`, `ItemLibrary`, `MarfaHost`), its views or its pages. Safe path: `MarfaSettingsHost` and the parts.
- **Page behind a missing state.** Flag a page that shows content while its permission is missing, the server does not answer, or no copy is open.
