import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

struct BehaviorTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

struct BehaviorTest {
    let name: String
    let run: () async throws -> Void
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw BehaviorTestFailure(message: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw BehaviorTestFailure(message: "\(message). Expected \(expected), got \(actual)")
    }
}

@main
enum KeylensBehaviorTests {
    static func main() async {
        let tests = [
            BehaviorTest(name: "ShortcutPressState requires exact modifier match") {
                let primaryKey = CGKeyCode(kVK_ANSI_S)
                let shortcut = HotkeyShortcut(
                    keyCode: primaryKey,
                    modifiers: [.maskAlternate]
                )

                try expect(
                    ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option)])),
                    "Alt+S should be pressed when S and Option are down"
                )
                try expect(
                    !ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey])),
                    "Alt+S should not be pressed without Option"
                )
                try expect(
                    !ShortcutPressState.isPressed(shortcut, keyState: keyState([primaryKey, CGKeyCode(kVK_Option), CGKeyCode(kVK_Shift)])),
                    "Alt+S should not be pressed with extra Shift"
                )
            },
            BehaviorTest(name: "HIDShortcutPressState requires primary key and Fn usage") {
                let shortcut = HotkeyShortcut(
                    keyCode: CGKeyCode(kVK_F18),
                    modifiers: [.maskSecondaryFn]
                )

                try expect(
                    HIDShortcutPressState.isPressed(
                        shortcut,
                        pressedUsages: [
                            HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18)),
                            HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                        ]
                    ),
                    "Fn+F18 should be pressed when F18 and Fn usages are down"
                )
                try expect(
                    !HIDShortcutPressState.isPressed(
                        shortcut,
                        pressedUsages: [
                            HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))
                        ]
                    ),
                    "Fn+F18 should not be pressed with only Fn"
                )
            },
            BehaviorTest(name: "Repository sync keeps existing cache when a download fails") {
                let root = try makeTemporaryDirectory()
                defer {
                    try? FileManager.default.removeItem(at: root)
                }

                let existingDirectory = root
                    .appendingPathComponent("Keylens", isDirectory: true)
                    .appendingPathComponent("DownloadedSVG", isDirectory: true)
                    .appendingPathComponent("owner_repo_main", isDirectory: true)
                try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
                let oldFile = existingDirectory.appendingPathComponent("old.svg")
                try Data("<svg>old</svg>".utf8).write(to: oldFile)

                MockURLProtocol.handler = { request in
                    let url = try requireURL(request)
                    if url.path == "/repos/owner/repo" {
                        return try jsonResponse(url: url, body: #"{"default_branch":"main"}"#)
                    }
                    if url.path == "/repos/owner/repo/contents/keymap-drawer/img" {
                        return try jsonResponse(
                            url: url,
                            body: #"[{"name":"old.svg","path":"keymap-drawer/img/old.svg","type":"file","download_url":"https://download.test/old.svg"},{"name":"new.svg","path":"keymap-drawer/img/new.svg","type":"file","download_url":"https://download.test/new.svg"}]"#
                        )
                    }
                    if url.host == "download.test", url.path == "/old.svg" {
                        return try dataResponse(url: url, body: "<svg>old-new</svg>")
                    }
                    if url.host == "download.test", url.path == "/new.svg" {
                        throw URLError(.timedOut)
                    }
                    throw URLError(.badURL)
                }

                let service = SVGRepositorySyncService(
                    session: makeMockSession(),
                    fileManager: .default,
                    applicationSupportRoot: root
                )

                do {
                    _ = try await service.sync(repositoryURL: "https://github.com/owner/repo")
                    throw BehaviorTestFailure(message: "Sync should fail when a download fails")
                } catch let error as URLError {
                    try expectEqual(error.code, .timedOut, "Failed download should surface its URL error")
                }

                let oldData = try String(contentsOf: oldFile, encoding: .utf8)
                try expectEqual(oldData, "<svg>old</svg>", "Existing cache should stay intact after failed sync")
                try expect(
                    !FileManager.default.fileExists(atPath: existingDirectory.appendingPathComponent("new.svg").path),
                    "Failed sync should not partially write new files into the live cache"
                )
            },
            BehaviorTest(name: "Repository sync replaces live cache after all downloads succeed") {
                let root = try makeTemporaryDirectory()
                defer {
                    try? FileManager.default.removeItem(at: root)
                }

                let liveDirectory = root
                    .appendingPathComponent("Keylens", isDirectory: true)
                    .appendingPathComponent("DownloadedSVG", isDirectory: true)
                    .appendingPathComponent("owner_repo_main", isDirectory: true)
                try FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
                try Data("<svg>stale</svg>".utf8).write(to: liveDirectory.appendingPathComponent("stale.svg"))

                MockURLProtocol.handler = { request in
                    let url = try requireURL(request)
                    if url.path == "/repos/owner/repo" {
                        return try jsonResponse(url: url, body: #"{"default_branch":"main"}"#)
                    }
                    if url.path == "/repos/owner/repo/contents/keymap-drawer/img" {
                        return try jsonResponse(
                            url: url,
                            body: #"[{"name":"fresh.svg","path":"keymap-drawer/img/fresh.svg","type":"file","download_url":"https://download.test/fresh.svg"}]"#
                        )
                    }
                    if url.host == "download.test", url.path == "/fresh.svg" {
                        return try dataResponse(url: url, body: "<svg>fresh</svg>")
                    }
                    throw URLError(.badURL)
                }

                let service = SVGRepositorySyncService(
                    session: makeMockSession(),
                    fileManager: .default,
                    applicationSupportRoot: root
                )

                let result = try await service.sync(repositoryURL: "https://github.com/owner/repo")
                try expectEqual(result.assets.count, 1, "Successful sync should return one asset")
                try expectEqual(
                    result.assets[0].localFilePath,
                    liveDirectory.appendingPathComponent("fresh.svg").path,
                    "Successful sync should return the promoted live file path"
                )
                try expect(
                    FileManager.default.fileExists(atPath: liveDirectory.appendingPathComponent("fresh.svg").path),
                    "Fresh SVG should exist in the live cache"
                )
                try expect(
                    !FileManager.default.fileExists(atPath: liveDirectory.appendingPathComponent("stale.svg").path),
                    "Stale SVG should be removed only after successful replacement"
                )
            },
            BehaviorTest(name: "Overlay reconciliation hides a removed latched asset") {
                let result = OverlayStateReconciler.reconcile(
                    state: OverlayReconciliationState(
                        latchedAssetID: "old",
                        hasTransientOverlay: false,
                        transientAssetID: nil,
                        tapHoldAssetID: nil
                    ),
                    validAssetIDs: ["new"]
                )

                try expectEqual(result.state.latchedAssetID, nil, "Removed latched asset should be cleared")
                try expectEqual(result.presentation, .hideOverlay, "Removed visible latched asset should hide overlay")
            },
            BehaviorTest(name: "Overlay reconciliation restores latched overlay after transient asset disappears") {
                let result = OverlayStateReconciler.reconcile(
                    state: OverlayReconciliationState(
                        latchedAssetID: "latched",
                        hasTransientOverlay: true,
                        transientAssetID: "transient",
                        tapHoldAssetID: nil
                    ),
                    validAssetIDs: ["latched"]
                )

                try expectEqual(result.state.latchedAssetID, "latched", "Valid latched asset should remain")
                try expectEqual(result.state.hasTransientOverlay, false, "Removed transient overlay should be cleared")
                try expectEqual(result.presentation, .presentLatchedOverlay("latched"), "Latched overlay should be restored")
                try expect(result.shouldStopOneShotDismiss, "Transient removal should stop one-shot dismissal")
            },
            BehaviorTest(name: "Settings ignore stale repository sync result after source changes") {
                let defaultsName = "keylens-tests-\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: defaultsName) else {
                    throw BehaviorTestFailure(message: "Could not create isolated UserDefaults")
                }
                defer {
                    defaults.removePersistentDomain(forName: defaultsName)
                }

                let sync = ControllableSVGSyncer()
                let settings = AppSettings(defaults: defaults, syncService: sync)

                await MainActor.run {
                    settings.updateRepositoryURL("https://github.com/owner/old")
                    settings.updateRepositoryBranch("main")
                    settings.syncSVGRepository()
                    settings.updateRepositoryURL("https://github.com/owner/new")
                }

                try await sync.waitUntilRepositorySyncStarted()
                sync.finishRepositorySync(
                    SVGSyncResult(
                        assets: [
                            SVGAsset(
                                id: "keymap-drawer/img/old.svg",
                                fileName: "old.svg",
                                sourceURL: "https://download.test/old.svg",
                                localFilePath: "/tmp/old.svg"
                            )
                        ],
                        branch: "main"
                    )
                )

                try await waitUntil {
                    await MainActor.run {
                        settings.isSyncingRepository == false
                    }
                }

                let configuration = await MainActor.run {
                    settings.configuration
                }

                try expectEqual(sync.capturedRepositoryURL, "https://github.com/owner/old", "Sync should use the source snapshot URL")
                try expectEqual(sync.capturedPreferredBranch, "main", "Sync should use the source snapshot branch")
                try expectEqual(configuration.repositoryURL, "https://github.com/owner/new", "User's newer repository URL should remain")
                try expect(configuration.svgAssets.isEmpty, "Stale sync result should not replace current SVG assets")
            },
            BehaviorTest(name: "Overlay asset renderer fails explicitly for missing files") {
                let result = OverlayAssetRenderer.loadAsset(at: "/tmp/definitely-missing-\(UUID().uuidString).svg")
                try expectEqual(result, .failure(.missingOrUnreadable), "Missing asset should be an explicit failure")
            },
            BehaviorTest(name: "Overlay asset renderer rejects unsafe SVG content") {
                let root = try makeTemporaryDirectory()
                defer {
                    try? FileManager.default.removeItem(at: root)
                }
                let svg = root.appendingPathComponent("unsafe.svg")
                try Data(#"<svg><script>alert("x")</script></svg>"#.utf8).write(to: svg)

                let result = OverlayAssetRenderer.loadAsset(at: svg.path)
                try expectEqual(result, .failure(.unsafeSVGContent), "SVG script content should be rejected")
            },
            BehaviorTest(name: "Overlay asset renderer loads safe SVG content") {
                let root = try makeTemporaryDirectory()
                defer {
                    try? FileManager.default.removeItem(at: root)
                }
                let svg = root.appendingPathComponent("safe.svg")
                try Data(#"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#.utf8).write(to: svg)

                let result = OverlayAssetRenderer.loadAsset(at: svg.path)
                switch result {
                case .success(.svg(let asset)):
                    try expect(asset.body.contains("<rect"), "Safe SVG body should be available for rendering")
                    try expectEqual(asset.baseURL, root, "SVG base URL should be its containing directory")
                default:
                    throw BehaviorTestFailure(message: "Safe SVG should load successfully, got \(result)")
                }
            },
            BehaviorTest(name: "Settings persist through injected UserDefaults") {
                let defaultsName = "keylens-tests-\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: defaultsName) else {
                    throw BehaviorTestFailure(message: "Could not create isolated UserDefaults")
                }
                defer {
                    defaults.removePersistentDomain(forName: defaultsName)
                }

                let sync = ControllableSVGSyncer()
                let settings = AppSettings(defaults: defaults, syncService: sync)
                await MainActor.run {
                    settings.updateOverlayDuration(4.2)
                    settings.updateOverlayPlacement(.bottomRight)
                }

                let reloaded = AppSettings(defaults: defaults, syncService: sync)
                let configuration = await MainActor.run {
                    reloaded.configuration
                }

                try expectEqual(configuration.overlayDuration, 4.2, "Injected defaults should persist overlay duration")
                try expectEqual(configuration.overlayPlacement, .bottomRight, "Injected defaults should persist overlay placement")
            },
            BehaviorTest(name: "Keyboard semantics map modifiers consistently") {
                try expectEqual(
                    KeyboardSemantics.modifierFlag(for: CGKeyCode(kVK_RightShift)),
                    .maskShift,
                    "Right Shift should map to Shift"
                )
                try expect(
                    KeyboardSemantics.modifierKeyCodes(for: .maskShift).contains(CGKeyCode(kVK_Shift)),
                    "Shift key codes should include left Shift"
                )
                try expect(
                    KeyboardSemantics.modifierKeyCodes(for: .maskShift).contains(CGKeyCode(kVK_RightShift)),
                    "Shift key codes should include right Shift"
                )
                try expect(
                    KeyboardSemantics.isSingleModifierShortcut(.firmwareReleaseSignal),
                    "Firmware release signal should be a single-modifier shortcut"
                )
            },
            BehaviorTest(name: "Keyboard semantics expose HID usages for shortcut polling") {
                try expect(
                    KeyboardSemantics.modifierUsages(for: .maskSecondaryFn)
                        .contains(HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift))),
                    "Fn modifier should expose the Generic Desktop SFShift usage"
                )
                try expect(
                    KeyboardSemantics.keyUsages(for: CGKeyCode(kVK_F18))?
                        .contains(HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18))) == true,
                    "F18 should expose its keyboard HID usage"
                )
            }
        ]

        var failures: [String] = []

        for test in tests {
            do {
                try await test.run()
                print("PASS \(test.name)")
            } catch {
                print("FAIL \(test.name): \(error)")
                failures.append(test.name)
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) behavior tests passed.")
        } else {
            print("\(failures.count) behavior test(s) failed.")
            Foundation.exit(1)
        }
    }

    private static func keyState(_ pressedKeys: Set<CGKeyCode>) -> ShortcutPressState.KeyStateProvider {
        { pressedKeys.contains($0) }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("keylens-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requireURL(_ request: URLRequest) throws -> URL {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func jsonResponse(url: URL, body: String, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
        let response = try httpResponse(url: url, statusCode: statusCode)
        return (response, Data(body.utf8))
    }

    private static func dataResponse(url: URL, body: String, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
        let response = try httpResponse(url: url, statusCode: statusCode)
        return (response, Data(body.utf8))
    }

    private static func httpResponse(url: URL, statusCode: Int) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    static func waitUntil(
        timeout: TimeInterval = 2.0,
        _ predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BehaviorTestFailure(message: "Timed out waiting for condition")
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ControllableSVGSyncer: SVGSyncing {
    private var repositoryContinuation: CheckedContinuation<SVGSyncResult, Error>?
    private var didStartRepositorySync = false

    private(set) var capturedRepositoryURL: String?
    private(set) var capturedPreferredBranch: String?

    func sync(repositoryURL: String, preferredBranch: String?) async throws -> SVGSyncResult {
        capturedRepositoryURL = repositoryURL
        capturedPreferredBranch = preferredBranch
        didStartRepositorySync = true

        return try await withCheckedThrowingContinuation { continuation in
            repositoryContinuation = continuation
        }
    }

    func sync(localDirectoryPath: String) throws -> SVGSyncResult {
        throw SVGRepositorySyncError.localDirectoryNotFound
    }

    func fetchBranches(repositoryURL: String) async throws -> RepositoryBranchCatalog {
        RepositoryBranchCatalog(branches: [], defaultBranch: nil, urlBranch: nil)
    }

    func waitUntilRepositorySyncStarted() async throws {
        try await KeylensBehaviorTests.waitUntil {
            self.didStartRepositorySync
        }
    }

    func finishRepositorySync(_ result: SVGSyncResult) {
        repositoryContinuation?.resume(returning: result)
        repositoryContinuation = nil
    }
}
