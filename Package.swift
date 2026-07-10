// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KeylensCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
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
                "InputMonitoringPermission.swift",
                "OverlayWindowController.swift",
                "SettingsView.swift",
                "ViewController.swift"
            ],
            sources: [
                "AppConfiguration.swift",
                "HIDShortcutPressState.swift",
                "HotkeyMonitor.swift",
                "HotkeyShortcut.swift",
                "KeyboardSemantics.swift",
                "OverlayAssetRenderer.swift",
                "OverlayInteraction.swift",
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
