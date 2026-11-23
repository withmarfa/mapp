# Settings

Settings is a window of its own (`SettingsWindowView`, a `Window` scene, not the system's `Settings` scene: that one is sized to its content for a few tabs, with no toolbar of ours and no resizable, remembered frame). What is agreed and built is in `docs/settings-storage.md` ("The Settings window") and `docs/agreed-designs.md` (`## Settings`); what was turned down is in `docs/rejected-designs.md`.

## Structure

- `Window/` is the shell: the window, the sidebar, the history behind Back and Forward (`SettingsNavigation`), and the one launcher every route opens the window through (`SettingsLauncher`; `Browser.showSettings` asks it). A page is listed in the sidebar only once it exists: add a case to `SettingsPage` (or `MarfaSettingsPage`), its group, its words for the sidebar's search, and its view in `SettingsDetail`.
- `Parts/` is every part a page draws with: `SettingsSection`, `SettingsRow`, the trailing controls, `SettingsHead`, `SettingsProblemRow`, `SettingsPageState`, `SettingsBar`, `SettingsSizeSlider`, `SettingsSwatches`, `ChoiceTiles`, `SettingsSearchField`, `SettingsMultiPopUp`, `SettingsOrderedList`, `SettingsPreview`, `SettingsShortcutField` and `SettingsShortcutSearch` (which take keys before the menus can), the tables, `SettingsAddRow`, `SettingsLinkRow`, `SettingsCheckRow`, `SettingsShowMoreRow`, `SettingsReadOnlyValue` and `SettingsSheet`. They name nothing of the app's model. A page never draws its own row, button, section or sheet.
- `App/` is the app's own pages and `AppSettingsHost`, which lends the Marfa's half what it needs. `Marfa/` is the Marfa's pages; read its `AGENTS.md`.

## Rules

- **Every color, font and measure is a named value** in `SettingsTokens`, never a literal in a page, so themes can come later. Text size goes through `settingsTextScale`.
- Use the system's control where it has one, at its own size and weight, and draw none where it does: switches (`SettingsToggle`, at the mini size, which is the boards' 36 points), pop-ups (`SettingsPopUp`, a menu `Picker` at the large size and the one shared width, 200 points, so a page's pop-ups line up; never a bare `Picker`), search fields (`SettingsSearchField`, `NSSearchField`; the sidebar's is `searchable`), text fields (`SettingsField` or `SettingsNumberField`, the rounded-border field at the large size, 200 points wide) and alerts. Buttons are `SettingsButton`: the system's `.bordered` at the large size, 28 points as the boards draw it (regular in a table), the default action and Update `.borderedProminent`, a destructive one the destructive role, tinted red. A click outside a text field ends editing, set once on the window (`settingsClickOutsideEndsEditing`), never per field.
- A row is a lead, a title, one line under it (two at most) and one trailing edge. A refused input keeps what was typed, with the red ring and one line under the title (`SettingsRow(error:)`). A problem's words are told whole (`lines: nil`).
- Something new with several fields is a `SettingsSheet`, in the middle of the whole window (not under the toolbar), growing to the window's height and then scrolling, and shown by `SettingsWindowView`, never `.sheet`. A page hands it over with `settingsSheet(presenting:dismiss:sheet:)`, and what it shows is read from an `@Observable` model, never the page's `@State`. A question before what cannot be undone is the system's alert.
- A row of buttons at the end of a page, such as Revert and Save, is a `SettingsBar`; buttons that act on one setting sit in its row. A page that can't be shown is a `SettingsPageState`, never a row.
- The window keeps its sidebar (`toolbar(removing: .sidebarToggle)`). Back and Forward are the View menu's own commands (`AppCommands`); a sub-page is pushed with `settingsPush`.
- What is typed in a page and not saved is handed over when the window closes (`AppSettingsHost.handOverDrafts`) and when the app quits (`Libraries.handOffDraftsAtQuit`, from `applicationShouldTerminate`, since a window's close is not posted at quit), through `Notices.notKept`. A Marfa page's model that holds a draft conforms to `OwnerDraftHolding` and registers with `host.ownerDrafts` when the page appears. A password is never handed over, and neither is a secret shown once: the person is told it was made and can't be shown again, in a notice that holds the quit. A key still being made when Settings closes is told about when its call ends (`OwnerContext.lateDraft`).
- A setting stored on the Mac is added to `MacSettings.keys` in the same change, or Reset This App's Settings misses it ([docs/settings-storage.md](../../docs/settings-storage.md#reset)).
- `Browser` keeps nothing of Settings. Never add a Settings place to the main window.

## Code Review Rules

- **Literal in a page.** Flag a color, font size or measure written in a page instead of a `SettingsTokens` value, and a row, button or section a page draws itself instead of the part.
- **Sheet under the toolbar.** Flag a `.sheet` in Settings where `settingsSheet` stands.
- **Setting missed by Reset.** Flag a new key in the defaults that is not in `MacSettings.keys`.
- **Input lost on refusal.** Flag a page that clears what was typed when the server refuses it, or drops an unsaved draft when the window closes.
