import SwiftUI

extension View {
    /// Shows the system's alert for files about to be added that are already in Marfa (`AlreadyInMarfa`), one
    /// question at a time. Open is the default button: Return then adds no second copy and loses nothing, since the
    /// files with no match are still added. A view that goes lets what waits go ahead unasked, as with no answer.
    func asksAboutFilesInMarfa(_ asking: AlreadyInMarfa.Asking) -> some View {
        modifier(AlreadyInMarfaAlert(asking: asking))
    }
}

private struct AlreadyInMarfaAlert: ViewModifier {
    let asking: AlreadyInMarfa.Asking

    func body(content: Content) -> some View {
        content
            .alert(
                asking.question?.title ?? "",
                // Every way out of the alert is one of its buttons, Escape being Cancel's, so only they answer.
                isPresented: Binding { asking.question != nil } set: { _ in },
                presenting: asking.question
            ) { question in
                Button("Add Anyway") { asking.answer(.addAnyway, to: question.id) }
                Button("Open") { asking.answer(.open, to: question.id) }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { asking.answer(.cancel, to: question.id) }
            } message: { question in
                Text(question.message)
            }
            .onAppear { asking.viewAppeared() }
            .onDisappear { asking.viewDisappeared() }
    }
}
