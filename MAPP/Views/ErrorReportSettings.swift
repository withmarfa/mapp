import SwiftUI

/// The switch for reporting errors and timings to WithMarfa, shown only in a build that carries a destination for
/// them (`Reporting.carriesDestination`). It is on until turned off, and turning it off stops reporting at once.
struct ErrorReportSettings: View {
    @AppStorage(Reporting.switchKey) private var sends = true

    var body: some View {
        Section {
            Toggle("Send Error Reports", isOn: $sends)
                .toggleStyle(.switch)
                .accessibilityIdentifier("SendErrorReports")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Sends errors and timings to WithMarfa to help fix problems. Never includes your items, their text, your server’s address or anything you type.")
        }
        .onChange(of: sends) { _, isOn in Reporting.shared.switchChanged(to: isOn) }
    }
}
