import Foundation
@testable import Gus
import Testing

@Suite("Platform identity")
struct PlatformIdentityTests {
    @Test("device identity reports the compiled platform")
    func platformNameMatchesCompiledPlatform() {
        #if os(tvOS)
            #expect(DeviceIdentity.platformName == "tvOS")
        #elseif os(visionOS)
            #expect(DeviceIdentity.platformName == "visionOS")
        #elseif os(macOS)
            #expect(DeviceIdentity.platformName == "macOS")
        #elseif os(iOS)
            #expect(DeviceIdentity.platformName == "iOS")
        #else
            #expect(DeviceIdentity.platformName == "Apple")
        #endif
    }

    @Test("device names cannot break or inject authorization fields", arguments: [
        "Eric’s Mac", "René的Mac", "Mac, Token=other", "A\"B", "Mac\r\nInjected: yes", "%E2%80%99", "Audit Mac"
    ])
    func authorizationDeviceNamePreservesValue(_ name: String) {
        let encoded = DeviceIdentity.authorizationDeviceName(name)
        #expect(encoded.utf8.allSatisfy { $0 >= 32 && $0 < 127 })
        #expect(!encoded.contains(","))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("\""))
        #expect(encoded.removingPercentEncoding == name)
    }
}
