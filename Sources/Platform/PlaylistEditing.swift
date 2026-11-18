import SwiftUI

/// Remote-friendly fallback; touch platforms use native List movement.
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

/// Keep drag and playback hit targets separate, including when a row has a menu.
struct PlaylistDragHandle: View {
    let title: String
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        #if os(tvOS)
            PlaylistReorderHandle(title: title, moveUp: moveUp, moveDown: moveDown, canMoveUp: canMoveUp, canMoveDown: canMoveDown)
        #else
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Reorder \(title)")
                .accessibilityAction(named: "Move Up") {
                    if canMoveUp {
                        moveUp()
                    }
                }
                .accessibilityAction(named: "Move Down") {
                    if canMoveDown {
                        moveDown()
                    }
                }
        #endif
    }
}

extension DynamicViewContent {
    @ViewBuilder func gusPlaylistMove(enabled: Bool, action: @escaping (IndexSet, Int) -> Void) -> some View {
        #if os(tvOS)
            self
        #else
            onMove(perform: enabled ? action : nil)
        #endif
    }
}

extension View {
    @ViewBuilder func gusPlaylistSwipeRemove(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        #if os(iOS) || os(visionOS)
            swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if enabled {
                    Button(role: .destructive, action: action) {
                        Label("Remove", systemImage: "trash")
                    }
                    .accessibilityLabel("Remove \(title)")
                }
            }
        #else
            self
        #endif
    }
}
