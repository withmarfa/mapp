import SwiftUI

extension View {
    /// Withdrawing the view releases pending adds because the person has not chosen to skip any files.
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
