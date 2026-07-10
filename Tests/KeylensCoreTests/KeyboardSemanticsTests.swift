import AppKit
import Carbon.HIToolbox
import Testing
@testable import KeylensCore

@Suite
struct KeyboardSemanticsTests {
    @Test
    func defaultAssignmentsAreUniqueAndKeepPreferredOrder() {
        let assignments = KeyboardSemantics.defaultAssignmentOrder

        #expect(assignments.count == 50)
        #expect(Set(assignments).count == assignments.count)
        #expect(assignments.prefix(4).map(\.cgKeyCode) == [
            CGKeyCode(kVK_LeftArrow),
            CGKeyCode(kVK_RightArrow),
            CGKeyCode(kVK_UpArrow),
            CGKeyCode(kVK_DownArrow)
        ])
        #expect(assignments[4].cgKeyCode == CGKeyCode(kVK_F1))
        #expect(assignments[23].cgKeyCode == CGKeyCode(kVK_F20))
        #expect(assignments[24].cgKeyCode == CGKeyCode(kVK_ANSI_A))
        #expect(assignments[49].cgKeyCode == CGKeyCode(kVK_ANSI_Z))
    }

    @Test
    func displayTitlesPreserveCurrentShortcutLabels() {
        let commandOptionS = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_S),
            modifiers: [.maskCommand, .maskAlternate]
        )

        #expect(KeyboardSemantics.displayTitle(for: nil) == "Unassigned")
        #expect(KeyboardSemantics.displayTitle(for: .firmwareReleaseSignal) == "Right Shift")
        #expect(KeyboardSemantics.displayTitle(for: commandOptionS) == "Cmd + Opt + S")
        #expect(
            KeyboardSemantics.displayTitle(for: HotkeyShortcut(keyCode: CGKeyCode(255))) == "KeyCode 255"
        )
    }

    @Test
    func eventFlagsMapToSupportedCGModifiers() {
        let flags: NSEvent.ModifierFlags = [
            .command, .option, .control, .shift, .function, .capsLock, .numericPad
        ]

        #expect(
            KeyboardSemantics.cgEventFlags(from: flags) == [
                .maskCommand,
                .maskAlternate,
                .maskControl,
                .maskShift,
                .maskSecondaryFn,
                .maskAlphaShift
            ]
        )
    }

    @Test
    func everyDefaultAssignmentHasOneTitleAndHIDMeaning() {
        let assignments = KeyboardSemantics.defaultAssignmentOrder
        let titles = assignments.map { KeyboardSemantics.displayTitle(for: $0) }

        #expect(Set(titles).count == assignments.count)
        for assignment in assignments {
            #expect(HIDShortcutPressState.supports(assignment))
        }
        for modifier in KeyboardSemantics.supportedModifiers {
            #expect(!KeyboardSemantics.modifierKeyCodes(for: modifier).isEmpty)
            #expect(!KeyboardSemantics.modifierUsages(for: modifier).isEmpty)
        }
    }
}
