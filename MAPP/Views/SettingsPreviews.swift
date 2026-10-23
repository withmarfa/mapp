#if DEBUG
import SwiftUI

private struct SettingsPreviewWindow: View {
    let page: SettingsPage
    let browser = Browser()

    var body: some View {
        let _ = browser.showSettings(page)
        MainView(browser: browser, restoresWindow: false)
            .environment(\.library, ItemPreviewFixtures.library)
            .environment(ItemPreviewFixtures.libraries(named: "MAPP.SettingsPreview"))
            .frame(width: 1280, height: 800)
    }
}

#Preview("Settings: Appearance") { SettingsPreviewWindow(page: .appearance) }
#Preview("Settings: Editor") { SettingsPreviewWindow(page: .editor) }
#Preview("Settings: Sidebar") { SettingsPreviewWindow(page: .sidebar) }
#Preview("Settings: Library") { SettingsPreviewWindow(page: .library) }
#Preview("Settings: Recently Deleted") { SettingsPreviewWindow(page: .recentlyDeleted) }
#Preview("Settings: About") { SettingsPreviewWindow(page: .about) }
#endif
