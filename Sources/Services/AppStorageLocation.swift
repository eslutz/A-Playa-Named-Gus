import Foundation

enum AppStorageLocation {
    static let folderName = "A Playa Named Gus"
    static let legacyFolderName = "Gus"

    static func applicationSupportDirectory() -> URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
    }

    static func appDirectory(applicationSupportDirectory baseDirectory: URL = applicationSupportDirectory()) -> URL {
        let directory = baseDirectory.appendingPathComponent(folderName, isDirectory: true)
        let legacyDirectory = baseDirectory.appendingPathComponent(legacyFolderName, isDirectory: true)
        migrateLegacyDirectoryIfNeeded(from: legacyDirectory, to: directory)
        return directory
    }

    private static func migrateLegacyDirectoryIfNeeded(from legacyDirectory: URL, to directory: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyDirectory.path),
              !fileManager.fileExists(atPath: directory.path)
        else { return }

        do {
            try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyDirectory, to: directory)
        } catch {
            // The stores create the new directory after this attempt; migration failure should not block launch.
        }
    }
}
