import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension GusMediaEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .url) { entity in
            let url = try await entity.shareLink()
            return Data(url.absoluteString.utf8)
        }
    }

    @MainActor
    private func shareLink() async throws -> URL {
        let session = try await GusIntentRuntime.session()
        let item = try await GusIntentRuntime.resolve(self, in: session)
        guard let id = item.id else { throw GusError.notFound }
        return ContentLink.item(id: id, serverID: session.server.id, provider: item.providerKind).universalURL
    }
}
