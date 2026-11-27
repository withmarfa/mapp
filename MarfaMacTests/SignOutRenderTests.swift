import SwiftUI
import Testing
@testable import MarfaMac

extension SettingsRenderTests {
    @Test func signOutWithUnsentChanges() async throws {
        let (libraries, _) = try await connected()
        let model = libraries.marfaSettings
        let unsent = UnsentChanges(ids: ["reply", "kiln", "paper"], texts: [
            .init(id: "reply", change: .edit, content: SyncContent(title: "Reply to Ines about the zine proofs"), date: nil),
            .init(id: "kiln", change: .edit, content: SyncContent(title: "Kiln log, firing 14"), date: nil),
            .init(id: "paper", change: .create, content: SyncContent(title: "Paper for the zine"), date: nil),
        ])
        let departure = MarfaSettingsModel.Departure(kind: .disconnect, unsent: unsent)
        try await page(.account, owner(), sheet: AnyView(DepartureSheet(model: model, departure: departure).environment(libraries)),
                       named: "Account, sign out with unsent changes")
    }
}
