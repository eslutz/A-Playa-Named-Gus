import Foundation
import JellyfinAPI
import Observation
import OSLog

struct PublicUserProfile: Identifiable, Hashable {
    let id: String
    let user: UserDto

    init(id: String? = nil, user: UserDto) {
        self.user = user
        self.id = id ?? Self.identifier(for: user)
    }

    var displayName: String {
        user.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? String(
            localized: "Jellyfin User",
            comment: "Fallback display name for a public Jellyfin user profile"
        )
    }

    static func profiles(for users: [UserDto]) -> [PublicUserProfile] {
        let derivedIDs = users.map(identifier(for:))
        let duplicateIDs = Set(derivedIDs.filter { id in derivedIDs.filter { $0 == id }.count > 1 })
        var duplicateCounters: [String: Int] = [:]

        return zip(users, derivedIDs).map { user, identifier in
            guard user.id?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil,
                  duplicateIDs.contains(identifier)
            else {
                return PublicUserProfile(id: identifier, user: user)
            }

            let counter = duplicateCounters[identifier, default: 0]
            duplicateCounters[identifier] = counter + 1
            return PublicUserProfile(id: "\(identifier)-\(counter)", user: user)
        }
    }

    private static func identifier(for user: UserDto) -> String {
        if let id = user.id?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return id
        }

        if let normalizedName = user.name?.normalizedPublicIdentifierComponent {
            return "public-user-\(normalizedName)"
        }

        return "public-user-unknown"
    }
}

@MainActor
@Observable
final class SignInStore {
    private(set) var state: LoadState = .idle
    private(set) var publicUsers: [PublicUserProfile] = []
    private(set) var loginDisclaimer: String?

    let imageBuilder: ImageURLBuilder

    private let client: JellyfinClient
    private let logger = Logger(category: .appModel)

    init(server: ServerConnection) {
        let client = JellyfinClientFactory.makeClient(url: server.url)
        self.client = client
        self.imageBuilder = ImageURLBuilder(client: client)
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            async let publicUsersTask = client.send(Paths.getPublicUsers)
            async let brandingTask = client.send(Paths.getBrandingOptions)
            let publicUsersResponse = try await publicUsersTask
            let brandingResponse = try await brandingTask
            publicUsers = PublicUserProfile.profiles(for: publicUsersResponse.value)
            loginDisclaimer = brandingResponse.value.loginDisclaimer?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Public sign-in data failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedPublicIdentifierComponent: String? {
        let lowered = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = lowered.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.nonEmpty
    }
}
