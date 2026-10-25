import SwiftUI

/// Issue history is scoped to the current account; manager actions still recheck the server on submission.
struct SeerrIssuesView: View {
    @Environment(SeerrStore.self) private var store
    var title: SeerrTitle?
    @State private var items: [SeerrIssue] = []
    @State private var filter: SeerrIssueFilter = .all
    @State private var total = 0
    @State private var offset = 0
    @State private var loading = false
    @State private var message: String?
    @State private var showingReport = false
    @State private var loadID = UUID()
    @State private var loadedRevision: UUID?

    var body: some View {
        List {
            if store.user?.canViewIssues == true {
                Picker("Status", selection: $filter) {
                    ForEach(SeerrIssueFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if title?.mediaInfo != nil, store.user?.canCreateIssues == true {
                    Button("Report an Issue") { showingReport = true }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary); Button("Refresh") { Task { await load(reset: true) } } }
                }
                ForEach(loadedRevision == store.revision ? items : []) { issue in
                    NavigationLink { SeerrIssueDetailView(issueID: issue.id) } label: {
                        VStack(alignment: .leading) {
                            Text("Issue #\(issue.id)")
                            Text(SeerrIssueType(rawValue: issue.issueType)?.title ?? String(localized: "Issue"))
                                .foregroundStyle(.secondary)
                            Text(issue.isOpen ? String(localized: "Open") : issue.isResolved ? String(localized: "Resolved") : String(localized: "Unknown Status"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if loading {
                    ProgressView()
                } else if offset < total {
                    Button("Load More") { Task { await load(reset: false) } }
                } else if items.isEmpty, message == nil {
                    Text("No issues found.").foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Issues Unavailable", systemImage: "exclamationmark.bubble", description: Text("Your Seerr account does not have permission to view issues."))
            }
        }
        .navigationTitle("My Issues")
        .task(id: "\(store.revision):\(filter.rawValue)") { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(isPresented: $showingReport, onDismiss: { Task { await load(reset: true) } }) {
            if let title {
                SeerrReportIssueView(title: title)
            }
        }
    }

    private func load(reset: Bool) async {
        guard let user = store.user, user.canViewIssues else { return }
        let requestID = UUID()
        loadID = requestID
        let expected = store.revision
        if reset {
            items = []; offset = 0; total = 0
        }
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }
        do {
            let client = try store.requireClient()
            let page = try await client.issues(filter: filter, createdBy: user.id, skip: reset ? 0 : offset)
            guard expected == store.revision, loadID == requestID, !Task.isCancelled else { return }
            let rows = title.map { selected in page.results.filter { $0.media?.tmdbId == selected.id && $0.media?.mediaType == selected.mediaType } } ?? page.results
            items = reset ? rows : items + rows.filter { row in !items.contains(where: { $0.id == row.id }) }
            offset = (reset ? 0 : offset) + page.results.count
            total = page.pageInfo.results
            loadedRevision = expected
            message = nil
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            message = error.localizedDescription
            store.handle(error)
        }
    }
}

struct SeerrReportIssueView: View {
    @Environment(SeerrStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: SeerrTitle
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var type: SeerrIssueType = .video
    @State private var description = ""
    @State private var submitting = false
    @State private var outcomeUnknown = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    @State private var confirmingRetry = false

    private var mutationKey: String {
        "report:\(title.mediaType?.rawValue ?? "unknown"):\(title.id)"
    }

    private var isAdmitted: Bool {
        store.admits(title) && ContentRatingGate.admits(
            MediaItem(officialRating: title.certification, type: title.mediaType == .tv ? .series : .movie),
            limit: ContentRatingGate.Limit(rawValue: contentLimit) ?? .off,
            hideUnrated: hideUnrated
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAdmitted {
                    Section(title.displayTitle) {
                        Picker("Issue Type", selection: $type) { ForEach(SeerrIssueType.allCases, id: \.self) { Text($0.title).tag($0) } }
                        TextField("Describe the problem", text: $description)
                    }
                    if let message {
                        Text(message).foregroundStyle(.secondary)
                    }
                    if outcomeUnknown || store.hasPendingSupportMutation(key: mutationKey) {
                        Text("A report may already have been submitted. Check Seerr before allowing another report.")
                        if let url = store.serverURL {
                            Link("Check Issues in Seerr", destination: url.appending(path: "issues"))
                        }
                        Button("Close and Check My Issues") { dismiss() }
                        Button("I Checked Seerr…") { confirmingRetry = true }
                    } else {
                        Button("Submit Issue") { operation = Task { await submit() } }
                            .disabled(submitting || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.user?.canCreateIssues != true)
                    }
                    if submitting {
                        ProgressView()
                    }
                } else {
                    ContentUnavailableView("Title Unavailable", systemImage: "hand.raised", description: Text("This title is outside the current content restrictions."))
                }
            }
            .seerrFormStyle()
            .modifier(SeerrSupportOperationLifetime(operation: $operation))
            .onChange(of: contentLimit + ":" + String(hideUnrated)) { _, _ in confirmingRetry = false }
            .navigationTitle("Report an Issue")
            .toolbar { ToolbarItem { Button("Cancel") { dismiss() }.disabled(submitting) } }
            .confirmationDialog("Allow another report for \(title.displayTitle)?", isPresented: $confirmingRetry, titleVisibility: .visible) {
                Button("Allow Another Report") { store.completeSupportMutation(key: mutationKey); outcomeUnknown = false; message = nil }
            } message: { Text("Confirm that you checked Seerr and another report is needed. An existing report will remain on Seerr.") }
        }
    }

    private func submit() async {
        guard !submitting, !outcomeUnknown, !store.hasPendingSupportMutation(key: mutationKey), isAdmitted else { return }
        let expected = store.revision
        submitting = true
        defer { submitting = false }
        do {
            try await store.refreshUser()
            guard expected == store.revision, !Task.isCancelled else { return }
            let client = try store.requireClient()
            guard let mediaType = title.mediaType else { throw SeerrClientError.invalidPayload }
            let current = try await client.details(mediaType: mediaType, id: title.id)
            guard expected == store.revision, store.admits(current), let mediaID = current.mediaInfo?.id else { throw SeerrConnectionError.notPermitted }
            try store.beginSupportMutation(key: mutationKey)
            _ = try await client.reportIssue(mediaID: mediaID, type: type, message: description)
            if expected == store.revision {
                store.completeSupportMutation(key: mutationKey)
            }
            guard expected == store.revision, !Task.isCancelled else { return }
            dismiss()
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            outcomeUnknown = error as? SeerrClientError == .mutationOutcomeUnknown
            message = error.localizedDescription
            store.handle(error)
        }
    }
}

private struct SeerrIssueDetailView: View {
    @Environment(SeerrStore.self) private var store
    let issueID: Int
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var issue: SeerrIssue?
    @State private var mediaTitle: String?
    @State private var comment = ""
    @State private var loading = false
    @State private var message: String?
    @State private var requiresRefresh = false
    @State private var confirmingStatus = false
    @State private var operation: Task<Void, Never>?
    @State private var loadID = UUID()
    @State private var loadedRevision: UUID?
    @State private var loadedRestrictions: String?
    @State private var confirmingCommentRetry = false
    private var restrictionID: String {
        contentLimit + ":" + String(hideUnrated)
    }

    private var mutationKey: String {
        "comment:\(issueID)"
    }

    var body: some View {
        Form {
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
            if let issue, loadedRevision == store.revision, loadedRestrictions == restrictionID {
                Section(mediaTitle ?? String(localized: "Issue #\(issue.id)")) {
                    LabeledContent("Status", value: issue.isOpen ? String(localized: "Open") : issue.isResolved ? String(localized: "Resolved") : String(localized: "Unknown"))
                    LabeledContent("Issue Type", value: SeerrIssueType(rawValue: issue.issueType)?.title ?? String(localized: "Unknown"))
                }
                Section("Comments") {
                    ForEach(issue.comments ?? []) { entry in
                        VStack(alignment: .leading) {
                            if let name = entry.user?.name {
                                Text(name).font(.headline)
                            }
                            Text(entry.message)
                        }
                    }
                    if let user = store.user, issue.canModify(user: user), !requiresRefresh {
                        if store.hasPendingSupportMutation(key: mutationKey) {
                            Text("A comment may already have been posted. Check Seerr before allowing another comment.")
                            if let url = store.serverURL {
                                Link("Check Issue in Seerr", destination: url.appending(path: "issues/\(issueID)"))
                            }
                            Button("I Checked Seerr…") { confirmingCommentRetry = true }
                        } else {
                            TextField("Add a comment", text: $comment)
                            Button("Post Comment") { operation = Task { await mutate(resolve: nil) } }
                                .disabled(loading || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button(issue.isOpen ? "Resolve Issue" : "Reopen Issue") { confirmingStatus = true }.disabled(loading)
                    }
                }
            }
            if loading {
                ProgressView()
            }
            Button("Refresh") { Task { await load() } }.disabled(loading)
        }
        .seerrFormStyle()
        .modifier(SeerrSupportOperationLifetime(operation: $operation))
        .onChange(of: restrictionID) { _, _ in confirmingStatus = false; confirmingCommentRetry = false }
        .navigationTitle("Issue #\(issueID)")
        .task(id: "\(store.revision):\(restrictionID)") { await load() }
        .confirmationDialog("Allow another comment on issue #\(issueID)?", isPresented: $confirmingCommentRetry, titleVisibility: .visible) {
            Button("Allow Another Comment") { store.completeSupportMutation(key: mutationKey) }
        } message: { Text("Confirm that you checked Seerr and another comment is needed. Existing comments remain on Seerr.") }
        .confirmationDialog(issue?.isOpen == true ? "Resolve this issue?" : "Reopen this issue?", isPresented: $confirmingStatus, titleVisibility: .visible) {
            Button(issue?.isOpen == true ? "Resolve Issue" : "Reopen Issue") { operation = Task { await mutate(resolve: issue?.isOpen == true) } }
        } message: { Text(mediaTitle ?? String(localized: "Issue #\(issueID)")) }
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        let expected = store.revision
        let restrictions = restrictionID
        issue = nil
        mediaTitle = nil
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }
        do {
            let client = try store.requireClient()
            let current = try await client.issue(id: issueID)
            guard let tmdbID = current.media?.tmdbId, let type = current.media?.mediaType else { throw SeerrConnectionError.notPermitted }
            let title = try await client.details(mediaType: type, id: tmdbID)
            guard store.admits(title) else { throw SeerrConnectionError.notPermitted }
            guard expected == store.revision, restrictions == restrictionID, loadID == requestID, !Task.isCancelled else { return }
            issue = current
            mediaTitle = title.displayTitle
            loadedRevision = expected
            loadedRestrictions = restrictions
            message = nil
            requiresRefresh = false
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            issue = nil
            message = error.localizedDescription
            store.handle(error)
        }
    }

    private func mutate(resolve: Bool?) async {
        guard !loading, !requiresRefresh, resolve != nil || !store.hasPendingSupportMutation(key: mutationKey) else { return }
        let expected = store.revision
        loading = true
        do {
            try await store.refreshUser()
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            let client = try store.requireClient()
            let updated: SeerrIssue
            if let resolve {
                updated = try await client.setIssueResolved(id: issueID, resolved: resolve)
            } else {
                try store.beginSupportMutation(key: mutationKey)
                updated = try await client.commentOnIssue(id: issueID, message: comment)
            }
            if resolve == nil, expected == store.revision {
                store.completeSupportMutation(key: mutationKey)
            }
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            issue = updated
            comment = ""
            message = nil
        } catch {
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            requiresRefresh = error as? SeerrClientError == .mutationOutcomeUnknown
            message = error.localizedDescription
            store.handle(error)
        }
        loading = false
    }
}

struct SeerrBlocklistView: View {
    @Environment(SeerrStore.self) private var store
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var items: [SeerrBlocklistItem] = []
    @State private var total = 0
    @State private var offset = 0
    @State private var loading = false
    @State private var message: String?
    @State private var removing: SeerrBlocklistItem?
    @State private var requiresRefresh = false
    @State private var operation: Task<Void, Never>?
    @State private var loadID = UUID()
    @State private var loadedRevision: UUID?
    @State private var loadedRestrictions: String?
    private var restrictionID: String {
        contentLimit + ":" + String(hideUnrated)
    }

    var body: some View {
        List {
            if store.user?.canViewBlocklist == true {
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
                ForEach(loadedRevision == store.revision && loadedRestrictions == restrictionID ? items : []) { item in
                    HStack {
                        Text(item.title ?? String(localized: "TMDB #\(item.tmdbId)"))
                        Spacer()
                        if store.user?.canManageBlocklist == true {
                            Button("Remove", role: .destructive) { removing = item }.disabled(loading || requiresRefresh)
                        }
                    }
                }
                if loading {
                    ProgressView()
                } else if offset < total {
                    Button("Load More") { Task { await load(reset: false) } }
                } else if items.isEmpty, message == nil {
                    Text("The blocklist is empty.").foregroundStyle(.secondary)
                }
                Button("Refresh") { Task { await load(reset: true) } }.disabled(loading)
            } else {
                ContentUnavailableView("Blocklist Unavailable", systemImage: "hand.raised", description: Text("Your Seerr account does not have permission to view the blocklist."))
            }
        }
        .navigationTitle("Blocklist")
        .modifier(SeerrSupportOperationLifetime(operation: $operation))
        .onChange(of: restrictionID) { _, _ in removing = nil }
        .task(id: "\(store.revision):\(restrictionID)") { await load(reset: true) }
        .confirmationDialog("Remove this title from the blocklist?", isPresented: Binding(get: { removing != nil }, set: {
            if !$0 {
                removing = nil
            }
        }), titleVisibility: .visible) {
            if let item = removing {
                Button("Remove \(item.title ?? String(item.tmdbId))", role: .destructive) { operation = Task { await remove(item) } }
            }
        } message: {
            Text("Seerr also removes this title’s catalog record and associated request and issue history. Media files remain on your media server.")
        }
    }

    private func load(reset: Bool) async {
        guard store.user?.canViewBlocklist == true else { return }
        let requestID = UUID()
        loadID = requestID
        let expected = store.revision
        let restrictions = restrictionID
        if reset {
            items = []; offset = 0; total = 0
        }
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }
        do {
            let client = try store.requireClient()
            let page = try await client.blocklist(skip: reset ? 0 : offset)
            var admitted: [SeerrBlocklistItem] = []
            for row in page.results {
                try Task.checkCancellation()
                guard row.mediaType == .movie || row.mediaType == .tv else { continue }
                if ContentRatingGate.storedLimit() != .off {
                    let detail = try await client.details(mediaType: row.mediaType, id: row.tmdbId)
                    let item = MediaItem(officialRating: detail.certification, type: row.mediaType == .tv ? .series : .movie)
                    guard ContentRatingGate.admitsStored(item) else { continue }
                }
                admitted.append(row)
            }
            guard expected == store.revision, restrictions == restrictionID, loadID == requestID, !Task.isCancelled else { return }
            items = reset ? admitted : items + admitted.filter { row in !items.contains(where: { $0.id == row.id }) }
            offset = (reset ? 0 : offset) + page.results.count
            total = page.pageInfo.results
            loadedRevision = expected
            loadedRestrictions = restrictions
            requiresRefresh = false
            message = nil
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            message = error.localizedDescription
            store.handle(error)
        }
    }

    private func remove(_ item: SeerrBlocklistItem) async {
        guard !loading, !requiresRefresh else { return }
        let expected = store.revision
        loading = true
        do {
            try await store.refreshUser()
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            try await store.requireClient().removeFromBlocklist(tmdbID: item.tmdbId, mediaType: item.mediaType)
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            items.removeAll { $0.id == item.id }
            offset = max(0, offset - 1)
            total = max(0, total - 1)
            store.recordBlock(mediaType: item.mediaType, id: item.tmdbId, blocked: false)
        } catch {
            guard expected == store.revision, !Task.isCancelled else { loading = false; return }
            requiresRefresh = error as? SeerrClientError == .mutationOutcomeUnknown
            message = error.localizedDescription
            store.handle(error)
        }
        loading = false
    }
}

struct SeerrBlocklistAction: View {
    @Environment(SeerrStore.self) private var store
    let title: SeerrTitle
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    var onChanged: () -> Void = {}
    @State private var confirming = false
    @State private var loading = false
    @State private var completed = false
    @State private var message: String?
    @State private var requiresRefresh = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        if store.user?.canManageBlocklist == true,
           ContentRatingGate.admits(
               MediaItem(officialRating: title.certification, type: title.mediaType == .tv ? .series : .movie),
               limit: ContentRatingGate.Limit(rawValue: contentLimit) ?? .off,
               hideUnrated: hideUnrated
           ), store.admits(title)
        {
            VStack(alignment: .leading) {
                if completed {
                    Text("Added to Blocklist").foregroundStyle(.secondary)
                } else {
                    Button("Add to Blocklist", role: .destructive) { confirming = true }.disabled(loading || requiresRefresh)
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
                if requiresRefresh {
                    Button("Refresh") { Task { await refresh() } }.disabled(loading)
                }
            }
            .confirmationDialog("Block \(title.displayTitle)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Block \(title.displayTitle)", role: .destructive) { operation = Task { await add() } }
            } message: { Text("This prevents Seerr requests for this title for all users.") }
            .modifier(SeerrSupportOperationLifetime(operation: $operation))
            .onChange(of: contentLimit + ":" + String(hideUnrated)) { _, _ in confirming = false }
        }
    }

    private func add() async {
        guard !loading, !requiresRefresh else { return }
        let expected = store.revision
        loading = true
        defer { loading = false }
        do {
            try await store.refreshUser()
            guard expected == store.revision, !Task.isCancelled else { return }
            try await store.requireClient().addToBlocklist(title: title)
            guard expected == store.revision, !Task.isCancelled else { return }
            completed = true
            if let type = title.mediaType {
                store.recordBlock(mediaType: type, id: title.id, blocked: true)
            }
            onChanged()
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            requiresRefresh = error as? SeerrClientError == .mutationOutcomeUnknown
            message = error.localizedDescription
            store.handle(error)
        }
    }

    private func refresh() async {
        guard let type = title.mediaType else { return }
        let expected = store.revision
        do {
            let current = try await store.requireClient().details(mediaType: type, id: title.id)
            guard expected == store.revision, !Task.isCancelled else { return }
            if let status = current.mediaInfo?.status, case .unknown = status {
                throw SeerrClientError.invalidResponse
            }
            completed = current.mediaInfo?.status == .blocklisted
            requiresRefresh = false
            message = nil
            store.recordBlock(mediaType: type, id: title.id, blocked: completed)
            onChanged()
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            message = error.localizedDescription
            store.handle(error)
        }
    }
}

struct SeerrPreferencesView: View {
    @Environment(SeerrStore.self) private var store
    @State private var regions: [SeerrRegion] = []
    @State private var languages: [SeerrLanguage] = []
    @State private var region = ""
    @State private var streamingRegion = ""
    @State private var language = ""
    @State private var emailEnabled = false
    @State private var emailEvents = 0
    @State private var originalEmailEvents = 0
    @State private var originalPreferences = SeerrRegionalPreferences(discoverRegion: "", streamingRegion: "", originalLanguage: "")
    @State private var loaded = false
    @State private var loading = false
    @State private var message: String?
    @State private var requiresRefresh = false
    @State private var operation: Task<Void, Never>?
    @State private var loadID = UUID()
    @State private var loadedRevision: UUID?

    var body: some View {
        Form {
            if loaded, loadedRevision == store.revision {
                Section("Catalog Language and Region") {
                    Picker("Discovery Region", selection: $region) {
                        Text("Server Default").tag("")
                        if !region.isEmpty, !regions.contains(where: { $0.code == region }) {
                            Text(region).tag(region)
                        }
                        ForEach(regions) { Text($0.name).tag($0.code) }
                    }
                    Picker("Streaming Region", selection: $streamingRegion) {
                        Text("Server Default").tag("")
                        if !streamingRegion.isEmpty, !regions.contains(where: { $0.code == streamingRegion }) {
                            Text(streamingRegion).tag(streamingRegion)
                        }
                        ForEach(regions) { Text($0.name).tag($0.code) }
                    }
                    Picker("Original Language", selection: $language) {
                        Text("Server Default").tag("")
                        if !language.isEmpty, !languages.contains(where: { $0.code == language }) {
                            Text(language).tag(language)
                        }
                        ForEach(languages) { Text($0.name).tag($0.code) }
                    }
                    Button("Save Catalog Preferences") { operation = Task { await save(email: false) } }.disabled(loading || requiresRefresh || regionalChanges.isEmpty)
                }
                .disabled(loading || requiresRefresh)
                if emailEnabled {
                    Section("Email Notifications") {
                        eventToggle("Request Approved", bit: 4)
                        eventToggle("Media Available", bit: 8)
                        eventToggle("Request Declined", bit: 64)
                        eventToggle("Issue Comments", bit: 512)
                        eventToggle("Issue Resolved", bit: 1024)
                        Button("Save Email Preferences") { operation = Task { await save(email: true) } }.disabled(loading || requiresRefresh || emailEvents == originalEmailEvents)
                    }
                }
            }
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
            if loading {
                ProgressView()
            }
            Button("Refresh") { Task { await load() } }.disabled(loading)
        }
        .seerrFormStyle()
        .modifier(SeerrSupportOperationLifetime(operation: $operation))
        .navigationTitle("Seerr Preferences")
        .task(id: store.revision) { await load() }
    }

    private func eventToggle(_ title: LocalizedStringKey, bit: Int) -> some View {
        Toggle(title, isOn: Binding(get: { emailEvents & bit != 0 }, set: { enabled in
            if enabled {
                emailEvents |= bit
            } else {
                emailEvents &= ~bit
            }
        })).disabled(loading || requiresRefresh)
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        let expected = store.revision
        loaded = false
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }
        do {
            let client = try store.requireClient()
            let regions = try await client.regions()
            let languages = try await client.languages()
            let preferences = try await client.regionalPreferences()
            let notifications = try await client.emailNotificationPreferences()
            guard expected == store.revision, loadID == requestID, !Task.isCancelled else { return }
            self.regions = regions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.languages = languages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            region = preferences.discoverRegion
            streamingRegion = preferences.streamingRegion
            language = preferences.originalLanguage
            originalPreferences = preferences
            emailEnabled = notifications.enabled
            emailEvents = notifications.events
            originalEmailEvents = notifications.events
            loaded = true
            loadedRevision = expected
            requiresRefresh = false
            message = nil
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            message = error.localizedDescription
            store.handle(error)
        }
    }

    private func save(email: Bool) async {
        guard !loading, !requiresRefresh else { return }
        let submittedPreferences = SeerrRegionalPreferences(discoverRegion: region, streamingRegion: streamingRegion, originalLanguage: language)
        let submittedRegionalChanges = regionalChanges
        let submittedEmailEvents = emailEvents
        let submittedEmailChanges = emailEvents ^ originalEmailEvents
        let expected = store.revision
        loading = true
        defer { loading = false }
        do {
            try await store.refreshUser()
            guard expected == store.revision, !Task.isCancelled else { return }
            let client = try store.requireClient()
            if email {
                try await client.updateEmailNotificationPreferences(events: submittedEmailEvents, changedMask: submittedEmailChanges)
            } else {
                try await client.updateRegionalPreferences(submittedPreferences, changedFields: submittedRegionalChanges)
            }
            guard expected == store.revision, !Task.isCancelled else { return }
            if email {
                originalEmailEvents = submittedEmailEvents
            } else {
                originalPreferences = submittedPreferences
            }
            message = String(localized: "Preferences saved.")
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            requiresRefresh = error as? SeerrClientError == .mutationOutcomeUnknown
            message = error.localizedDescription
            store.handle(error)
        }
    }

    private var regionalChanges: SeerrRegionalPreferenceFields {
        var fields: SeerrRegionalPreferenceFields = []
        if region != originalPreferences.discoverRegion {
            fields.insert(.discovery)
        }
        if streamingRegion != originalPreferences.streamingRegion {
            fields.insert(.streaming)
        }
        if language != originalPreferences.originalLanguage {
            fields.insert(.language)
        }
        return fields
    }
}

/// Unstructured button tasks must stop before committing work after navigation or account/restriction changes.
private struct SeerrSupportOperationLifetime: ViewModifier {
    @Environment(SeerrStore.self) private var store
    @Binding var operation: Task<Void, Never>?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    func body(content: Content) -> some View {
        content
            .onDisappear { operation?.cancel() }
            .onChange(of: store.revision) { _, _ in operation?.cancel() }
            .onChange(of: contentLimit + ":" + String(hideUnrated)) { _, _ in operation?.cancel() }
    }
}
