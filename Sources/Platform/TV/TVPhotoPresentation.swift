import SwiftUI

extension View {
    @ViewBuilder func gusTVPhotoHeading(title: String, position: Int, total: Int) -> some View {
        #if os(tvOS)
            safeAreaInset(edge: .top) {
                HStack(spacing: 32) {
                    Text(title).font(.headline).lineLimit(2)
                    Spacer()
                    if total > 0 {
                        Text("\(position) of \(total)").monospacedDigit()
                    }
                }
                .padding(.horizontal, 64).padding(.vertical, 24)
                .gusTVCanvas()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Photo.heading")
            }
        #else
            self
        #endif
    }
}
