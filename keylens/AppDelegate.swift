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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var overlayController: OverlayWindowController?
    private var triggerController: TriggerController?
    private var statusItem: NSStatusItem?
    private var hotkeyStatusMenuItem: NSMenuItem?
    private lazy var settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController()
        overlayController?.setImage(defaultOverlayImage())

        setupStatusMenu()
        setupTriggerController()
        requestInputMonitoringPermissionAndStartHotkey()

        settings.onConfigurationChanged = { [weak self] configuration in
            self?.apply(configuration: configuration)
        }

        apply(configuration: settings.configuration)

        if !settings.configuration.repositoryURL.isEmpty, settings.configuration.svgAssets.isEmpty {
            settings.syncSVGRepository()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        triggerController?.stop()
    }

    private func apply(configuration: AppConfiguration) {
        triggerController?.update(configuration: configuration)
        setHotkeyActive(InputMonitoringPermission.hasAccess())
    }

    private func defaultOverlayImage() -> NSImage {
        NSImage(named: NSImage.Name("Image")) ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    private func showOverlayForConfiguredDuration() {
        let duration = settings.configuration.overlayDuration

        if let first = settings.configuration.svgAssets.first {
            overlayController?.showAsset(at: first.localFilePath, for: duration)
            return
        }

        overlayController?.show(for: duration)
    }

    private func showOverlay(for assetID: String) {
        guard let asset = settings.configuration.svgAssets.first(where: { $0.id == assetID }) else {
            return
        }

        overlayController?.showAsset(at: asset.localFilePath, for: settings.configuration.overlayDuration)
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
        menu.addItem(NSMenuItem(title: "Sync SVG Repository", action: #selector(syncSVGRepository), keyEquivalent: ""))
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
            self?.showOverlay(for: event.assetID)
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
}

final class SettingsWindowController: NSWindowController {
    init() {
        let frame = NSRect(x: 0, y: 0, width: 620, height: 640)
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
