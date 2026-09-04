import AppKit
import Carbon.HIToolbox

enum TriggerAction: Equatable {
    /// A held layer: draw this asset and leave it up until a hide arrives.
    case hold(assetID: String)
    /// A hand-assigned hotkey: nothing will send a hide, so draw it for the
    /// configured duration and let it time out.
    case flash(assetID: String)
    /// The resting layer's signal. Every momentary layer returns to it on release.
    case hide
}

struct TriggerEvent {
    let action: TriggerAction
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

/// Resolved bindings for the event tap. Split out so the lookup can be exercised
/// without synthesizing CGEvents.
struct TriggerBindings: Equatable {
    var byShortcut: [HotkeyShortcut: TriggerAction] = [:]
    /// Matched on key code alone, deliberately. The show bindings want exact modifier
    /// matching -- that is what keeps a bare key from firing in every app. The resting
    /// signal is a different kind of event: it means "dismiss whatever is up", and it
    /// arrives whenever a layer is released, including while Shift or Cmd happens to be
    /// held. Requiring bare modifiers there would let an overlay ride out the backstop
    /// with the whole screen covered.
    var hideKeyCode: UInt16?

    func action(for shortcut: HotkeyShortcut) -> TriggerAction? {
        if let hideKeyCode, shortcut.keyCode == hideKeyCode {
            return .hide
        }

        return byShortcut[shortcut]
    }

    static func make(from configuration: AppConfiguration) -> TriggerBindings {
        let availableAssetIDs = Set(configuration.svgAssets.map(\.id))
        let heldAssetIDs = Set(configuration.layerAssetIDs)

        var byShortcut: [HotkeyShortcut: TriggerAction] = [:]
        for (assetID, shortcut) in configuration.hotkeyAssignments where availableAssetIDs.contains(assetID) {
            byShortcut[shortcut] = heldAssetIDs.contains(assetID) ? .hold(assetID: assetID) : .flash(assetID: assetID)
        }

        return TriggerBindings(byShortcut: byShortcut, hideKeyCode: configuration.hideShortcut?.keyCode)
    }
}

final class HotkeyTriggerSource: ConfigurableTriggerSource {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: TriggerBindings

    var onTrigger: ((TriggerEvent) -> Void)?
    var onStartError: ((String) -> Void)?
    var onRuntimeWarning: ((String) -> Void)?
    private var hasWarnedAboutUserInputDisable = false

    init(configuration: AppConfiguration) {
        bindings = TriggerBindings.make(from: configuration)
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
        bindings = TriggerBindings.make(from: configuration)
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if type == .flagsChanged, !Self.isModifierPress(event) {
            return
        }

        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let relevantFlags = event.flags.intersection(HotkeyShortcut.supportedModifiers)
        let shortcut = HotkeyShortcut(keyCode: eventKeyCode, modifiers: relevantFlags)

        guard let action = bindings.action(for: shortcut) else { return }
        onTrigger?(TriggerEvent(action: action))
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
        default:
            return nil
        }
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
