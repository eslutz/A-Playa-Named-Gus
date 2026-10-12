import SwiftUI

extension View {
    /// Handles pending content deep links (`gus://item/<id>`, `gus://play/<id>`) for the
    /// signed-in tree. Applied once at the signed-in root.
    func gusContentLinks() -> some View {
        modifier(ContentLinkHandler())
    }
}

/// Resolves content links through the active session. Detail links push into the current
/// tvOS stack or use a sheet on the other platforms; play links use the session player host.
/// Links that arrive while signed out stay pending in `AppNavigationModel` and are
/// consumed here once a session exists.
private struct ContentLinkHandler: ViewModifier {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(RootNavigationState.self) private var rootState
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session

    @State private var playerItem: ItemRef?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .task(id: navigation.contentLinkRequest) {
                guard navigation.contentLinkRequest > 0, let link = navigation.consumeContentLink() else { return }
                await resolve(link)
            }
            .sheet(item: Bindable(rootState).projectedValue.detailItem) { ref in
                NavigationStack {
                    ItemRouteDestination(item: ref.item)
                        .gusItemDestinations()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done", systemImage: "xmark") {
                                    rootState.detailItem = nil
                                }
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier("ContentLink.detailDone")
                            }
                        }
                }
                .gusSessionPlayerHost(state: rootState)
                .gusAudioHost(coordinator: audio)
                .gusNowPlaying(coordinator: audio, usesTabAccessory: false)
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
            guard link.accepts(server: session.server) else { throw GusError.notFound }
            let item = try await session.references.currentItem(MediaItem(providerKind: session.server.providerKind, id: link.itemID))
            guard ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
            try Task.checkCancellation()
            switch link {
            case .item:
                #if os(tvOS)
                    rootState.paths[rootState.selectedSectionID, default: NavigationPath()].append(ItemRef(item: item))
                #else
                    rootState.detailItem = ItemRef(item: item)
                #endif
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
