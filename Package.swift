// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KeylensCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KeylensCore", targets: ["KeylensCore"])
    ],
    targets: [
        .target(
            name: "KeylensCore",
            path: "keylens",
            exclude: [
                "AppConfiguration.swift",
                "AppDelegate.swift",
                "Assets.xcassets",
                "Base.lproj",
                "HIDKeyboardStateMonitor.swift",
                "HotkeyMonitor.swift",
                "InputMonitoringPermission.swift",
                "OverlayWindowController.swift",
                "SVGRepositorySyncService.swift",
                "SettingsView.swift",
                "ViewController.swift"
            ],
            sources: [
                "HIDShortcutPressState.swift",
                "HotkeyShortcut.swift",
                "ShortcutPressState.swift"
            ]
        ),
        .testTarget(
            name: "KeylensCoreTests",
            dependencies: ["KeylensCore"],
            path: "Tests/KeylensCoreTests"
        )
    ]
)
