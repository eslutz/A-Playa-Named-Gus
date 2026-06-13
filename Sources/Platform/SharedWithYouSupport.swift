import Foundation
import Observation
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
        func highlight(for url: URL) async -> SWHighlight? {
            await withCheckedContinuation { continuation in
                highlightCenter.getHighlightFor(url) { highlight, _ in
                    continuation.resume(returning: highlight)
                }
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
                store?.reloadHighlights(from: highlightCenter.highlights)
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
                highlight = await sharedWithYou.highlight(for: link.universalURL)
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
