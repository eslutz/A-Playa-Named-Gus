import SwiftUI

/// Seerr artwork uses the same geometry and native poster treatment as library media.
struct SeerrArtworkView: View {
    let path: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var contentMode: ContentMode = .fill
    var symbol = "film"
    var width = "w500"
    var fallbackURL: URL?

    var body: some View {
        ArtworkTile(url: SeerrArtwork.url(path: path, width: width), aspectRatio: aspectRatio, contentMode: contentMode, placeholderSymbol: symbol, fallbackURLs: [fallbackURL].compactMap { $0 })
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A result announces identity and availability together, without relying on tint.
struct SeerrTitleCard: View {
    let title: SeerrTitle

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.caption) {
            PosterCard(
                title: title.displayTitle,
                subtitle: title.seerrIdentityDescription,
                imageURL: title.imageURL(),
                placeholderSymbol: title.mediaType == .person ? "person" : "film",
                fallbackURLs: [title.backdropPath].compactMap { SeerrArtwork.url(path: $0, width: "w780") }
            )
            if let availability = title.seerrAvailabilityDescription {
                Text(availability)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.mediaAccessibility.label)
        .accessibilityValue(title.mediaAccessibility.value)
    }
}

struct SeerrTitleRow: View {
    let title: SeerrTitle

    var body: some View {
        HStack(alignment: .top, spacing: ContentSpacing.card) {
            SeerrArtworkView(
                path: title.mediaType == .person ? title.profilePath : title.posterPath,
                symbol: title.mediaType == .person ? "person" : "film",
                width: "w185",
                fallbackURL: SeerrArtwork.url(path: title.backdropPath, width: "w300")
            )
            .frame(width: 64)
            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                Text(title.displayTitle).font(.headline)
                Text(title.seerrIdentityDescription).font(.subheadline).foregroundStyle(.secondary)
                if let availability = title.seerrAvailabilityDescription {
                    Text(availability).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.mediaAccessibility.label)
        .accessibilityValue(title.mediaAccessibility.value)
    }
}

struct SeerrResultLink: View {
    let title: SeerrTitle
    let store: SeerrStore
    var usesList = false

    var body: some View {
        NavigationLink(value: store.navigationRoute(destination)) {
            if usesList {
                SeerrTitleRow(title: title)
            } else {
                SeerrTitleCard(title: title)
            }
        }
        .posterNavigationStyle()
        .accessibilityIdentifier("Seerr.title." + (title.mediaType?.rawValue ?? "unknown") + "." + String(title.id))
    }

    private var destination: SeerrRoute.Destination {
        if title.mediaType == .person {
            return .person(id: title.id, name: title.displayTitle)
        }
        return .title(title.mediaType ?? .unknown, title.id)
    }
}

extension SeerrTitle {
    var seerrIdentityDescription: String {
        [releaseYear, seerrTypeDescription].compactMap { $0 }.joined(separator: " · ")
    }

    var seerrTypeDescription: String {
        switch mediaType {
        case .movie: String(localized: "Movie")
        case .tv: String(localized: "TV Series")
        case .person: String(localized: "Person")
        default: String(localized: "Title")
        }
    }

    var seerrAvailabilityDescription: String? {
        guard mediaType == .movie || mediaType == .tv else { return nil }
        return mediaInfo?.status.seerrDescription
    }

    /// Provider-specific projection: TMDB/Seerr identity never becomes a Jellyfin ID.
    var mediaAccessibility: MediaItemAccessibility {
        MediaItemAccessibility(
            label: [displayTitle, seerrIdentityDescription].joined(separator: ", "),
            value: seerrAvailabilityDescription ?? ""
        )
    }
}

extension SeerrMediaStatus {
    var seerrDescription: String? {
        switch self {
        case .notRequested, .unknown: nil
        case .pending: String(localized: "Pending approval · Not available")
        case .processing: String(localized: "Processing in Seerr")
        case .partiallyAvailable: String(localized: "Partially available in Seerr")
        case .available: String(localized: "Available in Seerr")
        case .blocklisted: String(localized: "Blocked")
        case .deleted: String(localized: "Deleted media record")
        }
    }
}

extension SeerrDiscoveryFeed {
    var seerrTitle: String {
        switch self {
        case .trending: String(localized: "Trending")
        case .popularMovies: String(localized: "Popular Movies")
        case .popularTV: String(localized: "Popular TV Series")
        case .upcomingMovies: String(localized: "Upcoming Movies")
        case .upcomingTV: String(localized: "Upcoming TV Series")
        }
    }
}
