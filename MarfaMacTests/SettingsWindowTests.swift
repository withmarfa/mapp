import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MarfaMac

/// Where the Settings window is, how it is opened, and what its sidebar's search finds.
@MainActor
struct SettingsWindowTests {
    @Test func sidebarHasNineteenPagesInOrder() {
        #expect(SettingsPage.appGroups == [
            [.general, .connection, .appearance, .keyboard],
            [.editor, .lists, .layouts, .search],
        ])
        #expect(SettingsPage.marfaGroups == [
            [.account, .activity, .keys, .sources, .webhooks],
            [.types, .plugins, .connectors, .folders, .backups, .trash],
        ])
    }

    @Test func everyRoutablePageHasASidebarEntry() {
        let sidebar = (SettingsPage.appGroups + SettingsPage.marfaGroups).flatMap { $0 }
        let moved: [SettingsPage: SettingsPage] = [
            .overview: .account, .updates: .account, .addresses: .account, .fileStorage: .account,
            .history: .account, .housekeeping: .account, .limits: .account, .monitoring: .account,
            .startUp: .account, .apps: .keys, .links: .types, .onThisMac: .connection,
        ]
        #expect(Set(sidebar + Array(moved.keys)) == Set(SettingsPage.allCases))
        for page in SettingsPage.allCases {
            #expect(page.sidebarEntry == (moved[page] ?? page))
        }
    }

    @Test func movedPagesContributeToSidebarSearch() {
        #expect(SettingsPage.sidebarMatches("Add a Website") == [.account])
        #expect(SettingsPage.sidebarMatches("Open Marfa Links In") == [.keys])
        #expect(SettingsPage.sidebarMatches("New Link Type") == [.types])
        #expect(SettingsPage.sidebarMatches("Download Everything Again") == [.connection])
    }

    @Test func appearanceAndEditorRowsAppearInSidebarSearch() {
        for word in ["App icon", "Dock", "Interface text size", "Sidebar color"] {
            #expect(SettingsPage.sidebarMatches(word) == [.appearance])
        }
        for word in ["Font", "Code font", "PDF background", "Pinned properties", "Text size and width"] {
            #expect(SettingsPage.sidebarMatches(word) == [.editor])
        }
    }

    @Test func backAndForwardKeepMovedPageRoutes() {
        let launcher = SettingsLauncher()
        launcher.show(.addresses)
        #expect(launcher.navigation.page == .addresses)
        #expect(launcher.navigation.page.sidebarEntry == .account)

        launcher.show(.trash)
        #expect(launcher.navigation.page == .trash)
        launcher.navigation.back()
        #expect(launcher.navigation.page == .addresses)
        launcher.navigation.forward()
        #expect(launcher.navigation.page == .trash)
    }

    @Test func tablePreviewShowsAllThroughFiftyRows() {
        let short = SettingsTablePreview(total: 50)
        #expect(short.visibleCount == 50)
        #expect(short.countLabel == nil)

        let long = SettingsTablePreview(total: 51)
        #expect(long.visibleCount == 20)
        #expect(long.countLabel == "20 of 51")

        let expanded = SettingsTablePreview(total: 51, expanded: true)
        #expect(expanded.visibleCount == 51)
        #expect(expanded.countLabel == nil)
    }

    @Test func theMarfasPagesNameThePermissionTheyNeed() {
        #expect(MarfaSettingsPage.overview.permission == .instanceRead, "Overview opens with what the sign-in may read, and leaves the rest out")
        #expect(MarfaSettingsPage.trash.permission == .itemsPurge)
        #expect(MarfaSettingsPage.account.permission == nil, "Account opens without one and asks for sign_ins.manage from Change Password")
        #expect(MarfaSettingsPage.apps.permission == .grantsManage)
        #expect(MarfaSettingsPage.keys.permission == .keysManage)
        #expect(MarfaSettingsPage.addresses.permission == .configManage)
        #expect(MarfaSettingsPage.types.permission == .schemaWrite)
        #expect(MarfaSettingsPage.plugins.permission == .schemaWrite)
    }
}
