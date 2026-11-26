import Testing
@testable import MarfaMac

struct PersonAddressTests {
    @Test(arguments: [
        ("Ines Barros <ines@barroslima.example>", "Ines Barros", "ines@barroslima.example"),
        ("\"Barros, Ines\" <ines@barroslima.example>", "Barros, Ines", "ines@barroslima.example"),
        ("Pat \"PJ\" <pj@example.org>", "Pat \"PJ\"", "pj@example.org"),
        ("  \" Barros, Ines \"  <ines@barroslima.example>", "Barros, Ines", "ines@barroslima.example"),
        ("<ines@barroslima.example>", "ines@barroslima.example", nil),
        ("ines@barroslima.example", "ines@barroslima.example", nil),
        ("Calverts Deliveries", "Calverts Deliveries", nil),
    ] as [(String, String, String?)])
    func aPersonIsTheNameWithTheAddressApart(text: String, name: String, address: String?) {
        let person = PersonAddress(text)
        #expect(person?.name == name)
        #expect(person?.address == address)
    }

    @Test func nothingIsNoPerson() {
        #expect(PersonAddress("  ") == nil)
    }
}
