Debug build against the `demo` test instance, signed in with the test MAPP key (`-MAPPSampleLibrary -MAPPSyncSettings`), driven through the accessibility tree.

After turning Search > Show Snippets off:

    $ marfa items list --type app.mapp.preferences --json
    properties: {"appearance": {"toolbarLabelStyle": 7}, "search": {"searchShowsSnippets": false}}   (item version 3)

After choosing Description as the Secondary Line of Layouts > Decisions:

    $ marfa rows list <item> types --json
    {"key": "aic.decision", "setting": "look", "value": "{\"secondary\":[\"opening\",\"field:description\"]}"}

Remove… then Remove: the item was in the bin (`items list --state trashed`), no active item remained, and the section read "Kept on This Mac Only". Keep in Marfa Again: a new active item held the same settings.

Disconnect with the box ticked: no active settings item remained and the Marfa held two binned ones; the app was signed out.
