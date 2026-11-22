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

    /// Where the copy is, for the person to remove when MAPP can't.
    private var copyFolder: String {
        model.host.configuredConnection.map { model.host.location.directory(for: $0).path } ?? ""
    }

    var body: some View {
        SettingsSheet(title: Text("Changes Haven’t Been Sent"), isWide: true) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetSpacing) {
                if departure.isAskedAgain {
                    Text("More changes arrived while you were deciding. Look at them before you choose.")
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.warning)
                }
                if let unsent = departure.unsent {
                    Text(Words.notSent(unsent.count)).settingsFont(.title)
                    changes(unsent)
                } else {
                    Text(Words.cannotDiscard(folder: copyFolder)).settingsFont(.title)
                }
                Group {
                    if !canDiscard {
                        Text("Keep the copy and the changes stay on this Mac.")
                    } else if isOtherVersion {
                        Text("Keep the copy and the changes stay on this Mac. Install the previous build of MAPP from TestFlight and connect it to the same server, and it sends them. Discard the copy and they’re lost.")
                    } else {
                        Text("Keep the copy and the changes stay on this Mac. Connect to the same server again and they’re sent. Discard the copy and they’re lost.")
                    }
                }
                .settingsFont(.small)
                .foregroundStyle(SettingsTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                if departure.holdsSettingsRemoval {
                    Text(verbatim: words.removalWaiting)
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("DepartureRemovalWaiting")
                }
                if isDisconnecting, model.offersSettingsRemoval {
                    Toggle(words.disconnectChoice, isOn: Bindable(model).alsoRemovesSettings)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("DepartureRemoveSettings")
                    Text(verbatim: words.sendsWaitingChanges)
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } buttons: {
            if canDiscard {
                SettingsButton(isDisconnecting ? "Discard Changes and Disconnect" : "Discard Changes and Switch", role: .destructive) {
                    Task { await model.answer(.discardCopy) }
                }
                .disabled(model.alsoRemovesSettings)
                .accessibilityIdentifier("DepartureDiscard")
            }
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.cancelDeparture() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("DepartureCancel")
            SettingsButton(isDisconnecting ? "Keep Copy and Disconnect" : "Keep Copy and Switch") {
                Task { await model.answer(.keepCopy) }
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("DepartureKeep")
        }
        .disabled(model.isWorking)
        .accessibilityIdentifier("DepartureSheet")
    }

    @ViewBuilder private func changes(_ unsent: UnsentChanges) -> some View {
        if !unsent.texts.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetListSpacing) {
                    ForEach(unsent.texts) { text in
                        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetChangeSpacing) {
                            Text(text.content.plainText)
                                .textSelection(.enabled)
                                .lineLimit(SettingsTokens.Metric.sheetTextLines)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            SettingsButton("Copy Text", small: true) { copy(text.content.plainText) }
                        }
                        .padding(SettingsTokens.Metric.sheetChangePadding)
                        .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: SettingsTokens.Metric.sheetChangeRadius))
                    }
                }
            }
            .frame(maxHeight: SettingsTokens.Metric.sheetListMaxHeight)
        }
        if unsent.count > unsent.texts.count {
            Text(Words.moreNotShown(unsent.count - unsent.texts.count))
                .settingsFont(.small)
                .foregroundStyle(SettingsTokens.secondaryText)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
