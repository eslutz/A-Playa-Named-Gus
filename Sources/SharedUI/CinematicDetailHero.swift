import SwiftUI

/// Full-bleed backdrop header for an item detail screen: artwork, gradient scrim,
/// title block, play/up-next actions, and a caller-supplied accessory slot.
struct CinematicDetailHero<Accessory: View>: View {
    let item: MediaItem
    let backdropURL: URL?
    let play: () -> Void
    let isInUpNext: Bool
    let toggleUpNext: () -> Void
    @ViewBuilder let accessory: Accessory

    /// Scales the hero with Dynamic Type (capped — the hero is artwork-led, and text
    /// inside it wraps) so accessibility sizes don't clip the title block.
    @ScaledMetric(relativeTo: .title) private var heroTypeScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncPoster(url: backdropURL, contentMode: .fill, placeholderSymbol: item.type == .series ? "tv" : "film")
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.82),
                    .black.opacity(0.54),
                    .black.opacity(0.18),
                    .clear,
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            LinearGradient(
                colors: [.black.opacity(0.72), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            ViewThatFits(in: .horizontal) {
                wideOverlay
                compactOverlay
            }
            .foregroundStyle(.white)
            .padding(heroPadding)
        }
        .background(Color.black.opacity(0.22))
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .contain)
    }

    private var wideOverlay: some View {
        HStack(alignment: .bottom, spacing: 28) {
            titleBlock
                .frame(maxWidth: 760, alignment: .leading)

            Spacer(minLength: 24)

            actionStack
                .frame(width: actionWidth, alignment: .trailing)
        }
    }

    private var compactOverlay: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock
            actionStack
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayTitle)
                .font(titleFont)
                .fontWeight(.bold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HeroMetadataRow(item: item)

            if let overview = item.overview?.trimmedNilIfEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(4)
            }
        }
    }

    private var actionStack: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                playButton
                upNextButton
                accessory
            }

            VStack(alignment: .trailing, spacing: 10) {
                playButton
                HStack(spacing: 10) {
                    upNextButton
                    accessory
                }
            }
        }
    }

    /// Books (epub/text) have no AVKit playback surface; show metadata without Play.
    private var isPlayableItem: Bool {
        item.type != .book
    }

    @ViewBuilder
    private var playButton: some View {
        if isPlayableItem {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .gusProminentGlassButtonStyle()
            .controlSize(.large)
            .tint(.accentColor)
            .gusDefaultActionShortcut()
            .visionHoverEffect(cornerRadius: 10)
        }
    }

    private var upNextButton: some View {
        ItemUserActionButton(
            title: isInUpNext ? "Remove from Up Next" : "Add to Up Next",
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

    private var heroHeight: CGFloat {
        baseHeroHeight * min(max(heroTypeScale, 1.0), 1.5)
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

    private var actionWidth: CGFloat {
        #if os(tvOS) || os(visionOS)
            return 220
        #else
            return 180
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
        .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(Color.gusRatingStar)
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
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 36)
        }
        .gusGlassButtonStyle()
        .visionHoverEffect(cornerRadius: 10)
        .accessibilityLabel(title)
    }
}
