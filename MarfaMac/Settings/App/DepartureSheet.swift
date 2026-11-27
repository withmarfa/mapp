import AppKit
import SwiftUI

/// Asked when a copy is left while changes wait in it: keep it, so connecting to the same server again sends them, or
/// discard it with them. The text of what would be lost is shown, since it is the only copy. It sits in the middle of the
/// Settings window, as a sheet of the parts does.
struct DepartureSheet: View {
    @Environment(Libraries.self) private var libraries
    let model: MarfaSettingsModel
    let departure: MarfaSettingsModel.Departure

    private var isDisconnecting: Bool { departure.kind == .disconnect }

    private var words: ConnectionSettings {
        ConnectionSettings(standing: libraries.preferences.standing, name: LibraryDescription.name(libraries))
    }

    /// Whether the copy is one a different version of the app made. This version can't send what it holds, so keeping the
    /// copy does not send it on connecting again.
    private var isOtherVersion: Bool {
        if case .otherVersion = model.host.state { true } else { false }
    }

    /// Whether the person has been shown the changes they would lose. The package removes a copy only against the writes
    /// read from it, so a copy whose changes can't be listed is kept, never discarded.
    private var canDiscard: Bool { departure.unsent != nil }

    /// Where the copy is, for the person to remove when the app can't.
    private var copyFolder: String {
        model.host.configuredConnection.map { model.host.location.directory(for: $0).path } ?? ""
    }

    private var title: Text {
        guard isDisconnecting, let count = departure.unsent?.count else { return Text("Changes Haven’t Been Sent") }
        return count == 1 ? Text("1 Change Hasn’t Been Sent") : Text("\(count) Changes Haven’t Been Sent")
    }

    private var explanation: Text {
        if !canDiscard {
            Text("Keep the copy and the changes stay on this Mac.")
        } else if isOtherVersion {
            Text("Keep the copy and the changes stay on this Mac. Install the previous version of the app and connect it to the same server, and it sends them. Discard the copy and they’re lost.")
        } else if !isDisconnecting {
            Text("Keep the copy and the changes stay on this Mac. Connect to the same server again and they’re sent. Discard the copy and they’re lost.")
        } else if departure.unsent?.count == 1 {
            Text("Keep the copy and the change is sent when you sign in to this Marfa again. Discard it and the change is lost.")
        } else {
            Text("Keep the copy and they’re sent when you sign in to this Marfa again. Discard it and they’re lost.")
        }
    }

    var body: some View {
        SettingsSheet(title: title, line: explanation, isWide: true) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetSpacing) {
                if departure.isAskedAgain {
                    Text("More changes arrived while you were deciding. Look at them before you choose.")
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.warning)
                }
                if let unsent = departure.unsent {
                    if !isDisconnecting { Text(Words.notSent(unsent.count)).settingsFont(.title) }
                    changes(unsent)
                } else {
                    Text(Words.cannotDiscard(folder: copyFolder)).settingsFont(.title)
                }
                if departure.holdsSettingsRemoval {
                    Text(verbatim: words.removalWaiting)
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("DepartureRemovalWaiting")
                }
                if isDisconnecting, model.offersSettingsRemoval {
                    VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                        SettingsCheckRow(
                            verbatim: words.signOutChoice, line: words.sendsWaitingChanges,
                            isOn: Bindable(model).alsoRemovesSettings
                        )
                        .accessibilityIdentifier("DepartureRemoveSettings")
                        Text(verbatim: ConnectionSettings.removalRisk)
                            .settingsFont(.small)
                            .foregroundStyle(SettingsTokens.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } leading: {
            if canDiscard {
                SettingsButton(isDisconnecting ? "Discard and Sign Out" : "Discard Changes and Switch", role: .destructive) {
                    Task { await model.answer(.discardCopy) }
                }
                .disabled(model.alsoRemovesSettings)
                .accessibilityIdentifier("DepartureDiscard")
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelDeparture() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("DepartureCancel")
            // With the settings' removal ticked it deletes from the Marfa, so Return must not press it.
            SettingsButton(
                isDisconnecting ? "Keep Copy and Sign Out" : "Keep Copy and Switch", role: model.alsoRemovesSettings ? .normal : .confirm
            ) {
                Task { await model.answer(.keepCopy) }
            }
            .accessibilityIdentifier("DepartureKeep")
        }
        .disabled(model.isWorking)
        .accessibilityIdentifier("DepartureSheet")
    }

    @ViewBuilder private func changes(_ unsent: UnsentChanges) -> some View {
        if !unsent.texts.isEmpty {
            SettingsCard {
                ForEach(unsent.texts) { text in
                    let operation = wording(for: text.change)
                    let words = changeWords(text.content, operation: operation.title)
                    SettingsRow(title: words.title, line: words.line, lead: operation.lead, lines: nil) {
                        SettingsButton("Copy Text", small: true) { copy(text.content.plainText) }
                    }
                    .textSelection(.enabled)
                }
            }
        }
        if unsent.count > unsent.texts.count {
            Text(Words.moreNotShown(unsent.count - unsent.texts.count))
                .settingsFont(.small)
                .foregroundStyle(SettingsTokens.secondaryText)
        }
    }

    private func changeWords(_ content: SyncContent, operation: Text) -> (title: Text, line: Text) {
        guard let title = content.title, !title.isEmpty else { return (operation, Text(verbatim: content.plainText)) }
        var rest = content
        rest.title = nil
        let detail = rest.plainText
        return (Text(verbatim: title), detail.isEmpty ? operation : Text("\(operation)\n\(detail)"))
    }

    private func wording(for change: SyncProblemEntry.Change) -> (title: Text, lead: SettingsLead) {
        switch change {
        case .create: (Text("Created"), .symbol("plus"))
        case .edit: (Text("Edited"), .symbol("pencil"))
        default: (Text("Unsent change"), .none)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
