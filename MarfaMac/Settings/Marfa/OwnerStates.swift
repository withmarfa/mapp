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

extension OwnerFailure {
    /// What a page says in place of itself when the server's settings could not be read.
    init(_ failure: InstanceConfigFailure) {
        switch failure {
        case .unreachable: self = .unreachable
        case .notPermitted: self = .notPermitted(InstancePermission.configManage.rawValue)
        case .instanceChanged: self = .instanceChanged
        case .unsupported: self = .unsupported
        case .keyRefused: self = .signedOut
        case .refused(let reason): self = .refused(reason)
        case .failed(let reason): self = .failed(reason)
        }
    }
}

/// What the owner's pages say in place of themselves when the server could not give what they show.
struct OwnerFailureState: View {
    /// The page the state stands in for, which words what the app isn't allowed to do there.
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
        case .instanceChanged:
            SettingsPageState(
                symbol: "exclamationmark.triangle", title: Text("Another Marfa Answers"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Try Again", retry))
        case .unsupported:
            SettingsPageState(symbol: "gearshape", title: Text("No Server Settings"), line: Text(verbatim: OwnerWording.line(failure)))
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

/// A problem row in the page's words. A missing permission offers Allow More…, and a failed read with a retry offers Try Again.
struct OwnerProblemRow: View {
    let title: LocalizedStringKey
    let failure: OwnerFailure
    /// The row's own words for what the app isn't allowed to do, where the page's one line for its permission doesn't fit.
    var line: String?
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    var additionalActions: [SettingsProblemAction] = []
    var retry: (() -> Void)?

    var body: some View {
        SettingsProblemRow(
            title: Text(title), line: Text(verbatim: line ?? OwnerWording.line(failure, on: page)),
            symbol: isRefusal ? "lock" : "exclamationmark.triangle", tone: isRefusal ? nil : .orange, actions: actions
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

    /// A refusal for want of a permission leads with the lock, as a page that cannot be shown does.
    private var isRefusal: Bool {
        if case .notPermitted = failure { true } else { false }
    }

    private var isWaiting: Bool {
        if case .allowMore = offer { host.isAllowingMore } else { false }
    }

    private var actions: [SettingsProblemAction] {
        let offered: [SettingsProblemAction] = switch offer {
        case .allowMore(let scope):
            [SettingsProblemAction(host.isAllowingMore ? "Waiting…" : "Allow More…") { host.askForMore(naming: scope) }]
        case .tryAgain:
            retry.map { retry in [SettingsProblemAction("Try Again", perform: retry)] } ?? []
        case .nothing:
            []
        }
        return offered + additionalActions
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
