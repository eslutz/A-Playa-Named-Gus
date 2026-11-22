#if os(iOS)
    import ActivityKit
    import Foundation

    struct GusDownloadActivityAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable, Sendable {
            var activeCount: Int
            /// A single transfer can report a known fraction. A count covers a batch.
            var percent: Int?
            var title: String?
        }
    }
#endif
