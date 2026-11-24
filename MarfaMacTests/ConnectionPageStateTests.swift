import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// The head and the Account section of Connection in each state the boards draw (S26 to S30), as words in and out.
@Suite struct ConnectionPageStateTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test func accountWithoutEveryPermissionSaysHowManyAndOffersMore() {
        let grants: Set<InstancePermission> = [.itemsPurge, .configManage, .schemaWrite, .auditRead, .keysMint]
        let account = ConnectionAccount(state: .online, grants: grants, grantsRead: true, waiting: 0, serverName: "X")
        #expect(!account.holdsAll && account.held == 5)
        #expect(account.permissionsLine == "The app holds 5 of the owner’s 14 permissions.")
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
        #expect(!without.holdsAll && without.permissionsLine == "The app holds 13 of the owner’s 14 permissions.")
    }

    @Test func withoutTheNameScopeSignedInAsIsEmptyAndPointsToTheOneAllowMore() {
        let without = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: false, waiting: 0, serverName: "X")
        #expect(without.showsName && without.offersName)
        #expect(without.nameLine == "Allow More… lets the app read the owner’s name.")
        let with = ConnectionAccount(state: .online, grants: [], grantsRead: true, readsProfile: true, waiting: 0, serverName: "X")
        #expect(with.nameLine == nil)
        // Where no Allow More… is there to give the name, no line promises one.
        let unreached = ConnectionAccount(state: .offline(reason: nil), grants: [], grantsRead: true, readsProfile: false, waiting: 0, serverName: "X")
        #expect(unreached.showsName && unreached.nameLine == nil)
    }

    @Test func aCopyThatCannotSayWhatWaitsIsUnknownNotNone() {
        #expect(ConnectionAccount(state: .online, grants: [], grantsRead: true, waiting: nil, serverName: "X").unsent == "Unknown")
    }
}
