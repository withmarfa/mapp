---
summary: What files and items dropped on a list, a collection's row or a card do: where they go, the pill, the undo step and the toast.
paths:
  - MarfaMac/Model/FileImport.swift
  - MarfaMac/Model/FileDropTarget.swift
  - MarfaMac/Model/Browser+Drops.swift
  - MarfaMac/Views/WindowFiles.swift
---

# Dropping on a place

`docs/editing.md` says how an item is made; a dropped file is made as it says, its tier the place's.

- **Files dropped on a list join the place in view** (`Browser.fileDropTarget`). A collection makes them members, the Feed keeps them in the Feed, and any other place adds them to the Library, as the pill says.
- **A gray ring runs round a list while files are held over it** (`takesDroppedFiles`), with a pill, "Add 3 Files to Glaze tests", counting them; folders alone show none. The sidebar takes none, and an item dragged from the app is never imported again.
- **Where files go is fixed at the drop,** so a place that changes meanwhile does not move them.
- **A folder is refused and told,** never opened. A file named twice is added once, and one the server refuses is told.
- **A drop is one undo step and one toast** ("Added 3 Files", "Added 2 of 3 Files"). Undo takes the items out of the collection, then moves them to Recently Deleted.
- **The toast waits for the library to hold the items.** Where it does not in time, the toast has no Undo and the person is told; one that did not join is counted ("Added 3 Files, 1 not in Glaze tests").
- **A collection's row, card or sidebar row takes items and files** (`dropsInto`). Items already in it get no second edge, and the toast counts them. Nothing else in the sidebar takes a drop, and sub-items do not drag. Add to Collection… needs no drag.
