import Foundation
import Observation
import os
import SwiftUI

#if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
    import SharedWithYou
#endif

@MainActor
@Observable
final class SharedWithYouStore {
    private(set) var collectionTitle = String(
        localized: "Shared with You",
        comment: "Fallback title for Apple's Shared with You highlight collection"
    )
    private(set) var links: [ContentLink] = []
    private(set) var revision = 0

    #if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
        @ObservationIgnored private let highlightCenter: SWHighlightCenter
        @ObservationIgnored private let delegate: SharedWithYouHighlightDelegate
    #endif

    init() {
        #if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
            highlightCenter = SWHighlightCenter()
            delegate = SharedWithYouHighlightDelegate()
            collectionTitle = SWHighlightCenter.highlightCollectionTitle
            delegate.store = self
            highlightCenter.delegate = delegate
            reloadHighlights(from: highlightCenter.highlights)
        #endif
    }

    func refresh() {
        #if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
            reloadHighlights(from: highlightCenter.highlights)
        #endif
    }

    #if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
        func loadHighlight(for url: URL, receive: @escaping @MainActor @Sendable (SWHighlight?) -> Void) async {
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    highlightCenter.getHighlightFor(url) { highlight, _ in
                        // SWHighlightCenter.h guarantees this callback on the main
                        // queue. Consume the non-Sendable highlight there; only Void
                        // crosses the continuation boundary.
                        // SDK completion isolation is documented but not annotated.
                        nonisolated(unsafe) let mainQueueHighlight = highlight
                        MainActor.assumeIsolated {
                            if !cancelled.withLock({ $0 }) {
                                receive(mainQueueHighlight)
                            }
                            continuation.resume()
                        }
                    }
                }
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
        }

        fileprivate func reloadHighlights(from highlights: [SWHighlight]) {
            var seen: Set<ContentLink> = []
            let updatedLinks = highlights.compactMap { highlight -> ContentLink? in
                guard let link = ContentLink(url: highlight.url), seen.insert(link).inserted else {
                    return nil
                }
                return link
            }

            guard updatedLinks != links else { return }
            links = updatedLinks
            revision += 1
        }
    #endif
}

#if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
    private final class SharedWithYouHighlightDelegate: NSObject, SWHighlightCenterDelegate {
        weak var store: SharedWithYouStore?

        func highlightCenterHighlightsDidChange(_ highlightCenter: SWHighlightCenter) {
            Task { @MainActor [weak store] in
                // Read our own center on its owning actor; do not transfer the
                // delegate's non-Sendable center across queues.
                store?.refresh()
            }
        }
    }
#endif

#if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))
    struct SharedWithYouAttributionView: View {
        @Environment(SharedWithYouStore.self) private var sharedWithYou
        let link: ContentLink

        @State private var highlight: SWHighlight?

        var body: some View {
            Group {
                if let highlight {
                    PlatformSharedWithYouAttributionView(highlight: highlight)
                        .frame(maxWidth: 420, minHeight: 34, alignment: .leading)
                }
            }
            .task(id: link.universalURL) {
                await sharedWithYou.loadHighlight(for: link.universalURL) { highlight = $0 }
            }
        }
    }

    #if os(macOS)
        private struct PlatformSharedWithYouAttributionView: NSViewRepresentable {
            let highlight: SWHighlight

            func makeNSView(context: Context) -> SWAttributionView {
                let view = SWAttributionView()
                view.displayContext = .detail
                view.horizontalAlignment = .leading
                view.backgroundStyle = .material
                view.preferredMaxLayoutWidth = 420
                return view
            }

            func updateNSView(_ nsView: SWAttributionView, context: Context) {
                nsView.highlight = highlight
                nsView.preferredMaxLayoutWidth = 420
            }
        }
    #else
        private struct PlatformSharedWithYouAttributionView: UIViewRepresentable {
            let highlight: SWHighlight

            func makeUIView(context: Context) -> SWAttributionView {
                let view = SWAttributionView()
                view.displayContext = .detail
                view.horizontalAlignment = .leading
                view.backgroundStyle = .material
                view.preferredMaxLayoutWidth = 420
                return view
            }

            func updateUIView(_ uiView: SWAttributionView, context: Context) {
                uiView.highlight = highlight
                uiView.preferredMaxLayoutWidth = 420
            }
        }
    #endif
#else
    struct SharedWithYouAttributionView: View {
        let link: ContentLink

        var body: some View {
            EmptyView()
        }
    }
#endif
