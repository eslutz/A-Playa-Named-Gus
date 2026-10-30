import SwiftUI

struct SeerrRequestView: View {
    @Environment(SeerrStore.self) private var store
    let title: SeerrTitle
    var body: some View {
        SeerrRequestForm(draft: store.requestDraft(for: title))
    }
}

private struct SeerrRequestForm: View {
    @Environment(SeerrStore.self) private var store
    @Environment(RootNavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @Bindable var draft: SeerrRequestDraft
    @State private var confirmingRetry = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isConnected, store.admits(draft.title) {
                    if draft.phase == .confirmed, let request = draft.confirmed {
                        SeerrRequestConfirmation(title: draft.title, status: request.status.seerrRequestDescription) {
                            guard navigation.pushIPadRequestHistory() else { return false }
                            store.finishRequestDraft(title: draft.title)
                            dismiss()
                            return true
                        }
                    } else {
                        Form {
                            #if !os(tvOS)
                                Section {
                                    Text(draft.title.displayTitle).font(.headline)
                                    if let year = draft.title.releaseYear {
                                        Text(year).foregroundStyle(.secondary)
                                    }
                                } header: { Text(draft.type == .tv ? "Request Seasons" : "Request Movie") }
                            #endif
                            if draft.phase == .loading {
                                Section { ProgressView("Checking Request Eligibility…") }
                            } else if draft.phase == .uncertain {
                                Section {
                                    Label("Check Request Before Retrying", systemImage: "questionmark.circle")
                                    Text("Seerr may have received this request. Check its status before submitting another request.")
                                    Button { Task { await draft.check(store: store) } } label: {
                                        HStack {
                                            Text("Check Request"); if draft.isChecking {
                                                ProgressView()
                                            }
                                        }
                                    }.disabled(draft.isChecking)
                                    if let url = store.serverURL {
                                        Link("Check in Seerr", destination: url.appending(path: "requests"))
                                    }
                                    Button("Review Another Request") { confirmingRetry = true }.disabled(draft.isChecking)
                                }
                            } else {
                                review
                            }
                            if let message = draft.message {
                                Section { Text(message).foregroundStyle(.secondary) }
                            }
                        }
                        .gusTVRequestReview(title: draft.title)
                    }
                } else {
                    RestrictedContentView()
                }
            }
            .seerrFormStyle()
            .navigationTitle(draft.phase == .confirmed ? "Request" : "Review Request")
            .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton {
                if draft.phase == .confirmed {
                    store.finishRequestDraft(title: draft.title)
                }
                dismiss()
            }.disabled(draft.phase == .submitting) } }
            .interactiveDismissDisabled(draft.phase == .submitting)
            .confirmationDialog("Retry request for \(draft.title.displayTitle)?", isPresented: $confirmingRetry, titleVisibility: .visible) {
                Button("I Verified the Request Was Not Received") { Task { await draft.resetAfterVerification(store: store) } }
            } message: { Text("Only continue after checking Seerr and confirming the earlier request did not reach the server. Its result is still unknown in Gus.") }
            .task {
                if draft.phase != .uncertain {
                    await draft.load(store: store, resetSelection: draft.selectedSeasons.isEmpty)
                }
            }
            .onChange(of: store.revision) { _, _ in dismiss() }
            .onChange(of: contentLimit) {
                _, _ in if !store.admits(draft.title) {
                    dismiss()
                }
            }
            .onChange(of: hideUnrated) {
                _, _ in if !store.admits(draft.title) {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder private var review: some View {
        Section("Format") {
            Picker("Format", selection: $draft.is4K) {
                Text("Standard").tag(false)
                if draft.allows4K {
                    Text("4K").tag(true)
                }
            }
            .onChange(of: draft.is4K) { _, _ in Task { await draft.formatChanged(store: store) } }
            .disabled(draft.phase == .submitting)
        }
        if draft.type == .tv {
            Section {
                ForEach(draft.title.seasons ?? [], id: \.seasonNumber) { season in
                    let eligible = draft.eligibleSeasons.contains(season.seasonNumber)
                    Toggle(isOn: Binding(get: { draft.selectedSeasons.contains(season.seasonNumber) }, set: { value in
                        if value {
                            draft.selectedSeasons.insert(season.seasonNumber)
                        } else {
                            draft.selectedSeasons.remove(season.seasonNumber)
                        }
                    })) {
                        VStack(alignment: .leading) {
                            Text(season.seasonNumber == 0 ? String(localized: "Specials") : String(localized: "Season \(season.seasonNumber)"))
                            if !eligible {
                                Text("Unavailable for a new request").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!eligible || draft.settings?.partialRequestsEnabled != true || draft.phase == .submitting)
                }
            } header: { Text("Seasons") } footer: {
                if draft.settings?.partialRequestsEnabled != true {
                    Text("This server requests all eligible seasons together.")
                }
            }
        }
        if let quota = draft.quota?.status(for: draft.type) {
            Section("Request Limits") {
                if let remaining = quota.remaining, let limit = quota.limit, limit > 0 {
                    LabeledContent("Remaining", value: "\(remaining) / \(limit)")
                }
                if quota.restricted {
                    Text("Your request quota has been reached.")
                }
                if let account = draft.account {
                    Text(account.automaticallyApproves(draft.type, is4K: draft.is4K) ? "Eligible requests are automatically approved by Seerr." : "Seerr may require approval before this request is available.")
                }
            }
        }
        if !draft.servers.isEmpty {
            Section("Advanced Options") {
                Picker("Service", selection: $draft.serverID) {
                    Text("Server Default").tag(Int?.none)
                    ForEach(draft.servers) { Text($0.name).tag(Optional($0.id)) }
                }
                .onChange(of: draft.serverID) { _, _ in Task { await draft.loadOptions(store: store) } }
                if let service = draft.service {
                    Picker("Quality Profile", selection: $draft.profileID) {
                        Text("Server Default").tag(Int?.none)
                        ForEach(service.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Root Folder", selection: $draft.rootFolder) {
                        Text("Server Default").tag(String?.none)
                        ForEach(service.rootFolders, id: \.path) { Text($0.path).tag(Optional($0.path)) }
                    }
                    if let languages = service.languageProfiles, !languages.isEmpty {
                        Picker("Language", selection: $draft.languageID) {
                            Text("Server Default").tag(Int?.none)
                            ForEach(languages) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if draft.isLoadingOptions {
                    ProgressView("Loading Options…")
                }
            }.disabled(draft.phase == .submitting)
        } else {
            Section { Text("Uses the service, quality profile and destination configured on Seerr.").foregroundStyle(.secondary) }
        }
        Section {
            Button { Task { await draft.submit(store: store) } } label: {
                HStack {
                    if draft.phase == .submitting {
                        Text("Submitting Request…"); ProgressView()
                    } else if draft.type == .tv {
                        Text("Request \(draft.selectedSeasons.count) Seasons")
                    } else {
                        Text("Request Movie")
                    }
                }
            }
            .disabled(!draft.canSubmit)
            .accessibilityIdentifier("Seerr.submitRequest")
            if draft.message != nil {
                Button("Refresh Eligibility") { Task { await draft.load(store: store) } }.disabled(draft.phase == .submitting)
            }
        }
    }
}

/// Submission acknowledgment is distinct from approval and availability.
private struct SeerrRequestConfirmation: View {
    let title: SeerrTitle
    let status: String
    let openMainWindowHistory: () -> Bool
    @State private var showingHistory = false

    var body: some View {
        SeerrSetupLayout {
            HStack(alignment: .top, spacing: 16) {
                SeerrArtworkView(path: title.posterPath).frame(width: 64, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.displayTitle).font(.title3.bold())
                    if let year = title.releaseYear {
                        Text(year).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Request submitted", systemImage: "checkmark.circle").font(.title2.bold())
                Text(status).font(.headline)
                Text("Follow approval and availability in My Requests.").foregroundStyle(.secondary)
            }
            Button {
                if !openMainWindowHistory() {
                    showingHistory = true
                }
            } label: {
                Text("View My Requests").frame(maxWidth: .infinity).gusSeerrActionLabelSizing().gusProminentActionForeground()
            }
            .gusProminentGlassButtonStyle().gusProminentActionTint().controlSize(.large)
        }
        .navigationDestination(isPresented: $showingHistory) { SeerrRequestsView() }
    }
}
