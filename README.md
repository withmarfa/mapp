# MAPP

<img src="Design/AppIcon.png" width="128" alt="">

A native macOS markdown notes app: a sidebar, a list and a page, in the manner of Notes and Mail.

Requires macOS 27 and Xcode 27. Open `MAPP.xcodeproj` and run the `MAPP` scheme, or see `AGENTS.md` for the command line.


## Item interface

The existing sidebar and note list also browse projects, item types, and imported files. Details in the toolbar reveals the item's native inspector; View > Show Details provides the same action. New Item in the toolbar or File menu opens an Untitled page. Choose its type and optional parent, then press Return in the title or click the content area to start writing. Draft input stays in that window when you navigate away; New Item resumes it. File > Import Files creates a separate file item, while Attach Image embeds an image in a Markdown document. Property and relationship edits are saved to the selected folder. Markdown remains in the existing editor; photos, PDFs, and other files use native viewing or opening.

File-backed items use the workbench definitions as interim input. Files without a Markdown envelope expose their file information, but do not claim editable properties that the folder cannot persist. Marfa integration is a separate phase.

## Reviewing components in Xcode

Open `MAPP.xcodeproj`, choose the `MAPP` scheme, and open `MAPP/Views/ItemPreviewFixtures.swift`. Enable Editor > Canvas and resume a named preview. These previews use fixed sample items and an in-memory library; they do not read or write a person's working folder.

- **Editable Page Header** and **Long Title and Narrow Page** in `ItemPageHeader.swift` show inline title editing and status/parent controls.
- **Ticket Details** and **Project and Related Work** show dynamic properties and relationships.
- **Missing and Unfamiliar Values** shows unresolved targets and preserved unfamiliar properties.
- **Relationship Selection** and **New Item** expose the native editing flows.
- **Complete Item Window** renders the actual split view, toolbar, editor, and inspector against the in-memory library.
- **Unsaved Property Input** lets a rejected save be exercised by editing the field and committing it.

`MAPP/Views/ItemProperties.swift` also previews the individual property controls. `MAPP/Views/FileItemContent.swift` contains the file-view previews. Review the real app for editor behavior, window resizing, keyboard navigation, and saved-file persistence; the component canvas is for iterating on each piece.
