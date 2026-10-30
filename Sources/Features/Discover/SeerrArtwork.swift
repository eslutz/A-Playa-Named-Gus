import SwiftUI

/// Seerr artwork uses the same geometry and native poster treatment as library media.
struct SeerrArtworkView: View {
    let path: String?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var symbol = "film"
    var width = "w500"

    var body: some View {
        ArtworkTile(url: SeerrArtwork.url(path: path, width: width), aspectRatio: aspectRatio, placeholderSymbol: symbol)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A result announces identity and availability together, without relying on tint.
struct SeerrTitleCard: View {
    let title: SeerrTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterCard(
                title: title.displayTitle,
                subtitle: title.seerrIdentityDescription,
                imageURL: title.imageURL(),
                placeholderSymbol: title.mediaType == .person ? "person" : "film"
            )
            if title.mediaType != .person {
                Text(title.seerrAvailabilityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.seerrAccessibilityDescription)
    }
}

struct SeerrTitleRow: View {
    let title: SeerrTitle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SeerrArtworkView(
                path: title.mediaType == .person ? title.profilePath : title.posterPath,
                symbol: title.mediaType == .person ? "person" : "film"
            )
            .frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.displayTitle).font(.headline)
                Text(title.seerrIdentityDescription).font(.subheadline).foregroundStyle(.secondary)
                if title.mediaType != .person {
                    Text(title.seerrAvailabilityDescription).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.seerrAccessibilityDescription)
    }
}

struct SeerrResultLink: View {
    let title: SeerrTitle
    let store: SeerrStore
    var usesList = false

    var body: some View {
        NavigationLink {
            if title.mediaType == .person {
                SeerrPersonView(personID: title.id, displayName: title.displayTitle, store: store)
            } else {
                SeerrTitleDetailView(title: title, store: store)
            }
        } label: {
            if usesList {
                SeerrTitleRow(title: title)
            } else {
                SeerrTitleCard(title: title)
            }
        }
        .posterNavigationStyle()
        .accessibilityIdentifier("Seerr.title." + (title.mediaType?.rawValue ?? "unknown") + "." + String(title.id))
    }
}

extension SeerrTitle {
    /// Movie, TV and person IDs share a numeric namespace, so list identity includes type.
    var seerrCatalogID: String {
        "\(mediaType?.rawValue ?? "unknown"):\(id)"
    }

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

    var seerrAvailabilityDescription: String {
        guard let status = mediaInfo?.status else { return String(localized: "Availability unknown") }
        return status.seerrDescription
    }

    var seerrAccessibilityDescription: String {
        [displayTitle, seerrIdentityDescription, mediaType == .person ? nil : seerrAvailabilityDescription]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

extension SeerrMediaStatus {
    var seerrDescription: String {
        switch self {
        case .notRequested: String(localized: "Not requested")
        case .pending: String(localized: "Pending approval · Not available")
        case .processing: String(localized: "Processing in Seerr")
        case .partiallyAvailable: String(localized: "Partially available in Seerr")
        case .available: String(localized: "Available in Seerr")
        case .blocklisted: String(localized: "Blocked")
        case .deleted: String(localized: "Deleted media record")
        case .unknown: String(localized: "Availability unknown")
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
