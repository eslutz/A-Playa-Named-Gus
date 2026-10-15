import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI's built-in reorder handles sit on the right; native drag/drop lets the
/// requested left handle coexist with an independent trailing trash action.
struct PlaylistReorderHandle: View {
    let payload: PlaylistItemDrag
    let title: String
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        #if os(tvOS)
            Menu { moveActions } label: { Image(systemName: "line.3.horizontal").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Reorder \(title)")
        #else
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .onDrag {
                    let provider = NSItemProvider()
                    if let data = try? JSONEncoder().encode(payload) {
                        provider.registerDataRepresentation(forTypeIdentifier: "dev.ericslutz.gus.playlist-item", visibility: .ownProcess) { completion in
                            completion(data, nil)
                            return nil
                        }
                    }
                    return provider
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Reorder \(title)")
                .accessibilityHint("Drag to reorder this item")
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

    @ViewBuilder private var moveActions: some View {
        Button("Move Up", action: moveUp).disabled(!canMoveUp)
        Button("Move Down", action: moveDown).disabled(!canMoveDown)
    }
}

extension View {
    /// Decode the native drop before account and occurrence validation.
    @ViewBuilder func playlistDropTarget(enabled: Bool, action: @escaping @MainActor @Sendable (PlaylistItemDrag) -> Bool) -> some View {
        #if os(tvOS)
            self
        #else
            onDrop(of: [UTType(exportedAs: "dev.ericslutz.gus.playlist-item", conformingTo: .data)], isTargeted: nil) { providers in
                guard enabled, providers.count == 1 else { return false }
                providers[0].loadDataRepresentation(forTypeIdentifier: "dev.ericslutz.gus.playlist-item") { data, _ in
                    guard let data, data.count <= 16384,
                          let payload = try? JSONDecoder().decode(PlaylistItemDrag.self, from: data) else { return }
                    Task { @MainActor in
                        _ = action(payload)
                    }
                }
                return true
            }
        #endif
    }
}

/// tvOS has no GroupBox; its native stack retains the same contextual controls.
struct PlaylistEditingGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 0) { content }
        #else
            GroupBox { content }
        #endif
    }
}
