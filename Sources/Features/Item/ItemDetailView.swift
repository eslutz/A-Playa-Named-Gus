import JellyfinAPI
import SwiftUI

/// Item detail: backdrop, metadata, overview, and a **Play** button. On visionOS, a
/// **Cinema** toggle in a toolbar ornament opens the immersive space.
struct ItemDetailView: View {

    @Environment(SessionStore.self) private var session
    let item: BaseItemDto

    @State private var playerItem: ItemRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncPoster(
                    url: session.imageBuilder.backdropImageURL(for: item),
                    contentMode: .fill,
                    placeholderSymbol: "film"
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(item.displayTitle)
                    .font(.largeTitle.bold())

                metadataRow

                HStack(spacing: 16) {
                    Button {
                        playerItem = ItemRef(item: item)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    #if os(visionOS)
                    CinemaToggleButton(item: item)
                    #endif
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .playerPresentation(item: $playerItem)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let year = item.yearText {
                Label(year, systemImage: "calendar").labelStyle(.titleOnly)
            }
            if let runtime = item.runtimeText {
                Text(runtime)
            }
            if let rating = item.officialRating {
                Text(rating)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
            }
            if let community = item.communityRatingText {
                Text(community).foregroundStyle(.yellow)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
