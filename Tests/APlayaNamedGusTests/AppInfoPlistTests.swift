import Foundation
import Testing

@Suite("App Info.plist")
struct AppInfoPlistTests {
    @Test("app display name matches App Store listing")
    func appDisplayNameMatchesAppStoreListing() throws {
        let plist = try sourceInfoPlist()
        let displayName = try #require(plist["CFBundleDisplayName"] as? String)

        #expect(displayName == "A Playa Named Gus")
    }

    @Test("immersive spaces are allowed to open alongside the main window")
    func immersiveSpacesSupportMultipleScenes() throws {
        let plist = try sourceInfoPlist()
        let sceneManifest = try #require(plist["UIApplicationSceneManifest"] as? [String: Any])
        let supportsMultipleScenes = try #require(sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool)

        #expect(supportsMultipleScenes)
    }

    private func sourceInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: sourceInfoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        return try #require(plist as? [String: Any])
    }

    private var sourceInfoPlistURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Info.plist")
    }
}
