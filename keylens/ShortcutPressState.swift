import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum ShortcutPressState {
    typealias KeyStateProvider = (CGKeyCode) -> Bool

    nonisolated static func isPressed(_ shortcut: HotkeyShortcut, keyState: KeyStateProvider) -> Bool {
        guard currentModifiers(keyState: keyState) == shortcut.cgModifiers else {
            return false
        }

        if let modifier = KeyboardSemantics.modifierFlag(for: shortcut.cgKeyCode) {
            return shortcut.cgModifiers.contains(modifier) &&
                KeyboardSemantics.modifierKeyCodes(for: modifier).contains(where: keyState)
        }

        return keyState(shortcut.cgKeyCode)
    }

    nonisolated static func liveKeyState(_ keyCode: CGKeyCode) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: keyCode)
    }

    private nonisolated static func currentModifiers(keyState: KeyStateProvider) -> CGEventFlags {
        var modifiers: CGEventFlags = []

        for modifier in KeyboardSemantics.supportedModifiers
            where KeyboardSemantics.modifierKeyCodes(for: modifier).contains(where: keyState) {
            modifiers.insert(modifier)
        }

        return modifiers
    }
}
