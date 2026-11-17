import Foundation

/// Serializes file metadata validation independently of UI state. The download
/// coordinator retains its durable staging journal until the caller commits.
actor DownloadFilePreparation {
    static let shared = DownloadFilePreparation()

    func prepare(_ url: URL, fileExtension: String) async throws {
        if ["mp4", "m4v", "mov"].contains(fileExtension.lowercased()) {
            try OfflineMP4Compatibility.normalizeHEVCTag(in: url)
        }
    }

    func record(id: String, in files: OfflineDownloadFileStore) async throws -> OfflineDownloadRecord? {
        try files.readRecord(forRecordID: id)
    }

    func finalize(_ url: URL, expected: OfflineDownloadRecord, ownership: DownloadCompletionOwnership, in files: OfflineDownloadFileStore) throws -> OfflineDownloadRecord? {
        try files.finalizeDownloadedFile(url, expected: expected, ownership: ownership)
    }

    func fail(expected: OfflineDownloadRecord, ownership: DownloadCompletionOwnership, message: String, in files: OfflineDownloadFileStore) throws -> OfflineDownloadRecord? {
        try files.failFinalization(expected: expected, ownership: ownership, message: message)
    }
}
