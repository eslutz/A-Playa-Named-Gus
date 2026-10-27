@testable import Gus
import Testing

@Suite("Seerr request history authorization")
struct SeerrRequestHistoryTests {
    @Test("refresh applies new statuses and removes requests omitted by the server")
    func refreshReplacesStaleRequests() {
        let previous = [SeerrRequest(id: 10, status: .pending), SeerrRequest(id: 20, status: .pending)]
        let approved = SeerrRequest(id: 10, status: .approved)
        let refreshed = SeerrRequestPageReconciler.reconcile(current: previous, incoming: [approved], reset: true)
        #expect(refreshed == [approved])
        #expect(SeerrRequestPageReconciler.reconcile(current: refreshed, incoming: [], reset: true).isEmpty)
    }

    @Test("refresh follows server ordering while preserving returned request identities")
    func refreshUsesCurrentServerOrder() {
        let previous = [SeerrRequest(id: 10, status: .pending), SeerrRequest(id: 20, status: .pending)]
        let incoming = [SeerrRequest(id: 20, status: .approved), SeerrRequest(id: 10, status: .declined)]
        #expect(SeerrRequestPageReconciler.reconcile(current: previous, incoming: incoming, reset: true) == incoming)
    }

    @Test("overlapping later pages update existing requests without duplicating or moving their rows")
    func laterPageUpdatesOverlappingRequests() {
        let previous = [SeerrRequest(id: 10, status: .pending), SeerrRequest(id: 20, status: .pending)]
        let approved = SeerrRequest(id: 10, status: .approved)
        let next = SeerrRequest(id: 30, status: .pending)
        let appended = SeerrRequestPageReconciler.reconcile(current: previous, incoming: [approved, next, next], reset: false)
        #expect(appended == [approved, previous[1], next])
    }

    @Test("a missing request cannot confirm a cancellation without an acknowledged DELETE")
    func cancellationReadbackRequiresAcknowledgement() {
        let unknownMissing = SeerrHistoryReadbackPolicy.isSettled(action: .cancel, status: nil, acknowledged: false)
        let acknowledgedMissing = SeerrHistoryReadbackPolicy.isSettled(action: .cancel, status: nil, acknowledged: true)
        let stillPresent = SeerrHistoryReadbackPolicy.isSettled(action: .cancel, status: .pending, acknowledged: true)
        let noPendingAction = SeerrHistoryReadbackPolicy.isSettled(action: nil, status: nil, acknowledged: true)
        #expect(unknownMissing == false)
        #expect(acknowledgedMissing == true)
        #expect(stillPresent == false)
        #expect(noPendingAction == false)
    }

    @Test("unchanged or unknown readback never unlocks an approval decision", arguments: [SeerrHistoryAction.approve, .decline])
    func unresolvedReadbackRemainsLocked(action: SeerrHistoryAction) {
        let stillPending = SeerrHistoryReadbackPolicy.isSettled(action: action, status: .pending, acknowledged: false)
        let unknownState = SeerrHistoryReadbackPolicy.isSettled(action: action, status: .unknown(42), acknowledged: false)
        let missing = SeerrHistoryReadbackPolicy.isSettled(action: action, status: nil, acknowledged: false)
        #expect(stillPending == false)
        #expect(unknownState == false)
        #expect(missing == false)
        for status in [SeerrRequestStatus.approved, .declined, .failed, .completed] {
            let settled = SeerrHistoryReadbackPolicy.isSettled(action: action, status: status, acknowledged: false)
            #expect(settled == true)
        }
    }

    @Test("My Requests stays owned even when the signed-in user is an administrator")
    func ownHistoryDoesNotExpandWithAdministrativePermission() {
        let owner = SeerrUser(id: 3, permissions: .request)
        let administrator = SeerrUser(id: 9, permissions: .admin)
        let request = SeerrRequest(id: 10, status: .pending, requestedBy: owner)
        #expect(SeerrRequestHistoryPolicy.canRead(request, user: owner, managing: false))
        #expect(!SeerrRequestHistoryPolicy.canRead(request, user: administrator, managing: false))
        #expect(SeerrRequestHistoryPolicy.canRead(request, user: administrator, managing: true))
    }

    @Test("permission revocation immediately hides the management queue")
    func revokedManagementAccessFailsClosed() {
        let owner = SeerrUser(id: 3, permissions: .request)
        let manager = SeerrUser(id: 9, permissions: .manageRequests)
        let revoked = SeerrUser(id: 9, permissions: .requestView)
        let request = SeerrRequest(id: 10, status: .pending, requestedBy: owner)
        #expect(SeerrRequestHistoryPolicy.canRead(request, user: manager, managing: true))
        #expect(!SeerrRequestHistoryPolicy.canRead(request, user: revoked, managing: true))
        #expect(!SeerrRequestHistoryPolicy.canRead(request, user: nil, managing: true))
        #expect(!SeerrRequestHistoryPolicy.canModerate(request, user: revoked, managing: true))
    }

    @Test("cancellation never becomes an administrative delete action")
    func onlyPendingOwnedRequestsCanBeCancelled() {
        let owner = SeerrUser(id: 3, permissions: .request)
        let administrator = SeerrUser(id: 9, permissions: .admin)
        let pending = SeerrRequest(id: 10, status: .pending, requestedBy: owner)
        #expect(SeerrRequestHistoryPolicy.canCancel(pending, user: owner))
        #expect(!SeerrRequestHistoryPolicy.canCancel(pending, user: administrator))
        for status: SeerrRequestStatus in [.approved, .declined, .failed, .completed, .unknown(42)] {
            #expect(!SeerrRequestHistoryPolicy.canCancel(SeerrRequest(id: 10, status: status, requestedBy: owner), user: owner))
        }
    }

    @Test("an account switch or missing owner cannot retain cancellation eligibility")
    func changedAccountCannotCancelPreviousAccountsRequest() {
        let original = SeerrUser(id: 3, permissions: .request)
        let replacement = SeerrUser(id: 4, permissions: .request)
        let request = SeerrRequest(id: 10, status: .pending, requestedBy: original)
        #expect(!SeerrRequestHistoryPolicy.canRead(request, user: replacement, managing: false))
        #expect(!SeerrRequestHistoryPolicy.canCancel(request, user: replacement))
        let missingOwner = SeerrRequest(id: 10, status: .pending)
        #expect(!SeerrRequestHistoryPolicy.canRead(missingOwner, user: original, managing: false))
        #expect(!SeerrRequestHistoryPolicy.canCancel(missingOwner, user: original))
    }

    @Test("moderation requires both the manager screen and a fresh pending state")
    func moderationDoesNotSurviveStateChanges() {
        let manager = SeerrUser(id: 9, permissions: .manageRequests)
        let pending = SeerrRequest(id: 10, status: .pending)
        #expect(SeerrRequestHistoryPolicy.canModerate(pending, user: manager, managing: true))
        #expect(!SeerrRequestHistoryPolicy.canModerate(pending, user: manager, managing: false))
        for status: SeerrRequestStatus in [.approved, .declined, .failed, .completed, .unknown(42)] {
            #expect(!SeerrRequestHistoryPolicy.canModerate(SeerrRequest(id: 10, status: status), user: manager, managing: true))
        }
    }
}
