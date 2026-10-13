import SwiftUI

/// Full-bleed backdrop header for an item detail screen: artwork, gradient scrim,
/// title block, play/up-next actions, and a caller-supplied accessory slot.
struct CinematicDetailHero<Accessory: View>: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: MediaItem
    var playbackItem: MediaItem? = nil
    var primaryPlayEnabled = true
    let backdropURL: URL?
    let play: () -> Void
    let isInUpNext: Bool
    let toggleUpNext: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        standardHero.gusTVDetailHero(item: item, backdropURL: backdropURL) {
            HStack(spacing: 24) {
                playButton
                Menu { upNextButton; accessory } label: { Label("More", systemImage: "ellipsis") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("Detail.more")
                    .gusTVFocus(id: "more", section: "detail:" + ItemRef(item: item).id, ids: ["play", "more", "synopsis"], item: item)
            }
        }
    }

    private var standardHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 28) {
                titleBlock
                    .frame(maxWidth: 760, alignment: .leading)
                actionStack
                    .frame(width: DetailActionMetrics.maximumRowWidth)
            }
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                actionStack
            }
        }
        .padding(heroPadding)
        .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: baseHeroHeight, alignment: .bottomLeading)
        .background {
            GeometryReader { geometry in
                AsyncPoster(url: backdropURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1280), onExhausted: { _ = try? await session.references.currentItem(item) })
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.6), .black.opacity(0.2)], startPoint: .bottom, endPoint: .top)
                    }
            }
            // Extend artwork to the pane edge in landscape while keeping the
            // foreground controls inside the container's safe area.
            .ignoresSafeArea(.container, edges: .horizontal)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayTitle)
                .font(titleFont)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            HeroMetadataRow(item: item)

            if let overview = item.overview?.trimmedNilIfEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .accessibilityIdentifier("Detail.heroOverview")
            }
        }
        .foregroundStyle(.white)
        // Metadata and synopsis need a predictable contrast surface over arbitrary
        // artwork. Opaque black keeps white text independent of the image beneath it.
        .padding(12)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            playButton
            if item.type == .book {
                // Primary reading actions must stay realized when a short landscape
                // viewport scrolls the secondary lazy grid in and out of view.
                BookActionButtons(item: item)
            }
            HStack(spacing: 8) {
                upNextButton
                accessory
            }
            // These controls have spoken labels rather than visible text. Keep
            // symbols compact so accessibility text sizes cannot overlap peers.
            .dynamicTypeSize(...DynamicTypeSize.large)
            .buttonBorderShape(.capsule)
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
            Button(action: play) {
                Label(((playbackItem ?? item).userData?.playbackPositionTicks ?? 0) > 0 ? String(localized: "Resume") : String(localized: "Play"), systemImage: "play.fill")
                    .foregroundStyle(Color.gusProminentActionForeground)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("Detail.play")
            }
            .gusProminentGlassButtonStyle()
            .controlSize(.large)
            // Keep the primary action prominent without turning wide panes into
            // a full-width button. Narrow panes can still shrink naturally.
            .frame(maxWidth: min(320, DetailActionMetrics.maximumRowWidth))
            .tint(.accentColor)
            .gusDefaultActionShortcut()
            .gusTVFocus(id: "play", section: "detail:" + ItemRef(item: item).id, ids: ["play", "more", "synopsis"], initial: true, item: item)
            .visionHoverEffect(Capsule())
        }
    }

    private var upNextButton: some View {
        ItemUserActionButton(
            title: isInUpNext ? "Remove from Next Up" : "Add to Next Up",
            systemImage: isInUpNext ? "checkmark" : "plus",
            action: toggleUpNext
        )
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

    private var baseHeroHeight: CGFloat {
        #if os(tvOS)
            return 620
        #elseif os(visionOS)
            return 560
        #elseif os(macOS)
            return 480
        #else
            return 420
        #endif
    }

    private var heroPadding: CGFloat {
        #if os(tvOS) || os(visionOS)
            return 40
        #else
            return 24
        #endif
    }
}

// MARK: - Supporting types

/// Compact inline row of metadata tokens (year, runtime, rating, scores) shown in the hero.
struct HeroMetadataRow: View {
    let item: MediaItem

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
        .foregroundStyle(.white)
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
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5)))
        }
        if let community = item.communityRatingText {
            Text(community)
                .foregroundStyle(.white)
        }
        if let critic = item.criticRatingText {
            Text(String(localized: "Critic \(critic)", comment: "Critic score label, e.g. 'Critic 74%'"))
        }
    }
}

/// Icon-only glass button used for secondary hero actions (Up Next, etc.).
struct ItemUserActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .gusTVActionLabel()
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .gusGlassButtonStyle()
        .controlSize(.regular)
        .frame(minWidth: 44, minHeight: 44)
        .visionHoverEffect(Capsule())
        .accessibilityLabel(title)
    }
}
