import SwiftUI

/// What shows a page's sheet in the middle of the whole window, over the sidebar and the toolbar, as an alert is. A page
/// hands its sheet over here, so it never drops from under the toolbar and the window needs no knowledge of the page.
@Observable @MainActor final class SettingsSheetPresenter {
    private(set) var content: AnyView?
    @ObservationIgnored private(set) var dismissal: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    var isPresented: Bool { content != nil }

    func present(owner: UUID, dismiss: @escaping () -> Void, content: AnyView) {
        self.owner = owner
        dismissal = dismiss
        self.content = content
    }

    /// Takes the sheet away if `owner` put it there.
    func remove(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        dismissal = nil
        content = nil
    }

    /// Asks the sheet's page to close it, as Escape does.
    func dismiss() {
        dismissal?()
    }
}

extension EnvironmentValues {
    /// The window's sheet, where the window has one.
    @Entry var settingsSheets: SettingsSheetPresenter?
}

private struct PresentsSettingsSheet<Sheet: View>: ViewModifier {
    let isPresented: Bool
    let dismiss: () -> Void
    let sheet: Sheet
    @Environment(\.settingsSheets) private var presenter
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        if let presenter {
            content
                .onChange(of: isPresented, initial: true) { sync(presenter) }
                .onDisappear { presenter.remove(owner: owner) }
        } else {
            content.settingsSheet(isPresented: isPresented, dismiss: dismiss) { sheet }
        }
    }

    private func sync(_ presenter: SettingsSheetPresenter) {
        if isPresented {
            presenter.present(owner: owner, dismiss: dismiss, content: AnyView(sheet))
        } else {
            presenter.remove(owner: owner)
        }
    }
}

extension View {
    /// Shows `sheet` in the middle of the Settings window while `isPresented`. What the sheet shows must be read from
    /// an `@Observable` model, never from the page's own `@State`, since the window draws it.
    func settingsSheet(presenting isPresented: Bool, dismiss: @escaping () -> Void, @ViewBuilder sheet: () -> some View) -> some View {
        modifier(PresentsSettingsSheet(isPresented: isPresented, dismiss: dismiss, sheet: sheet()))
    }
}
