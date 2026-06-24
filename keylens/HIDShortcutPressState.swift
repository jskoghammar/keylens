import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

enum HIDShortcutPressState {
    static func supports(_ shortcut: HotkeyShortcut) -> Bool {
        if KeyboardSemantics.modifierFlag(for: shortcut.cgKeyCode) != nil {
            return true
        }

        return KeyboardSemantics.keyUsages(for: shortcut.cgKeyCode) != nil
    }

    static func isPressed(_ shortcut: HotkeyShortcut, pressedUsages: Set<HIDUsageToken>) -> Bool {
        guard currentModifiers(pressedUsages: pressedUsages) == shortcut.cgModifiers else {
            return false
        }

        if let modifier = KeyboardSemantics.modifierFlag(for: shortcut.cgKeyCode) {
            return KeyboardSemantics.modifierUsages(for: modifier).contains(where: pressedUsages.contains)
        }

        guard let primaryUsages = KeyboardSemantics.keyUsages(for: shortcut.cgKeyCode) else {
            return false
        }

        return primaryUsages.contains(where: pressedUsages.contains)
    }

    private static func currentModifiers(pressedUsages: Set<HIDUsageToken>) -> CGEventFlags {
        var modifiers: CGEventFlags = []

        for modifier in KeyboardSemantics.supportedModifiers
            where KeyboardSemantics.modifierUsages(for: modifier).contains(where: pressedUsages.contains) {
            modifiers.insert(modifier)
        }

        return modifiers
    }
}
