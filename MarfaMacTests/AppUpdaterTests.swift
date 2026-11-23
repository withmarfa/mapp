import Foundation
import Testing
@testable import MarfaMac

@Suite struct AppUpdaterTests {
    private let feed = "https://downloads.example.com/appcast.xml"
    private let key = "AbCdEf0123456789="

    @Test func aBuildWithBothValuesUpdatesItself() {
        #expect(UpdateSettings.isConfigured(in: [UpdateSettings.feedKey: feed, UpdateSettings.publicKeyKey: key]))
    }

    @Test func aBuildMissingEitherValueStartsNoUpdater() {
        #expect(!UpdateSettings.isConfigured(in: nil))
        #expect(!UpdateSettings.isConfigured(in: [:]))
        #expect(!UpdateSettings.isConfigured(in: [UpdateSettings.feedKey: feed]))
        #expect(!UpdateSettings.isConfigured(in: [UpdateSettings.publicKeyKey: key]))
        #expect(!UpdateSettings.isConfigured(in: [UpdateSettings.feedKey: "", UpdateSettings.publicKeyKey: key]))
        #expect(!UpdateSettings.isConfigured(in: [UpdateSettings.feedKey: feed, UpdateSettings.publicKeyKey: " \n"]))
        #expect(!UpdateSettings.isConfigured(in: [UpdateSettings.feedKey: feed, UpdateSettings.publicKeyKey: 3]))
    }

    @Test func theRepositoryBuildCarriesNoFeedAndNoKey() {
        // The test host is a Debug build, which never has them, so no test run offers to replace the app under test.
        #expect(AppUpdater.standard() == nil)
        #expect(!UpdateSettings.isConfigured(in: Bundle.main.infoDictionary))
    }

    @Test func betaVersionsAddTheBetaChannel() {
        #expect(UpdateSettings.allowedChannels(betaIsOn: true) == ["beta"])
        #expect(UpdateSettings.allowedChannels(betaIsOn: false).isEmpty)
    }

    @Test func noSparkleKeyIsSyncedAndBetaVersionsStaysOnThisMac() {
        #expect(PreferencesMap.staysOnMac.contains(UpdateSettings.betaKey))
        #expect(MacSettings.keys.contains(UpdateSettings.betaKey))
        let synced = PreferencesMap.syncedKeys
        #expect(!synced.contains(UpdateSettings.betaKey))
        #expect(!synced.contains { $0.hasPrefix("SU") })
    }
}
