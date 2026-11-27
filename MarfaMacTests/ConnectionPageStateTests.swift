import Marfa
import Testing
@testable import MarfaMac

/// How Connection shows owner permissions and unsent changes.
@Suite struct ConnectionPageStateTests {
    @Test func accountWithoutEveryPermissionSaysHowManyAndOffersMore() {
        let grants = ConnectionAccount.asked.subtracting([.schemaWrite, .keysMint])
        let account = ConnectionAccount(state: .online, grants: grants, grantsRead: true, waiting: 0)
        #expect(!account.holdsAll && account.held == 12)
        #expect(account.permissionsValue == "12 of 14")
        #expect(account.offersMore)
    }

    /// One count everywhere: a key's and an app's pages say "N of 14", and Connection counts the same 14 and asks for every
    /// one it does not hold, `sign_ins.manage` included.
    @Test func connectionCountsAndAsksForEveryOwnerPermission() {
        #expect(ConnectionAccount.asked == Set(InstancePermission.allCases) && ConnectionAccount.asked.count == 14)
        let account = ConnectionAccount(state: .online, grants: [.signInsManage], grantsRead: true, waiting: 0)
        #expect(account.held == 1 && account.total == 14)
        let all = ConnectionAccount(state: .online, grants: Set(InstancePermission.allCases), grantsRead: true, waiting: 0)
        #expect(all.holdsAll && all.permissionsValue == "All 14")
        #expect(!all.offersMore)
        let without = ConnectionAccount(
            state: .online, grants: Set(InstancePermission.allCases).subtracting([.signInsManage]), grantsRead: true, waiting: 0)
        #expect(!without.holdsAll && without.permissionsValue == "13 of 14" && without.offersMore)
        #expect(without.permissionsLine == "What you’ve allowed this app to manage. Allow More asks for the rest.")
        #expect(all.permissionsLine == "What you’ve allowed this app to manage.")
    }

    @Test(arguments: [
        (MarfaConnectionState.online, false, "checkmark.circle.fill", ConnectionAddressStatus.Tone.green, "Connected"),
        (.online, true, "arrow.down.circle.fill", .orange, "Update ready"),
        (.offline(reason: nil), true, "exclamationmark.circle.fill", .orange, "Not answering"),
        (.keyRefused, true, "xmark.circle.fill", .red, "Sign-in expired"),
        (.connecting, false, "ellipsis.circle.fill", .orange, "Connecting…"),
        (.inUse, false, "xmark.circle.fill", .red, "Library unavailable"),
    ])
    func addressStatus(state: MarfaConnectionState, updateReady: Bool, symbol: String, tone: ConnectionAddressStatus.Tone, words: String) {
        let status = ConnectionAddressStatus(state: state, updateReady: updateReady)
        #expect(status.symbol == symbol && status.tone == tone && status.words == words)
    }

    /// Signed In As is shown while the sign-in is held, answered or not, and not once it has ended.
    @Test func signedInAsIsShownWheneverTheSignInIsHeld() {
        func account(_ state: MarfaConnectionState, readsProfile: Bool = true) -> ConnectionAccount {
            ConnectionAccount(state: state, grants: [], grantsRead: true, readsProfile: readsProfile, waiting: 0)
        }
        #expect(account(.online).showsName && account(.connecting).showsName && account(.offline(reason: nil)).showsName)
        #expect(!account(.keyRefused).showsName && !account(.disconnected).showsName)
    }

    @Test func withoutTheNameScopeSignedInAsIsEmptyAndPointsToTheOneAllowMore() {
        let without = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: false, waiting: 0)
        #expect(without.showsName && without.offersName)
        #expect(without.nameLine == "Allow More lets the app read the owner’s name.")
        let with = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: true, waiting: 0)
        #expect(with.nameLine == nil)
        // Where no Allow More is there to give the name, no line promises one.
        let unreached = ConnectionAccount(state: .offline(reason: nil), grants: [], grantsRead: true, readsProfile: false, waiting: 0)
        #expect(unreached.showsName && unreached.nameLine == nil)
    }

    @Test func aCopyThatCannotSayWhatWaitsIsUnknownNotNone() {
        #expect(ConnectionAccount(state: .online, grants: [], grantsRead: true, waiting: nil).unsent == "Unknown")
    }
}
