import AppKit
import ApplicationServices

enum InputMonitoringPermission {
    static func hasAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func requestAccessIfNeeded() -> Bool {
        if hasAccess() {
            return true
        }

        return CGRequestListenEventAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
