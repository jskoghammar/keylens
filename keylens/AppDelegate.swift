import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct LayoutOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum TransientOverlayKind: Equatable {
        case timed
        case oneShot
        case hold
    }

    private struct TransientOverlayState {
        let assetID: String?
        let kind: TransientOverlayKind
    }

    private struct TapHoldInteraction {
        let assetID: String
        let token: UUID
        let shortcut: HotkeyShortcut?
        var didActivateHold = false
        let holdTask: DispatchWorkItem
        var releasePollTimer: Timer?
    }

    private struct PendingClearHoldCandidate {
        let assetID: String
        let previousLatchedOverlayAssetID: String?
    }

    private let settings = AppSettings.shared
    private var overlayController: OverlayWindowController?
    private var triggerController: TriggerController?
    private var statusItem: NSStatusItem?
    private var hotkeyStatusMenuItem: NSMenuItem?
    private lazy var settingsWindowController = SettingsWindowController()
    private let hidKeyboardStateMonitor = HIDKeyboardStateMonitor()
    private let oneShotDismissMonitor = OneShotAnyKeyDismissMonitor()
    private let tapHoldThreshold: TimeInterval = 0.5
    private var latchedOverlayAssetID: String?
    private var transientOverlay: TransientOverlayState?
    private var tapHoldInteraction: TapHoldInteraction?
    private var pendingClearHoldCandidate: PendingClearHoldCandidate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController()
        overlayController?.setImage(defaultOverlayImage())
        overlayController?.onHide = { [weak self] in
            self?.handleOverlayHidden()
        }

        setupStatusMenu()
        setupTriggerController()
        requestInputMonitoringPermissionAndStartHotkey()

        settings.onConfigurationChanged = { [weak self] configuration in
            self?.apply(configuration: configuration)
        }

        apply(configuration: settings.configuration)

        if settings.configuration.svgAssets.isEmpty,
           shouldAutoSync(configuration: settings.configuration) {
            settings.syncSVGRepository()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelTapHoldInteraction()
        oneShotDismissMonitor.stop()
        triggerController?.stop()
    }

    private func apply(configuration: AppConfiguration) {
        triggerController?.update(configuration: configuration)
        overlayController?.updatePlacement(configuration.overlayPlacement)
        reconcileOverlayState(using: configuration)
        setHotkeyActive(InputMonitoringPermission.hasAccess())
    }

    private func defaultOverlayImage() -> NSImage {
        NSImage(named: NSImage.Name("Image")) ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    private func showOverlayForConfiguredDuration() {
        cancelTapHoldInteraction()
        oneShotDismissMonitor.stop()
        pendingClearHoldCandidate = nil
        transientOverlay = TransientOverlayState(
            assetID: settings.configuration.svgAssets.first?.id,
            kind: .timed
        )
        presentOverlay(
            assetID: settings.configuration.svgAssets.first?.id,
            duration: settings.configuration.overlayDuration
        )
    }

    private func presentOverlay(assetID: String?, duration: TimeInterval?) {
        let placement = settings.configuration.overlayPlacement
        guard let assetID else {
            overlayController?.show(placement: placement, duration: duration)
            return
        }

        guard let asset = settings.configuration.svgAssets.first(where: { $0.id == assetID }) else {
            overlayController?.hide()
            return
        }

        overlayController?.showAsset(
            at: asset.localFilePath,
            placement: placement,
            duration: duration
        )
    }

    private func handleHotkeyTrigger(_ event: TriggerEvent) {
        switch event.target {
        case .asset(let assetID):
            if event.phase == .pressed {
                pendingClearHoldCandidate = nil
            }
            handleAssetHotkeyTrigger(assetID: assetID, phase: event.phase)
        case .clearHold:
            guard event.phase == .pressed else { return }
            if endActiveHoldOverlay() {
                return
            }
            revertPendingClearHoldCandidate()
        }
    }

    private func handleAssetHotkeyTrigger(assetID: String, phase: TriggerPhase) {
        let mode = settings.activationMode(for: assetID)

        switch mode {
        case .timed:
            guard phase == .pressed else { return }
            cancelTapHoldInteraction()
            oneShotDismissMonitor.stop()
            transientOverlay = TransientOverlayState(assetID: assetID, kind: .timed)
            presentOverlay(assetID: assetID, duration: settings.configuration.overlayDuration)

        case .toggle:
            guard phase == .pressed else { return }
            toggleLatchedOverlay(for: assetID)

        case .tapHold:
            handleTapHoldTrigger(assetID: assetID, phase: phase)

        case .oneShot:
            guard phase == .pressed else { return }
            cancelTapHoldInteraction()
            transientOverlay = TransientOverlayState(assetID: assetID, kind: .oneShot)
            presentOverlay(assetID: assetID, duration: nil)
            oneShotDismissMonitor.start { [weak self] in
                self?.overlayController?.hide()
            }
        }
    }

    private func handleOverlayHidden() {
        let shouldRestoreLatchedOverlay = transientOverlay != nil && latchedOverlayAssetID != nil
        oneShotDismissMonitor.stop()
        transientOverlay = nil

        if shouldRestoreLatchedOverlay {
            presentOverlay(assetID: latchedOverlayAssetID, duration: nil)
        }
    }

    private func toggleLatchedOverlay(for assetID: String) {
        cancelTapHoldInteraction()
        oneShotDismissMonitor.stop()
        transientOverlay = nil

        if latchedOverlayAssetID == assetID {
            latchedOverlayAssetID = nil
            overlayController?.hide()
            return
        }

        latchedOverlayAssetID = assetID
        presentOverlay(assetID: assetID, duration: nil)
    }

    private func handleTapHoldTrigger(assetID: String, phase: TriggerPhase) {
        switch phase {
        case .pressed:
            beginTapHoldInteraction(for: assetID)
        case .released:
            finishTapHoldInteraction(for: assetID)
        }
    }

    private func beginTapHoldInteraction(for assetID: String) {
        cancelTapHoldInteraction()

        let token = UUID()
        let holdTask = DispatchWorkItem { [weak self] in
            self?.activateTapHoldIfNeeded(assetID: assetID, token: token)
        }

        tapHoldInteraction = TapHoldInteraction(
            assetID: assetID,
            token: token,
            shortcut: settings.shortcut(for: assetID),
            holdTask: holdTask
        )

        DispatchQueue.main.asyncAfter(
            deadline: .now() + tapHoldThreshold,
            execute: holdTask
        )
    }

    private func activateTapHoldIfNeeded(assetID: String, token: UUID) {
        guard var interaction = tapHoldInteraction,
              interaction.assetID == assetID,
              interaction.token == token else {
            return
        }

        interaction.didActivateHold = true
        tapHoldInteraction = interaction

        oneShotDismissMonitor.stop()
        transientOverlay = TransientOverlayState(assetID: assetID, kind: .hold)
        presentOverlay(assetID: assetID, duration: nil)
        startTapHoldReleasePolling(for: assetID, token: token)
    }

    private func finishTapHoldInteraction(for assetID: String) {
        guard let interaction = tapHoldInteraction,
              interaction.assetID == assetID else {
            return
        }

        interaction.holdTask.cancel()
        interaction.releasePollTimer?.invalidate()
        tapHoldInteraction = nil

        if interaction.didActivateHold {
            if latchedOverlayAssetID == assetID {
                latchedOverlayAssetID = nil
            }
            if transientOverlay?.kind == .hold, transientOverlay?.assetID == assetID {
                overlayController?.hide()
            }
            return
        }

        let previousLatchedOverlayAssetID = latchedOverlayAssetID
        toggleLatchedOverlay(for: assetID)

        if settings.clearHoldShortcut() != nil {
            pendingClearHoldCandidate = PendingClearHoldCandidate(
                assetID: assetID,
                previousLatchedOverlayAssetID: previousLatchedOverlayAssetID
            )
        }
    }

    private func cancelTapHoldInteraction() {
        tapHoldInteraction?.holdTask.cancel()
        tapHoldInteraction?.releasePollTimer?.invalidate()
        tapHoldInteraction = nil
    }

    @discardableResult
    private func endActiveHoldOverlay() -> Bool {
        let isHoldingOverlay =
            transientOverlay?.kind == .hold ||
            tapHoldInteraction?.didActivateHold == true

        guard isHoldingOverlay else {
            return false
        }

        cancelTapHoldInteraction()

        if transientOverlay?.kind == .hold {
            overlayController?.hide()
        }

        pendingClearHoldCandidate = nil
        return true
    }

    private func revertPendingClearHoldCandidate() {
        guard let candidate = pendingClearHoldCandidate else {
            return
        }

        pendingClearHoldCandidate = nil
        latchedOverlayAssetID = candidate.previousLatchedOverlayAssetID
        transientOverlay = nil
        oneShotDismissMonitor.stop()

        if let assetID = candidate.previousLatchedOverlayAssetID {
            presentOverlay(assetID: assetID, duration: nil)
        } else {
            overlayController?.hide()
        }
    }

    private func startTapHoldReleasePolling(for assetID: String, token: UUID) {
        guard var interaction = tapHoldInteraction,
              interaction.assetID == assetID,
              interaction.token == token else {
            return
        }

        interaction.releasePollTimer?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                guard let activeInteraction = self.tapHoldInteraction,
                      activeInteraction.assetID == assetID,
                      activeInteraction.token == token,
                      activeInteraction.didActivateHold else {
                    timer.invalidate()
                    return
                }

                guard let shortcut = activeInteraction.shortcut else {
                    timer.invalidate()
                    self.finishTapHoldInteraction(for: assetID)
                    return
                }

                let isPressed =
                    self.hidKeyboardStateMonitor.isPressed(shortcut) ??
                    ShortcutPressState.isPressed(shortcut, keyState: ShortcutPressState.liveKeyState)

                if !isPressed {
                    timer.invalidate()
                    self.finishTapHoldInteraction(for: assetID)
                }
            }
        }

        timer.tolerance = 0.02
        interaction.releasePollTimer = timer
        tapHoldInteraction = interaction
    }

    private func reconcileOverlayState(using configuration: AppConfiguration) {
        let validAssetIDs = Set(configuration.svgAssets.map(\.id))
        let result = OverlayStateReconciler.reconcile(
            state: OverlayReconciliationState(
                latchedAssetID: latchedOverlayAssetID,
                hasTransientOverlay: transientOverlay != nil,
                transientAssetID: transientOverlay?.assetID,
                tapHoldAssetID: tapHoldInteraction?.assetID
            ),
            validAssetIDs: validAssetIDs
        )

        latchedOverlayAssetID = result.state.latchedAssetID

        if result.state.hasTransientOverlay == false {
            transientOverlay = nil
        }

        if result.shouldStopOneShotDismiss {
            oneShotDismissMonitor.stop()
        }

        if result.shouldCancelTapHold {
            cancelTapHoldInteraction()
        }

        switch result.presentation {
        case .hideOverlay:
            overlayController?.hide()
        case .presentLatchedOverlay(let assetID):
            presentOverlay(assetID: assetID, duration: nil)
        case nil:
            break
        }
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keylens")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        let statusLineItem = NSMenuItem(title: "Hotkey: Inactive", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(showOverlayNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Sync SVGs", action: #selector(syncSVGRepository), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Enable Hotkey Permission…", action: #selector(enableHotkeyPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Keylens", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
        hotkeyStatusMenuItem = statusLineItem
    }

    @objc private func showOverlayNow() {
        showOverlayForConfiguredDuration()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func syncSVGRepository() {
        settings.syncSVGRepository()
    }

    @objc private func enableHotkeyPermission() {
        requestInputMonitoringPermissionAndStartHotkey()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupTriggerController() {
        let hotkeySource = HotkeyTriggerSource(configuration: settings.configuration)
        hotkeySource.onStartError = { [weak self] message in
            self?.setHotkeyActive(false)
            self?.showInputMonitoringPermissionAlert(details: message)
        }
        hotkeySource.onRuntimeWarning = { [weak self] message in
            self?.setHotkeyActive(false)
            self?.showRuntimeHotkeyWarning(message)
        }

        let triggerController = TriggerController(source: hotkeySource)
        triggerController.onTrigger = { [weak self] event in
            self?.handleHotkeyTrigger(event)
        }

        self.triggerController = triggerController
    }

    private func requestInputMonitoringPermissionAndStartHotkey() {
        if InputMonitoringPermission.requestAccessIfNeeded() {
            triggerController?.start()
            setHotkeyActive(true)
            return
        }

        setHotkeyActive(false)
        showInputMonitoringPermissionAlert()
    }

    private func showInputMonitoringPermissionAlert(details: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Input Monitoring Required"
        let base = "Keylens needs Input Monitoring to detect global hotkeys. Enable it in Privacy & Security, then use \"Enable Hotkey Permission…\" from the menu."
        if let details, !details.isEmpty {
            alert.informativeText = "\(base)\n\nDetails: \(details)"
        } else {
            alert.informativeText = base
        }
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            InputMonitoringPermission.openSystemSettings()
        }
    }

    private func showRuntimeHotkeyWarning(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Hotkey Monitoring Paused"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setHotkeyActive(_ active: Bool) {
        if active {
            let mappingCount = activeMappingCount()
            hotkeyStatusMenuItem?.title = "Hotkey: Active (\(mappingCount) mapping\(mappingCount == 1 ? "" : "s"))"
        } else {
            hotkeyStatusMenuItem?.title = "Hotkey: Inactive"
        }
    }

    private func activeMappingCount() -> Int {
        let knownAssetIDs = Set(settings.configuration.svgAssets.map(\.id))
        return settings.configuration.hotkeyAssignments.keys.filter { knownAssetIDs.contains($0) }.count
    }

    private func shouldAutoSync(configuration: AppConfiguration) -> Bool {
        switch configuration.svgSourceType {
        case .repository:
            return !configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .localDirectory:
            return !configuration.localDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init() {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 760)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Keylens Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class OneShotAnyKeyDismissMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onDismiss: (() -> Void)?
    private var isArmed = false

    func start(onDismiss: @escaping () -> Void) {
        stop()

        self.onDismiss = onDismiss
        isArmed = false
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
            NSLog("%@", "One-shot dismiss monitor failed to create event tap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source

        // Arm on the next run-loop turn so the triggering hotkey press itself
        // does not immediately dismiss one-shot overlays.
        DispatchQueue.main.async { [weak self] in
            self?.isArmed = true
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        onDismiss = nil
        isArmed = false
    }

    deinit {
        stop()
    }

    private func handle(event: CGEvent, type: CGEventType) {
        guard isArmed else { return }

        if type == .flagsChanged, !Self.isModifierPress(event) {
            return
        }

        guard let onDismiss else { return }
        stop()
        onDismiss()
    }

    private static func isModifierPress(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let changed = KeyboardSemantics.modifierFlag(for: keyCode) else {
            // Treat unknown flagsChanged keys as presses (matches hotkey source behavior).
            return true
        }
        let currentFlags = event.flags.intersection(HotkeyShortcut.supportedModifiers)
        return currentFlags.contains(changed)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<OneShotAnyKeyDismissMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        monitor.handle(event: event, type: type)
        return Unmanaged.passUnretained(event)
    }
}
