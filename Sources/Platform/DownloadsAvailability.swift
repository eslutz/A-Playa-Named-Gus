enum DownloadsAvailability {
    static var isSupported: Bool {
        #if os(tvOS)
            return false
        #else
            return true
        #endif
    }
}
