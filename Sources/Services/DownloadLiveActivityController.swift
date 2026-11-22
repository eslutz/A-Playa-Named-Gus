#if os(iOS)
    import ActivityKit
    import Foundation

    /// One local activity per download batch. ActivityKit receives only its count,
    /// a coarse progress value, and an explicitly permitted title.
    @MainActor
    final class DownloadLiveActivityController {
        static let shared = DownloadLiveActivityController()
        private typealias DownloadLiveActivity = Activity<GusDownloadActivityAttributes>
        private var activityID: String?
        private var lastState: GusDownloadActivityAttributes.ContentState?
        private var lastSent = Date.distantPast
        private var pending: Task<Void, Never>?

        func endAll() {
            let retiring = Set(DownloadLiveActivity.activities.map(\.id))
            pending?.cancel()
            pending = nil
            activityID = nil
            lastState = nil
            guard !retiring.isEmpty else { return }
            Task { await Self.end(ids: retiring) }
        }

        func refresh(_ records: [OfflineDownloadRecord], session: SessionStore?, allowStart: Bool) {
            guard activityID != nil || allowStart else { return }
            guard let session, session.isActive, session.systemSurfacePreferences.personalHistoryEnabled,
                  session.ageRangeAccess.stage == .optional || session.ageRangeAccess.stage == .ready
            else {
                endAll()
                return
            }
            let policy = ContentRatingGate.storedPolicy()
            let eligible = records.filter {
                $0.status.isActive && $0.serverID == session.server.id && $0.userID == session.user.id && $0.isAdmitted(by: policy.admits)
            }
            guard !eligible.isEmpty else { endAll(); return }
            let single = eligible.count == 1 ? eligible[0] : nil
            let percent = single?.activity?.progress.map { Int(($0 * 20).rounded(.down)) * 5 }
            let title = session.systemSurfacePreferences.showsLockScreenTitles ? single.map { String($0.item.displayTitle.prefix(256)) } : nil
            let state = GusDownloadActivityAttributes.ContentState(activeCount: eligible.count, percent: percent, title: title)
            // Renew the stale date on long-running transfers without flooding ActivityKit.
            let now = Date.now
            guard lastState != state || now.timeIntervalSince(lastSent) >= 90 else { return }
            let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(180))
            if let id = activityID, DownloadLiveActivity.activities.contains(where: {
                $0.id == id && ($0.activityState == .active || $0.activityState == .stale)
            }) {
                let previous = pending
                pending = Task {
                    await previous?.value
                    guard !Task.isCancelled, activityID == id else { return }
                    await Self.update(id: id, state: state, date: now)
                }
            } else {
                activityID = nil
                guard allowStart, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
                activityID = try? DownloadLiveActivity.request(attributes: .init(), content: content, pushType: nil).id
                guard activityID != nil else { return }
            }
            lastState = state
            lastSent = now
        }

        /// ActivityKit's Activity reference is non-Sendable. Resolve it inside
        /// the same isolation region as its async operation; retain only its ID.
        private nonisolated static func end(ids: Set<String>) async {
            for activity in DownloadLiveActivity.activities where ids.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        private nonisolated static func update(id: String, state: GusDownloadActivityAttributes.ContentState, date: Date) async {
            guard let current = DownloadLiveActivity.activities.first(where: { $0.id == id }) else { return }
            await current.update(ActivityContent(state: state, staleDate: date.addingTimeInterval(180)))
        }
    }
#endif
