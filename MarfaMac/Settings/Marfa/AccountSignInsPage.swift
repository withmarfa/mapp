import SwiftUI

struct AccountSignInsPage: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    @State private var model: AccountModel
    @Environment(\.openURL) private var openURL

    init(page: MarfaSettingsPage, host: any MarfaSettingsHost) {
        self.page = page
        self.host = host
        _model = State(initialValue: AccountModel(context: OwnerContext(host: host)))
    }

    private static var unnamed: String { String(localized: "Passkey") }

    var body: some View {
        Group {
            if let failure = model.failure {
                OwnerFailureState(page: page, failure: failure, host: host) { Task { await load() } }
            } else if model.hasLoaded {
                SettingsPageColumn {
                    if page == .passkeys {
                        passkeysSection
                    } else {
                        browsersSection
                    }
                    if let note = model.note { SettingsNote(verbatim: note) }
                }
            } else {
                OwnerLoading()
            }
        }
        .task(id: host.serverAddress) { await load() }
        .toolbar {
            if page == .passkeys, model.hasLoaded, model.failure == nil {
                ToolbarItem {
                    Button("Add Passkey…") { Task { if let address = await model.passkeyAddress() { openURL(address) } } }
                }
            }
        }
        .onAppear { host.ownerDrafts.register(model) }
        .settingsSheet(presenting: model.sheet != nil, dismiss: { model.closeRename() }) { AccountSheet(model: model) }
        .alert(
            model.question?.title ?? "",
            isPresented: Binding {
                model.question != nil
            } set: {
                if !$0 { model.cancelQuestion() }
            },
            presenting: model.question
        ) { asked in
            Button("Cancel", role: .cancel) {}
            Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
        } message: { asked in
            Text(verbatim: asked.message)
        }
    }

    private func load() async { await model.loadSignIns(passkeysOnly: page == .passkeys) }

    private var passkeysSection: some View {
        SettingsSection(name: nil, footer: Text("Your browser opens to add one.")) {
            if model.passkeys.isEmpty {
                SettingsEmptyCard(symbol: "person.badge.key", title: Text("No Passkeys"), line: Text("Add a passkey to sign in with it."))
            }
            ForEach(model.passkeys) { passkey in
                SettingsRow(
                    verbatim: passkey.name ?? Self.unnamed, line: Self.line(added: passkey.added, used: passkey.lastUsed),
                    error: model.rowErrors[passkey.id].map { OwnerWording.line($0, on: page) }, lead: .symbol("touchid")
                ) {
                    SettingsMoreMenu {
                        Button("Rename…") { model.beginRename(passkey) }
                        Button("Remove…", role: .destructive) { model.askToRemove(passkey) }
                    }
                }
            }
        }
    }

    private var browsersSection: some View {
        SettingsSection("Signed In", footer: "Changing your password signs out every browser.") {
            if model.browsers.isEmpty {
                SettingsEmptyCard(symbol: "safari", title: Text("No Browsers"), line: Text("No browsers are signed in."))
            }
            ForEach(model.browsers) { browser in
                SettingsRow(
                    verbatim: browser.name, line: Self.line(added: browser.added, used: browser.lastUsed, signedIn: true),
                    error: model.rowErrors[browser.id].map { OwnerWording.line($0, on: page) }, lead: .symbol("safari")
                ) {
                    SettingsMoreMenu { Button("Sign Out…", role: .destructive) { model.askToEnd(browser) } }
                }
            }
        }
    }

    /// "Added 3 October. Used today."
    static func line(added: Date?, used: Date?, signedIn: Bool = false, now: Date = .now, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let added {
            let day = OwnerWording.day(added, now: now, calendar: calendar)
            parts.append(signedIn ? String(localized: "Signed in \(day).") : String(localized: "Added \(day)."))
        }
        parts.append(OwnerWording.used(used, now: now, calendar: calendar) + ".")
        return parts.joined(separator: " ")
    }
}
