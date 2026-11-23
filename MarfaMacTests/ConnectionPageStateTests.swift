import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// The head and the Account section of Connection in each state the boards draw (S26 to S30), as words in and out.
@Suite struct ConnectionPageStateTests {
    private static let now = Date(timeIntervalSince1970: 1_795_000_000)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func standing(_ state: MarfaConnectionState, report: SyncReport = SyncReport(), synced: Date? = nil) -> ConnectionStanding {
        ConnectionStanding(
            state: state, status: SyncStatus(state: state, report: report, now: Self.now), lastSynced: synced, now: Self.now,
            calendar: Self.calendar, format: DateFormat.standard)
    }

    @Test func connectedSaysItIsUpToDate() {
        let state = standing(.online, synced: Self.now.addingTimeInterval(-60))
        #expect(state.word == "Connected" && state.tone == .ok && state.action == .none)
        #expect(state.line?.hasPrefix("Up to date") == true)
    }

    @Test func notAnsweringOffersTryAgainAndSaysSince() {
        let state = standing(.offline(reason: "refused"), synced: Self.now.addingTimeInterval(-3_600))
        #expect(state.word == "Not Answering" && state.tone == .warning && state.action == .tryAgain)
        #expect(state.line?.hasPrefix("Not answering since ") == true && state.line?.hasSuffix("MAPP keeps trying.") == true)
        #expect(standing(.offline(reason: nil)).line == "Not answering. MAPP keeps trying.")
    }

    @Test func signedOutOffersSignInAndSaysTheCopyIsKept() {
        let state = standing(.keyRefused)
        #expect(state.word == nil && state.action == .signIn && state.tone == .problem)
        #expect(state.line == "Signed out. This Mac’s copy is kept.")
    }

    @Test func aLibraryThatCannotBeOpenedIsAProblemWithItsExplanationUnderTheCard() {
        let state = standing(.unavailable(message: "The store is damaged."))
        #expect(state.word == "Library unavailable" && state.tone == .problem && state.action == .none)
        #expect(state.detail?.hasSuffix("The store is damaged.") == true)
    }

    @Test func accountWithEveryPermissionSaysAllOfThem() {
        let account = ConnectionAccount(state: .online, grants: Set(InstancePermission.allCases), grantsRead: true, waiting: 0, serverName: "X")
        #expect(account.showsPermissions && account.holdsAll)
        #expect(account.permissionsValue == "All \(InstancePermission.allCases.count)")
        #expect(account.unsent == "None")
    }

    @Test func accountWithoutEveryPermissionSaysHowManyAndOffersMore() {
        let grants: Set<InstancePermission> = [.itemsPurge, .configManage, .schemaWrite, .auditRead, .keysMint]
        let account = ConnectionAccount(state: .online, grants: grants, grantsRead: true, waiting: 0, serverName: "X")
        #expect(!account.holdsAll && account.held == 5)
        #expect(account.permissionsLine == "MAPP holds 5 of the owner’s 14 permissions.")
    }

    /// One count everywhere: a key's and an app's pages say "N of 14", and Connection counts the same 14 and asks for every
    /// one it does not hold, `sign_ins.manage` included.
    @Test func connectionCountsAndAsksForEveryOwnerPermission() {
        #expect(ConnectionAccount.asked == Set(InstancePermission.allCases) && ConnectionAccount.asked.count == 14)
        let account = ConnectionAccount(state: .online, grants: [.signInsManage], grantsRead: true, waiting: 0, serverName: "X")
        #expect(account.held == 1 && account.total == 14)
        let all = ConnectionAccount(state: .online, grants: Set(InstancePermission.allCases), grantsRead: true, waiting: 0, serverName: "X")
        #expect(all.holdsAll && all.permissionsValue == "All 14")
        let without = ConnectionAccount(
            state: .online, grants: Set(InstancePermission.allCases).subtracting([.signInsManage]), grantsRead: true, waiting: 0, serverName: "X")
        #expect(!without.holdsAll && without.permissionsLine == "MAPP holds 13 of the owner’s 14 permissions.")
    }

    /// S26 to S30: Signed In As is shown while the sign-in is held, answered or not, and not once it has ended.
    @Test func signedInAsIsShownWheneverTheSignInIsHeld() {
        func account(_ state: MarfaConnectionState, readsProfile: Bool = true) -> ConnectionAccount {
            ConnectionAccount(state: state, grants: [], grantsRead: true, readsProfile: readsProfile, waiting: 0, serverName: "X")
        }
        #expect(account(.online).showsName && account(.connecting).showsName && account(.offline(reason: nil)).showsName)
        #expect(!account(.keyRefused).showsName && !account(.disconnected).showsName)
    }

    @Test func withoutTheNameScopeSignedInAsIsEmptyAndPointsToTheOneAllowMore() {
        let without = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: false, waiting: 0, serverName: "X")
        #expect(without.showsName && without.offersName)
        #expect(without.nameLine == "Allow More… lets MAPP read the owner’s name.")
        let with = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: true, waiting: 0, serverName: "X")
        #expect(with.nameLine == nil)
        // Where no Allow More… is there to give the name, no line promises one.
        let unreached = ConnectionAccount(state: .offline(reason: nil), grants: [], grantsRead: true, readsProfile: false, waiting: 0, serverName: "X")
        #expect(unreached.showsName && unreached.nameLine == nil)
    }

    @Test func notAnsweringSaysWhatWaitsAndNothingOfPermissions() {
        let account = ConnectionAccount(state: .offline(reason: nil), grants: [.itemsPurge], grantsRead: true, waiting: 3, serverName: "Castell Studio")
        #expect(!account.showsPermissions)
        #expect(account.unsent == "3 changes" && account.unsentLine == "Sent when Castell Studio answers.")
    }

    @Test func signedOutSaysChangesAreSentOnceSignedInAgain() {
        let account = ConnectionAccount(state: .keyRefused, grants: [], grantsRead: false, waiting: 3, serverName: "X")
        #expect(!account.showsPermissions)
        #expect(account.unsentLine == "Sent once you sign in again.")
        #expect(ConnectionAccount(state: .keyRefused, grants: [], grantsRead: false, waiting: 0, serverName: "X").unsentLine == nil)
    }

    @Test func aCopyThatCannotSayWhatWaitsIsUnknownNotNone() {
        #expect(ConnectionAccount(state: .online, grants: [], grantsRead: true, waiting: nil, serverName: "X").unsent == "Unknown")
    }

    /// withmarfa/mapp#454: progress stops showing once the copy has stopped.
    @Test func downloadProgressIsShownOnlyWhileTheCopyCanStillBeFilled() {
        let filling = LibraryFill(state: .filling, listed: 10, expected: 100)
        #expect(FillWording.shows(filling, in: .online) && FillWording.shows(filling, in: .connecting))
        for stopped: MarfaConnectionState in [.unavailable(message: "too old"), .keyRefused, .otherVersion(unsent: nil), .inUse, .offline(reason: nil), .disconnected] {
            #expect(!FillWording.shows(filling, in: stopped), "\(stopped)")
        }
        #expect(!FillWording.shows(LibraryFill(state: .complete), in: .online))
        #expect(!FillWording.shows(nil, in: .online))
    }
}
