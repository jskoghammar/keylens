import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import KeylensCore

final class HIDShortcutPressStateTests: XCTestCase {
    func testAltShortcutRequiresPrimaryKeyAndExactModifierMatch() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_S),
            modifiers: [.maskAlternate]
        )

        XCTAssertTrue(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftAlt))
                ]
            )
        )
        XCTAssertFalse(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS))
                ]
            )
        )
        XCTAssertFalse(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardS)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftAlt)),
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardLeftShift))
                ]
            )
        )
    }

    func testFnFunctionShortcutRequiresPrimaryFunctionKeyAndFnUsage() {
        let shortcut = HotkeyShortcut(
            keyCode: CGKeyCode(kVK_F18),
            modifiers: [.maskSecondaryFn]
        )

        XCTAssertTrue(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18)),
                    HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                ]
            )
        )
        XCTAssertFalse(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18))
                ]
            )
        )
        XCTAssertFalse(
            HIDShortcutPressState.isPressed(
                shortcut,
                pressedUsages: [
                    HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                ]
            )
        )
    }
}
