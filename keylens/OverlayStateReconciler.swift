import Foundation

struct OverlayReconciliationState: Equatable {
    var latchedAssetID: String?
    var hasTransientOverlay: Bool
    var transientAssetID: String?
    var tapHoldAssetID: String?
}

enum OverlayReconciliationPresentation: Equatable {
    case hideOverlay
    case presentLatchedOverlay(String)
}

struct OverlayReconciliationResult: Equatable {
    var state: OverlayReconciliationState
    var shouldStopOneShotDismiss: Bool
    var shouldCancelTapHold: Bool
    var presentation: OverlayReconciliationPresentation?
}

enum OverlayStateReconciler {
    static func reconcile(
        state: OverlayReconciliationState,
        validAssetIDs: Set<String>
    ) -> OverlayReconciliationResult {
        var next = state
        var shouldStopOneShotDismiss = false
        var shouldCancelTapHold = false
        var presentation: OverlayReconciliationPresentation?

        if let latchedAssetID = state.latchedAssetID,
           !validAssetIDs.contains(latchedAssetID) {
            next.latchedAssetID = nil
            if !state.hasTransientOverlay {
                presentation = .hideOverlay
            }
        }

        if state.hasTransientOverlay,
           let transientAssetID = state.transientAssetID,
           !validAssetIDs.contains(transientAssetID) {
            next.hasTransientOverlay = false
            next.transientAssetID = nil
            shouldStopOneShotDismiss = true

            if let latchedAssetID = next.latchedAssetID {
                presentation = .presentLatchedOverlay(latchedAssetID)
            } else {
                presentation = .hideOverlay
            }
        }

        if let tapHoldAssetID = state.tapHoldAssetID,
           !validAssetIDs.contains(tapHoldAssetID) {
            next.tapHoldAssetID = nil
            shouldCancelTapHold = true
        }

        return OverlayReconciliationResult(
            state: next,
            shouldStopOneShotDismiss: shouldStopOneShotDismiss,
            shouldCancelTapHold: shouldCancelTapHold,
            presentation: presentation
        )
    }
}
