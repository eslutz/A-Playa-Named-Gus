import SwiftUI

extension View {
    /// Handles pending content deep links (`gus://item/<id>`, `gus://play/<id>`) for the
    /// signed-in tree. Applied once at the signed-in root.
    func gusContentLinks() -> some View {
        modifier(ContentLinkHandler())
    }
}

/// Resolves a content link's item id through the active session and presents it
/// modally — detail links in a sheet (with full push navigation inside), play links
/// through the shared `playerPresentation` routing (video/audio/book/photo).
///
/// Modal presentation keeps deep links independent of which tab/sidebar section is
/// selected and of customized navigation, and works identically on every platform.
/// Links that arrive while signed out stay pending in `AppNavigationModel` and are
/// consumed here once a session exists.
private struct ContentLinkHandler: ViewModifier {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session

    @State private var detailItem: ItemRef?
    @State private var playerItem: ItemRef?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .task(id: navigation.contentLinkRequest) {
                guard navigation.contentLinkRequest > 0, let link = navigation.consumeContentLink() else { return }
                await resolve(link)
            }
            .sheet(item: $detailItem) { ref in
                NavigationStack {
                    ItemRouteDestination(item: ref.item)
                        .gusItemDestinations()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    detailItem = nil
                                }
                            }
                        }
                }
            }
            .playerPresentation(item: $playerItem)
            .alert(
                "Can't Open That",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func resolve(_ link: ContentLink) async {
        do {
            let item = try await session.mediaProvider.item(id: link.itemID)
            switch link {
            case .item:
                detailItem = ItemRef(item: item)
            case .play:
                playerItem = ItemRef(item: item)
            }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            errorMessage = gusError.localizedDescription
        }
    }
}
