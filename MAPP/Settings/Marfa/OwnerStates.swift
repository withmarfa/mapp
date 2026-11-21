import Marfa
import SwiftUI

extension MarfaSettingsHost {
    /// Asks the owner for the permission the server named, or for nothing in particular where it named none. Every page's
    /// Allow More… for a refusal goes through here.
    func askForMore(naming scope: String?) {
        let asked = scope.flatMap { InstancePermission(rawValue: $0) }
        Task { _ = await allowMore(asked.map { [$0] } ?? []) }
    }
}

/// What the owner's pages say in place of themselves when the server could not give what they show.
struct OwnerFailureState: View {
    /// The page the state stands in for, which words what MAPP isn't allowed to do there.
    let page: MarfaSettingsPage
    let failure: OwnerFailure
    let host: any MarfaSettingsHost
    let retry: () -> Void

    var body: some View {
        switch failure {
        case .notPermitted(let scope):
            SettingsPageState(
                symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: OwnerWording.permissionLine(scope, on: page)),
                action: (host.isAllowingMore ? "Waiting…" : "Allow More…", { host.askForMore(naming: scope) }))
            .disabled(host.isAllowingMore)
        case .unreachable:
            SettingsPageState(
                symbol: "wifi.exclamationmark", title: Text("Can’t Reach \(host.serverName)"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Try Again", retry))
        case .signedOut:
            SettingsPageState(
                symbol: "person.crop.circle.badge.exclamationmark", title: Text("Signed Out"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Open Connection…", { host.showConnection() }))
        default:
            SettingsPageState(
                symbol: "exclamationmark.triangle", title: Text("Couldn’t Read This Page"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Try Again", retry))
        }
    }
}

/// A page waiting for the server's first answer.
struct OwnerLoading: View {
    var body: some View {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity).background(SettingsTokens.page)
    }
}

/// A problem row for a call that failed, in a section already on the page: what went wrong in the page's words, and the one
/// action that helps. A refusal for want of a permission offers Allow More…; anything else offers Try Again where the page
/// has something to read again.
struct OwnerProblemRow: View {
    let title: LocalizedStringKey
    let failure: OwnerFailure
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    var retry: (() -> Void)?

    var body: some View {
        SettingsProblemRow(
            title: Text(title), line: Text(verbatim: OwnerWording.line(failure, on: page)), actions: actions
        )
        .disabled(isWaiting)
    }

    /// What a problem row offers for a failure: Allow More… for a refusal for want of a permission, Try Again for any
    /// other where the page can read again, and nothing where it cannot.
    enum Offer: Equatable {
        case allowMore(scope: String?)
        case tryAgain
        case nothing
    }

    static func offer(for failure: OwnerFailure, canRetry: Bool) -> Offer {
        if case .notPermitted(let scope) = failure { return .allowMore(scope: scope) }
        return canRetry ? .tryAgain : .nothing
    }

    private var offer: Offer { Self.offer(for: failure, canRetry: retry != nil) }

    private var isWaiting: Bool {
        if case .allowMore = offer { host.isAllowingMore } else { false }
    }

    private var actions: [SettingsProblemAction] {
        switch offer {
        case .allowMore(let scope):
            [SettingsProblemAction(host.isAllowingMore ? "Waiting…" : "Allow More…") { host.askForMore(naming: scope) }]
        case .tryAgain:
            retry.map { retry in [SettingsProblemAction("Try Again", perform: retry)] } ?? []
        case .nothing:
            []
        }
    }
}

/// A line under a page's rows that says why the last thing asked of the server was not done.
struct OwnerProblem: View {
    let title: LocalizedStringKey
    let failure: OwnerFailure
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    var retry: (() -> Void)?

    var body: some View {
        SettingsSection(name: nil) {
            OwnerProblemRow(title: title, failure: failure, page: page, host: host, retry: retry)
        }
    }
}

/// A line under a page's rows that says a change was not the person's own, such as a setting that moved somewhere else,
/// and that the person closes.
struct OwnerNotice: View {
    let title: LocalizedStringKey
    let line: String
    let close: () -> Void

    var body: some View {
        SettingsSection(name: nil) {
            SettingsProblemRow(title: Text(title), line: Text(verbatim: line), actions: [SettingsProblemAction("Close", perform: close)])
        }
    }
}
