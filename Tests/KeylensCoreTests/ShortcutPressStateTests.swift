import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import KeylensCore

final class ShortcutPressStateTests: XCTestCase {
    func testAltShortcutRequiresPrimaryKeyAndExactModifierMatch() {
        let primaryKey = CGKeyCode(kVK_ANSI_S)
        let shortcut = HotkeyShortcut(
            keyCode: primaryKey,
            modifiers: [.maskAlternate]
        )

        XCTAssertTrue(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option)]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option), CGKeyCode(kVK_Shift)]))
        )
    }

    func testFnFunctionShortcutRequiresFunctionModifierToRemainHeld() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_F18),
            modifiers: [.maskSecondaryFn]
        )

        XCTAssertTrue(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18), CGKeyCode(kVK_Function)]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18)]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18), CGKeyCode(kVK_Function), CGKeyCode(kVK_Shift)]))
        )
    }

    func testModifierOnlyShortcutStaysPressedOnlyWhileExactModifierStateMatches() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_Option),
            modifiers: [.maskAlternate]
        )

        XCTAssertTrue(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_Option)]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([]))
        )
        XCTAssertFalse(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_Option), CGKeyCode(kVK_Shift)]))
        )
    }

    private func keyState(_ pressedKeys: Set<CGKeyCode>) -> ShortcutPressState.KeyStateProvider {
        { pressedKeys.contains($0) }
    }
}
