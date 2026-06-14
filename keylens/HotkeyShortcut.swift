import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct HotkeyShortcut: Codable, Hashable {
    nonisolated static let navigationLayerSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_RightControl),
        modifiers: [.maskControl]
    )

    nonisolated static let symbolLayerSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_RightCommand),
        modifiers: [.maskCommand]
    )

    nonisolated static let firmwareReleaseSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_RightShift),
        modifiers: [.maskShift]
    )

    nonisolated static let legacyFirmwareReleaseSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_F20),
        modifiers: []
    )

    nonisolated static let legacyNavigationLayerSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_F18),
        modifiers: []
    )

    nonisolated static let legacySymbolLayerSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_F19),
        modifiers: []
    )

    nonisolated static let legacyChordFirmwareReleaseSignal = HotkeyShortcut(
        keyCode: CGKeyCode(kVK_F20),
        modifiers: [.maskControl, .maskAlternate, .maskCommand, .maskShift]
    )

    nonisolated static let supportedModifiers: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
        .maskAlphaShift
    ]

    var keyCode: UInt16
    var modifiersRawValue: UInt64

    nonisolated init(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        self.keyCode = UInt16(keyCode)
        modifiersRawValue = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    nonisolated var cgKeyCode: CGKeyCode {
        CGKeyCode(keyCode)
    }

    nonisolated var cgModifiers: CGEventFlags {
        CGEventFlags(rawValue: modifiersRawValue)
    }

    nonisolated func hasModifier(_ modifier: CGEventFlags) -> Bool {
        cgModifiers.contains(modifier)
    }

    nonisolated func withModifier(_ modifier: CGEventFlags, enabled: Bool) -> HotkeyShortcut {
        var modifiers = cgModifiers
        if enabled {
            modifiers.insert(modifier)
        } else {
            modifiers.remove(modifier)
        }
        return HotkeyShortcut(keyCode: cgKeyCode, modifiers: modifiers)
    }
}
