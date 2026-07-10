import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import KeylensCore

@Suite
struct HotkeyTriggerSourceTests {
    @Test
    func mappedKeyDownAndUpEmitPressedAndReleased() throws {
        let keyCode = CGKeyCode(1)
        let source = HotkeyTriggerSource(
            configuration: hotkeyConfiguration(shortcut: HotkeyShortcut(keyCode: keyCode))
        )
        var events: [TriggerEvent] = []
        source.onTrigger = { events.append($0) }

        source.receive(event: try keyEvent(keyCode, isDown: true), type: .keyDown)
        source.receive(event: try keyEvent(keyCode, isDown: false), type: .keyUp)

        #expect(events.count == 2)
        #expect(events[0].target == .asset("a"))
        #expect(events[0].phase == .pressed)
        #expect(events[1].target == .asset("a"))
        #expect(events[1].phase == .released)
    }

    @Test
    func dismissArmedByTriggerWaitsForNextKeyPress() throws {
        let keyCode = CGKeyCode(1)
        let source = HotkeyTriggerSource(
            configuration: hotkeyConfiguration(shortcut: HotkeyShortcut(keyCode: keyCode))
        )
        var dismissCount = 0
        source.onTrigger = { event in
            if event.phase == .pressed {
                source.armAnyKeyDismiss { dismissCount += 1 }
            }
        }

        source.receive(event: try keyEvent(keyCode, isDown: true), type: .keyDown)
        #expect(dismissCount == 0)

        let repeatedKeyDown = try keyEvent(keyCode, isDown: true)
        repeatedKeyDown.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        source.receive(event: repeatedKeyDown, type: .keyDown)
        #expect(dismissCount == 0)

        source.receive(event: try keyEvent(keyCode, isDown: false), type: .keyUp)
        #expect(dismissCount == 0)

        source.receive(event: try keyEvent(CGKeyCode(2), isDown: true), type: .keyDown)
        #expect(dismissCount == 1)

        source.receive(event: try keyEvent(CGKeyCode(3), isDown: true), type: .keyDown)
        #expect(dismissCount == 1)
    }

    @Test
    func armedDismissRunsBeforeMappedHotkeyTransition() throws {
        let source = HotkeyTriggerSource(
            configuration: hotkeyConfiguration(assignments: [
                "a": HotkeyShortcut(keyCode: 1),
                "b": HotkeyShortcut(keyCode: 2)
            ])
        )
        var observations: [String] = []
        source.onTrigger = { event in
            guard event.phase == .pressed,
                  case .asset(let assetID) = event.target else { return }
            observations.append("trigger:\(assetID)")
        }
        source.armAnyKeyDismiss { observations.append("dismiss") }

        source.receive(event: try keyEvent(2, isDown: true), type: .keyDown)

        #expect(observations == ["dismiss", "trigger:b"])
    }

    @Test
    func modifierReleaseDoesNotDismissButPressDoes() throws {
        let source = HotkeyTriggerSource(
            configuration: hotkeyConfiguration(shortcut: HotkeyShortcut(keyCode: 1))
        )
        var dismissCount = 0
        source.armAnyKeyDismiss { dismissCount += 1 }

        source.receive(
            event: try keyEvent(CGKeyCode(kVK_Shift), isDown: false, flags: []),
            type: .flagsChanged
        )
        #expect(dismissCount == 0)

        source.receive(
            event: try keyEvent(CGKeyCode(kVK_Shift), isDown: true, flags: .maskShift),
            type: .flagsChanged
        )
        #expect(dismissCount == 1)
    }

    @Test
    func capsLockToggleOffStillCountsAsAKeyPressForDismissal() throws {
        let source = HotkeyTriggerSource(
            configuration: hotkeyConfiguration(shortcut: HotkeyShortcut(keyCode: 1))
        )
        var dismissCount = 0
        source.armAnyKeyDismiss { dismissCount += 1 }

        source.receive(
            event: try keyEvent(CGKeyCode(kVK_CapsLock), isDown: true, flags: []),
            type: .flagsChanged
        )

        #expect(dismissCount == 1)
    }
}

private func hotkeyConfiguration(shortcut: HotkeyShortcut) -> AppConfiguration {
    hotkeyConfiguration(assignments: ["a": shortcut])
}

private func hotkeyConfiguration(assignments: [String: HotkeyShortcut]) -> AppConfiguration {
    AppConfiguration(
        svgSourceType: .localDirectory,
        repositoryURL: "",
        repositoryBranch: nil,
        localDirectoryPath: "/tmp",
        svgAssets: assignments.keys.sorted().map {
            SVGAsset(id: $0, fileName: "\($0).svg", sourceURL: "file:///\($0).svg", localFilePath: "/tmp/\($0).svg")
        },
        hotkeyAssignments: assignments,
        hotkeyModes: assignments.mapValues { _ in .timed },
        clearHoldShortcut: nil,
        overlayDuration: 1.2,
        overlayPlacement: .center
    )
}

private func keyEvent(
    _ keyCode: CGKeyCode,
    isDown: Bool,
    flags: CGEventFlags = []
) throws -> CGEvent {
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown))
    event.flags = flags
    return event
}
