#if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
    @preconcurrency import DeclaredAgeRange
    import SwiftUI

    /// One decision per signed-in account on this device. The device-wide ceiling
    /// survives switching Jellyfin accounts, offline use and declined requests.
    @MainActor @Observable
    final class AgeRangeAccess {
        enum Stage { case checking, optional, required, unavailable, ready }
        enum Response { case shared(Int?), declined }

        private(set) var stage = Stage.checking
        private(set) var requesting = false
        private(set) var message: String?
        private var checking = false
        private let defaults: UserDefaults
        private let offerKey: String
        private static let lastRequirementKey = "dev.ericslutz.gus.ageRangeRequired"

        init(scope: AccountScope, defaults: UserDefaults = .standard) {
            self.defaults = defaults
            offerKey = "dev.ericslutz.gus.ageRangeOffer." + scope.storageKey
        }

        func prepare(
            isCurrent: () -> Bool,
            requirement: () async throws -> Bool,
            request: () async throws -> Response
        ) async {
            guard !checking, stage == .checking || stage == .unavailable else { return }
            checking = true
            defer {
                checking = false
                // If the presenting window closes mid-lookup, another window
                // sharing this session can retry instead of waiting indefinitely.
                if stage == .checking {
                    stage = .unavailable
                }
            }
            stage = .checking
            let required: Bool
            do {
                required = try await requirement()
                guard isCurrent(), !Task.isCancelled else { return }
                defaults.set(required, forKey: Self.lastRequirementKey)
            } catch {
                guard isCurrent(), !Task.isCancelled else { return }
                guard let previous = defaults.object(forKey: Self.lastRequirementKey) as? Bool else {
                    defaults.set(true, forKey: ContentRatingGate.awaitingRangeKey)
                    stage = .unavailable
                    return
                }
                required = previous
                if required, defaults.object(forKey: ContentRatingGate.ageCeilingKey) != nil,
                   !defaults.bool(forKey: ContentRatingGate.awaitingRangeKey)
                {
                    // Previously accepted policy remains effective when offline.
                    stage = .ready
                    return
                }
            }
            guard isCurrent(), !Task.isCancelled else { return }
            defaults.set(required, forKey: ContentRatingGate.awaitingRangeKey)
            if required {
                stage = .required
                await check(isCurrent: isCurrent, request: request)
            } else {
                stage = defaults.bool(forKey: offerKey) ? .ready : .optional
            }
        }

        /// CarPlay and voice requests may restore an account before a phone window
        /// exists. Only the foreground window can present Apple's sharing sheet.
        func permitsExternalMedia(
            isCurrent: () -> Bool,
            requirement: () async throws -> Bool = AgeRangeAccess.systemRequirement
        ) async -> Bool {
            guard isCurrent(), !Task.isCancelled else { return false }
            if stage != .checking {
                return (stage == .ready || stage == .optional) && !defaults.bool(forKey: ContentRatingGate.awaitingRangeKey)
            }
            guard !checking else { return false }
            do {
                let required = try await requirement()
                guard isCurrent(), !Task.isCancelled else { return false }
                if stage == .checking, !checking {
                    defaults.set(required, forKey: Self.lastRequirementKey)
                    defaults.set(required, forKey: ContentRatingGate.awaitingRangeKey)
                    return !required
                }
                return (stage == .ready || stage == .optional) && !defaults.bool(forKey: ContentRatingGate.awaitingRangeKey)
            } catch {
                guard isCurrent(), !Task.isCancelled, !checking, stage == .checking,
                      let previous = defaults.object(forKey: Self.lastRequirementKey) as? Bool,
                      !defaults.bool(forKey: ContentRatingGate.awaitingRangeKey) else { return false }
                return !previous || defaults.object(forKey: ContentRatingGate.ageCeilingKey) != nil
            }
        }

        func deferOptionalOffer() {
            guard stage == .optional, !requesting else { return }
            defaults.set(true, forKey: offerKey)
            stage = .ready
        }

        func check(isCurrent: () -> Bool, request: () async throws -> Response) async {
            guard !requesting, isCurrent() else { return }
            requesting = true
            message = nil
            defer { requesting = false }
            do {
                let response = try await request()
                guard isCurrent(), !Task.isCancelled else { return }
                switch response {
                case let .shared(lower):
                    ContentRatingGate.applySharedRange(lowerBound: lower, userDefaults: defaults)
                    defaults.set(false, forKey: ContentRatingGate.awaitingRangeKey)
                    let policy = ContentRatingGate.storedPolicy(userDefaults: defaults)
                    message = policy.ageCeiling == .off
                        ? String(localized: "The shared age range allows your household settings.")
                        : String(localized: "Shared age range limit: \(policy.ageCeiling.title). Unrated media is hidden.")
                    defaults.set(true, forKey: offerKey)
                    stage = .ready
                case .declined:
                    message = String(localized: "No age range was shared. The limit is unchanged.")
                    if stage == .optional {
                        defaults.set(true, forKey: offerKey)
                        stage = .ready
                    }
                }
            } catch {
                guard isCurrent(), !Task.isCancelled else { return }
                message = String(localized: "Age range is unavailable. Try again later.")
            }
        }

        static func systemRequirement() async throws -> Bool {
            if #available(iOS 26.4, macOS 26.4, *) {
                return try await AgeRangeService.shared.requiredRegulatoryFeatures.contains(.declaredAgeRangeRequired)
            }
            if #available(iOS 26.2, macOS 26.2, *) {
                return try await AgeRangeService.shared.isEligibleForAgeFeatures
            }
            return false
        }
    }

    @MainActor
    private func sharedRange(using action: DeclaredAgeRangeAction) async throws -> AgeRangeAccess.Response {
        switch try await action(ageGates: 13, 16, 18) {
        case let .sharing(range): .shared(range.lowerBound)
        case .declinedSharing: .declined
        @unknown default: throw AgeRangeService.Error.notAvailable
        }
    }

    struct AgeRangeAccessHost: ViewModifier {
        let session: SessionStore
        @Environment(AppModel.self) private var app
        @Environment(\.requestAgeRange) private var requestAgeRange

        func body(content: Content) -> some View {
            let access = session.ageRangeAccess
            Group {
                switch access.stage {
                case .checking:
                    ProgressView("Checking Age Range…")
                case .ready:
                    content
                case .optional, .required, .unavailable:
                    ContentUnavailableView {
                        Label("Age Range", systemImage: "person.badge.shield.checkmark")
                    } description: {
                        if access.stage == .unavailable {
                            Text("Gus couldn't check whether age sharing is required. Connect to the internet and try again.")
                        } else if access.stage == .required {
                            Text("Apple requires sharing an age range before you can browse media.")
                        } else {
                            Text("Use your Apple age range to limit media on this device. You can also check it later in Settings.")
                        }
                        if let message = access.message {
                            Text(message)
                        }
                    } actions: {
                        if access.stage == .unavailable {
                            Button("Try Again") { Task { await prepare() } }
                        } else {
                            Button("Check Age Range") {
                                Task { await access.check(isCurrent: { session.isActive }) { try await sharedRange(using: requestAgeRange) } }
                            }
                        }
                        if access.stage == .optional {
                            Button("Not Now") { access.deferOptionalOffer() }
                        } else {
                            Button("Sign Out") { Task { await app.signOut() } }
                        }
                    }
                    .disabled(access.requesting)
                }
            }
            .onChange(of: access.stage) { _, _ in session.systemPrivacyDidChange() }
            .task { await prepare() }
        }

        private func prepare() async {
            let access = session.ageRangeAccess
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--gus-demo-server") || arguments.contains("--gus-debug-preview-session") {
                    // The local fixture server has no Apple Account. Model the optional
                    // decision without presenting a real Apple Account sheet in UI tests.
                    await access.prepare(isCurrent: { session.isActive }, requirement: { false }, request: { .declined })
                    if !arguments.contains("--gus-test-age-offer") {
                        access.deferOptionalOffer()
                    }
                    return
                }
            #endif
            await access.prepare(isCurrent: { session.isActive }, requirement: AgeRangeAccess.systemRequirement) {
                try await sharedRange(using: requestAgeRange)
            }
        }
    }

    struct AgeRangeDefaultsButton: View {
        @Environment(SessionStore.self) private var session
        @Environment(\.requestAgeRange) private var requestAgeRange

        var body: some View {
            let access = session.ageRangeAccess
            Button {
                Task { await access.check(isCurrent: { session.isActive }) { try await sharedRange(using: requestAgeRange) } }
            } label: {
                if access.requesting {
                    Label {
                        Text("Checking Age Range…")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Label("Check Age Range", systemImage: "person.badge.shield.checkmark")
                }
            }
            .disabled(access.requesting)
            if let message = access.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
#endif
