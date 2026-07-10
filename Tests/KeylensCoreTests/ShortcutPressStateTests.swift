import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import KeylensCore

@Suite
struct ShortcutPressStateTests {
    @Test
    func altShortcutRequiresPrimaryKeyAndExactModifierMatch() {
        let primaryKey = CGKeyCode(kVK_ANSI_S)
        let shortcut = HotkeyShortcut(
            keyCode: primaryKey,
            modifiers: [.maskAlternate]
        )

        #expect(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option)]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option), CGKeyCode(kVK_Shift)]))
        )
    }

    @Test
    func fnFunctionShortcutRequiresFunctionModifierToRemainHeld() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_F18),
            modifiers: [.maskSecondaryFn]
        )

        #expect(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18), CGKeyCode(kVK_Function)]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18)]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_F18), CGKeyCode(kVK_Function), CGKeyCode(kVK_Shift)]))
        )
    }

    @Test
    func modifierOnlyShortcutStaysPressedOnlyWhileExactModifierStateMatches() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_Option),
            modifiers: [.maskAlternate]
        )

        #expect(
            ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_Option)]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([]))
        )
        #expect(
            !ShortcutPressState.isPressed(shortcut, keyState: keyState([CGKeyCode(kVK_Option), CGKeyCode(kVK_Shift)]))
        )
    }

    private func keyState(_ pressedKeys: Set<CGKeyCode>) -> ShortcutPressState.KeyStateProvider {
        { pressedKeys.contains($0) }
    }
}
