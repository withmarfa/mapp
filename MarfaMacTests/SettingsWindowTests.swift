import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MarfaMac

/// Where the Settings window is, how it is opened, and what its sidebar's search finds.
@MainActor
struct SettingsWindowTests {
    @Test func theMarfasPagesNameThePermissionTheyNeed() {
        #expect(MarfaSettingsPage.overview.permission == .instanceRead, "Overview opens with what the sign-in may read, and leaves the rest out")
        #expect(MarfaSettingsPage.recentlyDeleted.permission == .itemsPurge)
        #expect(MarfaSettingsPage.account.permission == nil, "Account opens without one and asks for sign_ins.manage from Change Password")
        #expect(MarfaSettingsPage.apps.permission == .grantsManage)
        #expect(MarfaSettingsPage.keys.permission == .keysManage)
        #expect(MarfaSettingsPage.addresses.permission == .configManage)
        #expect(MarfaSettingsPage.types.permission == .schemaWrite)
        #expect(MarfaSettingsPage.plugins.permission == .schemaWrite)
    }
}
