import Foundation
import Testing
@testable import MarfaMac

struct AppLinksTests {
    @Test func aReportOpensANewIssueWithTheVersionsAndNothingElse() throws {
        let url = AppLinks.reportAProblem(version: "1.4.0", build: "212", system: "27.0.1")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "github.com")
        #expect(parts.path == "/withmarfa/marfa-mac/issues/new")
        #expect(parts.queryItems?.map(\.name) == ["body"])
        let body = try #require(parts.queryItems?.first?.value)
        #expect(body.contains("Marfa for Mac 1.4.0 (212)"))
        #expect(body.contains("macOS 27.0.1"))
        #expect(!body.contains("http"))
        #expect(!body.contains("@"))
    }
}
