import SwiftUI

/// Centers short setup flows, but scrolls naturally with the keyboard or large text.
struct SeerrSetupLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
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
    }
}
