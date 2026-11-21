import Foundation
import Marfa
import Observation

/// The Apps page: the apps the owner approved, with what each may reach. Access can only be narrowed, and narrowing or
/// disconnecting asks first. Every change is sent with the access it was read as, so a change made elsewhere is told, not
/// overwritten.
@Observable @MainActor final class AppsModel {
    /// A change waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case narrow(appID: String, scopes: [String])
            case disconnect(appID: String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
    }

    private let context: OwnerContext

    private(set) var apps: [AppAccess] = []
    private(set) var typeNames: [String: String] = [:]
    /// The keys each app made, by the app's client ID, where MAPP may list keys.
    private(set) var keysMade: [String: [KeyInfo]] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// One line under a row whose change was refused, by the app's id.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    var question: Question?
    /// The app an Apps page was disconnected from, so the page it was shown on can go back.
    private(set) var disconnected: String?

    init(context: OwnerContext) {
        self.context = context
    }

    func app(_ id: String) -> AppAccess? { apps.first { $0.id == id } }

    static func name(of app: AppAccess) -> String {
        if let name = app.name, !name.isEmpty { return name }
        switch app.kind {
        case .commandLine: return String(localized: "Command Line")
        case .web, .app: return app.clientID
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            apps = try await context.calls.apps()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        // What the access is called is a nicety: without the names the patterns say it.
        typeNames = (try? await context.calls.typeNames()) ?? typeNames
        if context.grants().contains(.keysManage), let keys = try? await context.calls.keys() {
            keysMade = Dictionary(grouping: keys.filter { $0.appClientID != nil }, by: { $0.appClientID ?? "" })
        } else {
            keysMade = [:]
        }
    }

    // MARK: Narrowing

    /// Asks before lowering what `pattern` may do for `app`.
    func askToNarrow(_ app: AppAccess, pattern: String, to level: AccessLevel) {
        ask(app, scopes: AccessScopes.narrowed(app.scopes, pattern: pattern, to: level))
    }

    func askToRemove(permission: String, from app: AppAccess) {
        ask(app, scopes: AccessScopes.removing(permission: permission, from: app.scopes))
    }

    private func ask(_ app: AppAccess, scopes: [String]) {
        guard scopes != app.scopes else { return }
        let name = Self.name(of: app)
        question = Question(
            action: .narrow(appID: app.id, scopes: scopes), title: String(localized: "Narrow \(name)’s access?"),
            message: String(localized: "\(name) must ask you to get it back. Keys it made that reach further stop working."),
            confirm: String(localized: "Narrow"))
    }

    func askToDisconnect(_ app: AppAccess) {
        let name = Self.name(of: app)
        question = Question(
            action: .disconnect(appID: app.id), title: String(localized: "Disconnect \(name)?"),
            message: String(localized: "\(name) stops working at once and must be approved again. Its webhooks are deleted. The keys it made keep working."),
            confirm: String(localized: "Disconnect"))
    }

    func cancelQuestion() { question = nil }

    func confirm(_ asked: Question) async {
        question = nil
        switch asked.action {
        case .narrow(let id, let scopes):
            guard let app = app(id) else { return }
            rowErrors[id] = nil
            do {
                try await context.calls.narrow(app, to: scopes)
                await load()
            } catch {
                await refused(error, appID: id)
            }
        case .disconnect(let id):
            guard let app = app(id) else { return }
            rowErrors[id] = nil
            do {
                try await context.calls.disconnect(app)
                apps.removeAll { $0.id == id }
                disconnected = id
            } catch {
                await refused(error, appID: id)
            }
        }
    }

    /// A refusal is told under the row and the page reads again, so what it shows is what the server holds.
    private func refused(_ failure: OwnerFailure, appID: String) async {
        rowErrors[appID] = failure
        await context.learn(from: failure)
        if failure == .conflict || failure == .notFound { await load() }
    }
}
