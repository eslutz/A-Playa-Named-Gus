@testable import Gus
import Testing

@Suite("Session credentials")
struct SessionCredentialTests {
    @Test("formats the keychain account from server and user identifiers")
    func formatsAccount() {
        let credential = SessionCredential(serverID: "server-1", userID: "user-7")

        #expect(credential.account == "server-1:user-7")
    }

    @Test("derives the keychain account from a stored user")
    func derivesAccountFromStoredUser() {
        let user = StoredUser(id: "user-7", name: "Shawn", serverID: "server-1")

        #expect(SessionCredential(user: user).account == "server-1:user-7")
    }
}
