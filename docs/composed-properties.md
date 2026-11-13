# Composed properties

Status: Location is built, not yet released. The other properties are agreed, not built; see "Built today".

Where it lives: `PropertyRow` (with its `Value`) under `MAPP/Model/Items/`, and `MarfaMapping` under `MAPP/Model/Marfa/`. Location is `ItemLocation` and `LocationFrame` under `MAPP/Model/Items/`, and `LocationPanelContent` and `LocationPanelModel` under `MAPP/Views/ValueEditing/`. Composed properties are built in a type's look from these.

A composed property is a property that MAPP builds from a type's fields and links. Marfa holds no such property, so building one changes nothing in Marfa and stores nothing new there.

## The properties

- **Location.** A place on a map, built from the `latitude` and `longitude` fields. Marfa's `core.event`, `core.entity.place`, `core.file.image` and `core.file.video` types have them, and a type may also carry `place` or address fields. A person looks for an area with a search, clicks the map to place the pin and drags it to adjust, and MAPP writes only that point's latitude and longitude. The numbers stay hidden unless the person turns on Show Coordinates. An event's name is its `place` field, a place item's name is the item's own name and is never changed, and an image or video has no name, so it shows the map only. See "How Location works".
- **Relation.** A link shown as a property: Parent, Children or In Collection. Marfa links items with edges, which are global, so a relation is how MAPP shows an edge as a row.
- **Count.** How many items a link reaches, or how many steps are done, such as "4 subtasks" or "3 of 7 done".
- **Reading time.** Worked out from the item's text.

## Later, not now

- **Rollup and Formula.** Marfa cannot sort or filter by a value that MAPP computes, so these wait.
- **A Marfa location kind.** Marfa has none today. When one exists, Location reads it in place of the two numbers.

## How Location works

- **Why a search never fills the pin.** Apple's Developer Program License Agreement (Attachment 6, section 2.5) allows map data to be stored only for a moment, and only a Place ID is exempt. Marfa has no field for a Place ID, so MAPP writes nothing that a search returned. A search result only moves the map to an area; the person places the pin.
- **One row.** A type with both numbers shows one Location row in place of the two (`mappin.and.ellipse`). It reads the name, or Map where the item has a point and no name. Latitude and longitude are rows of their own only while Show Coordinates is on. The row is in the property block, can be pinned, and is in the right sidebar as the name beside a small pin. Both open the same panel, and Customize Sidebar counts it as one property.
- **The panel.** A search field, an Apple map with the item's point as a pin, a name field where the type has a name, the Show Coordinates switch and Clear Location. The map is always an Apple map, with its logo and legal link left uncovered. A click on the map places the pin only where the item has none; after that the pin moves only when it is dragged, and a double-click only zooms the map.
- **One edit.** Placing or moving the pin writes both numbers, and the name if it changed, as one queued edit and one undo step. It works offline, though the map may then lack tiles. Clear Location removes both numbers in one undo step, keeps the name, and asks nothing.
- **When the name is written.** A typed name is written with the next placement, when the person presses Return, or when the panel closes, and not when the field loses focus. A click on the map with the name still in the field is then one edit and one undo step, not two. Escape drops a name that was not yet written. A name that cannot be written when the panel closes, because it changed elsewhere or was refused, goes to the clipboard and the person is told.
- **Before a write reaches the server.** The panel shows each change at once, building on the person's last change and not on what the server last confirmed. A placement cleared or moved back before an earlier one reaches the server is still written, so the last change the person made is the one kept.
- **When it cannot be drawn.** One number alone, or a pair outside latitude 90 or longitude 180, shows as stored and is not drawn, and the panel says it cannot show it. The numbers can still be cleared.
- **Where the map opens.** On the item's point; else round the places the person's most recent items hold; else the world.
- **An item that cannot be edited,** and every file, shows the map and its point, with no search, name field or Clear Location.
- **Show Coordinates** is one setting on this Mac (`showsCoordinates`, off by default; see [Settings storage](settings-storage.md)).

## Built today

Location is built (see above). A geographic or object field maps to a shape that the app shows but does not edit (`MarfaMapping`): the page's property block skips it, and the right sidebar prints it as plain text.

Reading time, relations and counts are not built. A saved web page's header shows only its description (`ReadingHeader`), and the right sidebar shows parent, children and links as the page's own sections, not as properties that a look can place.

## Open point

Only one is open: whether Marfa should add a field that holds a Place ID, so that a searched place could be kept.

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Item page](item-page.md)
