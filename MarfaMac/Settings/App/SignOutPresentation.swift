import AppKit
import SwiftUI

struct SignOutPresentation: ViewModifier {
    let model: MarfaSettingsModel
    let showConnection: () -> Void
    @Environment(Libraries.self) private var libraries
    @State private var showsRemovalFailure = false

    private var words: ConnectionSettings {
        ConnectionSettings(standing: libraries.preferences.standing, name: LibraryDescription.name(libraries))
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: model.isConfirmingDisconnect, initial: true) { _, requested in
                guard requested else { return }
                model.isConfirmingDisconnect = false
                SettingsAlert.confirm(
                    title: String(localized: "Sign Out?"),
                    message: String(localized: "Marfa for Mac removes its copy from this Mac and deletes the webhooks it made. Your items stay."),
                    confirm: String(localized: "Sign Out"),
                    checkbox: model.offersSettingsRemoval ? words.signOutChoice : nil,
                    window: NSApp.keyWindow
                ) { confirmed, checked in
                    guard confirmed else { return }
                    model.alsoRemovesSettings = checked
                    Task { await model.disconnect() }
                }
            }
            .onChange(of: model.host.configuredConnection) { previous, current in
                if previous != nil, current == nil { showConnection() }
            }
            .onChange(of: model.signOutNotice) { _, notice in
                if notice != nil { showConnection() }
            }
            .onChange(of: model.settingsRemovalFailure, initial: true) { _, failure in
                // Dismissing the alert must leave the pending choice available to disconnectAnyway().
                showsRemovalFailure = failure != nil
            }
            .alert("Couldn’t Remove This App’s Settings", isPresented: $showsRemovalFailure, presenting: model.settingsRemovalFailure) { _ in
                Button("Stay Signed In", role: .cancel) { model.stayConnected() }
                Button("Sign Out Anyway", role: .destructive) { Task { await model.disconnectAnyway() } }
            } message: { failure in
                Text(verbatim: failure.reason == .discardedChangesWait ? words.discardedChangesWait : words.removalNotTaken)
            }
    }
}
