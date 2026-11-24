import Foundation
import Testing
@testable import MarfaMac

struct LinkAppTitlesTests {
    private func candidate(_ name: String, _ version: String?, _ folder: String, path: String? = nil) -> LinkApp.Candidate {
        LinkApp.Candidate(
            url: URL(fileURLWithPath: (path ?? "/\(folder)") + "/\(name).app"), name: name, version: version, folder: folder,
            path: path ?? "/\(folder)")
    }

    @Test func appsSharingANameAreToldApartByVersionAndFolder() {
        let titles = LinkApp.titles(for: [
            candidate("Marfa", "0.0.12", "Applications"), candidate("Marfa", "0.0.13", "Debug"), candidate("Other", "2.0", "Applications"),
            candidate("Same", "1", "Debug", path: "/one/Debug"), candidate("Same", "1", "Debug", path: "/two/Debug"),
        ])
        #expect(titles == [
            "Marfa (0.0.12) in Applications", "Marfa (0.0.13) in Debug", "Other", "Same (1) in /one/Debug", "Same (1) in /two/Debug",
        ])
    }
}
