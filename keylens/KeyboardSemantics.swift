import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

struct HIDUsageToken: Hashable {
    let page: Int
    let usage: Int
}

enum KeyboardSemantics {
    static var defaultAssignmentOrder: [HotkeyShortcut] {
        KeyChoice.defaultAssignmentOrder
    }

    static func displayTitle(for shortcut: HotkeyShortcut?) -> String {
        guard let shortcut else { return "Unassigned" }

        if isSingleModifierShortcut(shortcut) {
            return keyTitle(for: shortcut)
        }

        var parts: [String] = []
        if shortcut.hasModifier(.maskCommand) { parts.append("Cmd") }
        if shortcut.hasModifier(.maskAlternate) { parts.append("Opt") }
        if shortcut.hasModifier(.maskControl) { parts.append("Ctrl") }
        if shortcut.hasModifier(.maskShift) { parts.append("Shift") }
        if shortcut.hasModifier(.maskSecondaryFn) { parts.append("Fn") }
        if shortcut.hasModifier(.maskAlphaShift) { parts.append("Caps") }
        parts.append(keyTitle(for: shortcut))
        return parts.joined(separator: " + ")
    }

    static func cgEventFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        let relevant = flags.intersection([.command, .option, .control, .shift, .function, .capsLock])
        var result: CGEventFlags = []
        if relevant.contains(.command) { result.insert(.maskCommand) }
        if relevant.contains(.option) { result.insert(.maskAlternate) }
        if relevant.contains(.control) { result.insert(.maskControl) }
        if relevant.contains(.shift) { result.insert(.maskShift) }
        if relevant.contains(.function) { result.insert(.maskSecondaryFn) }
        if relevant.contains(.capsLock) { result.insert(.maskAlphaShift) }
        return result
    }

    private static func keyTitle(for shortcut: HotkeyShortcut) -> String {
        modifierKeyTitle(for: shortcut.cgKeyCode) ??
            KeyChoice.all.first { $0.keyCode == shortcut.cgKeyCode }?.title ??
            "KeyCode \(shortcut.keyCode)"
    }

    static let supportedModifiers: [CGEventFlags] = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
        .maskAlphaShift
    ]

    static let supportedModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
        .maskAlphaShift
    ]

    static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
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

    static func modifierKeyCodes(for flag: CGEventFlags) -> [CGKeyCode] {
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

    static func modifierUsages(for flag: CGEventFlags) -> [HIDUsageToken] {
        switch flag {
        case .maskCommand:
            return [
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftGUI)),
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardRightGUI))
            ]
        case .maskAlternate:
            return [
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftAlt)),
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardRightAlt))
            ]
        case .maskControl:
            return [
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftControl)),
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardRightControl))
            ]
        case .maskShift:
            return [
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftShift)),
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardRightShift))
            ]
        case .maskSecondaryFn:
            return [
                HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
            ]
        case .maskAlphaShift:
            return [
                HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardCapsLock))
            ]
        default:
            return []
        }
    }

    static func keyUsages(for keyCode: CGKeyCode) -> [HIDUsageToken]? {
        let keyboardPage = Int(kHIDPage_KeyboardOrKeypad)

        switch Int(keyCode) {
        case kVK_ANSI_A: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardA))]
        case kVK_ANSI_B: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardB))]
        case kVK_ANSI_C: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardC))]
        case kVK_ANSI_D: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardD))]
        case kVK_ANSI_E: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardE))]
        case kVK_ANSI_F: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF))]
        case kVK_ANSI_G: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardG))]
        case kVK_ANSI_H: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardH))]
        case kVK_ANSI_I: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardI))]
        case kVK_ANSI_J: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardJ))]
        case kVK_ANSI_K: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardK))]
        case kVK_ANSI_L: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardL))]
        case kVK_ANSI_M: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardM))]
        case kVK_ANSI_N: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardN))]
        case kVK_ANSI_O: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardO))]
        case kVK_ANSI_P: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardP))]
        case kVK_ANSI_Q: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardQ))]
        case kVK_ANSI_R: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardR))]
        case kVK_ANSI_S: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardS))]
        case kVK_ANSI_T: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardT))]
        case kVK_ANSI_U: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardU))]
        case kVK_ANSI_V: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardV))]
        case kVK_ANSI_W: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardW))]
        case kVK_ANSI_X: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardX))]
        case kVK_ANSI_Y: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardY))]
        case kVK_ANSI_Z: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardZ))]
        case kVK_LeftArrow: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardLeftArrow))]
        case kVK_RightArrow: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardRightArrow))]
        case kVK_UpArrow: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardUpArrow))]
        case kVK_DownArrow: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardDownArrow))]
        case kVK_F1: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF1))]
        case kVK_F2: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF2))]
        case kVK_F3: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF3))]
        case kVK_F4: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF4))]
        case kVK_F5: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF5))]
        case kVK_F6: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF6))]
        case kVK_F7: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF7))]
        case kVK_F8: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF8))]
        case kVK_F9: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF9))]
        case kVK_F10: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF10))]
        case kVK_F11: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF11))]
        case kVK_F12: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF12))]
        case kVK_F13: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF13))]
        case kVK_F14: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF14))]
        case kVK_F15: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF15))]
        case kVK_F16: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF16))]
        case kVK_F17: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF17))]
        case kVK_F18: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF18))]
        case kVK_F19: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF19))]
        case kVK_F20: return [HIDUsageToken(page: keyboardPage, usage: Int(kHIDUsage_KeyboardF20))]
        default:
            return nil
        }
    }

    static func isModifierOnlyShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        guard let modifier = modifierFlag(for: shortcut.cgKeyCode) else {
            return false
        }

        return shortcut.cgModifiers.contains(modifier)
    }

    static func isSingleModifierShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        guard let modifier = modifierFlag(for: shortcut.cgKeyCode) else {
            return false
        }

        return shortcut.cgModifiers == modifier
    }

    static func modifierKeyTitle(for keyCode: CGKeyCode) -> String? {
        switch Int(keyCode) {
        case kVK_Shift:
            return "Left Shift"
        case kVK_RightShift:
            return "Right Shift"
        case kVK_Control:
            return "Left Ctrl"
        case kVK_RightControl:
            return "Right Ctrl"
        case kVK_Option:
            return "Left Opt"
        case kVK_RightOption:
            return "Right Opt"
        case kVK_Command:
            return "Left Cmd"
        case kVK_RightCommand:
            return "Right Cmd"
        default:
            return nil
        }
    }

    private struct KeyChoice {
        let keyCode: CGKeyCode
        let title: String

        static let arrowKeys = [
            KeyChoice(keyCode: CGKeyCode(kVK_LeftArrow), title: "Left Arrow"),
            KeyChoice(keyCode: CGKeyCode(kVK_RightArrow), title: "Right Arrow"),
            KeyChoice(keyCode: CGKeyCode(kVK_UpArrow), title: "Up Arrow"),
            KeyChoice(keyCode: CGKeyCode(kVK_DownArrow), title: "Down Arrow")
        ]

        static let letterKeys = zip(
            [
                kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
                kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
                kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
                kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                kVK_ANSI_Y, kVK_ANSI_Z
            ],
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        ).map { KeyChoice(keyCode: CGKeyCode($0), title: String($1)) }

        static let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ].enumerated().map { KeyChoice(keyCode: CGKeyCode($1), title: "F\($0 + 1)") }

        static let all = arrowKeys + letterKeys + functionKeys
        static let defaultAssignmentOrder = (arrowKeys + functionKeys + letterKeys).map {
            HotkeyShortcut(keyCode: $0.keyCode)
        }
    }
}
