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

/// The indicator and automatic advance share the same monotonic deadline.
struct SeerrCarouselTiming {
    static let interval: Duration = .seconds(7)

    private(set) var pageID: String?
    private var elapsed: Duration = .zero
    private var began: ContinuousClock.Instant?

    var deadline: ContinuousClock.Instant? {
        began?.advanced(by: Self.interval - elapsed)
    }

    mutating func update(pageID: String, rotating: Bool, at now: ContinuousClock.Instant) {
        if self.pageID != pageID {
            self.pageID = pageID
            elapsed = .zero
            began = nil
        }
        if rotating {
            if began == nil {
                began = now
            }
        } else if let began {
            elapsed += began.duration(to: now)
            self.began = nil
        }
    }

    func progress(at now: ContinuousClock.Instant) -> Double {
        let running = began.map { $0.duration(to: now) } ?? .zero
        return min(1, max(0, (elapsed + running) / Self.interval))
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
    @State private var timing = SeerrCarouselTiming()
    @State private var pageTransition: UUID?
    @State private var scrolling = false
    @GestureState private var dragging = false
    @State private var visible = false
    @State private var appeared = false
    @FocusState private var focusedControl: String?

    private struct Rotation: Equatable {
        let pageID: String
        let rotating: Bool
    }

    private struct Advance: Equatable {
        let pageID: String
        let nextID: String
        let deadline: ContinuousClock.Instant
    }

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
        let rotating = allowsRotation && appeared && visible && scenePhase == .active &&
            !paused && !scrolling && !dragging && pageTransition == nil && focusedControl == nil
        let advance = rotating && timing.pageID == pages[index].seerrCatalogID ? timing.deadline.map {
            Advance(pageID: pages[index].seerrCatalogID, nextID: selection.ids[(index + 1) % pages.count], deadline: $0)
        } : nil

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
                                    pageDot(id: title.seerrCatalogID, selected: index == offset, showsProgress: allowsRotation, rotating: rotating)
                                        .accessibilityHidden(true)
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
                .onAppear { appeared = true }
                .onDisappear { appeared = false }
                .onChange(of: Rotation(pageID: pages[index].seerrCatalogID, rotating: rotating), initial: true) { _, rotation in
                    timing.update(pageID: rotation.pageID, rotating: rotation.rotating, at: ContinuousClock.now)
                }
                .task(id: advance) {
                    guard let advance else { return }
                    do { try await ContinuousClock().sleep(until: advance.deadline) }
                    catch { return }
                    guard !Task.isCancelled, timing.deadline == advance.deadline, selectedID == advance.pageID else { return }
                    showPage(advance.nextID)
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

    @ViewBuilder private func pageDot(id: String, selected: Bool, showsProgress: Bool, rotating: Bool) -> some View {
        if selected, showsProgress {
            TimelineView(.animation(paused: !rotating)) { _ in
                let progress = timing.pageID == id ? timing.progress(at: ContinuousClock.now) : 0
                Circle().strokeBorder(.tint, lineWidth: 1.5)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.tint)
                            .frame(width: 10 * CGFloat(progress))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .clipShape(Circle())
                    }
            }
            .frame(width: 10, height: 10)
        } else {
            Image(systemName: selected ? "circle.fill" : "circle")
                .font(.caption2)
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
        NavigationLink(value: store.navigationRoute(.title(title.mediaType ?? .unknown, title.id))) {
            SeerrFeaturedCard(title: title).contentShape(Rectangle())
        }
        .posterNavigationStyle()
        .focused($focusedControl, equals: title.seerrCatalogID)
        .accessibilityLabel(title.mediaAccessibility.label)
        .accessibilityValue(title.mediaAccessibility.value)
        .accessibilityIdentifier("Seerr.hero." + (title.mediaType?.rawValue ?? "") + "." + String(title.id))
    }

    private func showPage(_ id: String) {
        guard selectedID != id else { return }
        #if os(macOS)
            withAnimation(reduceMotion ? nil : .snappy) {
                scrollPosition.scrollTo(id: id, anchor: .center)
            }
        #else
            if reduceMotion {
                selectedID = id
            } else {
                let transition = UUID()
                pageTransition = transition
                withAnimation(.snappy, completionCriteria: .removed) {
                    selectedID = id
                } completion: {
                    if pageTransition == transition {
                        pageTransition = nil
                    }
                }
            }
        #endif
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
