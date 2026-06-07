import Foundation

/// Multiplatform device identity used when constructing a `JellyfinClient.Configuration`.
///
/// Swiftfin derives client/device strings from `UIDevice`/`UIScreen`, which only exist
/// on iOS/tvOS. A Playa Named Gus is Apple-first across five platforms, so it uses a stored per-install
/// UUID plus a compile-time platform string — no `UIKit` — so the same code compiles on
/// macOS and visionOS.
enum DeviceIdentity {
    private static let deviceIDDefaultsKey = "dev.ericslutz.gus.deviceID"

    /// Short platform name, e.g. `iOS`, `iPadOS`, `tvOS`, `visionOS`, `macOS`.
    static var platformName: String {
        #if os(tvOS)
            return "tvOS"
        #elseif os(visionOS)
            return "visionOS"
        #elseif os(macOS)
            return "macOS"
        #elseif os(iOS)
            // iPadOS reports as iOS at compile time; refine at runtime where available.
            #if targetEnvironment(macCatalyst)
                return "macOS"
            #else
                return "iOS"
            #endif
        #else
            return "Apple"
        #endif
    }

    /// Client name sent to the server, e.g. `A Playa Named Gus iOS`. Shown in the server's devices list.
    static var clientName: String {
        "A Playa Named Gus \(platformName)"
    }

    /// Stable, per-install device identifier. Generated once and persisted in `UserDefaults`.
    static var deviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: deviceIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        defaults.set(new, forKey: deviceIDDefaultsKey)
        return new
    }

    /// Friendly device name. Uses the host name where meaningful, falling back to platform.
    static var deviceName: String {
        #if os(macOS)
            return Host.current().localizedName ?? "Mac"
        #else
            let host = ProcessInfo.processInfo.hostName
                .replacingOccurrences(of: ".local", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? "\(platformName) Device" : host
        #endif
    }

    /// App marketing version (`CFBundleShortVersionString`).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
