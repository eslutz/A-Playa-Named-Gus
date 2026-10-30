import SwiftUI

/// Centers short setup flows, but scrolls naturally with the keyboard or large text.
struct SeerrSetupLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
            Group(subviews: content) { children in
                HStack(alignment: .center, spacing: 80) {
                    VStack(alignment: .leading, spacing: 32) {
                        Text("Seerr").font(.largeTitle.bold())
                        children[0]
                    }.frame(maxWidth: 640, alignment: .leading)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            ForEach(children[1...]) { child in child }
                        }
                        .padding(32)
                    }
                }
                .padding(64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gusTVCanvas()
            }
        #else
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) { content }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(24)
                        .frame(maxWidth: 480)
                        .frame(minHeight: max(0, geometry.size.height), alignment: .center)
                        .frame(maxWidth: .infinity)
                }
                .seerrSetupKeyboardDismissal()
            }
        #endif
    }
}
