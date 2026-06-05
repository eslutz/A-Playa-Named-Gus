@testable import Gus
import JellyfinAPI
import Testing

@Suite("Public user profiles")
struct PublicUserProfileTests {
    @Test("uses server ids when available")
    func usesServerIDsWhenAvailable() {
        let profile = PublicUserProfile(user: UserDto(id: "user-1", name: "Ava"))

        #expect(profile.id == "user-1")
        #expect(profile.displayName == "Ava")
    }

    @Test("derives stable ids from public names")
    func derivesStableIDsFromPublicNames() {
        let profile = PublicUserProfile(user: UserDto(name: " Ava Taylor "))

        #expect(profile.id == "public-user-ava-taylor")
    }

    @Test("disambiguates duplicate derived ids")
    func disambiguatesDuplicateDerivedIDs() {
        let profiles = PublicUserProfile.profiles(for: [
            UserDto(name: "Guest"),
            UserDto(name: "Guest"),
            UserDto(id: "user-1", name: "Guest"),
        ])

        #expect(profiles.map(\.id) == ["public-user-guest-0", "public-user-guest-1", "user-1"])
    }
}
