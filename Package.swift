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
                "AppDelegate.swift",
                "Assets.xcassets",
                "Base.lproj",
                "HIDKeyboardStateMonitor.swift",
                "HotkeyMonitor.swift",
                "InputMonitoringPermission.swift",
                "OverlayWindowController.swift",
                "SettingsView.swift",
                "ViewController.swift"
            ],
            sources: [
                "AppConfiguration.swift",
                "HIDShortcutPressState.swift",
                "HotkeyShortcut.swift",
                "KeyboardSemantics.swift",
                "OverlayAssetRenderer.swift",
                "OverlayStateReconciler.swift",
                "SVGRepositorySyncService.swift",
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
