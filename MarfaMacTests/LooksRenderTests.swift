import SwiftUI
import Testing
@testable import MarfaMac

/// The Foundations looks (chips, person, keycaps, status marks, priority tones, the tinted type chip) drawn offscreen in
/// the light and the dark appearance, for a pull request's pictures. Skipped unless `MARFA_MAC_SETTINGS_RENDERS` names a folder.
@Suite(.enabled(if: SettingsRender.isRequested), .serialized, .hangLimit)
@MainActor struct LooksRenderTests {
    private struct Sheet: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                row("Status") {
                    PageChip(text: "Not started", kind: .status(.notStarted, chevron: true))
                    PageChip(text: "In progress", kind: .status(.inProgress, chevron: true))
                    PageChip(text: "Done", kind: .status(.completed, chevron: false))
                    PageChip(text: "Canceled", kind: .status(.canceled, chevron: false))
                }
                row("Priority") {
                    ForEach(Array(["Low", "Medium", "High", "Urgent"].enumerated()), id: \.offset) { index, name in
                        PageChip(text: name, kind: .option(OptionTone.prioritySteps[index]))
                    }
                }
                row("Option, tag, plain") {
                    PageChip(text: "Design", kind: .option(.teal))
                    PageChip(text: "research", kind: .tag)
                    PageChip(text: "12 Nov", kind: .plain)
                }
                row("In a row") {
                    PageChip(text: "High", kind: .option(.orange), size: .row)
                    PageChip(text: "research", kind: .tag, size: .row)
                    PageChip(text: "In progress", kind: .status(.inProgress, chevron: false), size: .row)
                }
                row("Type and link, as a fact") {
                    MarkedName(text: "Task", icon: "lucide:check-square")
                    MarkedName(text: "Field research", icon: nil)
                }
                row("Type being given") {
                    TintedChip(text: "Note", icon: "lucide:sticky-note")
                    TintedChip(text: "Task", icon: "lucide:check-square")
                }
                row("Person") {
                    PersonCircle(initials: "AC")
                    PagePerson(name: "August Cayzer", initials: "AC")
                    PersonCircle(initials: "MK", size: .row)
                }
                row("Type marks") {
                    TonedGlyph(id: "lucide:sticky-note")
                    TonedGlyph(id: "lucide:check-square")
                    TonedGlyph(id: "lucide:user")
                    TonedGlyph(id: "lucide:film")
                }
                row("Focus ring") {
                    TextField("Search", text: .constant("")).textFieldStyle(.plain).padding(.horizontal, 8).frame(width: 160, height: 28)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7, style: .continuous))
                        .appFocusRing(isFocused: true)
                }
                row("Keycaps") {
                    ShortcutKeys("⇧⌘P")
                    KeyCap(key: "K")
                }
            }
            .padding(20)
        }

        private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
            HStack(spacing: 10) {
                Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                content()
            }
        }
    }

    @Test func looks() async throws {
        for (scheme, label) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            try await SettingsRender.png(
                Sheet().background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 620, height: 470),
                named: "Looks, \(label)", appearance: scheme, settle: .milliseconds(300))
        }
    }
}
