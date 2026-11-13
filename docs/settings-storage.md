# Settings storage

Status: Built in v0.0.43. The single store for looks is agreed and not built; see [Looks](looks.md).

Where it lives: `ListKey`, `PageKey`, `OrderKey` and `InterfaceKey` under `MAPP/Views/`, and `PagePlacements`, `ViewLayouts`, `SidebarLayouts`, `IncludedSubtypes`, `DateFormat` and `RemotePictureSetting` under `MAPP/Model/`.

MAPP keeps its own settings in the app's defaults on this Mac and never writes them to Marfa. This page lists where each kind of setting lives, so you know which scope a new setting belongs to.

## Scopes

A setting has one scope. Pick the narrowest scope that matches what the person would expect.

| Scope | Where | Settings |
| --- | --- | --- |
| Every window | One key in the defaults. | `listRowStyle`, `listPreviewLines`, `listShowsPictures`, `listShowsTypeWhenMixed`, `dateFormat`, `noteSort`, `groupsByDate`, the page options in `PageKey` (`titleLines`, `linkLook`, `fullWidthPages` and others), `remotePictures`, the interface options in `InterfaceKey`. |
| A type | One value keyed by type identifier. | `pagePlacements` (pins, shown rows, property order, sidebar sections, where Linked From goes), `listTypeStyles`, `includedSubtypes`. |
| A saved view | One value keyed by the view's item identifier. | `viewLayouts`: a `ViewMacSettings` with the layout, columns, whether the board hides empty groups, the gallery's cards, the list's rows and the table's widths. |
| A place | A key built from the place. | `itemTableColumns` (the table's columns for each place), `indexLayout.<place>` and `indexWidth.<place>`. |
| A server | One value keyed by server address. | `sidebarLayouts`. |
| A window | Scene storage, or memory only. | The layout in `SceneStorage("browser")`, `detailsPresented` and `sidebarHidden`. `Browser.placeRows` holds a place's row choices in memory and loses them on quit. |

Column widths are `interfaceDefaultWidth.<column>`, and the right sidebar's width and open sections are `inspectorWidth` and the `inspector*Open` keys.

## Rules

- **Nothing goes to Marfa.** Marfa has no per-field icon, color or order, and a saved view holds no layout. A setting for how something looks stays on the Mac. See [Marfa and MAPP](marfa-and-mapp.md).
- **A type's setting has no inheritance today.** `pagePlacements` for a child type does not read its parent's. The agreed look store follows the `parent` chain; see [Looks](looks.md).
- **Unreadable stored text is set aside, not dropped.** When a stored value cannot be decoded, MAPP keeps the text under a `...SetAside` key (`pagePlacementsSetAside`, `viewLayoutsSetAside`, `sidebarLayoutsSetAside`) and starts from the defaults, so a person's arrangement can be recovered.
- **A saved view's Mac settings go only when the person deletes the view.** `Browser.forgetView`, reached from `Browser.deleteView`, is the one place that forgets them, because a view missing from a list proves nothing when a read failed.
- **A Debug build has its own values.** Its bundle identifier differs from the installed app's, so it never shares defaults, sign-ins or the return address with it. Key anything that must differ on `Bundle.main.bundleIdentifier`, never a literal.
- **A new field on a stored value is optional.** A value saved before the field existed must still decode.

## The agreed change

One store of looks, kept on this Mac for each server and exportable, replaces `listTypeStyles`, the row parts of `viewLayouts` (`rows` and `cards`) and the window's `placeRows`. Whether looks sync between Macs through Marfa is not decided. See [Looks](looks.md).

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Views and lists](views-and-lists.md)
