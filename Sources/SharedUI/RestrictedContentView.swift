import SwiftUI

/// Shown in place of detail or playback for an item above the household's content
/// rating limit. List filtering already hides restricted items; this covers every other
/// way an item can be reached (deep links, downloads, stale navigation) and explains
/// *why* the content is unavailable, per the family-safety brief.
struct RestrictedContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Restricted Content", systemImage: "lock.shield")
        } description: {
            Text("This item is above the content rating limit. A household member can change the limit in Settings under Content Restrictions.")
        }
    }
}
