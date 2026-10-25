import SwiftUI

/// Request approval and media availability are separate server-owned states.
struct SeerrRequestsView: View {
    @Environment(SeerrStore.self) private var store
    let managing: Bool
    @State private var filter: SeerrRequestFilter
    @State private var requests: [SeerrRequest] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var canLoadMore = false
    @State private var nextSkip = 0
    @State private var errorMessage: String?
    @State private var refreshID = UUID()
    @State private var loadID = UUID()

    init(managing: Bool = false) {
        self.managing = managing
        _filter = State(initialValue: managing ? .pending : .all)
    }

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $filter) {
                    ForEach(SeerrRequestFilter.allCases, id: \.self) { value in
                        Text(value.seerrHistoryDescription).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("Seerr.requests.filter")
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try Again") { refreshID = UUID() }
                }
            }
            if managing, store.user?.canManageRequests != true {
                ContentUnavailableView(
                    "Management Permission Required",
                    systemImage: "lock",
                    description: Text("Your Seerr account cannot review other users' requests.")
                )
            } else {
                ForEach(requests.filter { SeerrRequestHistoryPolicy.canRead($0, user: store.user, managing: managing) }) { request in
                    NavigationLink {
                        SeerrRequestDetailView(requestID: request.id, managing: managing) {
                            refreshID = UUID()
                        }
                    } label: {
                        SeerrRequestHistoryRow(request: request)
                    }
                }
                if isLoading {
                    ProgressView("Loading Requests")
                } else if hasLoaded, requests.isEmpty, errorMessage == nil {
                    ContentUnavailableView(
                        "No Requests",
                        systemImage: "tray",
                        description: Text("No requests match the selected status.")
                    )
                }
                if canLoadMore, !isLoading {
                    Button("Load More Requests") { Task { await load(reset: false) } }
                        .accessibilityIdentifier("Seerr.requests.more")
                }
            }
        }
        .navigationTitle(managing ? "Manage Requests" : "My Requests")
        .task(id: "\(store.revision):\(filter.rawValue):\(refreshID)") { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Requests", systemImage: "arrow.clockwise") { refreshID = UUID() }
                    .disabled(isLoading)
            }
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        guard reset || !isLoading else { return }
        let operation = UUID()
        let revision = store.revision
        loadID = operation
        isLoading = true
        errorMessage = nil
        if reset {
            requests = []
            nextSkip = 0
            canLoadMore = false
            hasLoaded = false
        }
        defer {
            if loadID == operation {
                isLoading = false
            }
        }
        do {
            try await store.refreshUser()
            guard revision == store.revision, !Task.isCancelled else { return }
            guard let user = store.user, !managing || user.canManageRequests else {
                throw SeerrConnectionError.notPermitted
            }
            let client = try store.requireClient()
            let skip = nextSkip
            let page = try await client.requests(filter: filter, requestedBy: managing ? nil : user.id, take: 20, skip: skip)
            guard revision == store.revision, loadID == operation, !Task.isCancelled else { return }
            var seen = Set(requests.map(\.id))
            let visible = page.results.filter { managing || $0.requestedBy?.id == user.id }
            requests.append(contentsOf: visible.filter { seen.insert($0.id).inserted })
            nextSkip = skip + page.results.count
            canLoadMore = !page.results.isEmpty && nextSkip < page.pageInfo.results
            hasLoaded = true
        } catch {
            guard revision == store.revision, loadID == operation, !Task.isCancelled else { return }
            store.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct SeerrRequestHistoryRow: View {
    @Environment(SeerrStore.self) private var store
    let request: SeerrRequest
    @State private var title: SeerrTitle?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    private var accessRevision: String {
        "\(store.revision):\(restriction):\(hideUnrated)"
    }

    var body: some View {
        Group {
            if let title, !store.admits(title) {
                Label("Restricted Request", systemImage: "lock.shield")
            } else {
                rowContent
            }
        }
        .task(id: "\(accessRevision):\(request.id)") {
            let access = accessRevision
            title = nil
            guard let mediaID = request.media?.tmdbId,
                  let type = request.type ?? request.media?.mediaType,
                  type == .movie || type == .tv,
                  let client = try? store.requireClient()
            else { return }
            do {
                let result = try await client.details(mediaType: type, id: mediaID)
                guard access == accessRevision, !Task.isCancelled else { return }
                title = result
            } catch {
                guard access == accessRevision, !Task.isCancelled else { return }
                store.handle(error)
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            SeerrArtworkView(path: title?.posterPath).frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title?.displayTitle ?? String(localized: "Request #\(request.id)")).font(.headline)
                Text("Request: \(request.status.seerrRequestDescription)")
                Text("Media: \(request.seerrMediaDescription)")
                Text(request.seerrFormatDescription)
                if let date = seerrRequestDate(request.createdAt) {
                    Text(date, style: .date)
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Every destructive or approval action is confirmed, revalidated and read back.
private struct SeerrRequestDetailView: View {
    @Environment(SeerrStore.self) private var store
    let requestID: Int
    let managing: Bool
    let didChange: () -> Void
    @State private var request: SeerrRequest?
    @State private var title: SeerrTitle?
    @State private var isLoading = false
    @State private var mutation: SeerrHistoryAction?
    @State private var confirming: SeerrHistoryAction?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var wasRemoved = false
    @State private var loadedAccess: String?
    @State private var loadID = UUID()
    @State private var mutationID = UUID()
    @State private var didMutate = false
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    private var accessRevision: String {
        "\(store.revision):\(restriction):\(hideUnrated)"
    }

    private var mayRead: Bool {
        loadedAccess == accessRevision && request.map {
            SeerrRequestHistoryPolicy.canRead($0, user: store.user, managing: managing)
        } == true
    }

    private var isRestricted: Bool {
        title.map { !store.admits($0) } ?? false
    }

    private var needsReadback: SeerrHistoryAction? {
        SeerrHistoryAction.allCases.first { store.hasPendingSupportMutation(key: journalKey($0)) }
    }

    private var cancellationAcknowledged: Bool {
        store.hasPendingSupportMutation(key: journalKey(.cancel) + ":acknowledged")
    }

    private func journalKey(_ action: SeerrHistoryAction) -> String {
        "request:\(requestID):\(action.rawValue)"
    }

    var body: some View {
        List {
            if mayRead, isRestricted {
                RestrictedContentView()
            } else if mayRead, let title {
                Section {
                    SeerrTitleRow(title: title)
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                    Button(needsReadback == nil ? "Refresh Request" : "Check Request Outcome") {
                        Task { await load() }
                    }
                    .disabled(isLoading || mutation != nil)
                }
            }
            if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(.secondary) }
            }
            if isLoading {
                ProgressView("Loading Request Details")
            }
            if let mutation {
                ProgressView(mutation.progressTitle)
            }
            if wasRemoved {
                ContentUnavailableView(
                    "Request Removed",
                    systemImage: "checkmark.circle",
                    description: Text("Seerr confirmed that this request is no longer present.")
                )
            } else if mayRead, !isRestricted, let request {
                details(request)
                actions(request)
            } else if !isLoading, request != nil, !mayRead {
                ContentUnavailableView(
                    "Request Access Unavailable",
                    systemImage: "lock",
                    description: Text("Your current Seerr account cannot view this request.")
                )
            } else if !isLoading, errorMessage == nil {
                ContentUnavailableView("Request Unavailable", systemImage: "tray")
            }
        }
        .navigationTitle(displayTitle)
        .task(id: accessRevision) { await load() }
        .refreshable { await load() }
        .onDisappear {
            if didMutate {
                didChange()
            }
        }
        .confirmationDialog(
            confirming?.confirmationTitle(title: displayTitle) ?? "",
            isPresented: Binding(get: { confirming != nil }, set: {
                if !$0 {
                    confirming = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let action = confirming {
                Button(action.buttonTitle, role: action.isDestructive ? .destructive : nil) {
                    confirming = nil
                    Task { await perform(action) }
                }
            }
            Button("Keep Request", role: .cancel) { confirming = nil }
        } message: {
            Text("Seerr will check your current account permissions and request status before applying this decision.")
        }
    }

    private var displayTitle: String {
        mayRead && !isRestricted ? title?.displayTitle ?? String(localized: "Request #\(requestID)") : String(localized: "Request")
    }

    private func details(_ request: SeerrRequest) -> some View {
        Section("Request Details") {
            LabeledContent("Request", value: request.status.seerrRequestDescription)
            LabeledContent("Media Availability", value: request.seerrMediaDescription)
            LabeledContent("Format", value: request.seerrFormatDescription)
            if let requester = request.requestedBy {
                LabeledContent("Requested By", value: requester.name)
            }
            if let date = seerrRequestDate(request.createdAt) {
                LabeledContent("Requested", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let date = seerrRequestDate(request.updatedAt) {
                LabeledContent("Updated", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let seasons = request.seasons, !seasons.isEmpty {
                LabeledContent("Seasons", value: seasons.map(\.seasonNumber).sorted().map(String.init).joined(separator: ", "))
            }
            Text("Approval does not mean media is available to play.").foregroundStyle(.secondary)
        }
    }

    private func actions(_ request: SeerrRequest) -> some View {
        Section("Actions") {
            if let user = store.user {
                if SeerrRequestHistoryPolicy.canModerate(request, user: user, managing: managing) {
                    Button("Approve Request") { confirming = .approve }
                    Button("Decline Request", role: .destructive) { confirming = .decline }
                }
                if SeerrRequestHistoryPolicy.canCancel(request, user: user) {
                    Button("Cancel My Request", role: .destructive) { confirming = .cancel }
                }
            }
            Button("Refresh Request") { Task { await load() } }
        }
        .disabled(isLoading || mutation != nil || needsReadback != nil)
    }

    @MainActor
    private func load() async {
        let revision = store.revision, access = accessRevision
        guard mutation == nil || loadedAccess != access else { return }
        let operation = UUID()
        loadID = operation
        if loadedAccess != access {
            loadedAccess = access
            request = nil; title = nil; statusMessage = nil; confirming = nil
            mutation = nil; mutationID = UUID(); wasRemoved = false
        }
        isLoading = true
        errorMessage = nil
        defer {
            if loadID == operation {
                isLoading = false
            }
        }
        do {
            try await store.refreshUser()
            let client = try store.requireClient()
            let current: SeerrRequest
            do {
                current = try await client.request(id: requestID)
            } catch SeerrClientError.notFound {
                guard access == accessRevision, loadID == operation, !Task.isCancelled else { return }
                if SeerrHistoryReadbackPolicy.isSettled(action: needsReadback, status: nil, acknowledged: cancellationAcknowledged) {
                    confirmRemoval()
                } else {
                    request = nil; title = nil
                    errorMessage = needsReadback == nil ? SeerrClientError.notFound.localizedDescription : String(localized: "Seerr has not confirmed this request outcome. Check Seerr before taking another action.")
                }
                return
            }
            guard access == accessRevision, loadID == operation, !Task.isCancelled else { return }
            guard current.id == requestID else { throw SeerrClientError.invalidResponse }
            guard SeerrRequestHistoryPolicy.canRead(current, user: store.user, managing: managing) else { throw SeerrConnectionError.notPermitted }
            request = current
            wasRemoved = false
            reconcile(current)
            if let id = current.media?.tmdbId, let type = current.type ?? current.media?.mediaType, type == .movie || type == .tv {
                let metadata = try await client.details(mediaType: type, id: id)
                guard access == accessRevision, loadID == operation, !Task.isCancelled else { return }
                title = metadata
            }
        } catch {
            guard revision == store.revision, access == accessRevision, loadID == operation, !Task.isCancelled else { return }
            store.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func perform(_ action: SeerrHistoryAction) async {
        guard mutation == nil, !isLoading, needsReadback == nil else { return }
        let revision = store.revision, access = accessRevision
        let operation = UUID()
        mutationID = operation
        mutation = action
        errorMessage = nil; statusMessage = nil
        var acceptedMutation = false, journalStarted = false
        defer {
            if mutationID == operation {
                mutation = nil
            }
        }
        do {
            try await store.refreshUser()
            let client = try store.requireClient()
            let current = try await client.request(id: requestID)
            guard access == accessRevision, !Task.isCancelled else { return }
            guard current.id == requestID, let user = store.user else { throw SeerrClientError.invalidResponse }
            request = current
            switch action {
            case .cancel:
                guard SeerrRequestHistoryPolicy.canCancel(current, user: user) else { throw SeerrConnectionError.notPermitted }
                guard needsReadback == nil else { throw SeerrClientError.mutationOutcomeUnknown }
                try store.beginSupportMutation(key: journalKey(action))
                journalStarted = true
                try await client.cancelRequest(id: requestID)
                acceptedMutation = true
                // Persist the DELETE acknowledgement independently of its readback.
                try store.beginSupportMutation(key: journalKey(.cancel) + ":acknowledged")
            case .approve, .decline:
                guard SeerrRequestHistoryPolicy.canModerate(current, user: user, managing: managing),
                      let mediaID = current.media?.tmdbId, let type = current.type ?? current.media?.mediaType,
                      type == .movie || type == .tv else { throw SeerrConnectionError.notPermitted }
                let metadata = try await client.details(mediaType: type, id: mediaID)
                guard access == accessRevision, !Task.isCancelled else { return }
                guard store.admits(metadata) else { throw SeerrConnectionError.notPermitted }
                guard needsReadback == nil else { throw SeerrClientError.mutationOutcomeUnknown }
                try store.beginSupportMutation(key: journalKey(action))
                journalStarted = true
                if action == .approve {
                    _ = try await client.approveRequest(id: requestID)
                } else {
                    _ = try await client.declineRequest(id: requestID)
                }
            }
            acceptedMutation = true
            guard access == accessRevision, !Task.isCancelled else { return }
            do {
                let result = try await client.request(id: requestID)
                guard access == accessRevision, !Task.isCancelled else { return }
                guard result.id == requestID else { throw SeerrClientError.invalidResponse }
                request = result
                reconcile(result)
            } catch SeerrClientError.notFound where action == .cancel {
                guard access == accessRevision, !Task.isCancelled else { return }
                confirmRemoval()
            }
            didMutate = true
        } catch {
            guard revision == store.revision, access == accessRevision, !Task.isCancelled else { return }
            if acceptedMutation || (error as? SeerrClientError) == .mutationOutcomeUnknown || error is CancellationError {
                didMutate = true
                errorMessage = String(localized: "The request outcome is unknown. Check the current request outcome before trying again.")
            } else {
                if journalStarted {
                    completeJournal()
                }
                errorMessage = error.localizedDescription
            }
            store.handle(error)
        }
    }

    private func confirmRemoval() {
        request = nil
        completeJournal()
        wasRemoved = true
        errorMessage = nil; statusMessage = nil
        didMutate = true
    }

    private func reconcile(_ current: SeerrRequest) {
        guard let pending = needsReadback else { return }
        guard SeerrHistoryReadbackPolicy.isSettled(action: pending, status: current.status, acknowledged: false) else {
            errorMessage = String(localized: "The request outcome is still unresolved. Check Seerr before taking another action.")
            return
        }
        completeJournal()
        switch current.status {
        case .approved: statusMessage = String(localized: "Seerr confirmed this request is approved.")
        case .declined: statusMessage = String(localized: "Seerr confirmed this request is declined.")
        default: statusMessage = String(localized: "Current request status: \(current.status.seerrRequestDescription)")
        }
        errorMessage = nil
        didMutate = true
    }

    private func completeJournal() {
        // Clear the acknowledgement first so a crash cannot leave an orphaned
        // acknowledgement that confirms an unrelated later cancellation.
        if cancellationAcknowledged {
            store.completeSupportMutation(key: journalKey(.cancel) + ":acknowledged")
        }
        for action in SeerrHistoryAction.allCases where store.hasPendingSupportMutation(key: journalKey(action)) {
            store.completeSupportMutation(key: journalKey(action))
        }
    }
}

/// Screen permissions are intentionally narrower than Seerr's administrative delete API.
enum SeerrRequestHistoryPolicy {
    static func canRead(_ request: SeerrRequest, user: SeerrUser?, managing: Bool) -> Bool {
        guard let user else { return false }
        return managing ? user.canManageRequests : request.requestedBy?.id == user.id
    }

    static func canCancel(_ request: SeerrRequest, user: SeerrUser) -> Bool {
        request.status == .pending && request.requestedBy?.id == user.id
    }

    static func canModerate(_ request: SeerrRequest, user: SeerrUser, managing: Bool) -> Bool {
        managing && user.canManageRequests && request.status == .pending
    }
}

/// A missing response or unchanged pending state cannot unlock another decision.
enum SeerrHistoryReadbackPolicy {
    static func isSettled(action: SeerrHistoryAction?, status: SeerrRequestStatus?, acknowledged: Bool) -> Bool {
        guard let action else { return false }
        if action == .cancel {
            return acknowledged && status == nil
        }
        guard let status else { return false }
        switch status {
        case .approved, .declined, .failed, .completed: return true
        case .pending, .unknown: return false
        }
    }
}

enum SeerrHistoryAction: String, CaseIterable, Sendable {
    case cancel, approve, decline

    var buttonTitle: String {
        switch self {
        case .cancel: String(localized: "Cancel My Request")
        case .approve: String(localized: "Approve Request")
        case .decline: String(localized: "Decline Request")
        }
    }

    var isDestructive: Bool {
        self != .approve
    }

    var progressTitle: String {
        switch self {
        case .cancel: String(localized: "Cancelling Request")
        case .approve: String(localized: "Approving Request")
        case .decline: String(localized: "Declining Request")
        }
    }

    func confirmationTitle(title: String) -> String {
        switch self {
        case .cancel: String(localized: "Cancel your request for \(title)?")
        case .approve: String(localized: "Approve the request for \(title)?")
        case .decline: String(localized: "Decline the request for \(title)?")
        }
    }
}

private extension SeerrRequest {
    var seerrMediaDescription: String {
        media?.availability(is4K: is4k == true).seerrDescription ?? String(localized: "Availability unknown")
    }

    var seerrFormatDescription: String {
        switch is4k {
        case true: String(localized: "4K")
        case false: String(localized: "Standard")
        case nil: String(localized: "Format not provided")
        }
    }
}

extension SeerrRequestStatus {
    var seerrRequestDescription: String {
        switch self {
        case .pending: String(localized: "Pending Approval")
        case .approved: String(localized: "Approved")
        case .declined: String(localized: "Declined")
        case .failed: String(localized: "Failed")
        case .completed: String(localized: "Completed")
        case .unknown: String(localized: "Unknown Request Status")
        }
    }
}

private extension SeerrRequestFilter {
    var seerrHistoryDescription: String {
        switch self {
        case .all: String(localized: "All Requests")
        case .approved: String(localized: "Approved")
        case .available: String(localized: "Available")
        case .pending: String(localized: "Pending Approval")
        case .processing: String(localized: "Processing")
        case .unavailable: String(localized: "Unavailable")
        case .failed: String(localized: "Failed")
        case .deleted: String(localized: "Deleted")
        case .completed: String(localized: "Completed")
        }
    }
}

private func seerrRequestDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
