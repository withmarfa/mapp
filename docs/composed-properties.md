# Composed properties

Status: Agreed, not built. None of these properties exists today; see "Built today".

Where it lives: `PropertyRow` (with its `Value`) under `MAPP/Model/Items/`, and `MarfaMapping` under `MAPP/Model/Marfa/`. Composed properties are built in a type's look from these.

A composed property is a property that MAPP builds from a type's fields and links. Marfa holds no such property, so building one changes nothing in Marfa and stores nothing new there.

## The properties

- **Location.** A place on a map, built from the `latitude` and `longitude` fields. Marfa's `core.event`, `core.entity.place`, `core.file.image` and `core.file.video` types have them, and a type may also carry `place` or address fields. A person searches for a place with MapKit and picks it, and MAPP writes the coordinates and the name. The numbers stay hidden unless the person turns on Show Coordinates. An image or video has no name field, so it shows the map only.
- **Relation.** A link shown as a property: Parent, Children or In Collection. Marfa links items with edges, which are global, so a relation is how MAPP shows an edge as a row.
- **Count.** How many items a link reaches, or how many steps are done, such as "4 subtasks" or "3 of 7 done".
- **Reading time.** Worked out from the item's text.

## Later, not now

- **Rollup and Formula.** Marfa cannot sort or filter by a value that MAPP computes, so these wait.
- **A Marfa location kind.** Marfa has none today. When one exists, Location reads it in place of the two numbers.

## Open point

Check Apple's MapKit terms for storing a search result before building Location.

## Built today

MAPP does not use MapKit and has no location editing. A geographic or object field maps to a shape that the app shows but does not edit (`MarfaMapping`): the page's property block skips it, and the right sidebar prints it as plain text.

Reading time, relations and counts are not built. A saved web page's header shows only its description (`ReadingHeader`), and the right sidebar shows parent, children and links as the page's own sections, not as properties that a look can place.

## Related pages

- [Looks](looks.md)
- [Marfa and MAPP](marfa-and-mapp.md)
- [Item page](item-page.md)
