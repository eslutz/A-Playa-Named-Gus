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
}
