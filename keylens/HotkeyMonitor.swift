import AppKit
import Carbon.HIToolbox

struct TriggerEvent {
    let assetID: String
}

protocol TriggerSource: AnyObject {
    var onTrigger: ((TriggerEvent) -> Void)? { get set }
    func start()
    func stop()
}

protocol ConfigurableTriggerSource: TriggerSource {
    func update(configuration: AppConfiguration)
}

final class TriggerController {
    private var source: TriggerSource

    var onTrigger: ((TriggerEvent) -> Void)? {
        didSet {
            source.onTrigger = onTrigger
        }
    }

    init(source: TriggerSource) {
        self.source = source
    }

    func start() {
        source.onTrigger = onTrigger
        source.start()
    }

    func stop() {
        source.stop()
    }

    // Keeps the trigger implementation swappable for future external triggers (e.g. ZMK events).
    func replaceSource(_ source: TriggerSource) {
        self.source.stop()
        self.source = source
        self.source.onTrigger = onTrigger
        self.source.start()
    }

    func update(configuration: AppConfiguration) {
        (source as? ConfigurableTriggerSource)?.update(configuration: configuration)
    }
}

final class HotkeyTriggerSource: ConfigurableTriggerSource {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [HotkeyShortcut: String]

    var onTrigger: ((TriggerEvent) -> Void)?
    var onStartError: ((String) -> Void)?
    var onRuntimeWarning: ((String) -> Void)?
    private var hasWarnedAboutUserInputDisable = false

    init(configuration: AppConfiguration) {
        bindings = Self.bindingsMap(from: configuration)
    }

    func start() {
        guard eventTap == nil else { return }

        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mask = keyDownMask | flagsChangedMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            let message = "Failed to create keyboard event tap. Verify Input Monitoring is enabled for Keylens and relaunch the app."
            NSLog("%@", message)
            onStartError?(message)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    func update(configuration: AppConfiguration) {
        bindings = Self.bindingsMap(from: configuration)
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if type == .flagsChanged, !Self.isModifierPress(event) {
            return
        }

        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let relevantFlags = event.flags.intersection(HotkeyShortcut.supportedModifiers)
        let shortcut = HotkeyShortcut(keyCode: eventKeyCode, modifiers: relevantFlags)

        guard let assetID = bindings[shortcut] else { return }
        onTrigger?(TriggerEvent(assetID: assetID))
    }

    private static func isModifierPress(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let changedModifier = modifierFlag(for: keyCode) else {
            return true
        }

        let currentFlags = event.flags.intersection(HotkeyShortcut.supportedModifiers)
        return currentFlags.contains(changedModifier)
    }

    private static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
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

    private static func bindingsMap(from configuration: AppConfiguration) -> [HotkeyShortcut: String] {
        let availableAssetIDs = Set(configuration.svgAssets.map(\.id))

        var map: [HotkeyShortcut: String] = [:]
        for (assetID, shortcut) in configuration.hotkeyAssignments where availableAssetIDs.contains(assetID) {
            map[shortcut] = assetID
        }
        return map
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let source = Unmanaged<HotkeyTriggerSource>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByUserInput, !source.hasWarnedAboutUserInputDisable {
                source.hasWarnedAboutUserInputDisable = true
                source.onRuntimeWarning?("Hotkey monitoring was disabled by macOS user input security. If Terminal Secure Keyboard Entry or another secure input mode is active, disable it and retry.")
            }

            if let tap = source.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        source.hasWarnedAboutUserInputDisable = false
        source.handle(event: event, type: type)

        return Unmanaged.passUnretained(event)
    }
}
