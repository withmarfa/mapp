import Foundation
import Testing
@testable import MAPP

/// Numbers typed into a property field are read the way the person's locale writes them.
struct PropertyNumberTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func aDecimalPointIsReadInEnglish() {
        #expect(PropertyNumber.parse("1.5", integer: false, locale: english) == Decimal(string: "1.5"))
        #expect(PropertyNumber.parse(" -2 ", integer: false, locale: english) == -2)
    }

    @Test func aDecimalCommaIsReadInGerman() {
        #expect(PropertyNumber.parse("1,5", integer: false, locale: german) == Decimal(string: "1.5"))
    }

    @Test func theOtherLocalesSeparatorIsNotANumber() {
        #expect(PropertyNumber.parse("1,5", integer: false, locale: english) == nil)
        #expect(PropertyNumber.parse("1.5", integer: false, locale: german) == nil)
    }

    @Test func anIntegerFieldRefusesAFraction() {
        #expect(PropertyNumber.parse("1.5", integer: true, locale: english) == nil)
        #expect(PropertyNumber.parse("1,5", integer: true, locale: german) == nil)
        #expect(PropertyNumber.parse("15", integer: true, locale: german) == 15)
    }

    @Test func noFieldTakesAnExponentOrWords() {
        for text in ["1e3", "1E3", "7 apples", "", "-", "1.2.3", "NaN", "٣"] {
            #expect(PropertyNumber.parse(text, integer: false, locale: english) == nil, "\(text)")
            #expect(PropertyNumber.parse(text, integer: true, locale: english) == nil, "\(text)")
        }
    }

    @Test func editingTextReadsBackAsTheSameNumber() throws {
        for locale in [english, german] {
            let value = try #require(Decimal(string: "1234.56"))
            let text = PropertyNumber.editing(value, locale: locale)
            #expect(PropertyNumber.parse(text, integer: false, locale: locale) == value)
        }
        #expect(PropertyNumber.editing(Decimal(string: "1234.5")!, locale: german) == "1234,5")
    }

    @Test func aDraftRefusesAFractionForAnInteger() {
        let draft = ItemPropertyDraft()
        draft.base = "5"
        draft.text = "1.5"
        draft.isDirty = true
        #expect(draft.commit(as: .number, rule: NumberRule(integer: true), current: "5", locale: english) == .invalid)
        #expect(draft.commit(as: .number, current: "5", locale: english) == .write(.number(Decimal(string: "1.5")!)))
        draft.text = "1e3"
        #expect(draft.commit(as: .number, rule: NumberRule(integer: true), current: "5", locale: english) == .invalid)
    }

    @Test func aDraftReadsGermanDecimals() {
        let draft = ItemPropertyDraft()
        draft.base = "5"
        draft.text = "1,5"
        draft.isDirty = true
        #expect(draft.commit(as: .number, current: "5", locale: german) == .write(.number(Decimal(string: "1.5")!)))
    }
}
