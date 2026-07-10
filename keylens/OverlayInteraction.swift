import Foundation

struct OverlayInteraction {
    enum Event: Equatable {
        case showConfiguredTimed
        case assetPressed(String)
        case assetReleased(String)
        case timerElapsed(UUID)
        case releaseObserved(UUID)
        case dismissKeyPressed
        case clearHoldPressed
        case configurationChanged(AppConfiguration)
        case presentationFailed(String)
    }

    enum Effect: Equatable {
        case present(String?)
        case schedule(UUID, after: TimeInterval)
        case cancel(UUID)
        case hide
        case armDismiss
        case disarmDismiss
        case startReleasePolling(UUID, HotkeyShortcut)
        case stopReleasePolling(UUID)
    }

    private var configuration: AppConfiguration
    private var timedToken: UUID?
    private var timedAssetID: String?
    private var latchedAssetID: String?
    private var oneShotAssetID: String?
    private var tapHoldInteraction: TapHoldInteraction?
    private var pendingTap: PendingTap?

    private struct TapHoldInteraction {
        let assetID: String
        let token: UUID
        let shortcut: HotkeyShortcut?
        var isHolding = false
    }

    private struct PendingTap {
        let assetID: String
        let shortcut: HotkeyShortcut?
        let previousLatchedAssetID: String?
    }

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .showConfiguredTimed:
            pendingTap = nil
            let interactionCancellation = cancelTapHoldInteraction()
            let transientCancellation = cancelTransient()
            let token = UUID()
            timedToken = token
            timedAssetID = configuration.svgAssets.first?.id
            return interactionCancellation + transientCancellation + [
                .present(timedAssetID),
                .schedule(token, after: configuration.overlayDuration)
            ]
        case .assetPressed(let assetID):
            guard configuration.svgAssets.contains(where: { $0.id == assetID }) else { return [] }
            pendingTap = nil
            let interactionCancellation = cancelTapHoldInteraction()

            switch configuration.hotkeyModes[assetID] ?? .timed {
            case .timed:
                let token = UUID()
                let cancellation = cancelTransient()
                timedToken = token
                timedAssetID = assetID
                return interactionCancellation + cancellation + [
                    .present(assetID),
                    .schedule(token, after: configuration.overlayDuration)
                ]
            case .toggle:
                return interactionCancellation + toggle(assetID)
            case .oneShot:
                let cancellation = cancelTransient()
                oneShotAssetID = assetID
                return interactionCancellation + cancellation + [.present(assetID), .armDismiss]
            case .tapHold:
                let token = UUID()
                tapHoldInteraction = TapHoldInteraction(
                    assetID: assetID,
                    token: token,
                    shortcut: configuration.hotkeyAssignments[assetID]
                )
                return interactionCancellation + [.schedule(token, after: 0.5)]
            }
        case .assetReleased(let assetID):
            guard let interaction = tapHoldInteraction,
                  interaction.assetID == assetID else { return [] }
            tapHoldInteraction = nil
            if interaction.isHolding {
                return finishHold(interaction)
            }
            let previousLatchedAssetID = latchedAssetID
            let effects = [.cancel(interaction.token)] + toggle(assetID)
            if configuration.clearHoldShortcut != nil {
                pendingTap = PendingTap(
                    assetID: interaction.assetID,
                    shortcut: interaction.shortcut,
                    previousLatchedAssetID: previousLatchedAssetID
                )
            }
            return effects
        case .timerElapsed(let token):
            if var interaction = tapHoldInteraction,
               interaction.token == token,
               let shortcut = interaction.shortcut {
                interaction.isHolding = true
                tapHoldInteraction = interaction
                return cancelTransient() + [
                    .present(interaction.assetID),
                    .startReleasePolling(token, shortcut)
                ]
            }
            guard timedToken == token else { return [] }
            timedToken = nil
            timedAssetID = nil
            return [.hide] + (latchedAssetID.map { [.present($0)] } ?? [])
        case .dismissKeyPressed:
            guard oneShotAssetID != nil else { return [] }
            oneShotAssetID = nil
            return [.disarmDismiss, .hide] + (latchedAssetID.map { [.present($0)] } ?? [])
        case .releaseObserved(let token):
            guard let interaction = tapHoldInteraction,
                  interaction.token == token,
                  interaction.isHolding else { return [] }
            tapHoldInteraction = nil
            return finishHold(interaction)
        case .clearHoldPressed:
            if let interaction = tapHoldInteraction, interaction.isHolding {
                tapHoldInteraction = nil
                return [.stopReleasePolling(interaction.token), .hide] +
                    (latchedAssetID.map { [.present($0)] } ?? [])
            }
            guard let pendingTap else { return [] }
            self.pendingTap = nil
            latchedAssetID = pendingTap.previousLatchedAssetID
            return latchedAssetID.map { [.present($0)] } ?? [.hide]
        case .configurationChanged(let configuration):
            self.configuration = configuration
            let validAssetIDs = Set(configuration.svgAssets.map(\.id))
            let removedLatch = latchedAssetID.map { !validAssetIDs.contains($0) } ?? false
            if removedLatch { latchedAssetID = nil }

            if let pendingTap {
                let remainsValid = configuration.clearHoldShortcut != nil &&
                    validAssetIDs.contains(pendingTap.assetID) &&
                    (configuration.hotkeyModes[pendingTap.assetID] ?? .timed) == .tapHold &&
                    configuration.hotkeyAssignments[pendingTap.assetID] == pendingTap.shortcut &&
                    (pendingTap.previousLatchedAssetID.map(validAssetIDs.contains) ?? true)
                if !remainsValid { self.pendingTap = nil }
            }

            var effects: [Effect] = []
            var displayedAssetWasRemoved = false
            if let timedAssetID, !validAssetIDs.contains(timedAssetID) {
                effects += cancelTimedExpiry()
                displayedAssetWasRemoved = true
            }

            if let oneShotAssetID, !validAssetIDs.contains(oneShotAssetID) {
                self.oneShotAssetID = nil
                effects.append(.disarmDismiss)
                displayedAssetWasRemoved = true
            }

            if let interaction = tapHoldInteraction {
                let remainsTapHold = validAssetIDs.contains(interaction.assetID) &&
                    (configuration.hotkeyModes[interaction.assetID] ?? .timed) == .tapHold &&
                    configuration.hotkeyAssignments[interaction.assetID] == interaction.shortcut
                if !remainsTapHold {
                    tapHoldInteraction = nil
                    pendingTap = nil
                    if interaction.isHolding {
                        effects.append(.stopReleasePolling(interaction.token))
                        displayedAssetWasRemoved = true
                    } else {
                        effects.append(.cancel(interaction.token))
                    }
                }
            }

            let hasVisibleTransient = timedToken != nil || oneShotAssetID != nil ||
                tapHoldInteraction?.isHolding == true
            if displayedAssetWasRemoved || (removedLatch && !hasVisibleTransient) {
                effects.append(.hide)
                if let latchedAssetID { effects.append(.present(latchedAssetID)) }
            }
            return effects
        case .presentationFailed(let assetID):
            if timedAssetID == assetID {
                return cancelTimedExpiry() + [.hide] +
                    (latchedAssetID.map { [.present($0)] } ?? [])
            }
            if oneShotAssetID == assetID {
                oneShotAssetID = nil
                return [.disarmDismiss, .hide] +
                    (latchedAssetID.map { [.present($0)] } ?? [])
            }
            if tapHoldInteraction?.assetID == assetID,
               tapHoldInteraction?.isHolding == true {
                return cancelTapHoldInteraction()
            }
            if latchedAssetID == assetID {
                latchedAssetID = nil
                return [.hide]
            }
            return []
        }
    }

    private mutating func finishHold(_ interaction: TapHoldInteraction) -> [Effect] {
        if latchedAssetID == interaction.assetID {
            latchedAssetID = nil
        }
        return [.stopReleasePolling(interaction.token), .hide] +
            (latchedAssetID.map { [.present($0)] } ?? [])
    }

    private mutating func cancelTapHoldInteraction() -> [Effect] {
        guard let interaction = tapHoldInteraction else { return [] }
        tapHoldInteraction = nil
        if interaction.isHolding {
            return [.stopReleasePolling(interaction.token), .hide] +
                (latchedAssetID.map { [.present($0)] } ?? [])
        }
        return [.cancel(interaction.token)]
    }

    private mutating func toggle(_ assetID: String) -> [Effect] {
        let cancellation = cancelTransient()
        if latchedAssetID == assetID {
            latchedAssetID = nil
            return cancellation + [.hide]
        }
        latchedAssetID = assetID
        return cancellation + [.present(assetID)]
    }

    private mutating func cancelTransient() -> [Effect] {
        let timedEffects = cancelTimedExpiry()
        guard oneShotAssetID != nil else { return timedEffects }
        oneShotAssetID = nil
        return timedEffects + [.disarmDismiss]
    }

    private mutating func cancelTimedExpiry() -> [Effect] {
        guard let timedToken else { return [] }
        self.timedToken = nil
        timedAssetID = nil
        return [.cancel(timedToken)]
    }
}
