import CryptoKit
import SwiftUI

/// Keep today's choices when a refresh reorders the feed or adds titles. Only IDs persist.
struct DailyTrendingSelection: Codable, Equatable {
    let day: Date
    let ids: [String]

    init(day: Date, candidates: [String], previous: Self?) {
        self.day = day
        var remaining = Set(candidates)
        let previousIDs = previous.flatMap { $0.day == day ? $0.ids : nil } ?? []
        let retained = previousIDs.filter { remaining.remove($0) != nil }
        let vacancies = max(0, 8 - retained.count)
        guard vacancies > 0 else {
            ids = Array(retained.prefix(8))
            return
        }
        // Rank the IDs by a daily digest so server ordering and Swift's per-process hash seed
        // cannot change the sample across launches.
        let seed = String(Int(day.timeIntervalSince1970))
        let ranked = remaining.map { id in
            (id: id, digest: SHA256.hash(data: Data("\(seed)/\(id)".utf8)))
        }.sorted { $0.digest.lexicographicallyPrecedes($1.digest) }
        ids = retained + ranked.prefix(vacancies).map(\.id)
    }
}

struct SeerrTrendingCarousel: View {
    let titles: [SeerrTitle]
    /// The local day of the successful Trending response, including while a refresh is pending.
    let day: Date
    let store: SeerrStore
    let canSaveSelection: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage private var savedSelection: Data
    @State private var selectedID: String?
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var paused = false
    @State private var scrolling = false
    @GestureState private var dragging = false
    @State private var visible = false
    @FocusState private var focusedControl: String?
    #if os(tvOS)
        private let indicatorSpacing: CGFloat = 12
    #else
        private let indicatorSpacing: CGFloat = 0
    #endif

    init(titles: [SeerrTitle], day: Date, store: SeerrStore, canSaveSelection: Bool = true) {
        self.titles = titles
        self.day = day
        self.store = store
        self.canSaveSelection = canSaveSelection
        _savedSelection = AppStorage(wrappedValue: Data(), store.featuredSelectionDefaultsKey)
    }

    var body: some View {
        let media = titles.filter { $0.mediaType == .movie || $0.mediaType == .tv }
        let byID = Dictionary(media.map { ($0.seerrCatalogID, $0) }, uniquingKeysWith: { first, _ in first })
        let previous = try? JSONDecoder().decode(DailyTrendingSelection.self, from: savedSelection)
        let selection = DailyTrendingSelection(day: day, candidates: Array(byID.keys), previous: previous)
        let pages = selection.ids.compactMap { byID[$0] }
        let index = selectedID.flatMap { selection.ids.firstIndex(of: $0) } ?? 0
        let allowsRotation = pages.count > 1 && !reduceMotion && !voiceOver
        let rotating = allowsRotation && visible && scenePhase == .active && !paused && !scrolling && !dragging && focusedControl == nil
        let nextID = rotating ? selection.ids[(index + 1) % pages.count] : nil

        Group {
            if !pages.isEmpty {
                VStack(spacing: 4) {
                    pager(pages: pages, current: pages[index])
                        .accessibilityIdentifier("Seerr.carousel")

                    if pages.count > 1 {
                        HStack(spacing: indicatorSpacing) {
                            ForEach(Array(pages.enumerated()), id: \.element.seerrCatalogID) { offset, title in
                                Button {
                                    showPage(title.seerrCatalogID)
                                } label: {
                                    Image(systemName: index == offset ? "circle.fill" : "circle")
                                        .font(.caption2)
                                        .frame(minWidth: 26, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .focused($focusedControl, equals: "indicator." + title.seerrCatalogID)
                                .accessibilityLabel(title.displayTitle)
                                .accessibilityValue(Text("\(offset + 1) of \(pages.count)"))
                                .accessibilityAddTraits(index == offset ? .isSelected : [])
                                .accessibilityIdentifier("Seerr.carousel.page.\(offset + 1)")
                            }
                            if allowsRotation {
                                Button { paused.toggle() } label: {
                                    Image(systemName: paused ? "play.fill" : "pause.fill")
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .focused($focusedControl, equals: "playback")
                                .accessibilityLabel(paused ? "Play Slideshow" : "Pause Slideshow")
                                .accessibilityIdentifier("Seerr.carousel.pause")
                            }
                        }
                        .buttonStyle(.borderless)
                        .tvFocusSection()
                        #if os(iOS) || os(visionOS)
                            .simultaneousGesture(SpatialTapGesture().onEnded { _ in focusedControl = nil })
                        #endif
                    }
                }
                .onGeometryChange(for: Bool.self) { proxy in
                    guard let viewport = proxy.bounds(of: .scrollView(axis: .vertical)) else { return true }
                    let bounds = CGRect(origin: .zero, size: proxy.size)
                    return bounds.intersection(viewport).height > min(bounds.height, viewport.height) / 2
                } action: { visible = $0 }
                .task(id: nextID) {
                    guard let nextID else { return }
                    do { try await Task.sleep(for: .seconds(7)) }
                    catch { return }
                    showPage(nextID)
                }
            }
        }
        .onChange(of: canSaveSelection ? selection : nil, initial: true) { _, selection in
            if let selection, previous != selection, !selection.ids.isEmpty, let data = try? JSONEncoder().encode(selection) {
                savedSelection = data
            }
        }
        .onChange(of: selection.ids, initial: true) { _, ids in
            if selectedID.map(ids.contains) != true {
                selectedID = ids.first
                #if os(macOS)
                    if let first = ids.first {
                        scrollPosition.scrollTo(id: first, anchor: .center)
                    }
                #endif
            }
        }
    }

    @ViewBuilder private func pager(pages: [SeerrTitle], current: SeerrTitle) -> some View {
        #if !os(macOS)
            // TabView needs an intrinsic height when embedded in a vertical feed. Size it
            // against the current card, including the stacked caption at large text sizes.
            SeerrFeaturedCard(title: current, measuring: true)
                .hidden()
                .accessibilityHidden(true)
                .overlay {
                    TabView(selection: Binding(get: { selectedID ?? current.seerrCatalogID }, set: { selectedID = $0 })) {
                        ForEach(pages, id: \.seerrCatalogID) { title in
                            cardLink(title)
                                .tag(title.seerrCatalogID)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .lookToScroll(.horizontal)
                    #if os(iOS) || os(visionOS)
                        .simultaneousGesture(DragGesture().updating($dragging) { _, state, _ in state = true })
                    #endif
                }
                .accessibilityElement(children: .contain)
        #else
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages, id: \.seerrCatalogID) { title in
                        cardLink(title)
                            .accessibilityHidden(title.seerrCatalogID != current.seerrCatalogID)
                            .containerRelativeFrame(.horizontal)
                            .id(title.seerrCatalogID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition($scrollPosition, anchor: .center)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.51) { visibleIDs in
                if let id = visibleIDs.first {
                    selectedID = id
                }
            }
            .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
        #endif
    }

    private func cardLink(_ title: SeerrTitle) -> some View {
        NavigationLink {
            SeerrTitleDetailView(title: title, store: store)
        } label: {
            SeerrFeaturedCard(title: title).contentShape(Rectangle())
        }
        .posterNavigationStyle()
        .focused($focusedControl, equals: title.seerrCatalogID)
        .accessibilityLabel(title.mediaAccessibility.label)
        .accessibilityValue(title.mediaAccessibility.value)
        .accessibilityIdentifier("Seerr.hero." + (title.mediaType?.rawValue ?? "") + "." + String(title.id))
    }

    private func showPage(_ id: String) {
        withAnimation(reduceMotion ? nil : .snappy) {
            #if !os(macOS)
                selectedID = id
            #else
                scrollPosition.scrollTo(id: id, anchor: .center)
            #endif
        }
    }
}

private struct SeerrFeaturedCard: View {
    let title: SeerrTitle
    var measuring = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(tvOS)
            HStack(alignment: .center, spacing: 64) {
                artwork.frame(maxWidth: 700)
                caption
                Spacer(minLength: 0)
            }
            .padding(32)
        #else
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    artwork
                    caption
                }
            } else {
                artwork.overlay(alignment: .bottomLeading) {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .overlay(alignment: .bottomLeading) { caption.padding(20).foregroundStyle(.white) }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        #endif
    }

    @ViewBuilder private var artwork: some View {
        if measuring {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
        } else {
            SeerrArtworkView(
                path: title.backdropPath,
                aspectRatio: 16.0 / 9.0,
                width: "w1280",
                fallbackURL: SeerrArtwork.url(path: title.posterPath, width: "w780")
            )
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.displayTitle).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text(title.seerrIdentityDescription).font(.subheadline)
        }
    }
}
