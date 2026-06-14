import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum ShortcutPressState {
    typealias KeyStateProvider = (CGKeyCode) -> Bool

    nonisolated static func isPressed(_ shortcut: HotkeyShortcut, keyState: KeyStateProvider) -> Bool {
        guard currentModifiers(keyState: keyState) == shortcut.cgModifiers else {
            return false
        }

        if let modifier = modifierFlag(for: shortcut.cgKeyCode) {
            return shortcut.cgModifiers.contains(modifier) && modifierKeyCodes(for: modifier).contains(where: keyState)
        }

        return keyState(shortcut.cgKeyCode)
    }

    nonisolated static func liveKeyState(_ keyCode: CGKeyCode) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: keyCode)
    }

    private nonisolated static func currentModifiers(keyState: KeyStateProvider) -> CGEventFlags {
        var modifiers: CGEventFlags = []

        for modifier in supportedModifiers where modifierKeyCodes(for: modifier).contains(where: keyState) {
            modifiers.insert(modifier)
        }

        return modifiers
    }

    private nonisolated static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand:
            return .maskCommand
        case kVK_Option, kVK_RightOption:
            return .maskAlternate
        case kVK_Control, kVK_RightControl:
            return .maskControl
        case kVK_Shift, kVK_RightShift:
            return .maskShift
        case kVK_Function:
            return .maskSecondaryFn
        case kVK_CapsLock:
            return .maskAlphaShift
        default:
            return nil
        }
    }

    private nonisolated static func modifierKeyCodes(for flag: CGEventFlags) -> [CGKeyCode] {
        switch flag {
        case .maskCommand:
            return [CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand)]
        case .maskAlternate:
            return [CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)]
        case .maskControl:
            return [CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl)]
        case .maskShift:
            return [CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift)]
        case .maskSecondaryFn:
            return [CGKeyCode(kVK_Function)]
        case .maskAlphaShift:
            return [CGKeyCode(kVK_CapsLock)]
        default:
            return []
        }
    }

    private nonisolated static let supportedModifiers: [CGEventFlags] = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
        .maskAlphaShift
    ]
}
