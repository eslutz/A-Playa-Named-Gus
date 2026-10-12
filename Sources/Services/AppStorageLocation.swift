import Foundation

enum AppStorageLocation {
    static let folderName = "A Playa Named Gus"

    static func applicationSupportDirectory() -> URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
    }

    static func appDirectory(applicationSupportDirectory baseDirectory: URL = applicationSupportDirectory()) -> URL {
        baseDirectory.appendingPathComponent(folderName, isDirectory: true)
    }
}
