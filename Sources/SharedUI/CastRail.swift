import SwiftUI

/// Horizontal cast and crew rail showing portrait thumbnails with name and role captions.
struct CastRail: View {
    @Environment(SessionStore.self) private var session
    let people: [MediaPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast & Crew")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(displayPeople, id: \.self) { person in
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack {
                                Rectangle()
                                    .fill(.thinMaterial)

                                if let imageURL = session.mediaProvider.personImageURL(for: person.source, maxWidth: 240) {
                                    AsyncPoster(url: imageURL, contentMode: .fill, placeholderSymbol: "person")
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 120, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .posterHoverEffect()

                            Text(person.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let role = person.role {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 120, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
            }
            .lookToScroll(.horizontal)
        }
    }

    private var displayPeople: [CastDisplayPerson] {
        people.prefix(16).compactMap(CastDisplayPerson.init)
    }
}

// MARK: - Display model

/// Validated wrapper that filters out people with blank names and trims role strings.
struct CastDisplayPerson: Hashable {
    let source: MediaPerson
    let name: String
    let role: String?

    init?(_ person: MediaPerson) {
        guard let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        self.source = person
        self.name = name
        self.role = person.role?.trimmedNilIfEmpty
    }
}
