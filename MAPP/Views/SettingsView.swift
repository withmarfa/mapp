import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            OrderOptions()
        }
        // The menus show these with icons; Settings rows, as in the system's own panes, do not.
        .labelStyle(.titleOnly)
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
