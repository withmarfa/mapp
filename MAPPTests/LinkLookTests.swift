@testable import MAPP
import Foundation
import Testing

@Suite(.hangLimit)
@MainActor struct LinkLookTests {
    /// The names the page accepts from the app (`editor/src/link-style.ts`); it drops any other.
    private let accepted = /^--(inkkit-wiki-link|link)-[a-z-]+$/

    @Test func everyVariableOfEveryLookIsOneThePageAccepts() {
        for look in LinkLook.allCases {
            for name in look.cssVariables().keys {
                #expect(name.wholeMatch(of: accepted) != nil, "\(look): \(name)")
            }
        }
    }

    @Test func everyLookGivesEveryToneItsIconAndTintColors() {
        for look in LinkLook.allCases {
            let variables = look.cssVariables()
            for tone in TypeTone.allCases {
                #expect(variables["--link-icon-\(tone.rawValue)"] != nil, "\(look) icon \(tone)")
                #expect(variables["--link-tint-\(tone.rawValue)"] != nil, "\(look) tint \(tone)")
            }
        }
    }

    @Test func onlyTheMarkAndTheTintedPillColorTheIcon() {
        for look in LinkLook.allCases {
            let color = look.cssVariables()["--link-icon-blue"]
            #expect((color != "currentcolor") == (look == .mark || look == .tintedPill), "\(look)")
        }
    }

    @Test func theIconShowsOnlyInTheLooksThatDrawOne() {
        for look in LinkLook.allCases {
            let hidden = look.cssVariables()["--inkkit-wiki-link-icon-display"] == "none"
            #expect(hidden == !look.showsIcon, "\(look)")
        }
    }

    @Test func everyPillHasTheNeutralFillForALinkWithNoKnownType() {
        let neutral = LinkLook.pill.cssVariables()["--inkkit-wiki-link-background"]
        #expect(neutral != nil)
        #expect(LinkLook.tintedPill.cssVariables()["--inkkit-wiki-link-background"] == neutral)
        #expect(LinkLook.tintedPill.cssVariables()["--inkkit-wiki-link-tint-strength"] == "100%")
        for look in LinkLook.allCases where look != .pill && look != .tintedPill {
            #expect(look.cssVariables()["--inkkit-wiki-link-background"] == nil, "\(look)")
        }
    }

    @Test func aStoredLookThatIsNotOneOfTheSixIsTheMark() throws {
        let defaults = try #require(UserDefaults(suiteName: "LinkLookTests-\(UUID().uuidString)"))
        #expect(LinkLook.stored(in: defaults) == .mark)
        defaults.set("neon", forKey: LinkLook.key)
        #expect(LinkLook.stored(in: defaults) == .mark)
        defaults.set("tintedPill", forKey: LinkLook.key)
        #expect(LinkLook.stored(in: defaults) == .tintedPill)
    }
}
