import SwiftUI

/// Remote-friendly fallback; touch platforms use native List row movement.
struct PlaylistReorderHandle: View {
    let title: String
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        Menu {
            Button("Move Up", action: moveUp).disabled(!canMoveUp)
            Button("Move Down", action: moveDown).disabled(!canMoveDown)
        } label: {
            Image(systemName: "line.3.horizontal").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Reorder \(title)")
    }
}
