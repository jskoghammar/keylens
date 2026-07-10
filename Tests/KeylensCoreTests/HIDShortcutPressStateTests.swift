import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import KeylensCore

@Suite
struct HIDShortcutPressStateTests {
    @Test
    func altShortcutRequiresPrimaryKeyAndExactModifierMatch() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_S),
            modifiers: [.maskAlternate]
        )

        #expect(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftAlt))
                ]
            )
        )
        #expect(
            !HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS))
                ]
            )
        )
        #expect(
            !HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftAlt)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftShift))
                ]
            )
        )
    }

    @Test
    func fnFunctionShortcutRequiresPrimaryFunctionKeyAndFnUsage() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_F18),
            modifiers: [.maskSecondaryFn]
        )

        #expect(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18)),
                    HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                ]
            )
        )
        #expect(
            !HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18))
                ]
            )
        )
        #expect(
            !HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                ]
            )
        )
    }
}
