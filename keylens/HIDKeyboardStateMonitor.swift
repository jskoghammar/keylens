import Foundation
import IOKit.hid

final class HIDKeyboardStateMonitor {
    private var manager: IOHIDManager?
    private var pressedUsages: Set<HIDUsageToken> = []
    private let lock = NSLock()
    private let runLoopMode = CFRunLoopMode.commonModes.rawValue

    private(set) var isAvailable = false

    init() {
        start()
    }

    deinit {
        stop()
    }

    func isPressed(_ shortcut: HotkeyShortcut) -> Bool? {
        guard isAvailable, HIDShortcutPressState.supports(shortcut) else {
            return nil
        }

        lock.lock()
        let snapshot = pressedUsages
        lock.unlock()
        return HIDShortcutPressState.isPressed(shortcut, pressedUsages: snapshot)
    }

    private func start() {
        guard manager == nil else { return }

        let options: IOOptionBits = 0
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)

        // Use all HID services here instead of only keyboard/keypad devices.
        // Apple laptops expose parts of the top-case keyboard stack on vendor
        // usage pages, and restricting enumeration to plain keyboard services
        // can miss Fn state transitions entirely.
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            Self.inputValueCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), runLoopMode)

        let result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
            return
        }

        self.manager = manager
        isAvailable = true
    }

    private func stop() {
        guard let manager else { return }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        IOHIDManagerClose(manager, 0)

        self.manager = nil
        isAvailable = false

        lock.lock()
        pressedUsages.removeAll()
        lock.unlock()
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))

        guard Self.shouldTrack(usagePage: usagePage, usage: usage) else {
            return
        }

        let token = HIDUsageToken(page: usagePage, usage: usage)
        let isPressed = IOHIDValueGetIntegerValue(value) != 0

        lock.lock()
        if isPressed {
            pressedUsages.insert(token)
        } else {
            pressedUsages.remove(token)
        }
        lock.unlock()
    }

    private static func shouldTrack(usagePage: Int, usage: Int) -> Bool {
        if usagePage == Int(kHIDPage_KeyboardOrKeypad) {
            return true
        }

        return usagePage == Int(kHIDPage_GenericDesktop) && usage == Int(kHIDUsage_GD_SFShift)
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let monitor = Unmanaged<HIDKeyboardStateMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleInputValue(value)
    }
}
