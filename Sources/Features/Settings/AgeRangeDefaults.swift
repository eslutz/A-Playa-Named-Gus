#if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
    import DeclaredAgeRange
    import SwiftUI

    /// Settings action that suggests a content-rating limit from Apple's Declared Age
    /// Range service (OS 26+). Privacy posture per `Documentation/family-safety-brief.md`:
    /// Gus receives only a range (gates 13/16/18), maps it to a tier in memory, persists
    /// only the resulting limit selection, and treats declined sharing as a silent no-op.
    ///
    /// Requires the `com.apple.developer.declared-age-range` entitlement at runtime; the
    /// request fails gracefully (status message, manual picker untouched) until the
    /// entitlement is granted and wired — the same staging used for CarPlay audio.
    @available(iOS 26.0, macOS 26.0, *)
    struct AgeRangeDefaultsButton: View {
        @Environment(\.requestAgeRange) private var requestAgeRange
        @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
        @State private var statusMessage: String?
        @State private var isRequesting = false

        var body: some View {
            Button {
                requestAndApply()
            } label: {
                if isRequesting {
                    Label {
                        Text("Checking Age Range…")
                    } icon: {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Label("Set from Age Range", systemImage: "person.badge.shield.checkmark")
                }
            }
            .disabled(isRequesting)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private func requestAndApply() {
            guard !isRequesting else { return }
            isRequesting = true
            statusMessage = nil
            Task {
                defer { isRequesting = false }
                do {
                    let response = try await requestAgeRange(ageGates: 13, 16, 18)
                    switch response {
                    case let .sharing(range):
                        apply(range)
                    case .declinedSharing:
                        statusMessage = String(
                            localized: "No age range was shared. The limit is unchanged.",
                            comment: "Status after the user declines Declared Age Range sharing"
                        )
                    @unknown default:
                        break
                    }
                } catch {
                    statusMessage = String(
                        localized: "Age range isn't available right now. Choose a limit manually instead.",
                        comment: "Status when the Declared Age Range request fails"
                    )
                }
            }
        }

        /// Maps the declared range onto a suggested limit. Adults (18+) are left
        /// unchanged; the range itself is discarded after this mapping.
        private func apply(_ range: AgeRangeService.AgeRange) {
            let suggested: ContentRatingGate.Limit?
            if let lower = range.lowerBound {
                switch lower {
                case ..<13: suggested = .general
                case 13 ..< 16: suggested = .teen
                case 16 ..< 18: suggested = .mature
                default: suggested = nil
                }
            } else {
                // No lower bound means the declared age is under the lowest gate (13).
                suggested = .general
            }

            guard let suggested else {
                statusMessage = String(
                    localized: "No restriction needed for the shared age range.",
                    comment: "Status when a declared adult age range leaves the limit unchanged"
                )
                return
            }

            contentLimitRawValue = suggested.rawValue
            statusMessage = String(
                localized: "Content limit set to \(suggested.title).",
                comment: "Status after Declared Age Range sets a content limit tier"
            )
        }
    }
#endif
