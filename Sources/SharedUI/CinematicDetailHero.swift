import SwiftUI

/// Full-bleed backdrop header for an item detail screen: artwork, gradient scrim,
/// title block, play/up-next actions, and a caller-supplied accessory slot.
struct CinematicDetailHero<Accessory: View>: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var bookProgress: BookDetailProgress? = nil
    var primaryPlayEnabled = true
    var playbackHasProgress = false
    var startFromBeginning: (() -> Void)? = nil
    let backdropURL: URL?
    let play: () -> Void
    let isInUpNext: Bool
    let toggleUpNext: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        if item.isBookFormat || hasOnlyCoverArtwork {
            DetailCoverHeader {
                let urls = session.mediaProvider.artworkURLs(for: item, request: .init(role: item.coverArtworkRole, maxWidth: 640))
                ArtworkTile(
                    url: urls.first,
                    aspectRatio: item.primaryImageAspectRatio.flatMap { $0 > 0 ? $0 : nil } ?? (item.type == .audioBook ? 1 : 2.0 / 3.0),
                    contentMode: .fit,
                    placeholderSymbol: item.artworkPlaceholderSymbol,
                    fallbackURLs: Array(urls.dropFirst())
                )
                .frame(maxWidth: 240)
                .accessibilityHidden(true)
            } summary: {
                Text(item.displayTitle).font(titleFont).accessibilityAddTraits(.isHeader)
                if item.isBookFormat {
                    if let authors = item.bookAuthorText {
                        Text("By \(authors)")
                    }
                    if item.type == .audioBook, !item.bookNarratorNames.isEmpty {
                        Text("Narrated by \(item.bookNarratorNames.formatted(.list(type: .and)))")
                    }
                    if let publicationDetails {
                        Text(publicationDetails).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    HeroMetadataRow(item: item, foreground: .secondary)
                }
                actionStack
                synopsis
            }
            .tvFocusSection()
        } else {
            platformHero
        }
    }

    /// A portrait poster is the whole header artwork when Jellyfin has no landscape alternative.
    private var hasOnlyCoverArtwork: Bool {
        guard let ratio = item.primaryImageAspectRatio, ratio > 0, ratio < 1.33 else { return false }
        return item.backdropImageTags.isEmpty && item.parentBackdropImageTags.isEmpty && item.imageTags["Thumb"] == nil
    }

    @ViewBuilder private var synopsis: some View {
        if let overview = item.overview {
            DetailSynopsis(title: item.displayTitle, overview: overview, identifier: "Detail.heroOverview", focusItem: item)
        }
    }

    private var publicationDetails: String? {
        let year = item.yearText.map { year in
            item.type == .book ? String(localized: "Published \(year)") : String(localized: "Released \(year)")
        }
        let duration = item.type == .audioBook ? item.runtimeText.map { String(localized: "Duration \($0)") } : nil
        if let year, let duration {
            return String(localized: "\(year) · \(duration)")
        }
        return year ?? duration
    }

    private var platformHero: some View {
        let urls = session.mediaProvider.artworkURLs(for: item, request: .init(role: item.type == .episode ? .episodeStill : .backdrop, maxWidth: 1920))
        return DetailBackdropHeader {
            AsyncPoster(url: urls.first ?? backdropURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: Array(urls.dropFirst()), onExhausted: { _ = try? await session.references.currentItem(item) })
        } summary: {
            Text(item.displayTitle).font(titleFont).accessibilityAddTraits(.isHeader)
            HeroMetadataRow(item: item, foreground: .secondary)
            actionStack
            synopsis
        }
        .gusTVDetailHero(item: item, backdropURL: urls.first ?? backdropURL) {
            VStack(alignment: .leading, spacing: 24) {
                playButton
                DetailActionRow {
                    upNextButton.gusTVDetailActionFocus(id: "nextUp", item: item)
                    accessory
                }
                .frame(maxWidth: 528)
                .tvFocusSection()
            }
        }
    }

    private var actionStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            playButton
            if item.type == .book {
                // Primary reading actions must stay realized when a short landscape
                // viewport scrolls the secondary lazy grid in and out of view.
                BookActionButtons(item: item, progress: bookProgress)
            } else if let bookProgress {
                BookDetailProgressBar(progress: bookProgress)
            }
            DetailActionRow {
                upNextButton.gusTVDetailActionFocus(id: "nextUp", item: item)
                #if !os(tvOS)
                    restartButton
                #endif
                accessory
            }
            // These controls have spoken labels rather than visible text. Keep
            // symbols compact so accessibility text sizes cannot overlap peers.
            .dynamicTypeSize(...DynamicTypeSize.large)
            .gusPhoneHeroAccessoryStyle(onArtwork: false)
            .frame(maxWidth: DetailActionMetrics.maximumRowWidth)
        }
    }

    /// Books (epub/text) have no AVKit playback surface; show metadata without Play.
    private var isPlayableItem: Bool {
        item.type != .book && primaryPlayEnabled
    }

    @ViewBuilder
    private var playButton: some View {
        if isPlayableItem {
            DetailPrimaryButton(playbackHasProgress ? "Resume" : "Play", systemImage: "play.fill", action: play)
                .accessibilityIdentifier("Detail.play")
                .gusDefaultActionShortcut()
                .gusTVDetailActionFocus(id: "play", item: item, initial: true)
        }
    }

    private var upNextButton: some View {
        ItemUserActionButton(
            title: isInUpNext ? "Remove from Next Up" : "Add to Next Up",
            compactTitle: "Next Up",
            systemImage: isInUpNext ? MediaActionSymbols.removeFromNextUp : MediaActionSymbols.addToNextUp,
            action: toggleUpNext
        )
        .accessibilityIdentifier("Detail.nextUp")
    }

    @ViewBuilder private var restartButton: some View {
        if isPlayableItem, let startFromBeginning {
            ItemUserActionButton(title: "Start from Beginning", systemImage: "arrow.counterclockwise", action: startFromBeginning)
                .accessibilityIdentifier("Detail.restart")
        }
    }

    /// Text styles (not fixed sizes) so the title participates in Dynamic Type.
    private var titleFont: Font {
        #if os(tvOS)
            return .largeTitle.bold()
        #elseif os(visionOS)
            return .extraLargeTitle.bold()
        #elseif os(macOS)
            return .largeTitle.bold()
        #else
            return .title.bold()
        #endif
    }
}

/// Let the lower edge of the backdrop fade into the system surface beneath the title.
struct DetailBackdropHeader<Artwork: View, Summary: View>: View {
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let summary: () -> Summary

    var body: some View {
        VStack(spacing: -32) {
            Color.clear
                .aspectRatio(1.55, contentMode: .fit)
                .frame(maxHeight: 440)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { geometry in
                        artwork().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .backgroundExtensionEffect()
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 12) { summary() }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Keep the complete cover visible and place the summary alongside it when space permits.
struct DetailCoverHeader<Artwork: View, Summary: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let summary: () -> Summary

    var body: some View {
        AdaptiveStack(horizontalMinimumWidth: 640, horizontalAlignment: .center, verticalAlignment: .center, horizontalSpacing: 32, verticalSpacing: 20) { _ in
            artwork().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) { summary() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background {
            if !reduceTransparency {
                GeometryReader { geometry in
                    artwork()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(2)
                        .blur(radius: 40)
                        .opacity(0.25)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                }
                .clipped()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }
}

struct DetailPrimaryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .gusProminentActionForeground()
                .frame(maxWidth: .infinity)
        }
        .gusProminentGlassButtonStyle()
        .controlSize(.large)
        .frame(maxWidth: primaryWidth)
        .gusProminentActionTint()
        .visionHoverEffect(Capsule())
    }

    private var primaryWidth: CGFloat {
        #if os(tvOS)
            528
        #else
            min(320, DetailActionMetrics.maximumRowWidth)
        #endif
    }
}

// MARK: - Supporting types

/// Compact inline row of metadata tokens (year, runtime, rating, scores) shown in the hero.
struct HeroMetadataRow: View {
    let item: MediaItem
    var foreground: Color = .white

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                tokens
            }

            VStack(alignment: .leading, spacing: 6) {
                tokens
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tokens: some View {
        if let locator = item.type == .episode ? item.episodeLocator : nil {
            Text(locator)
        }
        if let year = item.yearText {
            Text(year)
        }
        if let runtime = item.runtimeText {
            Text(runtime)
        }
        if let rating = item.officialRating {
            Text(rating)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(foreground.opacity(0.5)))
        }
        if let community = item.communityRatingText {
            Text(community)
                .foregroundStyle(foreground)
        }
        if let critic = item.criticRatingText {
            Text(String(localized: "Critic \(critic)", comment: "Critic score label, e.g. 'Critic 74%'"))
        }
    }
}

/// Secondary hero action with a visible caption on TV and a spoken label elsewhere.
struct ItemUserActionButton: View {
    let title: LocalizedStringKey
    var compactTitle: LocalizedStringKey? = nil
    let systemImage: String
    let action: () -> Void

    private var visibleTitle: LocalizedStringKey {
        #if os(tvOS)
            compactTitle ?? title
        #else
            title
        #endif
    }

    var body: some View {
        Button(action: action) {
            Label(visibleTitle, systemImage: systemImage)
                .gusDetailActionLabel()
        }
        .gusDetailActionControlStyle()
        .accessibilityLabel(title)
    }
}

extension View {
    /// Secondary detail buttons and menu triggers share native sizing and treatment.
    func gusDetailActionControlStyle() -> some View {
        gusGlassButtonStyle()
            .controlSize(.regular)
            .frame(minWidth: 44, minHeight: 44)
            .visionHoverEffect(Capsule())
    }
}

/// Essential actions stay realized even below a short or enlarged-text viewport.
/// A native grid is the narrow-pane alternative to the single horizontal row.
struct DetailActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GusGlassControlGroup {
            DetailActionLayout { content }
        }
    }
}

/// Wrap naturally sized controls and center each line beneath the primary action.
struct DetailActionLayout: Layout {
    #if os(tvOS)
        private let spacing: CGFloat = 24
    #elseif os(visionOS)
        private let spacing: CGFloat = 16
    #else
        private let spacing: CGFloat = 8
    #endif

    private struct Line {
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(width: CGFloat?, subviews: Subviews) -> [Line] {
        var rows: [Line] = []
        var line = Line()
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if let width, size.width > width {
                size = subview.sizeThatFits(.init(width: width, height: nil))
            }
            if let width, !line.sizes.isEmpty, line.width + spacing + size.width > width {
                rows.append(line)
                line = Line()
            }
            line.width += (line.sizes.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.sizes.append(size)
        }
        if !line.sizes.isEmpty {
            rows.append(line)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let rows = lines(width: width, subviews: subviews)
        return CGSize(
            width: width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var index = 0
        var y = bounds.minY
        for line in lines(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - line.width / 2
            for size in line.sizes {
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += line.height + spacing
        }
    }
}
