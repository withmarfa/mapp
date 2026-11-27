import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// Holds a fake call open until a test lets it go.
nonisolated final class OwnerCallGate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1)) }

    func wait() async { for await _ in stream { return } }
    func open() { continuation.yield() }
}

/// What the owner's pages ask of the server, held in memory: it answers as the server does, keeps what it was sent and fails
/// a named call on request.
nonisolated final class FakeOwnerCalls: OwnerCalls {
    struct State {
        var profile = OwnerProfile(username: "mira", emailIsReadable: true, email: nil)
        var picture: Data?
        var namesSent: [String] = []
        /// Names the server refuses once their send has been let go, as a refusal that comes after a wait.
        var namesRefused: Set<String> = []
        var picturesSent: [Data] = []
        var passkeys: [OwnerPasskey] = []
        var browsers: [BrowserSignIn] = []
        var password = "old password"
        var apps: [AppAccess] = []
        var names: [String: String] = [:]
        var keys: [KeyInfo] = []
        /// Who the sign-in is: a signed-in app, with no expiry of its own, unless a test says otherwise.
        var identity = OwnIdentity(keyID: nil, expires: nil)
        var settings = AddressSettings(
            instanceID: "instance-1", signIn: "https://marfa.test", addresses: ["https://marfa.test", "https://100.84.12.7"], websites: [])
        var reach = AddressPlan.Reach.notAsked
        var consequences: [AddressPlan.Consequence] = []
        var requiresConfirmation = false
        /// A call by name that fails, until cleared.
        var failures: [String: OwnerFailure] = [:]
        var calls: [String] = []
        var narrowed: [(app: AppAccess, scopes: [String])] = []
        /// What each namespace holds, by vendor, and what removing it answers (the data goes where it is complete).
        var appData: [String: AppData] = [:]
        var removalAnswer: [String: AppDataRemoved] = [:]
        var dataRemoved: [String] = []
        var disconnects: [(id: String, removingData: Bool)] = []
        var created: [NewKey] = []
        var changes: [(id: String, change: KeyChange)] = []
        var applied: [AddressPlan] = []
        var websitesSent: [[String]] = []
        var gates: [String: OwnerCallGate] = [:]
        var concerns: [AttentionConcern] = []
        var metrics = InstanceMetricsReading(version: "0.0.84", databaseBytes: nil, fileBytes: 0)
        var fileStores = FileStores(stores: [], orphanCount: 0, orphanBytes: 0, firstFound: nil, orphansComplete: true)
        var sources: [OwnerSource] = []
        var sourceLimit = SourceLimit(instanceID: "instance-1", isOn: false, types: [], sources: [], strictTypes: nil, allowlist: nil)
        /// The levers each enforcement write sent.
        var leversSent: [SourceLimit] = []
        /// What each enforcement write sent as Limit Sources, nil for off.
        var filtersSent: [SourceRuleValue?] { leversSent.map { $0.value(of: .filter) } }
        /// What each enforcement write sent as Who May Write, nil for off.
        var allowlistsSent: [SourceRuleValue?] { leversSent.map { $0.value(of: .allowlist) } }
        /// Run as a source limit write arrives, to let a test move the server under it.
        var beforeLimitWrite: (@Sendable () -> Void)?
        var webhooks: [OwnerWebhook] = []
        var deliveries: [String: [WebhookDeliveryInfo]] = [:]
        var webhooksMade: [NewWebhook] = []
        var webhookChanges: [(id: String, change: WebhookChange)] = []
        var redelivered: [String] = []
        var folders: [OwnerFolder] = []
        var reports: [String: FolderReport] = [:]
        /// How many folders the server holds, where the list it sent was cut.
        var foldersTotal: Int?
        /// How long a deliveries or folder-report call takes, so calls overlap and the most at once can be counted.
        var readDelay: Duration?
        var readsInFlight = 0
        var mostReadsInFlight = 0
        var health: ServerHealth? = ServerHealth(
            database: .ok, disk: .ok, files: .ok, backups: BackupsHealth(state: .ok, lastBackup: nil), housekeeping: HousekeepingHealth(failed: [], hold: nil))
        var upkeep = UpkeepSettings(instanceID: "instance-1", folder: "/Volumes/Studio Backup", objectStore: false, intervalSeconds: 3600, checksForUpdates: true)
        var upkeepChanges: [UpkeepSettingsChange] = []
        var backups: [BackupRecord] = []
        var backupsTaken = 0
        var restoreAnswer = BackupRestored(leftOut: [], added: 0, alreadyHeld: 0, secretsToSet: [])
        var restores: [BackupRecord] = []
        var update = UpdateStatus(
            running: "0.0.84", checksAutomatically: true, latest: nil, available: false, checkFailed: false, updatesItself: true, step: nil,
            progress: nil, last: nil)
        /// What each read of the update answers after the first, in order, once an update runs; the last stays.
        var updateReads: [UpdateStatus] = []
        var updatesStarted = 0
        var updatesChecked = 0
        var jobs: [HousekeepingJob] = []
        var clocksConfirmed = 0
        /// The time the server answers when the clock is confirmed; the date it was shown where nil.
        var clockConfirmedAt: Date?
        var connectorPlugins: [PluginConnectorSummary] = []
        var connectorControls: [String: ConnectorControl] = [:]
        var connectorRegistrations: [String: ConnectorRegistration] = [:]
        var connectorHosts: [ConnectorHostInfo] = []
        var connectorSettings: [String: ConnectorSettingsReading] = [:]
        /// Each settings write, as the plugin and the changes it sent.
        var connectorSettingsSent: [(plugin: String, changes: [String: ConnectorSettingChange])] = []
        /// The machine each assignment named.
        var connectorAssigned: [(plugin: String, host: String?)] = []
        /// The machines made, and the links answered, in order.
        var hostsMade: [String] = []
        var linksMade = 0
        /// The next assignment holds on the server, but its answer is lost as this failure.
        var assignAnswerLost: OwnerFailure?
        /// What the sign-in start answers, and the address the browser was asked to return to.
        var signInStart = ConnectorSignInStart(id: "sign-in-1", address: URL(string: "https://accounts.example.com/sign-in")!, expires: .now.addingTimeInterval(600))
        var signInReturnedTo: [String] = []
        var signInStatus = ConnectorSignInStatus.signedIn
        /// The ID the status read names, where it is not the start's: another sign-in replaced it.
        var signInReadID: String?
        /// What the server holds after a sign-in finishes: the setting the token goes in, which a finished sign-in sets.
        var signInSetsToken: (plugin: String, setting: String)?
        /// Each plugin's stored mapping, as the server holds it.
        var mappings: [String: ConnectorMappingReading] = [:]
        /// Each save, as the version and kinds it sent.
        var mappingSaves: [(plugin: String, version: Int, kinds: [String: KindMapping])] = []
        var mappingTypes: [String: MappingTypeInfo] = [:]
        /// What each preview read answers in turn, the last staying; the preview as asked is the first.
        var previewAnswers: [MappingPreviewStatus] = []
        var previewReads = 0
        var previewsAsked: [(kind: String, draft: KindMapping?)] = []
        /// How long a preview is kept, from when it is asked.
        var previewLife: TimeInterval = 600
        /// The items a rewrite would move, by kind, and each rewrite asked for.
        var rewriteCounts: [String: Int] = [:]
        var rewritesAsked: [(kinds: [String], dryRun: Bool)] = []
        /// Faults the next saves return, in place of the required-field check, until a test clears them.
        var scriptedMappingFaults: [MappingFault]?
        /// What a preview's start answers, where a test does not want the first pending state.
        var previewStart: MappingPreviewStatus?
        /// A failure a preview poll raises after it has been let go, so a test can fail one that is already waiting.
        var previewFailureAfterWait: OwnerFailure?
        /// How many calls of each name are inside `held`, waiting or about to wait.
        var waiting: [String: Int] = [:]
        var linkTypes: [OwnerLinkType] = []
        var linkTypeNames: [String: String] = [:]
        var linkTypesMade: [NewLinkType] = []
        /// The link types links still use, which a delete keeps.
        var linkTypesInUse: Set<String> = []
    }

    let state = Mutex(State())

    func fail(_ call: String, with failure: OwnerFailure?) { state.withLock { $0.failures[call] = failure } }
    var calls: [String] { state.withLock { $0.calls } }

    /// Holds the next calls named `call` open, once they have started, until the returned gate is opened.
    func hold(_ call: String) -> OwnerCallGate {
        let gate = OwnerCallGate()
        state.withLock { $0.gates[call] = gate }
        return gate
    }

    private func held(_ call: String) async {
        let gate = state.withLock { state -> OwnerCallGate? in
            state.waiting[call, default: 0] += 1
            return state.gates[call]
        }
        if let gate { await gate.wait() }
        state.withLock { $0.waiting[call, default: 0] -= 1 }
    }

    /// Takes `readDelay` while counted as in flight.
    private func counted() async {
        guard let delay = state.withLock({ state -> Duration? in
            guard state.readDelay != nil else { return nil }
            state.readsInFlight += 1
            state.mostReadsInFlight = max(state.mostReadsInFlight, state.readsInFlight)
            return state.readDelay
        }) else { return }
        try? await Task.sleep(for: delay)
        state.withLock { $0.readsInFlight -= 1 }
    }

    private func enter(_ call: String) throws(OwnerFailure) {
        let failure = state.withLock { state in
            state.calls.append(call)
            return state.failures[call]
        }
        if let failure { throw failure }
    }

    func profile() async throws(OwnerFailure) -> OwnerProfile {
        await held("profile")
        try enter("profile")
        return state.withLock { $0.profile }
    }

    func setProfileName(_ name: String) async throws(OwnerFailure) -> OwnerProfile {
        try enter("setProfileName")
        await held("setProfileName")
        if state.withLock({ $0.namesRefused.contains(name) }) { throw .refused("The name can’t be used.") }
        return state.withLock { state in
            state.namesSent.append(name)
            state.profile.name = name.trimmingCharacters(in: .whitespaces)
            return state.profile
        }
    }

    func setProfileContact(_ field: ProfileContactField, to value: String) async throws(OwnerFailure) -> OwnerProfile {
        await held("setProfileContact")
        try enter("setProfileContact")
        return state.withLock { state in
            switch field {
            case .username: state.profile.username = value.lowercased()
            case .email: state.profile.email = value.isEmpty ? nil : value.lowercased()
            }
            return state.profile
        }
    }

    func profilePicture() async throws(OwnerFailure) -> Data? {
        try enter("profilePicture")
        return state.withLock { $0.picture }
    }

    func setProfilePicture(_ picture: Data) async throws(OwnerFailure) -> OwnerProfile {
        try enter("setProfilePicture")
        return state.withLock { state in
            state.picturesSent.append(picture)
            state.picture = picture
            state.profile.hasPicture = true
            return state.profile
        }
    }

    func passkeys() async throws(OwnerFailure) -> [OwnerPasskey] {
        try enter("passkeys")
        return state.withLock { $0.passkeys }
    }

    func renamePasskey(_ id: String, to name: String) async throws(OwnerFailure) {
        try enter("renamePasskey")
        state.withLock { state in
            if let index = state.passkeys.firstIndex(where: { $0.id == id }) { state.passkeys[index].name = name }
        }
    }

    func removePasskey(_ id: String) async throws(OwnerFailure) {
        try enter("removePasskey")
        state.withLock { $0.passkeys.removeAll { $0.id == id } }
    }

    func passkeyAddAddress() async throws(OwnerFailure) -> URL {
        try enter("passkeyAddAddress")
        return URL(string: "https://marfa.test/passkeys/add")!
    }

    func browserSignIns() async throws(OwnerFailure) -> [BrowserSignIn] {
        try enter("browserSignIns")
        return state.withLock { $0.browsers }
    }

    func endSignIn(_ id: String) async throws(OwnerFailure) {
        try enter("endSignIn")
        state.withLock { $0.browsers.removeAll { $0.id == id } }
    }

    func changePassword(from current: String, to new: String) async throws(OwnerFailure) -> PasswordOutcome {
        try enter("changePassword")
        return state.withLock { state in
            guard current == state.password else { return .currentWrong }
            guard (8...128).contains(new.count) else { return .newRefused("The password must be 8 to 128 characters.") }
            state.password = new
            state.browsers = []
            return .changed
        }
    }

    func typeNames() async throws(OwnerFailure) -> [String: String] {
        try enter("typeNames")
        return state.withLock { $0.names }
    }

    func apps() async throws(OwnerFailure) -> [AppAccess] {
        try enter("apps")
        return state.withLock { $0.apps }
    }

    func narrow(_ app: AppAccess, to scopes: [String]) async throws(OwnerFailure) {
        try enter("narrow")
        try state.withLock { state throws(OwnerFailure) in
            guard let index = state.apps.firstIndex(where: { $0.id == app.id }) else { throw .notFound }
            guard state.apps[index].scopes == app.scopes else { throw .conflict }
            state.narrowed.append((app, scopes))
            state.apps[index].scopes = scopes
        }
    }

    func disconnect(_ app: AppAccess, removingData: Bool) async throws(OwnerFailure) {
        try enter("disconnect")
        state.withLock { state in
            state.disconnects.append((app.id, removingData))
            state.apps.removeAll { $0.id == app.id }
            if removingData { for vendor in app.vendors { state.appData[vendor] = nil } }
        }
    }

    func appData(vendor: String) async throws(OwnerFailure) -> AppData {
        try enter("appData")
        return try state.withLock { state throws(OwnerFailure) in
            guard let data = state.appData[vendor] else { throw .notFound }
            return data
        }
    }

    func removeAppData(vendor: String) async throws(OwnerFailure) -> AppDataRemoved {
        try enter("removeAppData")
        return state.withLock { state in
            state.dataRemoved.append(vendor)
            let answer = state.removalAnswer[vendor] ?? AppDataRemoved(removedItems: state.appData[vendor]?.total ?? 0, remainingItems: 0)
            if answer.isComplete { state.appData[vendor] = nil }
            return answer
        }
    }

    func keys() async throws(OwnerFailure) -> [KeyInfo] {
        await held("keys")
        try enter("keys")
        return state.withLock { $0.keys }
    }

    func create(_ key: NewKey) async throws(OwnerFailure) -> CreatedKey {
        let failure = state.withLock { state in
            state.calls.append("create")
            return state.failures["create"]
        }
        await held("create")
        if let failure { throw failure }
        return state.withLock { state in
            state.created.append(key)
            let id = "key-\(state.keys.count + 1)"
            state.keys.append(
                KeyInfo(
                    id: id, label: key.label, source: key.source, permissions: key.permissions, tier: key.tier, types: key.types,
                    created: .now, expires: key.expires, lastUsed: nil, appClientID: nil))
            return CreatedKey(id: id, label: key.label, secret: "marfa_k1_secret")
        }
    }

    func change(_ id: String, _ change: KeyChange) async throws(OwnerFailure) -> KeyInfo {
        try enter("change")
        return try state.withLock { state throws(OwnerFailure) in
            guard let index = state.keys.firstIndex(where: { $0.id == id }) else { throw .notFound }
            state.changes.append((id, change))
            if let label = change.label { state.keys[index].label = label }
            if let tier = change.tier { state.keys[index].tier = tier }
            switch change.expires {
            case .on(let date)?: state.keys[index].expires = date
            case .never?: state.keys[index].expires = nil
            case nil: break
            }
            if let types = change.types { state.keys[index].types = types }
            if let permissions = change.permissions { state.keys[index].permissions = permissions }
            return state.keys[index]
        }
    }

    func revoke(_ id: String) async throws(OwnerFailure) {
        try enter("revoke")
        try state.withLock { state throws(OwnerFailure) in
            guard state.keys.contains(where: { $0.id == id }) else { throw .notFound }
            state.keys.removeAll { $0.id == id }
        }
    }

    func identity() async throws(OwnerFailure) -> OwnIdentity {
        try enter("identity")
        return state.withLock { $0.identity }
    }

    func addresses() async throws(OwnerFailure) -> AddressSettings {
        try enter("addresses")
        return state.withLock { $0.settings }
    }

    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan {
        try enter("check")
        await held("check")
        return state.withLock { state in
            AddressPlan(
                askedSignIn: signIn, askedAddresses: addresses, signIn: signIn ?? state.settings.signIn,
                addresses: addresses ?? state.settings.addresses, requiresConfirmation: state.requiresConfirmation,
                consequences: state.consequences, reach: signIn == nil ? .notAsked : state.reach)
        }
    }

    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try enter("apply")
        return try state.withLock { state throws(OwnerFailure) in
            if let instanceID, instanceID != state.settings.instanceID { throw .instanceChanged }
            state.applied.append(plan)
            state.settings.signIn = plan.signIn
            state.settings.addresses = plan.addresses
            return state.settings
        }
    }

    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try enter("setWebsites")
        return state.withLock { state in
            state.websitesSent.append(websites)
            state.settings.websites = websites
            return state.settings
        }
    }

    func attention() async throws(OwnerFailure) -> [AttentionConcern] {
        try enter("attention")
        return state.withLock { $0.concerns }
    }

    func instanceMetrics() async throws(OwnerFailure) -> InstanceMetricsReading {
        try enter("instanceMetrics")
        return state.withLock { $0.metrics }
    }

    func fileStores() async throws(OwnerFailure) -> FileStores {
        try enter("fileStores")
        return state.withLock { $0.fileStores }
    }

    func sources() async throws(OwnerFailure) -> [OwnerSource] {
        try enter("sources")
        return state.withLock { $0.sources }
    }

    func sourceLimit() async throws(OwnerFailure) -> SourceLimit {
        try enter("sourceLimit")
        return state.withLock { $0.sourceLimit }
    }

    func setSourceLimit(_ levers: SourceLimit) async throws(OwnerFailure) -> SourceLimit {
        try enter("setSourceLimit")
        await held("setSourceLimit")
        state.withLock { $0.beforeLimitWrite }?()
        return try state.withLock { state throws(OwnerFailure) in
            guard state.sourceLimit.instanceID == levers.instanceID else { throw .instanceChanged }
            // The server replaces the enforcement whole, so every lever becomes what was sent.
            state.leversSent.append(levers)
            state.sourceLimit = levers
            return levers
        }
    }

    func webhooks() async throws(OwnerFailure) -> [OwnerWebhook] {
        try enter("webhooks")
        await held("webhooks")
        return state.withLock { $0.webhooks }
    }

    func webhook(_ id: String) async throws(OwnerFailure) -> OwnerWebhook {
        try enter("getWebhook")
        return try state.withLock { state throws(OwnerFailure) in
            guard let webhook = state.webhooks.first(where: { $0.id == id }) else { throw .notFound }
            return webhook
        }
    }

    func create(_ webhook: NewWebhook) async throws(OwnerFailure) -> CreatedWebhook {
        let failure = state.withLock { state in
            state.calls.append("createWebhook")
            return state.failures["createWebhook"]
        }
        await held("createWebhook")
        if let failure { throw failure }
        return state.withLock { state in
            state.webhooksMade.append(webhook)
            let made = OwnerWebhook(
                id: "hook-\(state.webhooks.count + 1)", url: webhook.url, events: webhook.events, typeFilter: webhook.typeFilter,
                secretTail: "8f2c", active: true, created: .now,
                maker: .init(kind: .app, id: "maker", name: "Marfa for Mac"))
            state.webhooks.append(made)
            return CreatedWebhook(webhook: made, secret: "whsec_3fKq8Vn2Lp7Xr1Tz9Bm4Yc6Wd0Hs5Ja2e7b91c4d60a38f5e1b9c2d7a4f08e63b15d9c0a7e24f")
        }
    }

    func change(webhook id: String, _ change: WebhookChange) async throws(OwnerFailure) -> OwnerWebhook {
        try enter("changeWebhook")
        return try state.withLock { state throws(OwnerFailure) in
            guard let index = state.webhooks.firstIndex(where: { $0.id == id }) else { throw .notFound }
            state.webhookChanges.append((id, change))
            if let url = change.url { state.webhooks[index].url = url }
            if let events = change.events { state.webhooks[index].events = events }
            if let filter = change.typeFilter { state.webhooks[index].typeFilter = filter }
            if let active = change.active { state.webhooks[index].active = active }
            var answered = state.webhooks[index]
            answered.maker = nil
            return answered
        }
    }

    func delete(webhook id: String) async throws(OwnerFailure) {
        try enter("deleteWebhook")
        try state.withLock { state throws(OwnerFailure) in
            guard state.webhooks.contains(where: { $0.id == id }) else { throw .notFound }
            state.webhooks.removeAll { $0.id == id }
        }
    }

    func deliveries(of webhook: String, limit: Int) async throws(OwnerFailure) -> [WebhookDeliveryInfo] {
        let answer = state.withLock { state -> Result<[WebhookDeliveryInfo], OwnerFailure> in
            state.calls.append("deliveries")
            if let failure = state.failures["deliveries"] { return .failure(failure) }
            return .success(Array((state.deliveries[webhook] ?? []).prefix(limit)))
        }
        await held("deliveries")
        await counted()
        return try answer.get()
    }

    func redeliver(_ delivery: String, of webhook: String) async throws(OwnerFailure) -> WebhookDeliveryInfo {
        try enter("redeliver")
        return try state.withLock { state throws(OwnerFailure) in
            guard let hook = state.webhooks.first(where: { $0.id == webhook }) else { throw .notFound }
            guard let index = state.deliveries[webhook]?.firstIndex(where: { $0.id == delivery }) else { throw .notFound }
            guard hook.active else { throw .redeliveryRefused(.webhookInactive) }
            guard state.deliveries[webhook]?[index].status == .failed else { throw .redeliveryRefused(.deliveryNotFailed) }
            state.redelivered.append(delivery)
            state.deliveries[webhook]?[index].status = .pending
            return state.deliveries[webhook]![index]
        }
    }

    func health() async throws(OwnerFailure) -> ServerHealth {
        try enter("health")
        guard let health = state.withLock({ $0.health }) else { throw .unreachable }
        return health
    }

    func upkeepSettings() async throws(OwnerFailure) -> UpkeepSettings {
        try enter("upkeepSettings")
        await held("upkeepSettings")
        return state.withLock { $0.upkeep }
    }

    func change(_ settings: UpkeepSettings, _ change: UpkeepSettingsChange) async throws(OwnerFailure) -> UpkeepSettings {
        try enter("changeUpkeep")
        return state.withLock { state in
            state.upkeepChanges.append(change)
            switch change.folder {
            case .set(let path)?: state.upkeep.folder = path
            case .remove?: state.upkeep.folder = nil
            case nil: break
            }
            if let seconds = change.intervalSeconds { state.upkeep.intervalSeconds = seconds }
            if let on = change.checksForUpdates { state.upkeep.checksForUpdates = on }
            return state.upkeep
        }
    }

    func backups() async throws(OwnerFailure) -> [BackupRecord] {
        try enter("backups")
        return state.withLock { $0.backups }
    }

    func backUpNow() async throws(OwnerFailure) -> BackupTaken {
        try enter("backUpNow")
        return state.withLock { state in
            state.backupsTaken += 1
            let taken = Date.now
            state.backups.insert(BackupRecord(instanceID: "instance-1", name: "now-\(state.backupsTaken).json", taken: taken, bytes: 1_000), at: 0)
            return BackupTaken(taken: taken, filesLost: 0, filesWaiting: 0)
        }
    }

    func restore(_ backup: BackupRecord) async throws(OwnerFailure) -> BackupRestored {
        try enter("restore")
        return state.withLock { state in
            state.restores.append(backup)
            return state.restoreAnswer
        }
    }

    func updateStatus() async throws(OwnerFailure) -> UpdateStatus {
        await held("updateStatus")
        try enter("updateStatus")
        return state.withLock { state in
            if !state.updateReads.isEmpty { state.update = state.updateReads.count > 1 ? state.updateReads.removeFirst() : state.updateReads[0] }
            return state.update
        }
    }

    func checkForUpdates() async throws(OwnerFailure) -> UpdateStatus {
        try enter("checkForUpdates")
        return state.withLock { state in
            state.updatesChecked += 1
            return state.update
        }
    }

    func startUpdate() async throws(OwnerFailure) -> UpdateStatus {
        try enter("startUpdate")
        return state.withLock { state in
            state.updatesStarted += 1
            state.update.progress = UpdateProgress(stage: .fetching, release: state.update.latest?.version)
            return state.update
        }
    }

    func housekeepingJobs() async throws(OwnerFailure) -> [HousekeepingJob] {
        try enter("housekeepingJobs")
        return state.withLock { $0.jobs }
    }

    func confirmClock() async throws(OwnerFailure) -> Date? {
        try enter("confirmClock")
        return state.withLock { state in
            state.clocksConfirmed += 1
            return state.clockConfirmedAt
        }
    }

    func folders() async throws(OwnerFailure) -> FolderListing {
        try enter("folders")
        return state.withLock { FolderListing(folders: $0.folders, total: $0.foldersTotal ?? $0.folders.count) }
    }

    func folderReport(_ id: String) async throws(OwnerFailure) -> FolderReport {
        try enter("folderReport")
        await held("folderReports")
        await counted()
        return try state.withLock { state throws(OwnerFailure) in
            guard let report = state.reports[id] else { throw .notFound }
            return report
        }
    }

    func connectorPlugins() async throws(OwnerFailure) -> [PluginConnectorSummary] {
        try enter("connectorPlugins")
        await held("connectorPlugins")
        return state.withLock { $0.connectorPlugins }
    }

    func connectorControl(of plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try enter("connectorControl")
        let control = state.withLock { $0.connectorControls[plugin] }
        // Held after the read, so a held read answers what the server held when it began.
        await held("connectorControl")
        guard let control else { throw .notFound }
        return control
    }

    func connectorRegistration(_ id: String) async throws(OwnerFailure) -> ConnectorRegistration {
        try enter("connectorRegistration")
        return try state.withLock { state throws(OwnerFailure) in
            guard let registration = state.connectorRegistrations[id] else { throw .notFound }
            return registration
        }
    }

    func connectorHosts() async throws(OwnerFailure) -> [ConnectorHostInfo] {
        try enter("connectorHosts")
        return state.withLock { $0.connectorHosts }
    }

    func connectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostInfo {
        try enter("connectorHost")
        return try state.withLock { state throws(OwnerFailure) in
            guard var host = state.connectorHosts.first(where: { $0.id == id }) else { throw .notFound }
            host.connectors = state.connectorControls.filter { $0.value.host == id }.keys.sorted()
            return host
        }
    }

    private static func link(for host: ConnectorHostInfo, _ count: Int) -> ConnectorHostLink {
        ConnectorHostLink(host: host, link: "https://marfa.castell.studio/connect#code-\(count)", expires: .now.addingTimeInterval(900))
    }

    func createConnectorHost(named name: String) async throws(OwnerFailure) -> ConnectorHostLink {
        try enter("createConnectorHost")
        await held("createConnectorHost")
        return state.withLock { state in
            state.linksMade += 1
            let host = ConnectorHostInfo(id: "host-\(state.hostsMade.count + 1)", name: name, lastSeen: nil, linked: false)
            state.hostsMade.append(name)
            state.connectorHosts.append(host)
            return Self.link(for: host, state.linksMade)
        }
    }

    func linkConnectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostLink {
        try enter("linkConnectorHost")
        return try state.withLock { state throws(OwnerFailure) in
            guard let host = state.connectorHosts.first(where: { $0.id == id }) else { throw .notFound }
            state.linksMade += 1
            return Self.link(for: host, state.linksMade)
        }
    }

    func connectorSettings(of plugin: String) async throws(OwnerFailure) -> ConnectorSettingsReading {
        try enter("connectorSettings")
        return try state.withLock { state throws(OwnerFailure) in
            guard let reading = state.connectorSettings[plugin] else { throw .notFound }
            return reading
        }
    }

    /// Applies each change as the server does: a value is set, `null` takes it away, and `missing` names each required
    /// setting left with no value and no default.
    func changeConnectorSettings(of plugin: String, _ changes: [String: ConnectorSettingChange]) async throws(OwnerFailure) -> ConnectorSettingsReading {
        try enter("changeConnectorSettings")
        await held("changeConnectorSettings")
        return try state.withLock { state throws(OwnerFailure) in
            state.connectorSettingsSent.append((plugin, changes))
            guard var reading = state.connectorSettings[plugin] else { throw .notFound }
            for (name, change) in changes {
                guard let index = reading.settings.firstIndex(where: { $0.name == name }) else { throw .refused("No such setting.") }
                switch change {
                case .set(let value):
                    reading.settings[index].isSet = true
                    reading.settings[index].value = reading.settings[index].secret ? nil : value
                case .clear:
                    reading.settings[index].isSet = false
                    reading.settings[index].value = reading.settings[index].defaultValue
                }
            }
            reading.missing = reading.settings.filter { $0.required && !$0.isSet && $0.defaultValue == nil }.map(\.name)
            state.connectorSettings[plugin] = reading
            return reading
        }
    }

    private func controlled(_ plugin: String, _ call: String, _ change: (inout ConnectorControl) throws(OwnerFailure) -> Void) async throws(OwnerFailure) -> ConnectorControl {
        try enter(call)
        return try state.withLock { state throws(OwnerFailure) in
            guard var control = state.connectorControls[plugin] else { throw .notFound }
            try change(&control)
            state.connectorControls[plugin] = control
            return control
        }
    }

    func pauseConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await controlled(plugin, "pauseConnector") { control throws(OwnerFailure) in
            control.paused = true
            control.runRequested = nil
        }
    }

    func resumeConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await controlled(plugin, "resumeConnector") { control throws(OwnerFailure) in control.paused = false }
    }

    func runConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await controlled(plugin, "runConnector") { control throws(OwnerFailure) in
            if control.paused { throw .connectorPaused }
            control.runRequested = .now
        }
    }

    func assignConnector(_ plugin: String, toHost host: String?) async throws(OwnerFailure) {
        try enter("assignConnector")
        try state.withLock { state throws(OwnerFailure) in
            guard var control = state.connectorControls[plugin] else { throw .notFound }
            state.connectorAssigned.append((plugin, host))
            control.host = host
            state.connectorControls[plugin] = control
            if let lost = state.assignAnswerLost {
                state.assignAnswerLost = nil
                throw lost
            }
        }
    }

    func startConnectorSignIn(of plugin: String, returningTo address: String) async throws(OwnerFailure) -> ConnectorSignInStart {
        try enter("startConnectorSignIn")
        return state.withLock { state in
            state.signInReturnedTo.append(address)
            return state.signInStart
        }
    }

    func connectorSignInStatus(of plugin: String) async throws(OwnerFailure) -> ConnectorSignInReading {
        try enter("connectorSignInStatus")
        return state.withLock { state in
            if state.signInStatus == .signedIn, let token = state.signInSetsToken, var reading = state.connectorSettings[token.plugin],
                let index = reading.settings.firstIndex(where: { $0.name == token.setting })
            {
                reading.settings[index].isSet = true
                state.connectorSettings[token.plugin] = reading
            }
            return ConnectorSignInReading(status: state.signInStatus, id: state.signInReadID ?? state.signInStart.id)
        }
    }

    // MARK: A connector's mapping

    func connectorMapping(of plugin: String) async throws(OwnerFailure) -> ConnectorMappingReading {
        try enter("connectorMapping")
        return try state.withLock { state throws(OwnerFailure) in
            guard let mapping = state.mappings[plugin] else { throw .notFound }
            return mapping
        }
    }

    /// Judges a save as the server does: the version must be current, and a kind landing on a type with a required field that
    /// nothing fills is refused, naming the field.
    func saveConnectorMapping(of plugin: String, version: Int, kinds: [String: KindMapping]) async throws(OwnerFailure) -> MappingSaveOutcome {
        try enter("saveConnectorMapping")
        await held("saveConnectorMapping")
        return try state.withLock { state throws(OwnerFailure) in
            state.mappingSaves.append((plugin, version, kinds))
            guard var mapping = state.mappings[plugin] else { throw .notFound }
            if version != mapping.version { return .stale(current: mapping.version) }
            if let faults = state.scriptedMappingFaults { return .refused(faults) }
            var faults: [MappingFault] = []
            for (name, kind) in kinds where kind.enabled {
                for field in state.mappingTypes[kind.targetType]?.fields ?? [] where field.required && kind.fields[field.name] == nil {
                    faults.append(MappingFault(path: "kinds.\(name).fields.\(field.name)", message: "\(kind.targetType) requires \(field.name)."))
                }
            }
            if !faults.isEmpty { return .refused(faults) }
            mapping.version += 1
            mapping.kinds = kinds
            state.mappings[plugin] = mapping
            return .saved(mapping)
        }
    }

    func startMappingPreview(of plugin: String, kind: String, draft: KindMapping?) async throws(OwnerFailure) -> MappingPreview {
        try enter("startMappingPreview")
        return state.withLock { state in
            state.previewsAsked.append((kind, draft))
            let expires = Date.now.addingTimeInterval(state.previewLife)
            return MappingPreview(id: "preview-\(state.previewsAsked.count)", status: state.previewStart ?? .pending, expires: expires)
        }
    }

    func mappingPreview(of plugin: String, id: String) async throws(OwnerFailure) -> MappingPreview {
        try enter("mappingPreview")
        await held("mappingPreview")
        if let failure = state.withLock({ $0.previewFailureAfterWait }) { throw failure }
        return state.withLock { state in
            let index = min(state.previewReads, max(state.previewAnswers.count - 1, 0))
            state.previewReads += 1
            let status = state.previewAnswers.isEmpty ? MappingPreviewStatus.pending : state.previewAnswers[index]
            return MappingPreview(id: id, status: status, expires: .now.addingTimeInterval(state.previewLife))
        }
    }

    func rewriteConnectorItems(of plugin: String, kinds: [String], dryRun: Bool) async throws(OwnerFailure) -> MappingRewrite {
        try enter("rewriteConnectorItems")
        await held("rewriteConnectorItems")
        if let failure = state.withLock({ $0.failures["rewriteConnectorItems"] }) { throw failure }
        return state.withLock { state in
            state.rewritesAsked.append((kinds, dryRun))
            let version = state.mappings[plugin]?.version ?? 0
            if !dryRun, var mapping = state.mappings[plugin] {
                mapping.rewrites.append(PendingRewrite(number: mapping.rewrites.count + 1, kinds: kinds, requested: .now))
                state.mappings[plugin] = mapping
            }
            return MappingRewrite(
                dryRun: dryRun, number: dryRun ? nil : version,
                version: version,
                kinds: Dictionary(uniqueKeysWithValues: kinds.map { kind in
                    (kind, .init(targetType: state.mappings[plugin]?.kinds[kind]?.targetType ?? "", count: state.rewriteCounts[kind] ?? 0))
                }))
        }
    }

    func mappingTypeOptions() async throws(OwnerFailure) -> [MappingTypeOption] {
        try enter("mappingTypeOptions")
        return state.withLock { $0.mappingTypes.values.map { MappingTypeOption(id: $0.id, label: $0.label, parent: nil) }.sorted { $0.id < $1.id } }
    }

    func mappingType(_ id: String) async throws(OwnerFailure) -> MappingTypeInfo {
        try enter("mappingType")
        return try state.withLock { state throws(OwnerFailure) in
            guard let type = state.mappingTypes[id] else { throw .notFound }
            return type
        }
    }

    func linkTypes() async throws(OwnerFailure) -> LinkTypeListing {
        try enter("linkTypes")
        return state.withLock { LinkTypeListing(linkTypes: $0.linkTypes, typeNames: $0.linkTypeNames) }
    }

    func register(_ linkType: NewLinkType) async throws(OwnerFailure) -> OwnerLinkType {
        try enter("registerLinkType")
        await held("registerLinkType")
        return state.withLock { state in
            state.linkTypesMade.append(linkType)
            let made = OwnerLinkType(
                id: linkType.id, label: linkType.label, reverseLabel: linkType.reverseLabel ?? linkType.label, cardinality: linkType.cardinality,
                fromTypes: linkType.fromTypes, toTypes: linkType.toTypes, shipped: false)
            state.linkTypes.append(made)
            return made
        }
    }

    func deleteLinkType(_ id: String) async throws(OwnerFailure) -> LinkTypeDeletion {
        try enter("deleteLinkType")
        return state.withLock { state in
            guard state.linkTypes.contains(where: { $0.id == id }) else { return .gone }
            if state.linkTypesInUse.contains(id) { return .inUse }
            state.linkTypes.removeAll { $0.id == id }
            return .deleted
        }
    }
}

/// What a context lends a model in a test, with the grants it holds and what Allow More… answers.
@MainActor final class OwnerBench {
    let calls = FakeOwnerCalls()
    var grants: Set<InstancePermission>
    var allowing: MarfaAllowMoreOutcome = .allowed
    /// The scopes beyond the owner's permissions the sign-in holds, and those an approval gives.
    var scopes: Set<String> = []
    var scopesApproved: Set<String> = []
    var asked: [Set<InstancePermission>] = []
    var refreshed = 0
    /// What a page handed over after Settings had closed.
    var late: [OwnerDraft] = []

    init(grants: Set<InstancePermission> = [.signInsManage, .grantsManage, .keysManage, .keysMint, .configManage, .webhooksManage]) {
        self.grants = grants
    }

    var context: OwnerContext {
        OwnerContext(
            calls: calls, grants: { [unowned self] in grants }, holds: { [unowned self] in scopes.contains($0) },
            allowMore: { [unowned self] permissions in
                asked.append(permissions)
                if allowing == .allowed { grants.formUnion(permissions) }
                if allowing == .allowed || allowing == .approvedFewer { scopes = scopesApproved }
                return allowing
            },
            refreshGrants: { [unowned self] in refreshed += 1 },
            lateDraft: { [unowned self] in late.append($0) })
    }
}

@MainActor
@Suite(.hangLimit) struct AccountModelTests {
    private func model(_ bench: OwnerBench) -> AccountModel { AccountModel(context: bench.context) }

    /// Signs a browser out the way the page does: it asks, and the owner agrees.
    private func signOut(_ account: AccountModel, _ browser: BrowserSignIn) async {
        account.askToEnd(browser)
        if let question = account.question { await account.confirm(question) }
    }

    @Test func theProfileIsShownAsTheServerHoldsIt() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        #expect(account.profile == OwnerProfile(username: "mira", emailIsReadable: true, email: nil))
        #expect(account.failure == nil)
    }

    @Test func aWrongCurrentPasswordKeepsWhatWasTypedWithOneLine() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        account.currentPassword = "not the password"
        account.newPassword = "a new password"
        await account.changePassword()
        #expect(account.currentPasswordError == "That isn’t your current password.")
        #expect(account.currentPassword == "not the password")
        #expect(account.newPassword == "a new password")
        #expect(account.sheet == .password)
        #expect(!account.passwordChanged)
    }

    @Test func aNewPasswordTheServerRefusesKeepsWhatWasTypedWithItsReason() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        account.currentPassword = "old password"
        account.newPassword = String(repeating: "x", count: 129)
        #expect(!account.isNewPasswordLongEnough)
        #expect(!account.canChangePassword, "a password outside 8 to 128 characters is never sent")
        account.newPassword = "short"
        #expect(!account.canChangePassword)
        #expect(!bench.calls.calls.contains("changePassword"))
    }

    @Test func aChangedPasswordEndsTheBrowsersAndIsNeverKept() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari on macOS")] }
        let account = model(bench)
        await account.load()
        #expect(account.browsers.count == 1)
        await account.beginChangePassword()
        account.currentPassword = "old password"
        account.newPassword = "a new password"
        await account.changePassword()
        #expect(account.passwordChanged)
        #expect(account.currentPassword.isEmpty && account.newPassword.isEmpty)
        #expect(account.browsers.isEmpty)
        account.closePasswordSheet()
        #expect(account.sheet == nil)
        #expect(!account.passwordChanged)
    }

    @Test func signInsManageIsAskedForFromChangePasswordAndThenTheSheetOpens() async {
        let bench = OwnerBench(grants: [])
        let account = model(bench)
        await account.load()
        #expect(bench.calls.calls == ["profile"], "the sign-ins are not read without the permission")
        #expect(!account.canManageSignIns)
        await account.beginChangePassword()
        #expect(bench.asked == [[.signInsManage]])
        #expect(account.sheet == .password)
        #expect(bench.calls.calls.contains("passkeys"), "the lists are read once it is held")
    }

    @Test func thePasswordSheetStaysClosedWhenTheReloadAfterApprovalIsSignedOut() async {
        let bench = OwnerBench(grants: [])
        let account = model(bench)
        await account.load()
        bench.calls.fail("profile", with: .signedOut)
        await account.beginChangePassword()
        #expect(bench.asked == [[.signInsManage]])
        #expect(account.gateFailure == .signedOut)
        #expect(account.sheet == nil)
    }

    @Test func allowMoreCancelledOpensNothingAndChangesNothing() async {
        let bench = OwnerBench(grants: [])
        bench.allowing = .cancelled
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        #expect(account.sheet == nil)
        #expect(account.note == nil)
        #expect(!account.canManageSignIns)
    }

    @Test func anApprovalWithoutThePermissionSaysSo() async {
        let bench = OwnerBench(grants: [])
        bench.allowing = .approvedFewer
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        #expect(account.sheet == nil)
        #expect(account.note?.contains("manage the owner’s sign-ins and passkeys") == true)
    }

    @Test func aWriteTheServerRefusesForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari")] }
        let account = model(bench)
        await account.load()
        bench.calls.fail("endSignIn", with: .notPermitted("sign_ins.manage"))
        await signOut(account, account.browsers[0])
        #expect(account.rowErrors["b"] == .notPermitted("sign_ins.manage"))
        #expect(account.browsers.count == 1)
        #expect(bench.refreshed == 1, "the grants held can be stale, so they are read again")
    }

    @Test func aPasskeyRenameTypedWhenSettingsClosesIsHandedBack() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "Phone")] }
        let account = model(bench)
        let drafts = OwnerDrafts()
        drafts.register(account)
        await account.load()
        account.beginRename(account.passkeys[0])
        #expect(drafts.takeAll().isEmpty, "a name left as it was is nothing to keep")
        account.beginRename(account.passkeys[0])
        account.renameDraft = " Work phone "
        #expect(drafts.takeAll() == [.typed(title: "Passkey Not Renamed", text: "Work phone")])
        #expect(account.sheet == nil)
        #expect(drafts.takeAll().isEmpty, "what was handed back is not handed back twice")
    }

    @Test func aPasswordTypedWhenSettingsClosesIsDroppedAndNeverHandedBack() async {
        let bench = OwnerBench()
        let account = model(bench)
        let drafts = OwnerDrafts()
        drafts.register(account)
        await account.load()
        await account.beginChangePassword()
        account.currentPassword = "old password"
        account.newPassword = "a new password"
        #expect(drafts.takeAll().isEmpty)
        #expect(account.currentPassword.isEmpty && account.newPassword.isEmpty)
        #expect(account.sheet == nil)
    }

    @Test func aPasskeyIsRenamedAndRemoved() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "MacBook Pro")] }
        let account = model(bench)
        await account.load()
        account.beginRename(account.passkeys[0])
        account.renameDraft = "Studio Mac"
        await account.rename()
        #expect(account.passkeys[0].name == "Studio Mac")
        #expect(account.sheet == nil)
        account.askToRemove(account.passkeys[0])
        #expect(account.passkeys.count == 1, "nothing is removed before the owner agrees")
        await account.confirm(try #require(account.question))
        #expect(account.passkeys.isEmpty)
    }

    @Test func aRefusedRenameKeepsTheTypedName() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "MacBook Pro")] }
        let account = model(bench)
        await account.load()
        account.beginRename(account.passkeys[0])
        account.renameDraft = "Studio Mac"
        bench.calls.fail("renamePasskey", with: .refused("Use a shorter name."))
        await account.rename()
        #expect(account.renameDraft == "Studio Mac")
        #expect(account.renameError == "Use a shorter name.")
        #expect(account.sheet == .renamePasskey("p"))
    }

    @Test func aSignInThatWasEndedElsewhereLeavesTheList() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari")] }
        let account = model(bench)
        await account.load()
        bench.calls.fail("endSignIn", with: .notFound)
        await signOut(account, account.browsers[0])
        #expect(account.browsers.isEmpty)
        #expect(account.rowErrors["b"] == nil)
    }

    @Test func signingABrowserOutAsksFirstNamingTheBrowser() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari on macOS")] }
        let account = model(bench)
        await account.load()
        account.askToEnd(account.browsers[0])
        let question = try #require(account.question)
        #expect(question.title == "Sign Out “Safari on macOS”?")
        #expect(!bench.calls.calls.contains("endSignIn"), "nothing is sent before the owner agrees")
        account.cancelQuestion()
        #expect(account.question == nil)
        #expect(account.browsers.count == 1)
        await account.confirm(question)
        #expect(bench.calls.calls.contains("endSignIn"))
        #expect(account.browsers.isEmpty)
    }

    @Test func aServerThatDoesNotAnswerIsTheWholePage() async {
        let bench = OwnerBench()
        bench.calls.fail("profile", with: .unreachable)
        let account = model(bench)
        await account.load()
        #expect(account.failure == .unreachable)
        #expect(account.hasLoaded)
    }

    @Test func addingAPasskeyOpensTheServersOwnAddress() async {
        let bench = OwnerBench()
        let account = model(bench)
        #expect(await account.passkeyAddress() == URL(string: "https://marfa.test/passkeys/add"))
        bench.calls.fail("passkeyAddAddress", with: .notPermitted("sign_ins.manage"))
        #expect(await account.passkeyAddress() == nil)
        #expect(account.note != nil)
    }

    @Test func theLinesUnderAPasskeySayWhenItWasAddedAndUsed() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let line = AccountSignInsPage.line(added: now.addingTimeInterval(-86_400 * 40), used: now, now: now, calendar: calendar)
        #expect(line.hasPrefix("Added "))
        #expect(line.hasSuffix("Used today."))
        #expect(AccountSignInsPage.line(added: nil, used: nil, now: now, calendar: calendar) == "Never used.")
    }
}

@MainActor
@Suite(.hangLimit) struct AppsModelTests {
    private func app(scopes: [String] = ["*:read", "*:write", "core.note:read", "keys.manage"]) -> AppAccess {
        AppAccess(id: "g1", clientID: "raycast", kind: .app, name: "Raycast", origins: [], scopes: scopes, granted: nil, lastUsed: nil)
    }

    private func bench(_ app: AppAccess) -> OwnerBench {
        let bench = OwnerBench()
        bench.grants.insert(.itemsPurge)
        bench.calls.state.withLock {
            $0.apps = [app]
            $0.names = ["core.note": "Note"]
        }
        return bench
    }

    @Test func disconnectWithoutPurgePermissionKeepsTheAppsData() async throws {
        var app = app()
        app.vendors = ["app.raycast"]
        let bench = bench(app)
        bench.grants.remove(.itemsPurge)
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(app)
        let question = try #require(model.question)
        #expect(question.checkbox == nil)
        await model.confirm(question)
        #expect(bench.calls.state.withLock { $0.disconnects.first?.removingData } == false)
    }

    @Test func anOAuthSignInUsesTheServerVerifiedClientID() async {
        var current = app()
        current.vendors = ["app.raycast"]
        let bench = bench(current)
        bench.calls.state.withLock {
            $0.appData["app.raycast"] = AppData(vendor: "app.raycast", types: [], clientID: current.clientID)
        }
        let model = AppsModel(context: bench.context, ownVendor: "app.raycast")
        await model.load()
        #expect(model.isCurrent(current))
        model.askToDisconnect(current)
        #expect(model.question?.message.contains("Disconnecting this app also signs this Mac out.") == true)

        bench.calls.state.withLock { $0.identity = OwnIdentity(keyID: "key-1", expires: nil) }
        await model.load()
        #expect(!model.isCurrent(current), "a key can read the namespace without using the app's grant to sign in")
    }

    @Test func narrowingAsksFirstAndSendsTheAccessItWasReadAs() async throws {
        let read = app()
        let bench = bench(read)
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .read)
        let question = try #require(model.question)
        #expect(question.title == "Narrow Raycast’s access?")
        #expect(bench.calls.state.withLock { $0.narrowed.isEmpty }, "nothing is sent before the owner agrees")
        await model.confirm(question)
        let sent = bench.calls.state.withLock { $0.narrowed }
        #expect(sent.first?.app.scopes == read.scopes, "the version read goes with the change")
        #expect(sent.first?.scopes == ["*:read", "core.note:read", "keys.manage"])
        #expect(model.apps[0].scopes == ["*:read", "core.note:read", "keys.manage"])
    }

    @Test func aCancelledNarrowingSendsNothing() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .none)
        model.cancelQuestion()
        #expect(model.question == nil)
        #expect(!bench.calls.calls.contains("narrow"))
    }

    @Test func nothingIsAskedWhereNothingWouldChange() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .write)
        #expect(model.question == nil)
    }

    @Test func aChangeMadeElsewhereIsToldAndTheAccessIsReadAgain() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .read)
        let question = try #require(model.question)
        bench.calls.state.withLock { $0.apps[0].scopes = ["core.note:read"] }
        await model.confirm(question)
        #expect(model.rowErrors["g1"] == .conflict)
        #expect(model.apps[0].scopes == ["core.note:read"], "what the server holds is what shows")
    }

    @Test func aPermissionIsRemovedByNarrowing() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemove(permission: "keys.manage", from: model.apps[0])
        await model.confirm(try #require(model.question))
        #expect(model.apps[0].scopes == ["*:read", "*:write", "core.note:read"])
    }

    @Test func disconnectingAsksFirstAndSaysItsKeysStay() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(model.apps[0])
        let question = try #require(model.question)
        #expect(question.message.contains("The keys it made keep working."))
        #expect(question.message.contains("Its webhooks are deleted."))
        #expect(!bench.calls.calls.contains("disconnect"))
        await model.confirm(question)
        #expect(model.apps.isEmpty)
        #expect(model.disconnected == "g1")
    }

    private func kept(_ vendor: String = "app.raycast", active: Int = 10, archived: Int = 1, trashed: Int = 2) -> AppData {
        AppData(vendor: vendor, types: [AppData.Kind(type: vendor + ".setting", active: active, archived: archived, trashed: trashed)])
    }

    private func bench(keeping vendors: [String: AppData]) -> OwnerBench {
        var holder = app()
        holder.vendors = vendors.keys.sorted()
        let bench = bench(holder)
        bench.calls.state.withLock { $0.appData = vendors }
        return bench
    }

    @Test func whatAnAppKeepsIsCountedByStateAndNeverSized() async {
        let bench = bench(keeping: ["app.raycast": kept()])
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        guard case .kept(let held)? = model.data["g1"] else {
            Issue.record("the data was not read")
            return
        }
        #expect(held.first?.total == 13)
        let line = AppDataWording.line(held[0], appName: "Raycast", keptByApp: false)
        #expect(line.contains("10 active") && line.contains("1 archived") && line.contains("2 in the trash"))
        #expect(line.hasSuffix("Only Raycast and you can read it."))
        #expect(!line.contains("KB"), "Marfa answers counts, so no size is told")
    }

    @Test func anAppThatHoldsNoNamespaceIsNotAsked() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        #expect(model.data["g1"] == .kept([]))
        #expect(!bench.calls.calls.contains("appData"))
    }

    @Test func removingDataAsksFirstAndShowsNothingLeft() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        let question = try #require(model.question)
        #expect(bench.calls.state.withLock { $0.dataRemoved.isEmpty }, "nothing is deleted before the owner agrees")
        await model.confirm(question)
        #expect(bench.calls.state.withLock { $0.dataRemoved } == ["app.raycast"])
        #expect(model.unfinished["g1"] == nil)
    }

    @Test func aRemovalThatStopsPartWayShowsWhatIsLeftNeverDone() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 1000, remainingItems: 500, stoppedBy: .unreachable)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        #expect(model.unfinished["g1"]?.remainingItems == 500)
        guard case .kept(let held)? = model.data["g1"] else {
            Issue.record("the data was not read again")
            return
        }
        #expect(held.first?.total == 13, "the counts shown are the server's, read again")
    }

    @Test func disconnectingKeepsTheDataUnlessTheBoxIsTicked() async throws {
        for ticked in [false, true] {
            let bench = bench(keeping: ["app.raycast": kept()])
            let model = AppsModel(context: bench.context)
            await model.load()
            await model.readData(of: model.apps[0])
            model.askToDisconnect(model.apps[0])
            let question = try #require(model.question)
            #expect(question.checkbox == "Also remove its data")
            await model.confirm(question, alsoRemovingData: ticked)
            #expect(bench.calls.state.withLock { $0.disconnects.first?.removingData } == ticked)
            #expect(bench.calls.state.withLock { $0.appData["app.raycast"] != nil } == !ticked)
        }
    }

    @Test func anAppWithNoDataIsNotOfferedTheBox() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(model.apps[0])
        #expect(model.question?.checkbox == nil)
    }

    @Test func moreDataThanOneWriteDeletesIsRemovedBeforeTheAppIsDisconnected() async throws {
        let bench = bench(keeping: ["app.raycast": kept(active: 1500)])
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        model.askToDisconnect(model.apps[0])
        await model.confirm(try #require(model.question), alsoRemovingData: true)
        #expect(bench.calls.state.withLock { $0.dataRemoved } == ["app.raycast"])
        #expect(bench.calls.state.withLock { $0.disconnects.count } == 1)
    }

    @Test func aDisconnectThatCannotFinishTheDataStaysConnected() async throws {
        let bench = bench(keeping: ["app.raycast": kept(active: 1500)])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 1000, remainingItems: 513, stoppedBy: .unreachable)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        model.askToDisconnect(model.apps[0])
        await model.confirm(try #require(model.question), alsoRemovingData: true)
        #expect(bench.calls.state.withLock { $0.disconnects.isEmpty }, "an app is not disconnected from data it still has")
        #expect(model.apps.count == 1)
        #expect(model.unfinished["g1"]?.remainingItems == 513)
    }

    @Test func aRemovalThatStopsAndCannotReadAgainSaysItemsWereRemovedNeverNothingChanged() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 1000, remainingItems: 500, stoppedBy: .unreachable)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        bench.calls.fail("appData", with: .unreachable)
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        guard case .failed? = model.data["g1"] else {
            Issue.record("the read should have failed")
            return
        }
        let note = try #require(model.removalNote(for: model.apps[0]))
        #expect(note.title == "Some Data May Be Left")
        #expect(
            note.line
                == "1,000 items were removed. The app lost the server partway through. Some of it may still be there. The app couldn’t read what is left. Remove it again to finish.")
        #expect(!note.line.contains("Nothing was changed"))
    }

    @Test func aRemovalThatStopsAndIsReadAgainDoesNotLeadWithNothingChanged() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 1000, remainingItems: 500, stoppedBy: .conflict)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        let note = try #require(model.removalNote(for: model.apps[0]))
        #expect(
            note.line
                == "1,000 items were removed. It changed somewhere else partway through. Some of it may still be there. Remove it again to finish.")
    }

    @Test func aRemovalThatRemovedNothingStillSaysNothingWasChanged() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 0, remainingItems: 13, stoppedBy: .unreachable)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        let note = try #require(model.removalNote(for: model.apps[0]))
        #expect(note.line == "The app can’t reach the server. Nothing was changed. Some of it is still there. Remove it again to finish.")
    }

    @Test func aDisconnectRefusedAfterTheDataWentSaysTheDataIsGoneAndTheAppIsStillConnected() async throws {
        let bench = bench(keeping: ["app.raycast": kept(active: 1500)])
        let model = AppsModel(context: bench.context)
        await model.load()
        await model.readData(of: model.apps[0])
        model.askToDisconnect(model.apps[0])
        bench.calls.fail("disconnect", with: .unreachable)
        await model.confirm(try #require(model.question), alsoRemovingData: true)
        #expect(bench.calls.state.withLock { $0.dataRemoved } == ["app.raycast"])
        #expect(model.apps.count == 1, "the app is still connected")
        #expect(model.disconnected == nil)
        #expect(model.rowErrors["g1"] == nil, "the row does not say Not Changed beside data that is gone")
        let note = try #require(model.removalNote(for: model.apps[0]))
        #expect(note.title == "Data Removed, Still Connected")
        #expect(
            note.line == "1,503 items were removed. Raycast is still connected. The app lost the server partway through. Disconnect it again to finish.")
        #expect(bench.calls.calls.filter { $0 == "appData" }.count >= 2, "what is left is read again")
    }

    @Test func aNewRemovalClearsWhatTheLastOneSaid() async throws {
        let bench = bench(keeping: ["app.raycast": kept()])
        bench.calls.state.withLock {
            $0.removalAnswer["app.raycast"] = AppDataRemoved(removedItems: 1000, remainingItems: 500, stoppedBy: .unreachable)
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        #expect(model.removalNote(for: model.apps[0]) != nil)
        bench.calls.state.withLock { $0.removalAnswer["app.raycast"] = nil }
        model.askToRemoveData(model.apps[0], vendor: "app.raycast")
        await model.confirm(try #require(model.question))
        #expect(model.removalNote(for: model.apps[0]) == nil)
    }

    @Test func theAppsOwnSettingsAreNeverRemovedFromHere() async throws {
        var own = app()
        own.vendors = ["app.marfa-mac"]
        let bench = bench(own)
        bench.calls.state.withLock { $0.appData["app.marfa-mac"] = kept("app.marfa-mac") }
        let model = AppsModel(context: bench.context, ownVendor: "app.marfa-mac")
        await model.load()
        model.askToRemoveData(model.apps[0], vendor: "app.marfa-mac")
        #expect(model.question == nil)
        model.askToDisconnect(model.apps[0])
        #expect(model.question?.checkbox == nil, "disconnecting never takes this app's settings with it")
        #expect(AppDataWording.line(kept("app.marfa-mac"), appName: "Marfa for Mac", keptByApp: true).contains("Remove them in Connection"))
    }

    @Test func aRefusalForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(model.apps[0])
        bench.calls.fail("disconnect", with: .notPermitted("grants.manage"))
        await model.confirm(try #require(model.question))
        #expect(model.rowErrors["g1"] == .notPermitted("grants.manage"))
        #expect(bench.refreshed == 1)
        #expect(model.apps.count == 1)
    }

    @Test func theKeysAnAppMadeAreListedOnlyWhereKeysCanBeListed() async {
        let bench = bench(app())
        bench.calls.state.withLock {
            $0.keys = [KeyInfo(id: "k", label: "Raycast capture", source: "raycast", permissions: [], tier: .feed, types: [:], appClientID: "raycast")]
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        #expect(model.keysMade["raycast"]?.map(\.label) == ["Raycast capture"])
        bench.grants = [.grantsManage]
        await model.load()
        #expect(model.keysMade.isEmpty)
    }

    @Test func aFailedKeysReadIsToldAndKeepsTheKeysAlreadyRead() async {
        let bench = bench(app())
        let key = KeyInfo(id: "k", label: "Raycast capture", source: "raycast", permissions: [], tier: .feed, types: [:], appClientID: "raycast")
        bench.calls.state.withLock { $0.keys = [key] }
        let model = AppsModel(context: bench.context)
        bench.calls.fail("keys", with: .unreachable)
        await model.load()
        #expect(model.failure == nil)
        #expect(model.keysFailure == .unreachable)
        #expect(model.apps.count == 1)

        bench.calls.fail("keys", with: nil)
        await model.load()
        #expect(model.keysFailure == nil)
        #expect(model.keysMade["raycast"] == [key])

        bench.calls.fail("keys", with: .notPermitted("keys.manage"))
        await model.load()
        #expect(model.keysFailure == .notPermitted("keys.manage"))
        #expect(model.keysMade["raycast"] == [key])
        #expect(bench.refreshed == 1)
    }

    @Test func scopesAreNarrowedAndNeverWidened() {
        let scopes = ["*:read", "*:write", "core.note:read", "keys.manage"]
        #expect(AccessScopes.narrowed(scopes, pattern: "*", to: .read) == ["*:read", "core.note:read", "keys.manage"])
        #expect(AccessScopes.narrowed(scopes, pattern: "*", to: .none) == ["core.note:read", "keys.manage"])
        #expect(AccessScopes.narrowed(scopes, pattern: "core.note", to: .write) == scopes, "a read is never made a write")
        let parsed = AccessScopes.parse(scopes)
        #expect(parsed.entries.map(\.pattern) == ["*", "core.note"])
        #expect(parsed.entries.map(\.level) == [.write, .read])
        #expect(parsed.permissions == ["keys.manage"])
    }

    @Test func narrowingAGrantThatHoldsOnlyAWriteLeavesARead() async throws {
        let scopes = ["core.note:write", "keys.manage"]
        #expect(AccessScopes.narrowed(scopes, pattern: "core.note", to: .read) == ["core.note:read", "keys.manage"])
        #expect(AccessScopes.narrowed(scopes, pattern: "core.note", to: .none) == ["keys.manage"])
        let bench = bench(app(scopes: scopes))
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "core.note", to: .read)
        await model.confirm(try #require(model.question))
        #expect(bench.calls.state.withLock { $0.narrowed.first?.scopes } == ["core.note:read", "keys.manage"], "a read is sent, never nothing")
    }

    @Test func aPatternIsNamedByTheTypeOrByWhatItReaches() {
        let names = ["core.note": "Note"]
        #expect(AccessScopes.title(of: "core.note", names: names) == "Note")
        #expect(AccessScopes.title(of: "*", names: names) == "All Data")
        #expect(AccessScopes.title(of: "core.*", names: names) == "Core Types")
        #expect(AccessScopes.title(of: "aic.ticket.*", names: names) == "Ticket Types")
        #expect(AccessScopes.title(of: "edge.*", names: names) == "All Links")
        #expect(AccessScopes.title(of: "app.mine", names: names) == "app.mine")
    }
}

@MainActor
@Suite(.hangLimit) struct KeysModelTests {
    @Test(arguments: [OwnerFailure.notPermitted("keys.manage"), .unreachable])
    func aFailedRevokeKeepsTheKeyAndExplainsWhy(_ failure: OwnerFailure) async throws {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToRevoke(try #require(model.key("k1")))
        bench.calls.fail("revoke", with: failure)
        await model.confirm(try #require(model.question))
        #expect(model.keys.map(\.id) == ["k1"])
        #expect(model.revoked == nil)
        #expect(model.rowErrors["k1"] == failure)
    }

    @Test func revokingTheCurrentKeySaysItSignsThisMacOut() async throws {
        let bench = bench([key()])
        bench.calls.state.withLock { $0.identity = OwnIdentity(keyID: "k1", expires: nil) }
        let model = KeysModel(context: bench.context)
        await model.load()
        let current = try #require(model.key("k1"))
        #expect(model.isCurrent(current))
        model.askToRevoke(current)
        #expect(model.question?.message.contains("signs this Mac out") == true)
    }

    @Test func anExpiredKeyIsDescribedInThePastTense() {
        let now = Date.now
        #expect(KeysPage.expiryLine(key(expires: now.addingTimeInterval(-60)), now: now).hasPrefix("Expired "))
    }

    @Test func anExpiringKeyRemainsListedOnTheAccountProblemsDestination() async {
        let soon = key(expires: .now.addingTimeInterval(86_400))
        let bench = bench([soon])
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.ownersKeys == [soon])
        #expect(KeysPage.expiryLine(soon).hasPrefix("Expires "))
        let concern = AttentionConcern(kind: .key, reference: soon.id, title: "A key expires tomorrow")
        #expect(concern.repair == .page(.keys))
    }

    @Test func mintGrantsScopedKeyAccessAndManageGrantsExtension() {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        bench.grants = [.grantsManage]
        #expect(!model.canReadKeys)
        bench.grants.insert(.keysMint)
        #expect(model.canReadKeys)
        #expect(!model.canExtend)
        bench.grants.insert(.keysManage)
        #expect(model.canExtend)
    }

    private func key(_ id: String = "k1", expires: Date? = nil, types: [String: AccessLevel] = ["*": .write, "core.note": .read]) -> KeyInfo {
        KeyInfo(id: id, label: "Importer", source: "importer", permissions: ["items.purge"], tier: .feed, types: types, expires: expires, appClientID: nil)
    }

    private func bench(_ keys: [KeyInfo]) -> OwnerBench {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.keys = keys }
        return bench
    }

    @Test func keysAreSplitIntoTheOwnersAndTheAppsAndNewKeyNeedsKeysMint() async {
        let bench = bench([key(), KeyInfo(id: "a", label: "App key", source: "app", permissions: [], tier: .feed, types: [:], appClientID: "raycast")])
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.ownersKeys.map(\.id) == ["k1"])
        #expect(model.appKeys.map(\.id) == ["a"])
        #expect(model.canMake)
        bench.grants.remove(.keysMint)
        #expect(!model.canMake, "listing and revoking are keys.manage, and making a key is a different permission")
    }

    @Test func aRefusedNewKeyKeepsTheSheetsInput() async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        model.draft.exceptions["core.note"] = .write
        bench.calls.fail("create", with: .refused("That source is taken by another key."))
        await model.make()
        #expect(model.draftError == "That source is taken by another key.")
        #expect(model.draft.name == "Lisbon zine importer")
        #expect(model.draft.exceptions == ["core.note": .write])
        #expect(model.sheet == .new)
        #expect(model.created == nil)
    }

    @Test func aMadeKeyIsShownOnceAndDroppedWhenTheSheetCloses() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        model.draft.permissions = ["items.purge"]
        await model.make()
        #expect(model.sheet == .shown)
        #expect(model.created?.secret == "marfa_k1_secret")
        let sent = try #require(bench.calls.state.withLock { $0.created.first })
        #expect(sent.types == ["*": .read])
        #expect(sent.permissions == ["items.purge"])
        #expect(sent.expires != nil, "a new key expires in 90 days unless the owner says otherwise")
        #expect(model.keys.map(\.label) == ["Lisbon zine importer"])
        model.closeSheet()
        #expect(model.created == nil)
        #expect(model.sheet == nil)
    }

    @Test func theSourceFollowsTheNameUntilItIsChanged() {
        #expect(KeysModel.source(from: "Lisbon zine importer!") == "lisbon-zine-importer")
        #expect(KeysModel.source(from: "  ") == "")
    }

    @Test func aKeyIsOnlyNarrowed() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.keys[0], pattern: "core.note", to: .write)
        #expect(model.question == nil, "a wider level is never asked or sent")
        #expect(bench.calls.state.withLock { $0.changes.isEmpty })
    }

    @Test func narrowingAKeyAsksFirstNamingTheChangeAndSaysItCantBeUndone() async throws {
        let bench = bench([key()])
        bench.calls.state.withLock { $0.names = ["core.note": "Note"] }
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.keys[0], pattern: "*", to: .read)
        let question = try #require(model.question)
        #expect(question.title == "Narrow “Importer”?")
        #expect(question.message.contains("All Data goes from Read and Edit to Read Only."))
        #expect(question.message.contains("can’t be undone"))
        #expect(bench.calls.state.withLock { $0.changes.isEmpty }, "nothing is sent before the owner agrees")
        model.cancelQuestion()
        #expect(model.keys[0].types["*"] == .write, "Cancel leaves the key as it was")
        await model.confirm(question)
        let sent = bench.calls.state.withLock { $0.changes }
        #expect(sent.first?.change.types == ["*": .read, "core.note": .read])
        #expect(model.keys[0].types["*"] == .read)
    }

    @Test func narrowingAKeyHoldingOnlyAWriteSendsARead() async throws {
        let bench = bench([key(types: ["core.note": .write])])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.keys[0], pattern: "core.note", to: .read)
        await model.confirm(try #require(model.question))
        #expect(bench.calls.state.withLock { $0.changes.first?.change.types } == ["core.note": .read])
    }

    @Test func removingAKeysPermissionAsksFirstAndSaysItCantBeUndone() async throws {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToRemove(permission: "items.purge", from: model.keys[0])
        let question = try #require(model.question)
        #expect(question.title == "Remove “Permanently Delete” from “Importer”?")
        #expect(question.message.contains("can’t be undone"))
        #expect(bench.calls.state.withLock { $0.changes.isEmpty }, "nothing is sent before the owner agrees")
        model.cancelQuestion()
        #expect(model.keys[0].permissions == ["items.purge"])
        await model.confirm(question)
        #expect(bench.calls.state.withLock { $0.changes.first?.change.permissions } == [])
        #expect(model.keys[0].permissions.isEmpty)
    }

    @Test func ownerPermissionsAreCountedNeverAllOrNothing() {
        #expect(OwnerWording.permissionCount(0, of: 14) == "None")
        #expect(OwnerWording.permissionCount(3, of: 14) == "3 of 14")
        #expect(OwnerWording.permissionCount(14, of: 14) == "14 of 14")
    }

    @Test func theOwnerPermissionsOfAKeyAndAnAppAreASubpageOfTheirOwn() {
        let key = KeysPage.subpage(for: key())
        let page = OwnerPermissions.subpage(of: key)
        #expect(page != key)
        let found = OwnerPermissions.owner(of: String(page.id.dropFirst(4)))
        #expect(found.isList)
        #expect("key:" + found.base == key.id)
        #expect(!OwnerPermissions.owner(of: String(key.id.dropFirst(4))).isList)
        #expect(OwnerPermissions.owner(of: "g2").base == "g2")
    }

    @Test func escapeInNewKeysPermissionsGoesBackToItsFieldsKeepingWhatWasChosen() {
        let model = KeysModel(context: bench([]).context)
        model.beginNewKey()
        model.draft.name = "Importer"
        model.draft.permissions = ["items.purge"]
        model.isChoosingPermissions = true
        model.dismissSheet()
        #expect(model.sheet == .new && !model.isChoosingPermissions)
        #expect(model.draft.permissions == ["items.purge"] && model.draft.name == "Importer")
        model.dismissSheet()
        #expect(model.sheet == nil)
    }

    @Test func aNewKeyStartsOnItsFieldsEvenAfterPermissionsWereOpen() {
        let model = KeysModel(context: bench([]).context)
        model.beginNewKey()
        model.isChoosingPermissions = true
        model.closeSheet()
        model.beginNewKey()
        #expect(!model.isChoosingPermissions)
    }

    @Test func aNewKeyRefusedForItsSourceSaysSoOnTheSourceField() async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        bench.calls.fail("create", with: .sourceHeld("Another key already has this source."))
        await model.make()
        #expect(model.sourceError == "Another key already has this source.")
        #expect(model.draftError == nil)
        #expect(model.draft.source == "lisbon-zine")
        #expect(model.sheet == .new)
    }

    @Test(arguments: [
        ".", " .. ", "OAuth:reserved", "oauth:\u{0301}reserved", "restored:reserved", "connector-host:reserved", String(repeating: "x", count: 201),
    ])
    func anInvalidSourceKeepsTheDraftAndShowsTheFieldWithoutMakingAKey(source: String) async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = source

        await model.make()

        #expect(model.sourceError != nil)
        #expect(model.draftError == nil)
        #expect(model.draft.source == source)
        #expect(model.draft.name == "Lisbon zine importer")
        #expect(model.sheet == .new)
        #expect(!bench.calls.calls.contains("create"))
    }

    @Test func closingSettingsHandsBackTheNewKeysTypedFields() async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        #expect(drafts.takeAll().isEmpty, "no sheet open, nothing to hand back")
        model.beginNewKey()
        #expect(drafts.takeAll().isEmpty, "an empty sheet holds nothing")
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        #expect(
            drafts.takeAll() == [.typed(title: "Key Not Made", text: "Name: Lisbon zine importer\nSource: lisbon-zine")])
        #expect(model.sheet == nil)
        #expect(drafts.takeAll().isEmpty, "what was handed back is not handed back twice")
    }

    @Test func aKeyShownWhenSettingsClosesIsToldAboutNeverHandedBack() async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        await model.make()
        #expect(model.sheet == .shown)
        let taken = drafts.takeAll()
        #expect(
            taken == [
                .told(
                    title: "Key Not Copied",
                    message: "The key “Lisbon zine importer” was made, and its secret can’t be shown again. If you didn’t copy it, revoke the key on the Keys page.")
            ])
        #expect(!String(describing: taken).contains("marfa_k1_secret"), "the secret is never handed over")
        #expect(model.created == nil)
        #expect(model.sheet == nil)
    }

    @Test func aKeyMadeWhileSettingsClosesIsToldAboutOnceTheCallEnds() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        let gate = bench.calls.hold("create")
        let making = Task { await model.make() }
        #expect(try await eventuallyAsking { bench.calls.calls.contains("create") })
        #expect(drafts.takeAll().isEmpty, "a sheet that is making is not taken from")
        #expect(bench.late.isEmpty)
        gate.open()
        await making.value
        #expect(
            bench.late == [
                .told(
                    title: "Key Not Copied",
                    message: "The key “Lisbon zine importer” was made, and its secret can’t be shown again. If you didn’t copy it, revoke the key on the Keys page.")
            ])
        #expect(model.created == nil, "the secret is dropped, not kept for a window that is gone")
        #expect(model.sheet == nil)
    }

    @Test func closingDuringTheKeyListRefreshDropsTheShownSecretAndTellsTheOwner() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        let refresh = bench.calls.hold("keys")
        defer { refresh.open() }
        let making = Task { await model.make() }
        try #require(await eventually { model.sheet == .shown })
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        #expect(String(describing: drafts).contains("Key Not Copied"))
        #expect(!String(describing: drafts).contains("marfa_k1_secret"))
        #expect(model.created == nil)
        #expect(model.sheet == nil)
        refresh.open()
        await making.value
        #expect(bench.late.isEmpty)
    }

    @Test func aKeyRefusedWhileSettingsClosesHandsBackWhatWasTyped() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        bench.calls.fail("create", with: .refused("No."))
        let gate = bench.calls.hold("create")
        let making = Task { await model.make() }
        #expect(try await eventuallyAsking { bench.calls.calls.contains("create") })
        #expect(drafts.takeAll().isEmpty)
        gate.open()
        await making.value
        #expect(bench.late == [.typed(title: "Key Not Made", text: "Name: Lisbon zine importer\nSource: lisbon-zine")])
        #expect(model.sheet == nil)
    }

    @Test func aKeyMadeWithSettingsOpenIsShownNotToldAbout() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Importer"
        model.draft.source = "importer"
        await model.make()
        #expect(model.sheet == .shown)
        #expect(bench.late.isEmpty)
    }

    @Test func aRenameTypedWhenSettingsClosesIsHandedBack() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        await model.load()
        model.beginRename(model.keys[0])
        #expect(drafts.takeAll().isEmpty, "a name left as it was is nothing to keep")
        model.beginRename(model.keys[0])
        model.renameDraft = "  Zine importer  "
        #expect(drafts.takeAll() == [.typed(title: "Key Not Renamed", text: "Zine importer")])
        #expect(model.sheet == nil)
        #expect(drafts.takeAll().isEmpty)
        model.beginRename(model.keys[0])
        model.renameDraft = "   "
        #expect(drafts.takeAll().isEmpty, "a blank name is nothing to keep")
    }

    // MARK: Extend

    private static let day: TimeInterval = 86_400

    @Test func aKeyOffersOnlyDaysLaterThanItsOwnEndAndNeverWhereTheAppsSignInDoesNotEnd() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.extensions(of: model.keys[0]) == [.days(30), .days(90), .days(365), .never], "7 days is sooner than it ends")
        bench.calls.state.withLock { $0.keys[0].expires = nil }
        await model.load()
        #expect(model.extensions(of: model.keys[0]).isEmpty, "a key that never ends has nothing to extend")
    }

    @Test func whenTheAppsOwnSignInEndCantBeReadNothingIsOfferedNotNeverAndNotPastIt() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        bench.calls.fail("identity", with: .unreachable)
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.failure == nil, "the keys are listed")
        #expect(model.extensions(of: model.keys[0]).isEmpty, "unknown is not the same as no limit")
        #expect(model.identityFailure == .unreachable, "the page shows the failure with Try Again")
        model.beginExtend(model.keys[0])
        #expect(model.sheet == nil, "there is nothing to extend to")
        bench.calls.fail("identity", with: nil)
        await model.load()
        #expect(model.identityFailure == nil)
        #expect(model.extensions(of: model.keys[0]) == [.days(30), .days(90), .days(365), .never])
    }

    @Test func aKeyIsHeldToTheEndOfTheKeyTheAppIsSignedInWith() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        bench.calls.state.withLock {
            $0.identity = OwnIdentity(keyID: "me", expires: .now.addingTimeInterval(Self.day * 100))
        }
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.extensions(of: model.keys[0]) == [.days(30), .days(90)], "none past the caller's own end, and never is past every end")
        bench.calls.state.withLock { $0.keys[0].expires = .now.addingTimeInterval(Self.day * 100) }
        await model.load()
        #expect(model.extensions(of: model.keys[0]).isEmpty)
    }

    @Test func extendingSendsOnlyALaterDateAndKeepsTheKey() async throws {
        let ends = Date.now.addingTimeInterval(Self.day * 10)
        let bench = bench([key(expires: ends)])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.beginExtend(model.keys[0])
        #expect(model.sheet == .extend("k1"))
        #expect(model.extensionChoice == .days(30), "the first choice is the nearest later one")
        model.extensionChoice = .days(90)
        await model.extend()
        let sent = bench.calls.state.withLock { $0.changes }
        #expect(sent.count == 1)
        let want = try #require(KeysModel.Extension.days(90).date())
        guard case .on(let sentDate)? = sent[0].change.expires else { Issue.record("an expiry is sent"); return }
        #expect(abs(sentDate.timeIntervalSince(want)) < 5)
        #expect(sent[0].change == KeyChange(expires: .on(sentDate)), "nothing but the expiry is sent")
        #expect(model.sheet == nil)
        #expect((model.keys[0].expires ?? .distantPast) > ends)
        #expect(model.keys[0].source == "importer" && model.keys[0].permissions == ["items.purge"], "the key itself is unchanged")
    }

    @Test func extendingToNeverClearsTheEnd() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.beginExtend(model.keys[0])
        model.extensionChoice = .never
        await model.extend()
        #expect(bench.calls.state.withLock { $0.changes.map(\.change.expires) } == [.never])
        #expect(model.keys[0].expires == nil)
    }

    @Test func aRefusedExtensionKeepsTheSheetAndTheChoiceWithOneLine() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.beginExtend(model.keys[0])
        model.extensionChoice = .days(365)
        bench.calls.fail("change", with: .notPermitted("keys.manage"))
        await model.extend()
        #expect(model.sheet == .extend("k1") && model.extensionChoice == .days(365))
        #expect(model.extendError == "The app isn’t allowed to give a key more time.")
        #expect(bench.refreshed == 1, "the server's answer wins over what the app thinks it holds")
        bench.calls.fail("change", with: .notPermitted(nil))
        await model.extend()
        #expect(model.extendError == "Choose a date before the app’s sign-in ends.")
        bench.calls.fail("change", with: .unreachable)
        await model.extend()
        #expect(model.extendError == "The app can’t reach the server. Nothing was changed.")
        #expect(model.sheet == .extend("k1"))
        bench.calls.fail("change", with: nil)
        await model.extend()
        #expect(model.sheet == nil && model.extendError == nil)
    }

    @Test func aKeyRevokedElsewhereWhileExtendingIsToldGone() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.beginExtend(model.keys[0])
        bench.calls.state.withLock { $0.keys = [] }
        await model.extend()
        #expect(model.isGone("k1") && model.key("k1") == nil)
        #expect(model.extendError == "It was removed somewhere else.")
    }

    @Test func extendingNeedsManageKeys() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.canExtend)
        bench.grants.remove(.keysManage)
        #expect(!model.canExtend)
    }

    @Test func aSheetLeftOpenWhenSettingsClosesHasNothingToKeep() async {
        let bench = bench([key(expires: .now.addingTimeInterval(Self.day * 10))])
        let model = KeysModel(context: bench.context)
        let drafts = OwnerDrafts()
        drafts.register(model)
        await model.load()
        model.beginExtend(model.keys[0])
        #expect(drafts.takeAll().isEmpty)
        #expect(model.sheet == nil)
    }

    @Test func revokingAsksFirstAndGoesBack() async throws {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToRevoke(model.keys[0])
        let question = try #require(model.question)
        #expect(!bench.calls.calls.contains("revoke"))
        await model.confirm(question)
        #expect(model.keys.isEmpty)
        #expect(model.revoked == "k1")
    }

    @Test func aKeyRevokedElsewhereWhileItsPageIsOpenIsToldGone() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        bench.calls.state.withLock { $0.keys = [] }
        await model.setTier(.library, of: model.keys[0])
        #expect(model.key("k1") == nil)
        #expect(model.isGone("k1"))
        await model.load()
        #expect(model.key("k1") == nil)
    }

    @Test func aRefusedChangeNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        bench.calls.fail("change", with: .notPermitted("keys.manage"))
        await model.setTier(.library, of: model.keys[0])
        #expect(model.rowErrors["k1"] == .notPermitted("keys.manage"))
        #expect(bench.refreshed == 1)
        #expect(model.keys[0].tier == .feed)
    }

    @Test func aNewKeyOffersOnlyThePermissionsTheAppHolds() {
        let bench = OwnerBench(grants: [.keysMint, .keysManage, .itemsPurge])
        #expect(KeysModel(context: bench.context).givablePermissions == ["items.purge", "keys.manage", "keys.mint"])
    }
}

@MainActor
@Suite(.hangLimit) struct AddressesModelTests {
    private func model(_ bench: OwnerBench = OwnerBench()) async -> (AddressesModel, OwnerBench) {
        let model = AddressesModel(context: bench.context)
        await model.load()
        return (model, bench)
    }

    @Test func anAddressIsAnOriginWithNoPath() {
        #expect(AddressesModel.origin(from: "Studio.Castell.design") == "https://studio.castell.design")
        #expect(AddressesModel.origin(from: "http://castell-studio.local:8210/") == "http://castell-studio.local:8210")
        #expect(AddressesModel.origin(from: "https://marfa.test/path") == nil)
        #expect(AddressesModel.origin(from: "ftp://marfa.test") == nil)
        #expect(AddressesModel.origin(from: "marfa test") == nil)
        #expect(AddressesModel.origin(from: "") == nil)
        #expect(AddressesModel.display("https://marfa.test") == "marfa.test")
        #expect(AddressesModel.display("http://marfa.test:8210") == "http://marfa.test:8210")
        #expect(AddressesModel.kind(of: "https://100.84.12.7") == "An IP address.")
        #expect(AddressesModel.kind(of: "http://castell-studio.local") == "On the local network.")
        #expect(AddressesModel.kind(of: "https://studio.castell.design") == nil)
    }

    @Test func theSignInAddressIsLeftOutOfTheOthers() async {
        let (model, _) = await model()
        #expect(model.signInAddress == "https://marfa.test")
        #expect(model.otherAddresses == ["https://100.84.12.7"])
    }

    @Test func anAddressIsCheckedBeforeItIsAddedAndThenAdded() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        #expect(bench.calls.calls.contains("check"))
        #expect(model.canConfirm)
        #expect(bench.calls.state.withLock { $0.applied.isEmpty }, "nothing is written by a check")
        await model.confirm()
        #expect(model.settings?.addresses == ["https://marfa.test", "https://100.84.12.7", "https://studio.castell.design"])
        #expect(model.sheet == nil)
    }

    @Test func anAddressTheCheckRefusesSaysWhyInOneLineAndKeepsTheInput() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "not an address"
        await model.check()
        #expect(model.inputError == "Use an address like https://marfa.example, with no path.")
        #expect(!model.canConfirm)
        model.input = "studio.castell.design"
        bench.calls.fail("check", with: .refused("An address can’t hold a path."))
        await model.check()
        #expect(model.inputError == "An address can’t hold a path.")
        #expect(model.input == "studio.castell.design")
        #expect(!model.canConfirm)
        await model.confirm()
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
    }

    @Test func aCheckOfOneAddressNeverWritesAnother() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "a.castell.design"
        await model.check()
        #expect(model.canConfirm)
        model.input = "b.castell.design"
        #expect(!model.canConfirm, "what was checked is not what is typed")
        #expect(model.currentPlan == nil)
        await model.confirm()
        #expect(bench.calls.state.withLock { $0.applied.isEmpty }, "nothing is written for an address that was not checked")
        await model.check()
        #expect(model.canConfirm)
        await model.confirm()
        #expect(model.settings?.addresses.last == "https://b.castell.design")
        #expect(model.settings?.addresses.contains("https://a.castell.design") == false)
    }

    @Test func aCheckOfOneSignInAddressNeverMovesToAnother() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .answers; $0.requiresConfirmation = true }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "a.castell.design"
        await model.check()
        #expect(model.canConfirm)
        model.input = "b.castell.design"
        #expect(!model.canConfirm)
        await model.confirm()
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
        #expect(model.settings?.signIn == "https://marfa.test")
        await model.check()
        await model.confirm()
        #expect(model.settings?.signIn == "https://b.castell.design")
    }

    @Test func aWebsiteAlreadyAllowedIsNotAddedAgain() async {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        await model.confirm()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.confirm()
        #expect(bench.calls.state.withLock { $0.websitesSent.count } == 1)
    }

    @Test func closingSettingsHandsBackTheTypedAddress() async {
        let (model, _) = await model()
        let drafts = OwnerDrafts()
        drafts.register(model)
        #expect(drafts.takeAll().isEmpty)
        model.begin(.addAddress)
        #expect(drafts.takeAll().isEmpty, "an empty sheet holds nothing")
        model.begin(.addAddress)
        model.input = " studio.castell.design "
        #expect(drafts.takeAll() == [.typed(title: "Address Not Added", text: "studio.castell.design")])
        #expect(model.sheet == nil)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        #expect(drafts.takeAll() == [.typed(title: "Sign-In Address Not Changed", text: "studio.castell.design")])
        model.begin(.addWebsite)
        model.input = "castell.studio"
        #expect(drafts.takeAll() == [.typed(title: "Website Not Added", text: "castell.studio")])
    }

    @Test func anAddressAlreadyHeldIsToldNotChecked() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "https://100.84.12.7"
        await model.check()
        #expect(model.inputError == "It’s already an address.")
        #expect(!bench.calls.calls.contains("check"))
    }

    @Test func aSignInAddressThatDoesNotAnswerCannotBeChosenAndSaysWhy() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .notAnswering(reason: "not_this_instance"); $0.requiresConfirmation = true }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        #expect(model.inputError == "Something answers there, but not this server.")
        #expect(!model.canConfirm)
    }

    @Test func movingTheSignInAddressShowsWhatChangesAndWritesExactlyThat() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.reach = .answers
            $0.requiresConfirmation = true
            $0.consequences = [.init(code: "browser_sessions_end", sentence: "Every browser signs in again.", count: 2)]
        }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        #expect(model.plan?.consequences.map(\.code) == ["browser_sessions_end"])
        #expect(model.canConfirm)
        await model.confirm()
        let applied = try #require(bench.calls.state.withLock { $0.applied.first })
        #expect(applied.askedSignIn == "https://studio.castell.design")
        #expect(applied.requiresConfirmation)
        #expect(model.settings?.signIn == "https://studio.castell.design")
    }

    @Test func aMoveTheOwnerDidNotConfirmKeepsTheDraftForAnotherAttempt() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .answers; $0.requiresConfirmation = true }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.fail("apply", with: .notConfirmed)
        await model.confirm()
        #expect(model.approvalNotice == "Nothing was changed: the sign-in wasn’t confirmed.")
        #expect(model.inputError == nil)
        #expect(model.input == "studio.castell.design")
        #expect(model.sheet == .changeSignIn)
        #expect(model.settings?.signIn == "https://marfa.test")
        #expect(model.canConfirm)

        bench.calls.fail("apply", with: nil)
        await model.confirm()
        #expect(model.approvalNotice == nil)
        #expect(model.sheet == nil)
        #expect(model.settings?.signIn == "https://studio.castell.design")
    }

    @Test func removingAnAddressChecksThenAsksThenWrites() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.consequences = [.init(code: "address_removed", sentence: "Links that use 100.84.12.7 stop working.", count: nil)] }
        let (model, _) = await model(bench)
        await model.askToRemove(address: "https://100.84.12.7")
        let question = try #require(model.question)
        #expect(question.message == "Links that use 100.84.12.7 stop working.")
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
        await model.confirm(question)
        #expect(model.settings?.addresses == ["https://marfa.test"])
    }

    @Test func anotherInstanceAnsweringIsToldAndNothingIsWritten() async throws {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.state.withLock { $0.settings.instanceID = "instance-2" }
        await model.confirm()
        #expect(model.inputError == "Another Marfa now answers at this address. Nothing was sent.")
        #expect(model.settings?.instanceID == "instance-1", "the other Marfa's settings are not adopted")
        #expect(model.input == "studio.castell.design")
    }

    private func count(_ call: String, in bench: OwnerBench) -> Int { bench.calls.calls.filter { $0 == call }.count }

    @Test func anAddressAddedWhileTheSettingsChangedReadsAndChecksAgainAndWritesNothingOverTheNewerList() async throws {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.state.withLock { $0.settings.addresses.append("https://newer.test") }
        bench.calls.fail("apply", with: .conflict)
        let reads = count("addresses", in: bench)
        let checks = count("check", in: bench)
        await model.confirm()
        #expect(count("addresses", in: bench) == reads + 1, "the list is read again")
        #expect(count("check", in: bench) == checks + 1, "and the address checked against it")
        #expect(model.settings?.addresses.contains("https://newer.test") == true)
        #expect(model.currentPlan?.askedAddresses?.contains("https://newer.test") == true, "a retry builds on the newer list")
        #expect(model.inputError == OwnerWording.line(.conflict))
        #expect(model.input == "studio.castell.design")
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
    }

    @Test func aSignInAddressChangedWhileTheSettingsChangedReadsAndChecksAgain() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .answers }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.fail("apply", with: .conflict)
        let reads = count("addresses", in: bench)
        let checks = count("check", in: bench)
        await model.confirm()
        #expect(count("addresses", in: bench) == reads + 1)
        #expect(count("check", in: bench) == checks + 1)
        #expect(model.inputError == OwnerWording.line(.conflict))
        #expect(model.sheet == .changeSignIn)
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
    }

    @Test func anAddressRemovedWhileTheSettingsChangedReadsTheNewerList() async throws {
        let (model, bench) = await model()
        await model.askToRemove(address: "https://100.84.12.7")
        let question = try #require(model.question)
        bench.calls.state.withLock { $0.settings.addresses.append("https://newer.test") }
        bench.calls.fail("apply", with: .conflict)
        let reads = count("addresses", in: bench)
        await model.confirm(question)
        #expect(count("addresses", in: bench) == reads + 1)
        #expect(model.settings?.addresses.contains("https://newer.test") == true)
        #expect(model.rowErrors["https://100.84.12.7"] == .conflict)
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
    }

    @Test func aWebsiteAddedWhileTheSettingsChangedReadsAndChecksAgainAndWritesNothingOverTheNewerList() async throws {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        bench.calls.state.withLock { $0.settings.websites = ["https://newer.test"] }
        bench.calls.fail("setWebsites", with: .conflict)
        let reads = count("addresses", in: bench)
        await model.confirm()
        #expect(count("addresses", in: bench) == reads + 1)
        #expect(model.settings?.websites == ["https://newer.test"])
        #expect(model.inputError == OwnerWording.line(.conflict))
        #expect(model.input == "castell.studio")
        #expect(model.sheet == .addWebsite)
        #expect(bench.calls.state.withLock { $0.websitesSent.isEmpty })
    }

    @Test func aWebsiteAddedElsewhereMeanwhileIsToldAsAlreadyAllowed() async throws {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        bench.calls.state.withLock { $0.settings.websites = ["https://castell.studio"] }
        bench.calls.fail("setWebsites", with: .conflict)
        await model.confirm()
        #expect(model.inputError == "It’s already allowed.")
    }

    @Test func aWebsiteRemovedWhileTheSettingsChangedReadsTheNewerList() async throws {
        let (model, bench) = await model()
        bench.calls.state.withLock { $0.settings.websites = ["https://castell.studio"] }
        await model.load()
        model.askToRemove(website: "https://castell.studio")
        let question = try #require(model.question)
        bench.calls.state.withLock { $0.settings.websites.append("https://newer.test") }
        bench.calls.fail("setWebsites", with: .conflict)
        await model.confirm(question)
        #expect(model.settings?.websites == ["https://castell.studio", "https://newer.test"])
        #expect(model.rowErrors["https://castell.studio"] == .conflict)
    }

    @Test func aCheckThatEndsAfterTheInputChangedNeverWritesTheErrorLine() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .notAnswering(reason: nil) }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        let gate = bench.calls.hold("check")
        let stale = Task { await model.check() }
        #expect(try await eventuallyAsking { bench.calls.calls.contains("check") })
        model.input = "marfa test"
        await model.check()
        let line = model.inputError
        #expect(line == "Use an address like https://marfa.example, with no path.")
        gate.open()
        await stale.value
        #expect(model.inputError == line, "the stale answer is dropped")
        #expect(model.plan == nil)
        #expect(!model.isChecking)
    }

    @Test func aWebsiteIsAddedAndRemovedAfterAsking() async throws {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        await model.confirm()
        #expect(model.settings?.websites == ["https://castell.studio"])
        model.askToRemove(website: "https://castell.studio")
        let question = try #require(model.question)
        #expect(bench.calls.state.withLock { $0.websitesSent.count } == 1)
        await model.confirm(question)
        #expect(model.settings?.websites == [])
    }

    @Test func aRefusedWebsiteKeepsTheInputWithTheServersLine() async {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        bench.calls.fail("setWebsites", with: .notPermitted("config.manage"))
        await model.confirm()
        #expect(model.inputError?.contains("see and change the server’s settings") == true)
        #expect(model.input == "castell.studio")
        #expect(bench.refreshed == 1)
    }
}

@MainActor
@Suite(.hangLimit) struct OwnerWordingTests {
    @Test func everyFailureSaysSomethingInOneLine() {
        let failures: [OwnerFailure] = [
            .unreachable, .signedOut, .notPermitted("grants.manage"), .notPermitted(nil), .notPermitted("odd.scope"), .notFound,
            .conflict, .instanceChanged, .notConfirmed, .refused("Because."), .sourceHeld("Taken."), .failed("Broken."),
        ]
        for failure in failures { #expect(!OwnerWording.line(failure).isEmpty) }
        #expect(OwnerWording.line(.notPermitted("odd.scope")).contains("odd.scope"))
    }

    @Test func aRefusalNamesNoButtonSinceTheRowOffersItsOwn() {
        for scope in [nil] + InstancePermission.allCases.map(\.rawValue) + ["odd.scope"] {
            #expect(!OwnerWording.permissionLine(scope).contains("Allow More"), "\(scope ?? "none")")
        }
        #expect(OwnerWording.line(.notPermitted(nil)) == "The app isn’t allowed to do this.")
    }

    @Test func aProblemRowOffersAllowMoreForARefusalForWantOfAPermissionAndTryAgainForTheRest() {
        for retry in [true, false] {
            #expect(OwnerProblemRow.offer(for: .notPermitted("config.manage"), canRetry: retry) == .allowMore(scope: "config.manage"))
            #expect(OwnerProblemRow.offer(for: .notPermitted(nil), canRetry: retry) == .allowMore(scope: nil))
        }
        #expect(OwnerProblemRow.offer(for: .unreachable, canRetry: true) == .tryAgain)
        #expect(OwnerProblemRow.offer(for: .failed("No."), canRetry: false) == .nothing)
    }

    @Test func aRowThatWasRefusedAsksForTheNamedPermissionOnlyThroughTheHost() async {
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: FakeInstanceConfig([:])) }
        let host = StubMarfaHost(settings: settings)
        host.askForMore(naming: "webhooks.manage")
        host.askForMore(naming: nil)
        #expect(await eventually { host.allowed == [[.webhooksManage], []] })
    }

    @Test func aPageSaysARefusalInItsOwnWordsWhereItNamesThePagesPermission() {
        #expect(OwnerWording.line(.notPermitted("webhooks.manage"), on: .webhooks) == MarfaSettingsPage.webhooks.permissionLine)
        #expect(OwnerWording.line(.notPermitted("keys.manage"), on: .webhooks) == OwnerWording.permissionLine("keys.manage"))
        #expect(OwnerWording.line(.unreachable, on: .webhooks) == OwnerWording.line(.unreachable))
    }

    @Test(arguments: [
        ("webhook_inactive", "Turn on Sending to send this delivery again."),
        ("credential_unavailable", "The key or app that created this webhook no longer has access. Create a new webhook for future deliveries."),
        ("delivery_not_failed", "Only failed deliveries can be sent again."),
        ("delivery_expired", "This delivery expired and can’t be sent again."),
        ("unknown", "The server couldn’t do that."),
    ])
    func aRedeliveryRefusalUsesTheAppWording(reason: String, wording: String) {
        let error = MarfaError.server(
            status: 409, code: "conflict", message: "The server’s words.", details: .object(["reason": .string(reason)]), server: nil)
        #expect(OwnerWording.problemLine(ClientOwnerCalls.failure(error), on: .webhooks, canRetry: false) == wording)
    }

    @Test func aPausedConnectorRefusalTellsTheOwnerToResumeIt() {
        let error = MarfaError.server(status: 409, code: "connector_paused", message: "The server’s words.", details: nil, server: nil)
        let failure = ClientOwnerCalls.failure(error)
        #expect(failure == .connectorPaused)
        #expect(OwnerWording.problemLine(failure, on: .connectors, canRetry: false) == "The connector is paused. Resume it, then choose Run Now.")
    }

    @Test func anotherMarfaAnsweringIsItsOwnFailureWithTheWordsOfTheSettingsPage() {
        #expect(ClientOwnerCalls.failure(MarfaError.instanceChanged(message: "Another instance answers.", server: nil)) == .instanceChanged)
        #expect(
            ClientOwnerCalls.failure(MarfaError.instanceChanged(message: "Another instance answers.", server: nil), plainConflict: { _ in .conflict })
                == .instanceChanged)
        #expect(OwnerWording.line(.instanceChanged) == InstanceConfigFailure.anotherMarfaSentence)
        #expect(InstanceConfigFailure.instanceChanged.message.hasPrefix(InstanceConfigFailure.anotherMarfaSentence))
    }

    @Test func theServersSettingsFailuresAreTheOwnerPagesFailures() {
        #expect(OwnerFailure(.unreachable) == .unreachable)
        #expect(OwnerFailure(.keyRefused) == .signedOut)
        #expect(OwnerFailure(.notPermitted) == .notPermitted("config.manage"))
        #expect(OwnerFailure(.instanceChanged) == .instanceChanged)
        #expect(OwnerFailure(.unsupported) == .unsupported)
        #expect(OwnerFailure(.refused("Too big.")) == .refused("Too big."))
        #expect(OwnerFailure(.failed("Broke.")) == .failed("Broke."))
        #expect(OwnerWording.line(.unsupported) == InstanceConfigFailure.unsupported.message)
    }

    @Test func aConflictIsChangedElsewhereOnlyWhereTheCallSaysSo() {
        func answer(_ code: String) -> MarfaError { .server(status: 409, code: code, message: "The server’s words.", details: nil, server: nil) }
        #expect(ClientOwnerCalls.failure(answer("sign_in_address_check_failed")) == .refused("The server’s words."))
        #expect(ClientOwnerCalls.failure(answer("sign_in_address_change_unconfirmed")) == .refused("The server’s words."))
        #expect(ClientOwnerCalls.failure(answer("conflict")) == .refused("The server’s words."), "a 409 is not changed elsewhere by default")
        #expect(ClientOwnerCalls.failure(answer("conflict"), plainConflict: { _ in .conflict }) == .conflict, "a grant read before it changed")
        #expect(ClientOwnerCalls.failure(answer("conflict"), plainConflict: { .sourceHeld($0) }) == .sourceHeld("The server’s words."))
        #expect(
            ClientOwnerCalls.failure(MarfaError.versionConflict(message: "Stale.", server: nil), plainConflict: { .sourceHeld($0) }) == .conflict)
        #expect(
            ClientOwnerCalls.failure(MarfaError.instanceChanged(message: "Another instance.", server: nil)) == .instanceChanged,
            "another Marfa answering at the address is not a change somewhere else")
        #expect(
            ClientOwnerCalls.failure(answer("sign_in_address_check_failed"), plainConflict: { _ in .conflict }) == .refused("The server’s words."),
            "the address refusals keep the server’s words whatever the call")
    }

    @Test func aConfigWriteReadsA409AsTheSettingsChangingUnderIt() {
        let conflict = MarfaError.server(status: 409, code: "conflict", message: "Changed.", details: nil, server: nil)
        #expect(ClientOwnerCalls.failure(conflict, plainConflict: ClientOwnerCalls.configConflict) == .conflict)
        let refusal = MarfaError.server(status: 409, code: "sign_in_address_change_unconfirmed", message: "Confirm.", details: nil, server: nil)
        #expect(ClientOwnerCalls.failure(refusal, plainConflict: ClientOwnerCalls.configConflict) == .refused("Confirm."))
    }

    @Test func whenIsToldByDayAndNeverByTimeAlone() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(OwnerWording.used(now, now: now, calendar: calendar) == "Used today")
        #expect(OwnerWording.used(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Used yesterday")
        #expect(OwnerWording.used(now.addingTimeInterval(-86_400 * 3), now: now, calendar: calendar) == "Used 3 days ago")
        #expect(OwnerWording.used(nil, now: now, calendar: calendar) == "Never used")
    }
}
