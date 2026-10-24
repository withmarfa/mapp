# Native view studies

This preview compares two collection layouts and four page treatments in SwiftUI. It is not a saved-view implementation. The package pin, connection, instance name, and shared Views storage are unchanged.

## Board

Choose **View > View as Board** (Command-4). Group by a choice field or a text field with recommended values from the current items' types. The board shows empty declared lanes and keeps missing, invalid, and non-applicable values visible. Text recommendations do not prohibit other text values.

Select a card, then open it with Return or a double-click. Use its Move To menu or drag it into a lane to change that field. The destination is checked against each item's own type. Required fields cannot be cleared. Moves use the existing library setter and undo system; remote writes retain the library's normal queued-write behavior. Manual card ordering and saved board configuration are outside this preview.

Compare Comfortable and Compact cards. Field and density choices are retained for each place during the window's lifetime, then cleared when the library changes.

## Agenda

Choose **View > View as Agenda** (Command-5). Select a date field supplied by the current items' types. Date-only values stay on their local calendar day; timestamps use the local time zone. Undated, invalid, and non-applicable items remain visible below dated entries. Open a row with Return or a double-click and return through Back to Agenda.

The agenda is read-only. The current item model combines date and datetime fields, so rescheduling could otherwise lose time information. It does not infer dates from an item's text or silently substitute its edit time.

## Interface Studies

In a Debug build, open **Window > Interface Studies**, or find it in the command palette. These pages contain fictional sample content and hold changes only in that window.

- **Reading page:** compare inline properties with a side rail, comfortable with wider reading, and serif with system typography. A narrow window brings the rail back above the article.
- **Highlight page:** a quotation, source context, a local note, and links back into its reading and collection.
- **Search:** grouped results with snippets and source context, type filters, and a selected-result preview. A narrow window opens the preview in a sheet.
- **Collection overview:** a short description, next actions, reading, and related material. The sample checklist and links work locally.

The reference is the earlier Marfa Mac app HTML concept: its Inbox source context, reading and highlight pages, grouped search, and agenda ideas. The studies omit the first-launch and console screens August rejected.

## Disposable sample tour

Launch a Debug build with `-MAPPSampleFolder -MAPPViewStudies`. It creates temporary Board and Agenda folders alongside the ordinary sample notes, starts on a task board, and does not connect to a server. Select the Agenda folder and switch to Agenda to see dated and undated sessions. Standard sample launches and UI-test fixtures are unchanged when the studies flag is absent.
