import Foundation
import Testing
@testable import KeylensCore

@Suite
struct OverlayInteractionTests {
    @Test
    func timedPressPresentsAndSchedulesConfiguredExpiry() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed], duration: 2.5)
        )

        let effects = interaction.handle(.assetPressed("a"))

        #expect(effects.first == .present("a"))
        guard case .schedule(_, let delay) = try #require(effects.last) else {
            Issue.record("Timed press should schedule expiry")
            return
        }
        #expect(delay == 2.5)
    }

    @Test
    func currentTimedExpiryHidesOverlay() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed])
        )
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(interaction.handle(.timerElapsed(token)) == [.hide])
    }

    @Test
    func newerTimedPressCancelsOldExpiryAndMakesItStale() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed, "b": .timed])
        )
        let oldToken = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        let replacementEffects = interaction.handle(.assetPressed("b"))

        #expect(replacementEffects.first == .cancel(oldToken))
        #expect(replacementEffects.contains(.present("b")))
        #expect(interaction.handle(.timerElapsed(oldToken)).isEmpty)
    }

    @Test
    func togglePressLatchesThenSecondPressHides() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .toggle])
        )

        #expect(interaction.handle(.assetPressed("a")) == [.present("a")])
        #expect(interaction.handle(.assetPressed("a")) == [.hide])
    }

    @Test
    func timedExpiryRestoresLatchedOverlay() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(interaction.handle(.timerElapsed(token)) == [.hide, .present("b")])
    }

    @Test
    func oneShotDismissDisarmsAndRestoresLatch() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .oneShot, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))

        #expect(interaction.handle(.assetPressed("a")) == [.present("a"), .armDismiss])
        #expect(
            interaction.handle(.dismissKeyPressed) == [.disarmDismiss, .hide, .present("b")]
        )
        #expect(interaction.handle(.dismissKeyPressed).isEmpty)
    }

    @Test
    func tapReleaseBeforeThresholdCancelsDelayAndToggles() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold],
                shortcuts: ["a": shortcut]
            )
        )
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(interaction.handle(.assetReleased("a")) == [.cancel(token), .present("a")])
    }

    @Test
    func holdThresholdPresentsAndStartsReleasePolling() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold],
                shortcuts: ["a": shortcut]
            )
        )
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(
            interaction.handle(.timerElapsed(token)) == [
                .present("a"),
                .startReleasePolling(token, shortcut)
            ]
        )
    }

    @Test
    func heldReleaseStopsPollingHidesAndRestoresDifferentLatch() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(token))

        #expect(
            interaction.handle(.releaseObserved(token)) == [
                .stopReleasePolling(token),
                .hide,
                .present("b")
            ]
        )
        #expect(interaction.handle(.releaseObserved(token)).isEmpty)
    }

    @Test
    func clearHoldEndsHoldWithoutClearingSameAssetLatch() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold],
                shortcuts: ["a": shortcut]
            )
        )
        let tapToken = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.assetReleased("a"))
        #expect(interaction.handle(.timerElapsed(tapToken)).isEmpty)

        let holdToken = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(holdToken))

        #expect(
            interaction.handle(.clearHoldPressed) == [
                .stopReleasePolling(holdToken),
                .hide,
                .present("a")
            ]
        )
    }

    @Test
    func clearHoldRevertsMostRecentTap() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))

        #expect(interaction.handle(.clearHoldPressed) == [.present("b")])
        #expect(interaction.handle(.clearHoldPressed).isEmpty)
    }

    @Test
    func removingLatchedAssetHidesOverlay() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .toggle])
        )
        _ = interaction.handle(.assetPressed("a"))

        #expect(
            interaction.handle(
                .configurationChanged(configuration(assetIDs: ["b"], modes: ["b": .toggle]))
            ) == [.hide]
        )
    }

    @Test
    func removingTimedAssetCancelsExpiryAndRestoresLatch() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(
            interaction.handle(
                .configurationChanged(configuration(assetIDs: ["b"], modes: ["b": .toggle]))
            ) == [.cancel(token), .hide, .present("b")]
        )
        #expect(interaction.handle(.timerElapsed(token)).isEmpty)
    }

    @Test
    func removingUnderlyingLatchKeepsValidTimedOverlayVisible() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(
            interaction.handle(
                .configurationChanged(configuration(assetIDs: ["a"], modes: ["a": .timed]))
            ).isEmpty
        )
        #expect(interaction.handle(.timerElapsed(token)) == [.hide])
    }

    @Test
    func removingOneShotAssetDisarmsAndRestoresLatch() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .oneShot, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))

        #expect(
            interaction.handle(
                .configurationChanged(configuration(assetIDs: ["b"], modes: ["b": .toggle]))
            ) == [.disarmDismiss, .hide, .present("b")]
        )
    }

    @Test
    func reconfiguringPendingTapHoldCancelsItsThreshold() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold],
                shortcuts: ["a": shortcut]
            )
        )
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(
            interaction.handle(
                .configurationChanged(
                    configuration(modes: ["a": .timed], shortcuts: ["a": shortcut])
                )
            ) == [.cancel(token)]
        )
        #expect(interaction.handle(.timerElapsed(token)).isEmpty)
    }

    @Test
    func configurationChangeCancelsEveryInvalidAdapterBeforeHiding() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .timed, "b": .tapHold],
                shortcuts: ["b": shortcut]
            )
        )
        let timedToken = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        let holdToken = try scheduledToken(from: interaction.handle(.assetPressed("b")))

        #expect(
            interaction.handle(.configurationChanged(configuration(assetIDs: []))) == [
                .cancel(timedToken),
                .cancel(holdToken),
                .hide
            ]
        )
        #expect(interaction.handle(.timerElapsed(timedToken)).isEmpty)
        #expect(interaction.handle(.timerElapsed(holdToken)).isEmpty)
    }

    @Test
    func overlappingTapHoldDismissesOldHoldBeforeSchedulingNewOne() throws {
        let firstShortcut = HotkeyShortcut(keyCode: 1)
        let secondShortcut = HotkeyShortcut(keyCode: 2)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .tapHold],
                shortcuts: ["a": firstShortcut, "b": secondShortcut]
            )
        )
        let firstToken = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(firstToken))

        let effects = interaction.handle(.assetPressed("b"))

        #expect(effects.prefix(2) == [.stopReleasePolling(firstToken), .hide])
        #expect(try scheduledToken(from: effects) != firstToken)
        #expect(interaction.handle(.releaseObserved(firstToken)).isEmpty)
    }

    @Test
    func menuShowUsesFallbackWhenNoAssetsExist() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(assetIDs: [], duration: 3)
        )

        let effects = interaction.handle(.showConfiguredTimed)

        #expect(effects.first == .present(nil))
        guard case .schedule(_, let delay) = try #require(effects.last) else {
            Issue.record("Menu show should schedule expiry")
            return
        }
        #expect(delay == 3)
    }

    @Test
    func menuShowDiscardsPendingClearHoldRollback() {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))

        _ = interaction.handle(.showConfiguredTimed)

        #expect(interaction.handle(.clearHoldPressed).isEmpty)
    }

    @Test
    func failedTransientPresentationCancelsItAndRestoresLatch() throws {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .timed, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))

        #expect(
            interaction.handle(.presentationFailed("a")) == [
                .cancel(token),
                .hide,
                .present("b")
            ]
        )
    }

    @Test
    func failedOneShotPresentationDisarmsDismissAndRestoresLatch() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .oneShot, "b": .toggle])
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))

        #expect(
            interaction.handle(.presentationFailed("a")) == [
                .disarmDismiss,
                .hide,
                .present("b")
            ]
        )
    }

    @Test
    func failedHoldPresentationStopsPollingAndRestoresLatch() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(token))

        #expect(
            interaction.handle(.presentationFailed("a")) == [
                .stopReleasePolling(token),
                .hide,
                .present("b")
            ]
        )
    }

    @Test
    func failedLatchedPresentationClearsTheLatch() {
        var interaction = OverlayInteraction(
            configuration: configuration(modes: ["a": .toggle])
        )
        _ = interaction.handle(.assetPressed("a"))

        #expect(interaction.handle(.presentationFailed("a")) == [.hide])
        #expect(interaction.handle(.presentationFailed("a")).isEmpty)
    }

    @Test
    func heldReleaseClearsSameAssetLatch() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(token))

        #expect(
            interaction.handle(.assetReleased("a")) == [.stopReleasePolling(token), .hide]
        )
    }

    @Test
    func reconfiguringActiveHoldStopsPollingAndRestoresLatch() throws {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        let token = try scheduledToken(from: interaction.handle(.assetPressed("a")))
        _ = interaction.handle(.timerElapsed(token))

        #expect(
            interaction.handle(
                .configurationChanged(
                    configuration(modes: ["a": .timed, "b": .toggle], shortcuts: ["a": shortcut])
                )
            ) == [.stopReleasePolling(token), .hide, .present("b")]
        )
    }

    @Test
    func unknownAssetEventsDoNothing() {
        var interaction = OverlayInteraction(configuration: configuration())

        #expect(interaction.handle(.assetPressed("missing")).isEmpty)
        #expect(interaction.handle(.assetReleased("missing")).isEmpty)
    }

    @Test
    func unknownAssetPressPreservesPendingClearHoldRollback() {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))

        #expect(interaction.handle(.assetPressed("missing")).isEmpty)
        #expect(interaction.handle(.clearHoldPressed) == [.present("b")])
    }

    @Test
    func removingPendingRollbackTargetPreventsItFromBeingRestored() {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))

        #expect(
            interaction.handle(
                .configurationChanged(
                    configuration(
                        assetIDs: ["a"],
                        modes: ["a": .tapHold],
                        shortcuts: ["a": shortcut]
                    )
                )
            ).isEmpty
        )
        #expect(interaction.handle(.clearHoldPressed).isEmpty)
    }

    @Test
    func removingTappedAssetDiscardsItsPendingRollback() {
        let shortcut = HotkeyShortcut(keyCode: 1)
        var interaction = OverlayInteraction(
            configuration: configuration(
                modes: ["a": .tapHold, "b": .toggle],
                shortcuts: ["a": shortcut]
            )
        )
        _ = interaction.handle(.assetPressed("b"))
        _ = interaction.handle(.assetPressed("a"))
        _ = interaction.handle(.assetReleased("a"))

        #expect(
            interaction.handle(
                .configurationChanged(configuration(assetIDs: ["b"], modes: ["b": .toggle]))
            ) == [.hide]
        )
        #expect(interaction.handle(.clearHoldPressed).isEmpty)
    }
}

private func scheduledToken(from effects: [OverlayInteraction.Effect]) throws -> UUID {
    for effect in effects {
        if case .schedule(let token, _) = effect { return token }
    }
    Issue.record("Expected a scheduled effect")
    throw MissingEffect()
}

private struct MissingEffect: Error {}

private func configuration(
    assetIDs: [String] = ["a", "b"],
    modes: [String: HotkeyActivationMode] = [:],
    shortcuts: [String: HotkeyShortcut] = [:],
    clearHoldShortcut: HotkeyShortcut? = .firmwareReleaseSignal,
    duration: TimeInterval = 1.2
) -> AppConfiguration {
    AppConfiguration(
        svgSourceType: .localDirectory,
        repositoryURL: "",
        repositoryBranch: nil,
        localDirectoryPath: "/tmp",
        svgAssets: assetIDs.map {
            SVGAsset(id: $0, fileName: "\($0).svg", sourceURL: "file:///\($0).svg", localFilePath: "/tmp/\($0).svg")
        },
        hotkeyAssignments: shortcuts,
        hotkeyModes: modes,
        clearHoldShortcut: clearHoldShortcut,
        overlayDuration: duration,
        overlayPlacement: .center
    )
}
