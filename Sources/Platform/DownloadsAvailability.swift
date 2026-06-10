enum DownloadsAvailability {
    static var isSupported: Bool {
        #if os(tvOS)
            return false
        #else
            return true
        #endif
    }

    /// Storage budget for offline downloads. Conservative on watch hardware per the
    /// watchOS brief (audio-only content, small system volumes).
    static var softCapBytes: Int64 {
        #if os(watchOS)
            return 2 * 1024 * 1024 * 1024
        #else
            return 20 * 1024 * 1024 * 1024
        #endif
    }
}
