import Foundation
import Testing

struct AppConfigurationTests {
    @Test func bundleIdentifierIsTheWithMarfaOne() {
        #expect(Bundle.main.bundleIdentifier == "com.withmarfa.mapp")
    }
}
