import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MAPP

/// Where the Settings window is, how it is opened, and what its sidebar's search finds.
@MainActor
struct SettingsWindowTests {
    @Test func aNewPageIsAPlaceBackReturnsToAndForwardGoesTo() {
        let navigation = SettingsNavigation()
        navigation.show(.editor)
        navigation.show(.connection)
        #expect(navigation.page == .connection)
        #expect(navigation.canGoBack)
        #expect(!navigation.canGoForward)

        navigation.back()
        #expect(navigation.page == .editor)
        #expect(navigation.canGoForward)
        navigation.forward()
        #expect(navigation.page == .connection)
    }

    @Test func showingThePageAlreadyShownAddsNoPlace() {
        let navigation = SettingsNavigation()
        navigation.show(.lists)
        navigation.show(.lists)
        navigation.back()
        #expect(navigation.page == .appearance, "one Back left the page it was on")
        #expect(!navigation.canGoBack)
    }

    @Test func aNewPageAfterGoingBackDropsWhatForwardHeld() {
        let navigation = SettingsNavigation()
        navigation.show(.editor)
        navigation.show(.lists)
        navigation.back()
        navigation.show(.connection)
        #expect(!navigation.canGoForward)
        navigation.back()
        #expect(navigation.page == .editor)
    }

    @Test func aSubpageIsPushedOnItsPageAndNamesTheToolbarUntilBackReturns() {
        let navigation = SettingsNavigation()
        navigation.show(.recentlyDeleted)
        #expect(navigation.title == "Recently Deleted")
        navigation.push(RecentlyDeletedPage.allDeleted)
        #expect(navigation.page == .recentlyDeleted)
        #expect(navigation.title == RecentlyDeletedPage.allDeleted.title)
        navigation.push(RecentlyDeletedPage.allDeleted)
        navigation.back()
        #expect(navigation.current.subpage == nil, "pushing the sub-page shown twice added one place")
        #expect(navigation.title == "Recently Deleted")
    }

    @Test func openingAtAPageShowsItAndOpensTheWindowEachTime() {
        let launcher = SettingsLauncher()
        var opened = 0
        launcher.open = { opened += 1 }
        launcher.show(.editor)
        #expect(launcher.navigation.page == .editor)
        launcher.show()
        #expect(launcher.navigation.page == .editor, "no page leaves Settings where it was")
        launcher.show(.connection)
        #expect(launcher.navigation.page == .connection, "Command-comma with Settings open names a page and brings it forward")
        #expect(opened == 3)
    }

    @Test func aBrowsersSettingsRouteOpensThePageInTheLauncherWindow() {
        let launcher = SettingsLauncher()
        var opened = 0
        launcher.open = { opened += 1 }
        let browser = Browser()
        browser.openSettings = { launcher.show($0) }
        browser.showSettings(.recentlyDeleted)
        #expect(launcher.navigation.page == .recentlyDeleted)
        #expect(opened == 1)
    }

    @Test func theSearchFindsAPageByItsNameAndByTheRowsItHolds() {
        #expect(SettingsPage.connection.matches("conn"))
        #expect(SettingsPage.appearance.matches("Palettes"))
        #expect(SettingsPage.editor.matches("spelling"))
        #expect(SettingsPage.general.matches("week starts"))
        #expect(SettingsPage.general.matches("Reset"))
        #expect(SettingsPage.appearance.matches("code font"))
        #expect(SettingsPage.general.matches("Open Items"))
        #expect(!SettingsPage.lists.matches("Open Items"), "Open Items moved to General")
        #expect(!SettingsPage.editor.matches("Remote Pictures"), "Pictures from Websites moved to General")
        #expect(SettingsPage.overview.matches("Health"))
        #expect(SettingsPage.history.matches("Version"))
        #expect(SettingsPage.fileStorage.matches("Unused"))
        #expect(SettingsPage.recentlyDeleted.matches("Permanently Delete After"))
        #expect(!SettingsPage.lists.matches("Palettes"))
        #expect(SettingsPage.lists.matches("  "), "an empty search keeps every page")
    }

    @Test func aSearchThatFindsNothingKeepsNoPage() {
        #expect(SettingsPage.all.filter { $0.matches("zzzz-nothing") }.isEmpty)
        #expect(SettingsPage.all.filter { $0.matches("Recently") } == [.recentlyDeleted])
    }

    @Test func onlyThePagesThatExistAreListed() {
        #expect(SettingsPage.mappGroups.flatMap { $0 } == [.general, .appearance, .keyboard, .editor, .lists, .layouts, .search, .onThisMac, .connection])
        #expect(SettingsPage.marfaGroups.flatMap { $0 } == [.overview, .account, .apps, .keys, .addresses, .sources, .recentlyDeleted, .history, .fileStorage, .webhooks, .folders])
    }

    @Test func theMarfasPagesNameThePermissionTheyNeed() {
        #expect(MarfaSettingsPage.overview.permission == .instanceRead, "Overview opens with what the sign-in may read, and leaves the rest out")
        #expect(MarfaSettingsPage.recentlyDeleted.permission == .itemsPurge)
        #expect(MarfaSettingsPage.account.permission == nil, "Account opens without one and asks for sign_ins.manage from Change Password")
        #expect(MarfaSettingsPage.apps.permission == .grantsManage)
        #expect(MarfaSettingsPage.keys.permission == .keysManage)
        #expect(MarfaSettingsPage.addresses.permission == .configManage)
    }

    @Test func aServerThatLastAnsweredTodayIsToldByTheTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(MarfaPageGate<EmptyView>.notAnswering(nil, now: now, calendar: calendar) == "MAPP keeps trying.")
        let today = MarfaPageGate<EmptyView>.notAnswering(now.addingTimeInterval(-60), now: now, calendar: calendar)
        #expect(today.hasPrefix("Last answered today, "))
        let earlier = MarfaPageGate<EmptyView>.notAnswering(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)
        #expect(!earlier.contains("today"))
    }

    @Test func theConnectionHeadNamesTheServerWithoutItsSchemeAndSaysWhenItWasUpToDate() throws {
        #expect(SettingsWording.hostName(of: try #require(URL(string: "https://marfa.castell.studio"))) == "marfa.castell.studio")
        #expect(SettingsWording.hostName(of: try #require(URL(string: "http://localhost:8080/"))) == "localhost:8080")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let english = Locale(identifier: "en_GB")
        #expect(ConnectionHeadWording.upToDate(since: nil, now: now, locale: english) == "Up to date")
        #expect(ConnectionHeadWording.upToDate(since: now.addingTimeInterval(-20), now: now, locale: english) == "Up to date just now")
        let later = ConnectionHeadWording.upToDate(since: now.addingTimeInterval(-125), now: now, locale: english)
        #expect(later.hasPrefix("Up to date ") && later.contains("minute"))
    }
}
