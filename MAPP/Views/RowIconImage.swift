import MarfaIcons
import SwiftUI

/// A `RowIcon` drawn: a type's icon through the Swift SDK, which chooses the SF Symbol or artwork that stands for
/// it, or an SF Symbol the app chose for something that is not a type.
struct RowIconImage: View {
    let icon: RowIcon

    var body: some View {
        switch icon {
        case .symbol(let name): Image(systemName: name)
        case .type(let name): TypeIcon(name: name)
        }
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label for a menu or a button's title, where the mark has to be an image: a type's icon through the Swift
    /// SDK.
    init<S: StringProtocol>(_ title: S, typeIcon: String?) {
        self.init {
            Text(title)
        } icon: {
            Image(typeIcon: typeIcon)
        }
    }
}
