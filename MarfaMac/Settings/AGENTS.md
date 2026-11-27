# Settings

`docs/settings-window.md` has the design of the window, its parts and the app's pages. Read it first.

## Structure

- **`Window/` is the shell:** the window, the sidebar, the history (`SettingsNavigation`) and the launcher that every route uses (`SettingsLauncher`, through `Browser.showSettings`).
- **`Parts/` is every part a page draws with,** from `SettingsSection` and `SettingsRow` to the tables and `SettingsSheet`. Look there before you make one.
- **`App/` is the app's pages** and `AppSettingsHost`, which lends the Marfa's half what it needs. `Marfa/` is the Marfa's pages.
- **`Browser` keeps nothing of Settings,** and the main window holds no Settings place.

## Controls

- **Use the system's control through its part:** `SettingsToggle`, `SettingsPopUp` (never a bare `Picker`, so a page's pop-ups line up), `SettingsField`, `SettingsNumberField`, `SettingsSearchField` and `SettingsButton`. Use `SettingsHeaderPopUp` for choices that fit their title.
- **Text size goes through `settingsTextScale`.**
- **A click outside a field ends editing once for the window** (`settingsClickOutsideEndsEditing`), never per field.
- **A page hands over its sheet with `settingsSheet(presenting:dismiss:sheet:)`.** A question before what cannot be undone is the system's alert.
- **Pages push sub-pages through `settingsNavigation`.** Every routable page maps to its sidebar entry for selection and search.
- **Put an add button beside the section's title** through `SettingsSection`'s accessory. Use `SettingsTabs` for page views.

## Drafts

- **What is typed and not saved is handed over on two paths:** when the window closes (`AppSettingsHost.handOverDrafts`) and when the app quits (`Libraries.handOffDraftsAtQuit`), because a quit posts no window close. Both end in `Notices.notKept`.
- **A Marfa page's model that holds a draft conforms to `OwnerDraftHolding`** and registers with `host.ownerDrafts` when the page appears.
- **A password and a one-time secret are never handed over.** The person is told that the secret was made, in a notice that holds the quit. A key still being made is told about when its call ends (`OwnerContext.lateDraft`).

## Code Review Rules

- **Literal in a page.** Flag a color, font size or measure that is not a `SettingsTokens` value, and a row, button or section that a page draws itself.
- **Button breaking the rule.** Flag a sheet's confirm that is not `role: .confirm`, a destructive action at the trailing edge or titled with the thing's name, a wrong …, and a row with two trailing controls outside the two exceptions.
- **Sheet under the toolbar.** Flag a `.sheet` where `settingsSheet` stands.
- **Setting missed by Reset.** Flag a new defaults key that is not in `MacSettings.keys`.
- **Input lost on refusal.** Flag a page that clears what was typed when the server refuses it, or drops an unsaved draft when the window closes.
