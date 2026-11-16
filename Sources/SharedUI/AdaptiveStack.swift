import SwiftUI

/// Changes the native stack layout without replacing its content or control identity.
/// The available width belongs to this container, including in a split view or sheet.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let horizontalMinimumWidth: CGFloat
    var horizontalAlignment: VerticalAlignment = .center
    var verticalAlignment: HorizontalAlignment = .leading
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    var prefersVertical = false
    var containerAlignment: Alignment = .leading
    @ViewBuilder let content: (Bool) -> Content
    @State private var availableWidth: CGFloat = 0

    private var isHorizontal: Bool {
        !prefersVertical && !dynamicTypeSize.isAccessibilitySize && availableWidth >= horizontalMinimumWidth
    }

    var body: some View {
        let layout = isHorizontal
            ? AnyLayout(HStackLayout(alignment: horizontalAlignment, spacing: horizontalSpacing))
            : AnyLayout(VStackLayout(alignment: verticalAlignment, spacing: verticalSpacing))
        layout { content(isHorizontal) }
            .frame(maxWidth: .infinity, alignment: containerAlignment)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}
