import SwiftUI

/// Horizontal cast and crew rail showing portrait thumbnails with name and role captions.
struct CastRail: View {
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var navigation
    let item: MediaItem

    var body: some View {
        let context = "detail:" + ItemRef(item: item).id
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast & Crew")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(displayPeople, id: \.focusID) { person in
                        if person.target.id != nil {
                            Button { navigation.openRelatedSearch(person.target, focusContext: context) } label: { card(person) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Search for related titles")
                                .accessibilityIdentifier("Detail.related." + person.focusID)
                                .gusTVFocus(id: person.focusID, section: context + ":cast", ids: displayPeople.map(\.focusID), context: context)
                        } else {
                            card(person).gusTVFocusableInfo()
                        }
                    }
                }
                .gusTVRailPadding()
            }
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }

    private func card(_ person: CastDisplayPerson) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Rectangle()
                    .fill(.thinMaterial)

                if let imageURL = session.mediaProvider.personImageURL(for: person.source, maxWidth: Int(CastCardMetrics.width * 2)) {
                    AsyncPoster(url: imageURL, contentMode: .fill, placeholderSymbol: "person")
                } else {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: CastCardMetrics.width, height: portraitHeight)
            .clipShape(portraitShape)
            .posterHoverEffect()

            VStack(alignment: .leading, spacing: 7) {
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
            .padding(16)
        }
        .frame(width: CastCardMetrics.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var portraitHeight: CGFloat {
        #if os(tvOS)
            CastCardMetrics.width
        #else
            CastCardMetrics.height
        #endif
    }

    private var portraitShape: RoundedRectangle {
        #if os(tvOS)
            RoundedRectangle(cornerRadius: CastCardMetrics.width / 2, style: .continuous)
        #else
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        #endif
    }

    private var displayPeople: [CastDisplayPerson] {
        var seen = Set<String>()
        return Array(item.people.compactMap(CastDisplayPerson.init).filter { seen.insert($0.focusID).inserted }.prefix(16))
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
