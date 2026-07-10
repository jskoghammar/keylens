import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid
import Testing
@testable import KeylensCore

@Suite(.serialized)
struct CoreBehaviorTests {
    @Test
    func failedRepositoryDownloadLeavesExistingCacheUntouched() async throws {
        let root = try makeTemporaryDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: root)
        }

        let existingDirectory = root
            .appendingPathComponent("Keylens", isDirectory: true)
            .appendingPathComponent("DownloadedSVG", isDirectory: true)
            .appendingPathComponent("owner_repo_main", isDirectory: true)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        let oldFile = existingDirectory.appendingPathComponent("old.svg")
        try Data("<svg>old</svg>".utf8).write(to: oldFile)

        MockURLProtocol.install { request in
            let url = try requireURL(request)
            if url.path == "/repos/owner/repo" {
                return try response(url: url, body: #"{"default_branch":"main"}"#)
            }
            if url.path == "/repos/owner/repo/contents/keymap-drawer/img" {
                return try response(
                    url: url,
                    body: #"[{"name":"old.svg","path":"keymap-drawer/img/old.svg","type":"file","download_url":"https://download.test/old.svg"},{"name":"new.svg","path":"keymap-drawer/img/new.svg","type":"file","download_url":"https://download.test/new.svg"}]"#
                )
            }
            if url.host == "download.test", url.path == "/old.svg" {
                return try response(url: url, body: "<svg>old-new</svg>")
            }
            if url.host == "download.test", url.path == "/new.svg" {
                throw URLError(.timedOut)
            }
            throw URLError(.badURL)
        }

        let service = SVGRepositorySyncService(
            session: makeMockSession(),
            applicationSupportRoot: root
        )

        do {
            _ = try await service.sync(repositoryURL: "https://github.com/owner/repo")
            Issue.record("Sync should fail when a download fails")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }

        #expect(try String(contentsOf: oldFile, encoding: .utf8) == "<svg>old</svg>")
        #expect(!FileManager.default.fileExists(atPath: existingDirectory.appendingPathComponent("new.svg").path))
    }

    @Test
    func successfulRepositoryDownloadReplacesLiveCache() async throws {
        let root = try makeTemporaryDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: root)
        }

        let liveDirectory = root
            .appendingPathComponent("Keylens", isDirectory: true)
            .appendingPathComponent("DownloadedSVG", isDirectory: true)
            .appendingPathComponent("owner_repo_main", isDirectory: true)
        try FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
        try Data("<svg>stale</svg>".utf8).write(to: liveDirectory.appendingPathComponent("stale.svg"))

        MockURLProtocol.install { request in
            let url = try requireURL(request)
            if url.path == "/repos/owner/repo" {
                return try response(url: url, body: #"{"default_branch":"main"}"#)
            }
            if url.path == "/repos/owner/repo/contents/keymap-drawer/img" {
                return try response(
                    url: url,
                    body: #"[{"name":"fresh.svg","path":"keymap-drawer/img/fresh.svg","type":"file","download_url":"https://download.test/fresh.svg"}]"#
                )
            }
            if url.host == "download.test", url.path == "/fresh.svg" {
                return try response(url: url, body: "<svg>fresh</svg>")
            }
            throw URLError(.badURL)
        }

        let service = SVGRepositorySyncService(
            session: makeMockSession(),
            applicationSupportRoot: root
        )
        let result = try await service.sync(repositoryURL: "https://github.com/owner/repo")

        #expect(result.assets.count == 1)
        #expect(result.assets[0].localFilePath == liveDirectory.appendingPathComponent("fresh.svg").path)
        #expect(FileManager.default.fileExists(atPath: liveDirectory.appendingPathComponent("fresh.svg").path))
        #expect(!FileManager.default.fileExists(atPath: liveDirectory.appendingPathComponent("stale.svg").path))
    }

    @Test
    @MainActor
    func staleRepositorySyncDoesNotReplaceCurrentConfiguration() async throws {
        let defaultsName = "keylens-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let sync = ControllableSVGSyncer()
        let settings = AppSettings(defaults: defaults, syncService: sync)
        settings.updateRepositoryURL("https://github.com/owner/old")
        settings.updateRepositoryBranch("main")
        settings.syncSVGRepository()
        settings.updateRepositoryURL("https://github.com/owner/new")

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
            await MainActor.run { !settings.isSyncingRepository }
        }

        #expect(sync.capturedRepositoryURL == "https://github.com/owner/old")
        #expect(sync.capturedPreferredBranch == "main")
        #expect(settings.configuration.repositoryURL == "https://github.com/owner/new")
        #expect(settings.configuration.svgAssets.isEmpty)
    }

    @Test
    @MainActor
    func injectedDefaultsPersistSettings() throws {
        let defaultsName = "keylens-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let settings = AppSettings(defaults: defaults, syncService: SVGRepositorySyncService())
        settings.updateOverlayDuration(4.2)
        settings.updateOverlayPlacement(.bottomRight)

        let configuration = AppSettings(
            defaults: defaults,
            syncService: SVGRepositorySyncService()
        ).configuration
        #expect(configuration.overlayDuration == 4.2)
        #expect(configuration.overlayPlacement == .bottomRight)
    }

    @Test
    func modifiersMapConsistently() {
        #expect(KeyboardSemantics.modifierFlag(for: CGKeyCode(kVK_RightShift)) == .maskShift)
        #expect(KeyboardSemantics.modifierKeyCodes(for: .maskShift).contains(CGKeyCode(kVK_Shift)))
        #expect(KeyboardSemantics.modifierKeyCodes(for: .maskShift).contains(CGKeyCode(kVK_RightShift)))
        #expect(KeyboardSemantics.isSingleModifierShortcut(.firmwareReleaseSignal))
    }

    @Test
    func HIDUsagesSupportShortcutPolling() {
        #expect(
            KeyboardSemantics.modifierUsages(for: .maskSecondaryFn)
                .contains(HIDUsageToken(page: Int(kHIDPage_GenericDesktop), usage: Int(kHIDUsage_GD_SFShift)))
        )
        #expect(
            KeyboardSemantics.keyUsages(for: CGKeyCode(kVK_F18))?
                .contains(HIDUsageToken(page: Int(kHIDPage_KeyboardOrKeypad), usage: Int(kHIDUsage_KeyboardF18))) == true
        )
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("keylens-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requireURL(_ request: URLRequest) throws -> URL {
    guard let url = request.url else { throw URLError(.badURL) }
    return url
}

private func response(
    url: URL,
    body: String,
    statusCode: Int = 200
) throws -> (HTTPURLResponse, Data) {
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    ) else {
        throw URLError(.badServerResponse)
    }
    return (response, Data(body.utf8))
}

private func waitUntil(
    timeout: TimeInterval = 2.0,
    _ predicate: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TestTimeout()
}

private struct TestTimeout: Error {}

private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    private static func currentHandler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.currentHandler() else {
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

private final class ControllableSVGSyncer: SVGSyncing {
    private let lock = NSLock()
    private var repositoryContinuation: CheckedContinuation<SVGSyncResult, Error>?
    private var didStartRepositorySync = false
    private var repositoryURL: String?
    private var preferredBranch: String?

    var capturedRepositoryURL: String? {
        lock.lock()
        defer { lock.unlock() }
        return repositoryURL
    }

    var capturedPreferredBranch: String? {
        lock.lock()
        defer { lock.unlock() }
        return preferredBranch
    }

    func sync(repositoryURL: String, preferredBranch: String?) async throws -> SVGSyncResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.repositoryURL = repositoryURL
            self.preferredBranch = preferredBranch
            didStartRepositorySync = true
            repositoryContinuation = continuation
            lock.unlock()
        }
    }

    func sync(localDirectoryPath: String) throws -> SVGSyncResult {
        throw SVGRepositorySyncError.localDirectoryNotFound
    }

    func fetchBranches(repositoryURL: String) async throws -> RepositoryBranchCatalog {
        RepositoryBranchCatalog(branches: [], defaultBranch: nil, urlBranch: nil)
    }

    func waitUntilRepositorySyncStarted() async throws {
        try await waitUntil {
            self.repositorySyncDidStart
        }
    }

    private var repositorySyncDidStart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStartRepositorySync && repositoryContinuation != nil
    }

    func finishRepositorySync(_ result: SVGSyncResult) {
        lock.lock()
        let continuation = repositoryContinuation
        repositoryContinuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
