import SwiftUI

/// Horizontal cast and crew rail showing portrait thumbnails with name and role captions.
struct CastRail: View {
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var navigation
    @Environment(\.detailScrollViewport) private var viewport
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var cardWidth = CastCardMetrics.width
    let item: MediaItem

    var body: some View {
        let context = "detail:" + ItemRef(item: item).id
        let people = displayPeople
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            HStack {
                Text("Cast & Crew")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            if typeSize.isAccessibilitySize {
                LazyVStack(alignment: .leading, spacing: ContentSpacing.card) {
                    credits(people, context: context)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: ContentSpacing.card) {
                        credits(people, context: context)
                    }
                    .gusTVRailPadding()
                }
                .lookToScroll(.horizontal)
                .gusTVRailViewport()
            }
        }
    }

    private func credits(_ people: [CastDisplayPerson], context: String) -> some View {
        let focusIDs = people.map(\.focusID)
        return ForEach(people, id: \.focusID) { person in
            if person.target.id != nil {
                Button { navigation.openRelatedSearch(person.target, viewport: viewport?.location) } label: { card(person) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Search for related titles")
                    .accessibilityIdentifier("Detail.related." + person.focusID)
                    .gusTVFocus(id: person.focusID, section: context + ":cast", ids: focusIDs, context: context)
            } else {
                card(person).gusTVFocusableInfo()
            }
        }
    }

    private func card(_ person: CastDisplayPerson) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: ContentSpacing.card))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: ContentSpacing.group))
        let portraitWidth = typeSize.isAccessibilitySize ? CastCardMetrics.width / 2 : cardWidth
        return layout {
            ZStack {
                Rectangle()
                    .fill(.thinMaterial)

                if let imageURL = session.mediaProvider.personImageURL(for: person.source, maxWidth: Int(CastCardMetrics.width * 2)) {
                    CastPortrait(url: imageURL)
                } else {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: portraitWidth, height: portraitWidth * portraitAspect)
            .clipShape(portraitShape)
            .posterHoverEffect()

            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                Text(person.name)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let role = person.role {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: typeSize.isAccessibilitySize ? nil : cardWidth, alignment: .leading)
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var portraitAspect: CGFloat {
        #if os(tvOS)
            1
        #else
            CastCardMetrics.height / CastCardMetrics.width
        #endif
    }

    private var portraitShape: RoundedRectangle {
        #if os(tvOS)
            RoundedRectangle(cornerRadius: cardWidth / 2, style: .continuous)
        #else
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        #endif
    }

    private var displayPeople: [CastDisplayPerson] {
        var seen = Set<String>()
        return item.people.compactMap(CastDisplayPerson.init).filter { seen.insert($0.focusID).inserted }
    }
}

/// Measure every credit so the tallest caption fits. Only visible portraits request artwork.
private struct CastPortrait: View {
    let url: URL
    @State private var hasAppeared = false

    var body: some View {
        AsyncPoster(url: hasAppeared ? url : nil, contentMode: .fill, placeholderSymbol: "person")
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                if visible {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - Display model

/// Validated wrapper that filters out people with blank names and trims role strings.
struct CastDisplayPerson: Hashable {
    let source: MediaPerson
    let name: String
    let role: String?

    var target: RelatedSearch {
        RelatedSearch(kind: .person, id: source.id, name: name)
    }

    var focusID: String {
        target.identityKey + ":" + (role ?? source.creditType ?? "")
    }

    init?(_ person: MediaPerson) {
        guard let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        self.source = person
        self.name = name
        self.role = person.role?.trimmedNilIfEmpty ?? person.creditType?.trimmedNilIfEmpty
    }
}
