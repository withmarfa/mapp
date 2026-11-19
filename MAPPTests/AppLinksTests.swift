import Foundation
import Testing
@testable import MAPP

struct AppLinksTests {
    @Test func aReportOpensANewIssueWithTheVersionsAndNothingElse() throws {
        let url = AppLinks.reportAProblem(version: "1.4.0", build: "212", system: "27.0.1")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "github.com")
        #expect(parts.path == "/withmarfa/mapp/issues/new")
        #expect(parts.queryItems?.map(\.name) == ["body"])
        let body = try #require(parts.queryItems?.first?.value)
        #expect(body.contains("MAPP 1.4.0 (212)"))
        #expect(body.contains("macOS 27.0.1"))
        #expect(!body.contains("http"))
        #expect(!body.contains("@"))
    }

    @Test func theReportFromThisMacNamesTheRunningSystem() throws {
        let parts = try #require(URLComponents(url: AppLinks.reportFromThisMac, resolvingAgainstBaseURL: false))
        let body = try #require(parts.queryItems?.first?.value)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #expect(body.contains("macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"))
    }

    @Test func everyHelpItemButTheShortcutsOpensAnAddress() {
        for item in HelpItem.allCases where item != .keyboardShortcuts {
            #expect(item.url?.scheme == "https", "\(item)")
        }
        #expect(HelpItem.keyboardShortcuts.url == nil)
        #expect(HelpItem.help.url == AppLinks.help)
        #expect(HelpItem.marfaDocumentation.url?.absoluteString == "https://docs.marfa.so")
    }
}
