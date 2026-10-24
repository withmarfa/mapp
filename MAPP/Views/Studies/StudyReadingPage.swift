import SwiftUI

struct StudyReaderOptions {
    var propertiesInRail = false
    var wide = false
    var serif = true
}

struct StudyReadingPage: View {
    @Binding var options: StudyReaderOptions
    let open: (InterfaceStudy) -> Void

    var body: some View {
        GeometryReader { geometry in
            let showsRail = options.propertiesInRail && geometry.size.width >= 850
            VStack(spacing: 0) {
                optionsBar
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        article(inlineProperties: !showsRail)
                            .frame(maxWidth: options.wide ? 880 : 680, alignment: .leading)
                            .padding(.horizontal, geometry.size.width < 600 ? 24 : 44)
                            .padding(.vertical, 44)
                            .frame(maxWidth: .infinity)
                    }
                    if showsRail {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                Text("About this reading").font(.headline)
                                StudyReadingProperties(vertical: true)
                                Divider()
                                Text("In this collection").font(.headline)
                                StudyRelatedLink(title: "A garden in a small space", subtitle: "Collection overview", symbol: "square.stack") {
                                    open(.collection)
                                }
                            }
                            .padding(24)
                        }
                        .frame(width: 260)
                        .background(.quaternary.opacity(0.3))
                    }
                }
            }
        }
    }

    private var optionsBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { optionPickers }
            VStack(alignment: .leading, spacing: 12) { optionPickers }
        }
        .controlSize(.small)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var optionPickers: some View {
        Picker("Properties", selection: $options.propertiesInRail) {
            Text("Inline").tag(false)
            Text("Side rail").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 230)
        Picker("Reading width", selection: $options.wide) {
            Text("Comfortable").tag(false)
            Text("Wide").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 230)
        Picker("Typeface", selection: $options.serif) {
            Text("Serif").tag(true)
            Text("System").tag(false)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
    }

    private func article(inlineProperties: Bool) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                StudyEyebrow(title: "Field & Street", symbol: "newspaper")
                Text("The case for small, wet corners")
                    .font(.system(size: 38, weight: .semibold, design: options.serif ? .serif : .default))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 16) {
                    Text("Mara Quinn")
                    Text("6 min read")
                }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("A little space for rain can change the way a whole garden works.")
                    .font(.system(size: 20, design: options.serif ? .serif : .default))
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
            }

            if inlineProperties {
                Divider()
                StudyReadingProperties(vertical: false)
                if options.propertiesInRail {
                    Text("Properties move above the page in a narrower window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 22) {
                Text("Every garden has a place where the rain lingers. It might be the low corner beside a path, or the strip beneath a downpipe. We tend to see it as a problem to drain away. It can also be a place to begin.")
                Text("The small rain garden in this story started with observation: where water arrived, how long it stayed, and which plants were already happy there. Its shape followed those answers. The planting came later.")
                Text("Start with what is already there")
                    .font(.system(size: 25, weight: .semibold, design: options.serif ? .serif : .default))
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)
                Text("A shallow basin does not need to look like a piece of engineering. Sedges give it a soft edge. Iris brings a brief, bright season. A flat stone marks the crossing, so the wet corner becomes part of the route through the garden rather than a place to avoid.")
                Text("Begin with one corner. Watch it through a few heavy showers before deciding what it needs. A useful garden is often the result of paying attention to a small thing for a little longer.")
            }
            .font(.system(size: 18, design: options.serif ? .serif : .default))
            .lineSpacing(8)
            .textSelection(.enabled)

            Divider().padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected reading").font(.headline).padding(.bottom, 6)
                StudyRelatedLink(title: "A small space asks for fewer ideas", subtitle: "Highlight from Small Is Plenty", symbol: "quote.opening") {
                    open(.highlight)
                }
                Divider()
                StudyRelatedLink(title: "A garden in a small space", subtitle: "Ideas, observations, and the next small step", symbol: "square.stack") {
                    open(.collection)
                }
            }
            Text("Fictional article for this interface study.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StudyReadingProperties: View {
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
        ViewThatFits(in: .horizontal) {
            layout { fields }
            VStack(alignment: .leading, spacing: 16) { fields }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var fields: some View {
        property("Source", value: "Field & Street")
        property("Context", value: "Small-space gardening")
        property("Saved", value: "Today at 7:42 AM")
    }

    private func property(_ label: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
