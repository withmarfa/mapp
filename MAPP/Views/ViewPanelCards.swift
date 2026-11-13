import SwiftUI

/// The panel's section for a gallery, in place of Columns: what fills each card's picture area, and how large a card
/// is. What a card says under its picture is its type's look (`TypeLook`), not a choice of the view. A saved view's
/// choices are kept on this Mac as they are made, and a place's last as long as the window (`Browser.changeCards`).
struct ViewPanelCards: View {
    let browser: Browser
    let panel: ViewPanel

    var body: some View {
        let cards = browser.cards
        ViewPanelSection(title: "Cards", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Preview")
                    Spacer(minLength: 0)
                    Picker("Preview", selection: Binding { cards.preview } set: { value in browser.changeCards { $0.preview = value } }) {
                        ForEach(ViewCards.Preview.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelCardPreview")
                }
                HStack {
                    Text("Size")
                    Spacer(minLength: 0)
                    Picker("Size", selection: Binding { cards.size } set: { value in browser.changeCards { $0.size = value } }) {
                        ForEach(ViewCards.Size.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelCardSize")
                }
                Toggle("Fit Picture", isOn: Binding { cards.fitsPicture } set: { value in browser.changeCards { $0.fitsPicture = value } })
                    .disabled(!cards.preview.showsPicture)
                    .help(cards.preview.showsPicture ? "" : String(localized: "Only a card with a picture can fit it."))
                    .accessibilityIdentifier("ViewPanelCardFitPicture")
            }
        }
    }
}

extension ViewCards.Preview {
    var title: String {
        switch self {
        case .pictureOrText: String(localized: "Picture or Text")
        case .picture: String(localized: "Picture")
        case .text: String(localized: "Text")
        case .none: String(localized: "None")
        }
    }
}

extension ViewCards.Size {
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}
