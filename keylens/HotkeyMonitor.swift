import AppKit
import Carbon.HIToolbox

enum TriggerTarget: Hashable {
    case asset(String)
    case clearHold
}

struct TriggerEvent {
    let target: TriggerTarget
    let phase: TriggerPhase
}

enum TriggerPhase: Equatable {
    case pressed
    case released
}

final class HotkeyTriggerSource {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [HotkeyShortcut: TriggerTarget]
    private var pressedKeyCodes: Set<CGKeyCode> = []
    private var pressedModifierKeyCodes: Set<CGKeyCode> = []
    private var modifierTapCandidates: [CGKeyCode: Set<HotkeyShortcut>] = [:]
    private var currentModifiers: CGEventFlags = []
    private var activeShortcuts: Set<HotkeyShortcut> = []
    private var anyKeyDismiss: (() -> Void)?

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
        let keyUpMask = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mask = keyDownMask | keyUpMask | flagsChangedMask
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
        pressedKeyCodes.removeAll()
        pressedModifierKeyCodes.removeAll()
        modifierTapCandidates.removeAll()
        currentModifiers = []
        activeShortcuts.removeAll()
        anyKeyDismiss = nil
    }

    func armAnyKeyDismiss(_ action: @escaping () -> Void) {
        anyKeyDismiss = action
    }

    func disarmAnyKeyDismiss() {
        anyKeyDismiss = nil
    }

    func update(configuration: AppConfiguration) {
        bindings = Self.bindingsMap(from: configuration)
        activeShortcuts = activeShortcuts.intersection(Set(bindings.keys))
        modifierTapCandidates.removeAll()
    }

    func receive(event: CGEvent, type: CGEventType) {
        if Self.isKeyPress(event: event, type: type), let action = anyKeyDismiss {
            anyKeyDismiss = nil
            action()
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let relevantFlags = event.flags.intersection(KeyboardSemantics.supportedModifierFlags)

        switch type {
        case .keyDown:
            pressedKeyCodes.insert(keyCode)
            modifierTapCandidates.removeAll()
            currentModifiers = relevantFlags
        case .keyUp:
            pressedKeyCodes.remove(keyCode)
            currentModifiers = relevantFlags
        case .flagsChanged:
            if let modifier = KeyboardSemantics.modifierFlag(for: keyCode) {
                if relevantFlags.contains(modifier) {
                    invalidateModifierTapCandidates(except: keyCode)
                    beginModifierTapCandidates(for: keyCode, flags: relevantFlags)
                    pressedModifierKeyCodes.insert(keyCode)
                } else {
                    let tapCandidates = endModifierTapCandidates(for: keyCode)
                    pressedModifierKeyCodes.remove(keyCode)
                    if pressedKeyCodes.isEmpty {
                        emitModifierTaps(tapCandidates)
                    }
                }
            }
            currentModifiers = relevantFlags
        default:
            return
        }

        emitTransitions()
    }

    private func emitTransitions() {
        let nextActiveShortcuts = Set(
            bindings.keys.filter {
                guard !Self.isModifierOnlyShortcut($0) else {
                    return false
                }
                return Self.isShortcutActive(
                    $0,
                    pressedKeyCodes: pressedKeyCodes,
                    pressedModifierKeyCodes: pressedModifierKeyCodes,
                    modifiers: currentModifiers
                )
            }
        )

        let releasedShortcuts = Self.sortedShortcuts(activeShortcuts.subtracting(nextActiveShortcuts))
        let pressedShortcuts = Self.sortedShortcuts(nextActiveShortcuts.subtracting(activeShortcuts))
        activeShortcuts = nextActiveShortcuts

        for shortcut in releasedShortcuts {
            guard let target = bindings[shortcut] else { continue }
            onTrigger?(TriggerEvent(target: target, phase: .released))
        }

        for shortcut in pressedShortcuts {
            guard let target = bindings[shortcut] else { continue }
            onTrigger?(TriggerEvent(target: target, phase: .pressed))
        }
    }

    private static func isShortcutActive(
        _ shortcut: HotkeyShortcut,
        pressedKeyCodes: Set<CGKeyCode>,
        pressedModifierKeyCodes: Set<CGKeyCode>,
        modifiers: CGEventFlags
    ) -> Bool {
        guard modifiers == shortcut.cgModifiers else {
            return false
        }

        if let modifier = KeyboardSemantics.modifierFlag(for: shortcut.cgKeyCode) {
            return shortcut.cgModifiers.contains(modifier) &&
                pressedKeyCodes.isEmpty &&
                pressedModifierKeyCodes.contains(shortcut.cgKeyCode)
        }

        return pressedKeyCodes.contains(shortcut.cgKeyCode)
    }

    private static func isKeyPress(event: CGEvent, type: CGEventType) -> Bool {
        if type == .keyDown {
            return event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        }
        guard type == .flagsChanged else { return false }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if Int(keyCode) == kVK_CapsLock { return true }
        guard let changedModifier = KeyboardSemantics.modifierFlag(for: keyCode) else {
            return true
        }
        let flags = event.flags.intersection(KeyboardSemantics.supportedModifierFlags)
        return flags.contains(changedModifier)
    }

    private func beginModifierTapCandidates(for keyCode: CGKeyCode, flags: CGEventFlags) {
        let candidates = bindings.keys.filter {
            KeyboardSemantics.isModifierOnlyShortcut($0) &&
                $0.cgKeyCode == keyCode &&
                $0.cgModifiers == flags
        }

        guard !candidates.isEmpty, pressedKeyCodes.isEmpty else {
            return
        }

        modifierTapCandidates[keyCode] = Set(candidates)
    }

    private func endModifierTapCandidates(for keyCode: CGKeyCode) -> Set<HotkeyShortcut> {
        modifierTapCandidates.removeValue(forKey: keyCode) ?? []
    }

    private func invalidateModifierTapCandidates(except keyCode: CGKeyCode) {
        modifierTapCandidates = modifierTapCandidates.filter { $0.key == keyCode }
    }

    private func emitModifierTaps(_ shortcuts: Set<HotkeyShortcut>) {
        for shortcut in Self.sortedShortcuts(shortcuts) {
            guard let target = bindings[shortcut] else { continue }
            onTrigger?(TriggerEvent(target: target, phase: .pressed))
            onTrigger?(TriggerEvent(target: target, phase: .released))
        }
    }

    private static func isModifierOnlyShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        KeyboardSemantics.isModifierOnlyShortcut(shortcut)
    }

    private static func sortedShortcuts(_ shortcuts: Set<HotkeyShortcut>) -> [HotkeyShortcut] {
        shortcuts.sorted {
            if $0.keyCode == $1.keyCode {
                return $0.modifiersRawValue < $1.modifiersRawValue
            }
            return $0.keyCode < $1.keyCode
        }
    }

    private static func bindingsMap(from configuration: AppConfiguration) -> [HotkeyShortcut: TriggerTarget] {
        let availableAssetIDs = Set(configuration.svgAssets.map(\.id))

        var map: [HotkeyShortcut: TriggerTarget] = [:]
        for (assetID, shortcut) in configuration.hotkeyAssignments where availableAssetIDs.contains(assetID) {
            map[shortcut] = .asset(assetID)
        }

        if let clearHoldShortcut = configuration.clearHoldShortcut {
            map[clearHoldShortcut] = .clearHold
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

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        source.hasWarnedAboutUserInputDisable = false
        source.receive(event: event, type: type)

        return Unmanaged.passUnretained(event)
    }
}
