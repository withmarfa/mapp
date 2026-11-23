import Foundation
import Marfa
import Observation

/// The Addresses page: where the instance signs people in, the other addresses it answers on and the websites allowed to
/// call it. An address is added, removed or moved only after the server's own check says what it would do, and moving
/// the sign-in address shows what changes and asks first. The instance read is named in every write, so another instance
/// answering at the address is told, not written to.
@Observable @MainActor final class AddressesModel: OwnerDraftHolding {
    enum Sheet: Equatable {
        case addAddress
        case addWebsite
        case changeSignIn
    }

    /// A removal waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case removeAddress(String)
            case removeWebsite(String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
    }

    private let context: OwnerContext

    private(set) var settings: AddressSettings?
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var sheet: Sheet?
    var input = ""
    /// What the server last said a typed change would do. It answers the address that was typed then, so read it through
    /// `currentPlan`.
    private(set) var plan: AddressPlan?
    /// Why the typed address can't be used, in one line; the sheet keeps what was typed.
    private(set) var inputError: String?
    private(set) var isChecking = false
    private(set) var isWriting = false
    /// One line under the page's rows after a refused change, by the address or website.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    var question: Question?
    private var checking = 0

    init(context: OwnerContext) {
        self.context = context
    }

    // MARK: Spelling

    /// The origin a person typed: a scheme, a host and an optional port, with `https` where none is typed. Nil for what is
    /// not one, such as a path.
    static func origin(from text: String) -> String? {
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains(" ") else { return nil }
        if !typed.contains("://") { typed = "https://" + typed }
        while typed.hasSuffix("/") { typed.removeLast() }
        guard let components = URLComponents(string: typed), let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.path.isEmpty, components.query == nil,
            components.fragment == nil
        else { return nil }
        return scheme + "://" + host.lowercased() + (components.port.map { ":\($0)" } ?? "")
    }

    /// An origin as a row shows it: without `https://`.
    static func display(_ origin: String) -> String {
        origin.hasPrefix("https://") ? String(origin.dropFirst(8)) : origin
    }

    /// What kind of address a row is, where that can be told from the address.
    static func kind(of origin: String) -> String? {
        let host = URLComponents(string: origin)?.host ?? display(origin)
        if host.hasSuffix(".local") { return String(localized: "On the local network.") }
        let isNumber = host.split(separator: ".").count == 4 && host.split(separator: ".").allSatisfy { Int($0) != nil }
        return isNumber || host.contains(":") ? String(localized: "An IP address.") : nil
    }

    // MARK: Reading

    var signInAddress: String? { settings?.signIn }
    /// The addresses besides the one people sign in at.
    var otherAddresses: [String] { settings.map { settings in settings.addresses.filter { $0 != settings.signIn } } ?? [] }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            settings = try await context.calls.addresses()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
        }
    }

    // MARK: The sheets

    func begin(_ sheet: Sheet) {
        input = ""
        plan = nil
        inputError = nil
        self.sheet = sheet
    }

    func close() {
        guard !isWriting else { return }
        sheet = nil
        plan = nil
        inputError = nil
        input = ""
    }

    /// Asks the server what the typed change would do. Typing again while an answer waits drops the older answer.
    func check() async {
        checking += 1
        let mine = checking
        isChecking = false
        plan = nil
        inputError = nil
        guard let settings, let sheet else { return }
        guard let origin = Self.origin(from: input) else {
            if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                inputError = String(localized: "Use an address like https://marfa.example, with no path.")
            }
            return
        }
        if sheet == .addWebsite {
            inputError = settings.websites.contains(origin) ? String(localized: "It’s already allowed.") : nil
            return
        }
        if sheet == .addAddress, settings.addresses.contains(origin) {
            inputError = String(localized: "It’s already an address.")
            return
        }
        isChecking = true
        defer { if mine == checking { isChecking = false } }
        do {
            let asked = sheet == .changeSignIn
                ? try await context.calls.check(signIn: origin, addresses: nil)
                : try await context.calls.check(signIn: nil, addresses: settings.addresses + [origin])
            guard mine == checking else { return }
            plan = asked
            if case .notAnswering(let reason) = asked.reach { inputError = Self.notAnswering(reason) }
        } catch {
            guard mine == checking else { return }
            inputError = OwnerWording.line(error)
            await context.learn(from: error)
        }
    }

    static func notAnswering(_ reason: String?) -> String {
        switch reason {
        case "timed_out": String(localized: "Nothing answered there in time.")
        case "not_this_instance": String(localized: "Something answers there, but not this server.")
        default: String(localized: "Nothing answers there.")
        }
    }

    /// What the server said about the address typed now, or nil while it has said nothing about it: an answer about an
    /// earlier address, or about addresses that have since changed, is never read as this one's.
    var currentPlan: AddressPlan? {
        guard let plan, let settings, let origin = Self.origin(from: input) else { return nil }
        switch sheet {
        case .changeSignIn?: return plan.askedSignIn == origin ? plan : nil
        case .addAddress?: return plan.askedAddresses == settings.addresses + [origin] ? plan : nil
        case .addWebsite?, nil: return nil
        }
    }

    /// Whether Add or Change can be chosen: the server checked what is typed now and found nothing wrong.
    var canConfirm: Bool {
        guard let plan = currentPlan, inputError == nil, !isWriting, !isChecking else { return false }
        if case .notAnswering = plan.reach { return false }
        return true
    }

    /// Makes the change the sheet shows. A refusal keeps what was typed.
    func confirm() async {
        guard let sheet else { return }
        switch sheet {
        case .addWebsite:
            await commitWebsite(adding: Self.origin(from: input))
        case .addAddress, .changeSignIn:
            guard canConfirm, let plan = currentPlan else { return }
            isWriting = true
            defer { isWriting = false }
            do {
                settings = try await context.calls.apply(plan, instanceID: settings?.instanceID)
                self.sheet = nil
                self.plan = nil
                input = ""
            } catch {
                inputError = OwnerWording.line(error)
                await context.learn(from: error)
                if error == .conflict { await readAgainAndCheck(telling: error) }
            }
        }
    }

    /// The settings changed while a write waited: reads them again and checks what is typed against them, so a retry
    /// builds on the newer list, and keeps the line that says what happened unless the check found a reason of its own.
    private func readAgainAndCheck(telling failure: OwnerFailure) async {
        await load()
        await check()
        inputError = inputError ?? OwnerWording.line(failure)
    }

    private func commitWebsite(adding origin: String?) async {
        guard let settings, let origin, inputError == nil, !settings.websites.contains(origin) else { return }
        isWriting = true
        defer { isWriting = false }
        do {
            self.settings = try await context.calls.setWebsites(settings.websites + [origin], instanceID: settings.instanceID)
            sheet = nil
            input = ""
        } catch {
            inputError = OwnerWording.line(error)
            await context.learn(from: error)
            if error == .conflict { await readAgainAndCheck(telling: error) }
        }
    }

    // MARK: Removing

    /// Asks the server what removing `address` would do, then asks the owner.
    func askToRemove(address: String) async {
        guard let settings else { return }
        rowErrors[address] = nil
        do {
            let asked = try await context.calls.check(signIn: nil, addresses: settings.addresses.filter { $0 != address })
            let says = asked.consequences.map(\.sentence).joined(separator: " ")
            question = Question(
                action: .removeAddress(address), title: String(localized: "Remove \(Self.display(address))?"),
                message: says.isEmpty ? String(localized: "The server stops answering there.") : says,
                confirm: String(localized: "Remove"))
            removalPlan = asked
        } catch {
            rowErrors[address] = error
            await context.learn(from: error)
        }
    }

    private var removalPlan: AddressPlan?

    func askToRemove(website: String) {
        rowErrors[website] = nil
        question = Question(
            action: .removeWebsite(website), title: String(localized: "Remove \(Self.display(website))?"),
            message: String(localized: "Pages on it can no longer call the server."), confirm: String(localized: "Remove"))
    }

    func cancelQuestion() {
        question = nil
        removalPlan = nil
    }

    func confirm(_ asked: Question) async {
        question = nil
        guard let settings else { return }
        switch asked.action {
        case .removeAddress(let address):
            guard let plan = removalPlan else { return }
            removalPlan = nil
            do {
                self.settings = try await context.calls.apply(plan, instanceID: settings.instanceID)
            } catch {
                rowErrors[address] = error
                await context.learn(from: error)
                if error == .conflict { await load() }
            }
        case .removeWebsite(let website):
            do {
                self.settings = try await context.calls.setWebsites(settings.websites.filter { $0 != website }, instanceID: settings.instanceID)
            } catch {
                rowErrors[website] = error
                await context.learn(from: error)
                if error == .conflict { await load() }
            }
        }
    }

    // MARK: Closing

    /// The address typed in a sheet that is open, which the app gives back when Settings closes. A sheet that is writing
    /// is not taken from: the write ends with the sheet.
    func takeDrafts() -> [OwnerDraft] {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sheet, !isWriting, !typed.isEmpty else { return [] }
        let title =
            switch sheet {
            case .addAddress: String(localized: "Address Not Added")
            case .addWebsite: String(localized: "Website Not Added")
            case .changeSignIn: String(localized: "Sign-In Address Not Changed")
            }
        close()
        return [.typed(title: title, text: typed)]
    }
}
