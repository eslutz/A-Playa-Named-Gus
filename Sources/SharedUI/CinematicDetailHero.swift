import SwiftUI

/// Full-bleed backdrop header for an item detail screen: artwork, gradient scrim,
/// title block, play/up-next actions, and a caller-supplied accessory slot.
struct CinematicDetailHero<Accessory: View>: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    let item: MediaItem
    var playbackItem: MediaItem? = nil
    var primaryPlayEnabled = true
    var playbackHasProgress = false
    var startFromBeginning: (() -> Void)? = nil
    let backdropURL: URL?
    let play: () -> Void
    let isInUpNext: Bool
    let toggleUpNext: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation {
                iPadHero
            } else {
                legacyHero
            }
        #else
            legacyHero
        #endif
    }

    #if os(iOS)
        private var iPadHero: some View {
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 32) {
                        iPadArtworkAndActions.frame(width: item.type == .book ? 240 : 400)
                        iPadOverview.frame(minWidth: 280, maxWidth: 680, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 24) {
                    iPadArtworkAndActions.frame(maxWidth: item.type == .book ? 240 : 400, alignment: .leading)
                    iPadOverview
                }
            }
            .padding(24)
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var iPadArtworkAndActions: some View {
            VStack(alignment: .leading, spacing: 16) {
                AsyncPoster(
                    url: item.type == .book ? session.mediaProvider.primaryImageURL(for: item, context: .posterGrid) : backdropURL,
                    placeholderSymbol: item.artworkPlaceholderSymbol,
                    fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1280)
                )
                .aspectRatio(item.type == .book ? 2.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
                HeroMetadataRow(item: item, foreground: .secondary)
                actionStack
            }
        }

        private var iPadOverview: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let overview = item.overview?.trimmedNilIfEmpty {
                    Text("Synopsis").font(.headline)
                    Text(overview).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("Detail.heroOverview")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    #endif

    private var legacyHero: some View {
        standardHero.gusTVDetailHero(item: item, backdropURL: backdropURL) {
            VStack(alignment: .leading, spacing: 24) {
                playButton.frame(maxWidth: .infinity)
                HStack(spacing: 24) {
                    upNextButton
                        .frame(maxWidth: .infinity)
                        .gusTVDetailActionFocus(id: "nextUp", item: item)
                    Group(subviews: accessory) { actions in
                        ForEach(actions) { action in action.frame(maxWidth: .infinity) }
                    }
                }
                .frame(width: primaryActionWidth)
                .tvFocusSection()
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
                        LinearGradient(colors: heroScrim, startPoint: .bottom, endPoint: .top)
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
        // The iPhone's full hero scrim provides contrast; wider layouts keep their copy panel.
        .gusPhoneHeroCopy()
    }

    private var heroScrim: [Color] {
        #if os(iOS)
            if widthClass == .compact {
                return [.black.opacity(0.95), .black.opacity(0.72), .black.opacity(0.15)]
            }
        #endif
        return [.black.opacity(0.85), .black.opacity(0.6), .black.opacity(0.2)]
    }

    private var actionStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            playButton
            if item.type == .book {
                // Primary reading actions must stay realized when a short landscape
                // viewport scrolls the secondary lazy grid in and out of view.
                BookActionButtons(item: item)
            }
            DetailActionRow {
                upNextButton
                restartButton
                accessory
            }
            // These controls have spoken labels rather than visible text. Keep
            // symbols compact so accessibility text sizes cannot overlap peers.
            .dynamicTypeSize(...DynamicTypeSize.large)
            .gusPhoneHeroAccessoryStyle()
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
                Label(playbackHasProgress ? String(localized: "Resume") : String(localized: "Play"), systemImage: "play.fill")
                    .gusProminentActionForeground()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("Detail.play")
            }
            .gusProminentGlassButtonStyle()
            .controlSize(.large)
            // Keep the primary action prominent without turning wide panes into
            // a full-width button. Narrow panes can still shrink naturally.
            .frame(maxWidth: primaryActionWidth)
            .gusProminentActionTint()
            .gusDefaultActionShortcut()
            .gusTVDetailActionFocus(id: "play", item: item, initial: true)
            .visionHoverEffect(Capsule())
        }
    }

    private var primaryActionWidth: CGFloat {
        #if os(tvOS)
            528
        #else
            min(320, DetailActionMetrics.maximumRowWidth)
        #endif
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

    private var baseHeroHeight: CGFloat {
        #if os(tvOS)
            return 620
        #elseif os(visionOS)
            return 560
        #elseif os(macOS)
            return 480
        #elseif os(iOS)
            return widthClass == .compact ? 550 : 420
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
                .frame(maxWidth: .infinity, minHeight: DetailActionMetrics.minimumLabelHeight)
        }
        .gusGlassButtonStyle()
        .controlSize(.regular)
        .frame(minWidth: 44, minHeight: 44)
        .visionHoverEffect(Capsule())
        .accessibilityLabel(title)
    }
}

/// Essential actions stay realized even below a short or enlarged-text viewport.
/// A native grid is the narrow-pane alternative to the single horizontal row.
struct DetailActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GusGlassControlGroup {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { content }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    Group(subviews: content) { actions in
                        ForEach(Array(stride(from: 0, to: actions.count, by: 2)), id: \.self) { start in
                            GridRow {
                                ForEach(actions[start ..< min(start + 2, actions.count)]) { action in action }
                            }
                        }
                    }
                }
            }
        }
    }
}
