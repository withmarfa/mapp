# Settings

Settings is a window of its own (`SettingsWindowView`, a `Window` scene, not the system's `Settings` scene: that one is sized to its content for a few tabs, with no toolbar of ours and no resizable, remembered frame). What is agreed and built is in `docs/settings-storage.md` ("The Settings window") and `docs/agreed-designs.md` (`## Settings`); what was turned down is in `docs/rejected-designs.md`.

## Structure

- `Window/` is the shell: the window, the sidebar, the history behind Back and Forward (`SettingsNavigation`), and the one launcher every route opens the window through (`SettingsLauncher`; `Browser.showSettings` asks it). A page is listed in the sidebar only once it exists: add a case to `SettingsPage` (or `MarfaSettingsPage`), its group, its words for the sidebar's search, and its view in `SettingsDetail`.
- `Parts/` is every part a page draws with: `SettingsSection`, `SettingsRow`, the trailing controls, `SettingsHead`, `SettingsProblemRow`, `SettingsPageState`, `SettingsBar`, `SettingsSizeSlider`, `SettingsSwatches`, `ChoiceTiles`, `PatternList`, the tables and `SettingsSheet`. They name nothing of MAPP's model. A page never draws its own row, button, section or sheet.
- `MAPP/` is MAPP's own pages and `MAPPMarfaSettingsHost`, which lends the Marfa's half what it needs. `Marfa/` is the Marfa's pages; read its `AGENTS.md`.

## Rules

- **Every color, font and measure is a named value** in `SettingsTokens`, never a literal in a page, so themes can come later. Text size goes through `settingsTextScale`.
- Use the system's control where it has one: toggles, pop-ups, alerts and text fields. A pop-up is `SettingsPopUp` (200 by 28: the large control size with flexible sizing; never a bare `Picker`), and a field is `SettingsField` or `SettingsNumberField`. Buttons are drawn by `SettingsButton`: gray, 28 points (22 in a table), blue only for Update, a pale red fill for a destructive one. Focus is a gray ring.
- A row is a lead, a title, one line under it (two at most) and one trailing edge. A refused input keeps what was typed, with the red ring and one line under the title (`SettingsRow(error:)`). A problem's words are told whole (`lines: nil`).
- Something new with several fields is a `SettingsSheet`, in the middle of the window and shown from `SettingsWindowView`, never `.sheet`. A question before what cannot be undone is the system's alert.
- A row of buttons at the end of a page, such as Revert and Save, is a `SettingsBar`; buttons that act on one setting sit in its row. A page that can't be shown is a `SettingsPageState`, never a row.
- The window keeps its sidebar (`toolbar(removing: .sidebarToggle)`). Back and Forward are the View menu's own commands (`AppCommands`); a sub-page is pushed with `settingsPush`.
- What is typed in a page and not saved is handed over when the window closes (`MAPPMarfaSettingsHost.handOverDrafts`) and when the app quits (`Libraries.handOffDraftsAtQuit`, from `applicationShouldTerminate`, since a window's close is not posted at quit), through `Notices.notKept`.
- A setting stored on the Mac is added to `MacSettings.keys` in the same change, or Reset MAPP's Settings misses it ([docs/settings-storage.md](../../docs/settings-storage.md#reset)).
- `Browser` keeps nothing of Settings. Never add a Settings place to the main window.

## Code Review Rules

- **Literal in a page.** Flag a color, font size or measure written in a page instead of a `SettingsTokens` value, and a row, button or section a page draws itself instead of the part.
- **Sheet under the toolbar.** Flag a `.sheet` in Settings where `settingsSheet` stands.
- **Setting missed by Reset.** Flag a new key in the defaults that is not in `MacSettings.keys`.
- **Input lost on refusal.** Flag a page that clears what was typed when the server refuses it, or drops an unsaved draft when the window closes.
