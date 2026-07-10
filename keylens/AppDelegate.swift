import AppKit
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
    private let settings = AppSettings.shared
    private var overlayController: OverlayWindowController?
    private var hotkeySource: HotkeyTriggerSource?
    private var statusItem: NSStatusItem?
    private var hotkeyStatusMenuItem: NSMenuItem?
    private lazy var settingsWindowController = SettingsWindowController()
    private let hidKeyboardStateMonitor = HIDKeyboardStateMonitor()
    private lazy var overlayInteraction = OverlayInteraction(configuration: settings.configuration)
    private var overlayTasks: [UUID: DispatchWorkItem] = [:]
    private var releasePollTimers: [UUID: Timer] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController()
        overlayController?.setImage(defaultOverlayImage())

        setupStatusMenu()
        setupHotkeySource()
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
        cancelOverlayAdapters()
        hotkeySource?.stop()
    }

    private func apply(configuration: AppConfiguration) {
        hotkeySource?.update(configuration: configuration)
        overlayController?.updatePlacement(configuration.overlayPlacement)
        send(.configurationChanged(configuration))
        setHotkeyActive(InputMonitoringPermission.hasAccess())
    }

    private func defaultOverlayImage() -> NSImage {
        NSImage(named: NSImage.Name("Image")) ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    private func showOverlayForConfiguredDuration() {
        send(.showConfiguredTimed)
    }

    private func handleHotkeyTrigger(_ event: TriggerEvent) {
        switch event.target {
        case .asset(let assetID):
            send(event.phase == .pressed ? .assetPressed(assetID) : .assetReleased(assetID))
        case .clearHold:
            if event.phase == .pressed { send(.clearHoldPressed) }
        }
    }

    private func send(_ event: OverlayInteraction.Event) {
        execute(overlayInteraction.handle(event))
    }

    private func execute(_ effects: [OverlayInteraction.Effect]) {
        var failedAssetIDs: [String] = []

        for effect in effects {
            switch effect {
            case .present(let assetID):
                if !presentOverlayAsset(assetID), let assetID {
                    failedAssetIDs.append(assetID)
                }
            case .hide:
                overlayController?.hide()
            case .schedule(let token, let delay):
                scheduleOverlayEvent(token: token, delay: delay)
            case .cancel(let token):
                overlayTasks.removeValue(forKey: token)?.cancel()
            case .startReleasePolling(let token, let shortcut):
                startReleasePolling(token: token, shortcut: shortcut)
            case .stopReleasePolling(let token):
                stopReleasePolling(token: token)
            case .armDismiss:
                hotkeySource?.armAnyKeyDismiss { [weak self] in
                    self?.send(.dismissKeyPressed)
                }
            case .disarmDismiss:
                hotkeySource?.disarmAnyKeyDismiss()
            }
        }

        for assetID in failedAssetIDs {
            send(.presentationFailed(assetID))
        }
    }

    private func presentOverlayAsset(_ assetID: String?) -> Bool {
        let placement = settings.configuration.overlayPlacement
        guard let assetID else {
            overlayController?.show(placement: placement)
            return true
        }
        guard let asset = settings.configuration.svgAssets.first(where: { $0.id == assetID }) else {
            return false
        }
        return overlayController?.showAsset(
            at: asset.localFilePath,
            placement: placement
        ) ?? false
    }

    private func scheduleOverlayEvent(token: UUID, delay: TimeInterval) {
        overlayTasks.removeValue(forKey: token)?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self,
                  self.overlayTasks.removeValue(forKey: token) != nil else { return }
            self.send(.timerElapsed(token))
        }
        overlayTasks[token] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func startReleasePolling(token: UUID, shortcut: HotkeyShortcut) {
        stopReleasePolling(token: token)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self,
                      self.releasePollTimers[token] === timer else {
                    timer.invalidate()
                    return
                }

                let isPressed =
                    self.hidKeyboardStateMonitor.isPressed(shortcut) ??
                    ShortcutPressState.isPressed(shortcut, keyState: ShortcutPressState.liveKeyState)
                if !isPressed {
                    self.send(.releaseObserved(token))
                }
            }
        }
        timer.tolerance = 0.02
        releasePollTimers[token] = timer
    }

    private func stopReleasePolling(token: UUID) {
        releasePollTimers.removeValue(forKey: token)?.invalidate()
    }

    private func cancelOverlayAdapters() {
        overlayTasks.values.forEach { $0.cancel() }
        overlayTasks.removeAll()
        releasePollTimers.values.forEach { $0.invalidate() }
        releasePollTimers.removeAll()
        hotkeySource?.disarmAnyKeyDismiss()
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

    private func setupHotkeySource() {
        let hotkeySource = HotkeyTriggerSource(configuration: settings.configuration)
        hotkeySource.onStartError = { [weak self] message in
            self?.setHotkeyActive(false)
            self?.showInputMonitoringPermissionAlert(details: message)
        }
        hotkeySource.onRuntimeWarning = { [weak self] message in
            self?.setHotkeyActive(false)
            self?.showRuntimeHotkeyWarning(message)
        }

        hotkeySource.onTrigger = { [weak self] event in
            self?.handleHotkeyTrigger(event)
        }

        self.hotkeySource = hotkeySource
    }

    private func requestInputMonitoringPermissionAndStartHotkey() {
        if InputMonitoringPermission.requestAccessIfNeeded() {
            hotkeySource?.start()
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
