# The Marfa's half of Settings

Status: Account, Apps, Keys and Addresses are built, beside Overview and Recently Deleted.

Where it lives: `MarfaSettingsPage`, `MarfaSettingsHost`, `OwnerCalls`, `ClientOwnerCalls`, `AccountModel`, `AppsModel`, `KeysModel`, `AddressesModel`, `AccountPage`, `AppsPage`, `KeysPage` and `AddressesPage` under `MAPP/Settings/Marfa/`.

The Marfa's pages show and change what the server holds, as the owner. They stand alone: they reach only the parts and the host protocol ([Agreed designs](agreed-designs.md#settings), `MAPP/Settings/Marfa/AGENTS.md`). Every call needs the server and is never queued. A page opens only when the sign-in holds its permission; the server's answer wins over what MAPP thinks it holds, so a call refused with `403 forbidden` names the permission the server says is missing, and the grants are read again.

## What each page does

| Page | Permission to open | What it holds |
| --- | --- | --- |
| Account | none | The owner's username and email as the server holds them (read only), Change Password…, the passkeys (Rename, Remove, Add a Passkey…, which opens the server's own page) and the browsers signed in (Sign Out). |
| Apps | `grants.manage` | The connected apps. An app's page holds its access by type, which can only be narrowed, its owner permissions, the keys it made and Disconnect. |
| Keys | `keys.manage` | The owner's keys and the keys apps made. A key's page holds its expiry (it can only be made to end sooner), its tier, its source, its access (narrowing only) and Revoke. New Key… needs `keys.mint`. |
| Addresses | `config.manage` | The sign-in address, the other addresses and the websites allowed to call the server. |

## Rules

- **`sign_ins.manage` is asked for from Account, never at sign-in.** The first time the owner chooses Change Password, or Allow More… beside the sign-ins, MAPP asks for it. Cancelled, or approved without it, nothing opens and the page says so.
- **A password is never kept.** It lives in the sheet's fields until the call ends, is never logged, and is cleared on success, on Cancel and when the sheet closes. A wrong current password keeps both fields with the red ring and one line.
- **Narrowing asks first, and only narrows.** An app's access is sent with the access it was read as; a change made elsewhere is told as a conflict, the page reads again and nothing is changed. A key's access is sent with `narrow_only`. Disconnecting an app deletes its webhooks and leaves the keys it made working (`keys-and-oauth/grant-revoke-keeps-keys`, `events/webhook-grant-revoked`).
- **A key is shown once.** The sheet that follows New Key holds the plaintext; closing it drops it. Copy marks the clipboard concealed and clears it after a minute if nothing else was copied.
- **An address is checked before it is written.** The server's `POST /config/address-check` says what adding, removing or moving would do. Moving the sign-in address shows the consequences in the sheet and writes exactly what was checked; the server asks for a recent sign-in, which the package shows in place. Every write names the instance that was read.
- **A sheet is shown by the window.** A page hands its sheet to `SettingsSheetPresenter` (`settingsSheet(presenting:)`), which draws it in the middle of the window; what it shows is read from the page's model.

## Left out

- Name and picture, which MAPP does not ask to change, and Add Passkey's list refresh after the browser returns.
- Extending a key, which waits on a server release.
- Apps' Tidying settings, the Private Addresses switch and Raycast's own settings item, which need server or settings-model work.
