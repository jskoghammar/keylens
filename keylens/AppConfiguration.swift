import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

struct SVGAsset: Codable, Hashable, Identifiable {
    let id: String
    let fileName: String
    let sourceURL: String
    let localFilePath: String
}

enum SVGSourceType: String, Codable, CaseIterable, Identifiable {
    case repository
    case localDirectory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repository:
            return "GitHub Repository"
        case .localDirectory:
            return "Local Directory"
        }
    }
}

enum HotkeyActivationMode: String, Codable, CaseIterable, Identifiable {
    case timed
    case toggle
    case tapHold
    case oneShot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timed:
            return "Time"
        case .toggle:
            return "Toggle"
        case .tapHold:
            return "Tap/Hold"
        case .oneShot:
            return "One Shot"
        }
    }
}

enum OverlayPlacement: String, Codable, CaseIterable, Identifiable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center:
            return "Center"
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

struct AppConfiguration: Codable, Equatable {
    var svgSourceType: SVGSourceType
    var repositoryURL: String
    var repositoryBranch: String?
    var localDirectoryPath: String
    var svgAssets: [SVGAsset]
    var hotkeyAssignments: [String: HotkeyShortcut]
    var hotkeyModes: [String: HotkeyActivationMode]
    var clearHoldShortcut: HotkeyShortcut?
    var overlayDuration: TimeInterval
    var overlayPlacement: OverlayPlacement

    private enum CodingKeys: String, CodingKey {
        case svgSourceType
        case repositoryURL
        case repositoryBranch
        case localDirectoryPath
        case svgAssets
        case hotkeyAssignments
        case hotkeyModes
        case clearHoldShortcut
        case overlayDuration
        case overlayPlacement
    }

    static let `default` = AppConfiguration(
        svgSourceType: .repository,
        repositoryURL: "",
        repositoryBranch: nil,
        localDirectoryPath: "",
        svgAssets: [],
        hotkeyAssignments: [:],
        hotkeyModes: [:],
        clearHoldShortcut: .firmwareReleaseSignal,
        overlayDuration: 1.2,
        overlayPlacement: .center
    )

    init(
        svgSourceType: SVGSourceType,
        repositoryURL: String,
        repositoryBranch: String?,
        localDirectoryPath: String,
        svgAssets: [SVGAsset],
        hotkeyAssignments: [String: HotkeyShortcut],
        hotkeyModes: [String: HotkeyActivationMode],
        clearHoldShortcut: HotkeyShortcut?,
        overlayDuration: TimeInterval,
        overlayPlacement: OverlayPlacement
    ) {
        self.svgSourceType = svgSourceType
        self.repositoryURL = repositoryURL
        self.repositoryBranch = repositoryBranch
        self.localDirectoryPath = localDirectoryPath
        self.svgAssets = svgAssets
        self.hotkeyAssignments = hotkeyAssignments
        self.hotkeyModes = hotkeyModes
        self.clearHoldShortcut = clearHoldShortcut
        self.overlayDuration = overlayDuration
        self.overlayPlacement = overlayPlacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        svgSourceType = try container.decodeIfPresent(SVGSourceType.self, forKey: .svgSourceType) ?? .repository
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL) ?? ""
        repositoryBranch = try container.decodeIfPresent(String.self, forKey: .repositoryBranch)
        localDirectoryPath = try container.decodeIfPresent(String.self, forKey: .localDirectoryPath) ?? ""
        svgAssets = try container.decodeIfPresent([SVGAsset].self, forKey: .svgAssets) ?? []
        hotkeyAssignments = try container.decodeIfPresent([String: HotkeyShortcut].self, forKey: .hotkeyAssignments) ?? [:]
        hotkeyModes = try container.decodeIfPresent([String: HotkeyActivationMode].self, forKey: .hotkeyModes) ?? [:]
        clearHoldShortcut = try container.decodeIfPresent(HotkeyShortcut.self, forKey: .clearHoldShortcut)
        overlayDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .overlayDuration) ?? 1.2
        overlayPlacement = try container.decodeIfPresent(OverlayPlacement.self, forKey: .overlayPlacement) ?? .center
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(svgSourceType, forKey: .svgSourceType)
        try container.encode(repositoryURL, forKey: .repositoryURL)
        try container.encodeIfPresent(repositoryBranch, forKey: .repositoryBranch)
        try container.encode(localDirectoryPath, forKey: .localDirectoryPath)
        try container.encode(svgAssets, forKey: .svgAssets)
        try container.encode(hotkeyAssignments, forKey: .hotkeyAssignments)
        try container.encode(hotkeyModes, forKey: .hotkeyModes)
        try container.encodeIfPresent(clearHoldShortcut, forKey: .clearHoldShortcut)
        try container.encode(overlayDuration, forKey: .overlayDuration)
        try container.encode(overlayPlacement, forKey: .overlayPlacement)
    }
}

struct KeyChoice: Identifiable, Hashable {
    let keyCode: CGKeyCode
    let title: String

    var id: UInt16 { UInt16(keyCode) }

    static let arrowKeys: [KeyChoice] = [
        KeyChoice(keyCode: CGKeyCode(kVK_LeftArrow), title: "Left Arrow"),
        KeyChoice(keyCode: CGKeyCode(kVK_RightArrow), title: "Right Arrow"),
        KeyChoice(keyCode: CGKeyCode(kVK_UpArrow), title: "Up Arrow"),
        KeyChoice(keyCode: CGKeyCode(kVK_DownArrow), title: "Down Arrow")
    ]

    static let letterKeys: [KeyChoice] = [
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_A), title: "A"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_B), title: "B"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_C), title: "C"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_D), title: "D"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_E), title: "E"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_F), title: "F"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_G), title: "G"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_H), title: "H"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_I), title: "I"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_J), title: "J"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_K), title: "K"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_L), title: "L"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_M), title: "M"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_N), title: "N"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_O), title: "O"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_P), title: "P"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_Q), title: "Q"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_R), title: "R"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_S), title: "S"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_T), title: "T"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_U), title: "U"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_V), title: "V"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_W), title: "W"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_X), title: "X"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_Y), title: "Y"),
        KeyChoice(keyCode: CGKeyCode(kVK_ANSI_Z), title: "Z")
    ]

    static let functionKeys: [KeyChoice] = [
        KeyChoice(keyCode: CGKeyCode(kVK_F1), title: "F1"),
        KeyChoice(keyCode: CGKeyCode(kVK_F2), title: "F2"),
        KeyChoice(keyCode: CGKeyCode(kVK_F3), title: "F3"),
        KeyChoice(keyCode: CGKeyCode(kVK_F4), title: "F4"),
        KeyChoice(keyCode: CGKeyCode(kVK_F5), title: "F5"),
        KeyChoice(keyCode: CGKeyCode(kVK_F6), title: "F6"),
        KeyChoice(keyCode: CGKeyCode(kVK_F7), title: "F7"),
        KeyChoice(keyCode: CGKeyCode(kVK_F8), title: "F8"),
        KeyChoice(keyCode: CGKeyCode(kVK_F9), title: "F9"),
        KeyChoice(keyCode: CGKeyCode(kVK_F10), title: "F10"),
        KeyChoice(keyCode: CGKeyCode(kVK_F11), title: "F11"),
        KeyChoice(keyCode: CGKeyCode(kVK_F12), title: "F12"),
        KeyChoice(keyCode: CGKeyCode(kVK_F13), title: "F13"),
        KeyChoice(keyCode: CGKeyCode(kVK_F14), title: "F14"),
        KeyChoice(keyCode: CGKeyCode(kVK_F15), title: "F15"),
        KeyChoice(keyCode: CGKeyCode(kVK_F16), title: "F16"),
        KeyChoice(keyCode: CGKeyCode(kVK_F17), title: "F17"),
        KeyChoice(keyCode: CGKeyCode(kVK_F18), title: "F18"),
        KeyChoice(keyCode: CGKeyCode(kVK_F19), title: "F19"),
        KeyChoice(keyCode: CGKeyCode(kVK_F20), title: "F20")
    ]

    static let all: [KeyChoice] = arrowKeys + letterKeys + functionKeys

    static let defaultAssignmentOrder: [HotkeyShortcut] = {
        let preferred = arrowKeys + functionKeys + letterKeys
        return preferred.map { HotkeyShortcut(keyCode: $0.keyCode, modifiers: []) }
    }()
}

protocol SVGSyncing: AnyObject {
    func sync(repositoryURL: String, preferredBranch: String?) async throws -> SVGSyncResult
    func sync(localDirectoryPath: String) throws -> SVGSyncResult
    func fetchBranches(repositoryURL: String) async throws -> RepositoryBranchCatalog
}

extension SVGRepositorySyncService: SVGSyncing {}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: .standard, syncService: SVGRepositorySyncService())

    @Published private(set) var configuration: AppConfiguration {
        didSet {
            persist(configuration)
            onConfigurationChanged?(configuration)
        }
    }

    @Published private(set) var isSyncingRepository = false
    @Published private(set) var isLoadingRepositoryBranches = false
    @Published private(set) var availableRepositoryBranches: [String] = []
    @Published private(set) var repositorySyncMessage: String?

    var onConfigurationChanged: ((AppConfiguration) -> Void)?

    private let defaults: UserDefaults
    private let syncService: SVGSyncing
    private var syncOperationID: UUID?
    private var branchLoadOperationID: UUID?

    private struct SVGSyncSourceSnapshot: Equatable {
        let sourceType: SVGSourceType
        let repositoryURL: String
        let repositoryBranch: String?
        let localDirectoryPath: String
    }

    private enum DefaultsKey {
        static let configurationV2 = "settings.configuration.v2"

        // Legacy keys for migration from the single-hotkey configuration.
        static let legacyKeyCode = "settings.hotkey.keyCode"
        static let legacyModifiers = "settings.hotkey.modifiers"
        static let legacyDuration = "settings.overlay.duration"
    }

    init(defaults: UserDefaults, syncService: SVGSyncing) {
        self.defaults = defaults
        self.syncService = syncService
        configuration = Self.loadConfiguration(defaults: defaults)
    }

    func updateSVGSourceType(_ value: SVGSourceType) {
        guard configuration.svgSourceType != value else { return }
        configuration.svgSourceType = value
        repositorySyncMessage = nil
    }

    func updateRepositoryURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.repositoryURL != trimmed else { return }

        configuration.repositoryURL = trimmed
        configuration.repositoryBranch = nil
        availableRepositoryBranches = []
    }

    func updateLocalDirectoryPath(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.localDirectoryPath != trimmed else { return }
        configuration.localDirectoryPath = trimmed
    }

    func updateRepositoryBranch(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty {
            configuration.repositoryBranch = nil
        } else {
            configuration.repositoryBranch = trimmed
        }
    }

    func updateOverlayDuration(_ duration: TimeInterval) {
        configuration.overlayDuration = duration
    }

    func updateOverlayPlacement(_ placement: OverlayPlacement) {
        configuration.overlayPlacement = placement
    }

    func shortcut(for assetID: String) -> HotkeyShortcut? {
        configuration.hotkeyAssignments[assetID]
    }

    func setShortcut(_ shortcut: HotkeyShortcut?, for assetID: String) {
        var updated = configuration
        var assignments = updated.hotkeyAssignments

        if let shortcut {
            // Enforce one hotkey -> one SVG mapping to avoid ambiguous triggers.
            assignments = assignments.filter { $0.value != shortcut || $0.key == assetID }
            if updated.clearHoldShortcut == shortcut {
                updated.clearHoldShortcut = nil
            }
            assignments[assetID] = shortcut
        } else {
            assignments.removeValue(forKey: assetID)
        }

        updated.hotkeyAssignments = assignments
        configuration = updated
    }

    func activationMode(for assetID: String) -> HotkeyActivationMode {
        configuration.hotkeyModes[assetID] ?? .timed
    }

    func setActivationMode(_ mode: HotkeyActivationMode, for assetID: String) {
        var modes = configuration.hotkeyModes
        modes[assetID] = mode
        configuration.hotkeyModes = modes
    }

    func clearHoldShortcut() -> HotkeyShortcut? {
        configuration.clearHoldShortcut
    }

    func setClearHoldShortcut(_ shortcut: HotkeyShortcut?) {
        var updated = configuration

        if let shortcut {
            updated.hotkeyAssignments = updated.hotkeyAssignments.filter { $0.value != shortcut }
            updated.clearHoldShortcut = shortcut
        } else {
            updated.clearHoldShortcut = nil
        }

        configuration = updated
    }

    func hotkeyDescription(for shortcut: HotkeyShortcut?) -> String {
        guard let shortcut else {
            return "Unassigned"
        }

        if KeyboardSemantics.isSingleModifierShortcut(shortcut) {
            return keyTitle(for: shortcut)
        }

        var parts: [String] = []
        if shortcut.hasModifier(.maskCommand) { parts.append("Cmd") }
        if shortcut.hasModifier(.maskAlternate) { parts.append("Opt") }
        if shortcut.hasModifier(.maskControl) { parts.append("Ctrl") }
        if shortcut.hasModifier(.maskShift) { parts.append("Shift") }
        if shortcut.hasModifier(.maskSecondaryFn) { parts.append("Fn") }
        if shortcut.hasModifier(.maskAlphaShift) { parts.append("Caps") }

        let keyTitle = keyTitle(for: shortcut)
        parts.append(keyTitle)

        return parts.joined(separator: " + ")
    }

    private func keyTitle(for shortcut: HotkeyShortcut) -> String {
        if let modifierTitle = KeyboardSemantics.modifierKeyTitle(for: shortcut.cgKeyCode) {
            return modifierTitle
        }

        return KeyChoice.all.first(where: { UInt16($0.keyCode) == shortcut.keyCode })?.title ?? "KeyCode \(shortcut.keyCode)"
    }

    func syncSVGRepository() {
        guard !isSyncingRepository else { return }

        let snapshot = currentSyncSourceSnapshot()

        switch snapshot.sourceType {
        case .repository:
            guard !snapshot.repositoryURL.isEmpty else {
                repositorySyncMessage = "Enter a GitHub repository URL first."
                return
            }
        case .localDirectory:
            guard !snapshot.localDirectoryPath.isEmpty else {
                repositorySyncMessage = "Enter a local directory path first."
                return
            }
        }

        let operationID = UUID()
        syncOperationID = operationID
        isSyncingRepository = true
        repositorySyncMessage = nil
        let syncService = self.syncService

        Task.detached(priority: .userInitiated) { [weak self, syncService, snapshot, operationID] in
            do {
                let syncResult: SVGSyncResult
                switch snapshot.sourceType {
                case .repository:
                    syncResult = try await syncService.sync(
                        repositoryURL: snapshot.repositoryURL,
                        preferredBranch: snapshot.repositoryBranch
                    )
                case .localDirectory:
                    syncResult = try syncService.sync(localDirectoryPath: snapshot.localDirectoryPath)
                }

                await self?.finishSync(
                    result: .success(syncResult),
                    snapshot: snapshot,
                    operationID: operationID
                )
            } catch {
                await self?.finishSync(
                    result: .failure(error),
                    snapshot: snapshot,
                    operationID: operationID
                )
            }
        }
    }

    private func currentSyncSourceSnapshot() -> SVGSyncSourceSnapshot {
        SVGSyncSourceSnapshot(
            sourceType: configuration.svgSourceType,
            repositoryURL: configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines),
            repositoryBranch: configuration.repositoryBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
            localDirectoryPath: configuration.localDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func finishSync(
        result: Result<SVGSyncResult, Error>,
        snapshot: SVGSyncSourceSnapshot,
        operationID: UUID
    ) {
        guard syncOperationID == operationID else {
            return
        }

        defer {
            syncOperationID = nil
            isSyncingRepository = false
        }

        guard currentSyncSourceSnapshot() == snapshot else {
            repositorySyncMessage = nil
            return
        }

        switch result {
        case .success(let syncResult):
            applySyncedAssets(syncResult.assets)

            switch snapshot.sourceType {
            case .repository:
                if let branch = syncResult.branch, !branch.isEmpty {
                    configuration.repositoryBranch = branch
                    if !availableRepositoryBranches.contains(branch) {
                        availableRepositoryBranches.append(branch)
                        availableRepositoryBranches.sort()
                    }
                    repositorySyncMessage = "Found \(syncResult.assets.count) SVG file(s) on \(branch)."
                } else {
                    repositorySyncMessage = "Found \(syncResult.assets.count) SVG file(s)."
                }
            case .localDirectory:
                repositorySyncMessage = "Found \(syncResult.assets.count) SVG file(s) in the local directory."
            }

        case .failure(let error):
            repositorySyncMessage = "Failed to sync SVGs: \(error.localizedDescription)"
        }
    }

    private func normalizedAssetName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applySyncedAssets(_ assets: [SVGAsset]) {
        let previousAssetsByID = Dictionary(
            uniqueKeysWithValues: configuration.svgAssets.map { ($0.id, $0) }
        )
        let previousFileNames = Set(configuration.svgAssets.map { normalizedAssetName($0.fileName) })

        var previousShortcutsByFileName: [String: HotkeyShortcut] = [:]
        for (assetID, shortcut) in configuration.hotkeyAssignments {
            guard let asset = previousAssetsByID[assetID] else { continue }
            previousShortcutsByFileName[normalizedAssetName(asset.fileName)] = shortcut
        }

        var previousModesByFileName: [String: HotkeyActivationMode] = [:]
        for (assetID, mode) in configuration.hotkeyModes {
            guard let asset = previousAssetsByID[assetID] else { continue }
            previousModesByFileName[normalizedAssetName(asset.fileName)] = mode
        }

        var assignments: [String: HotkeyShortcut] = [:]
        var modes: [String: HotkeyActivationMode] = [:]
        var usedShortcuts: Set<HotkeyShortcut> = []

        // Preserve shortcuts and modes when the SVG filename is unchanged.
        for asset in assets {
            let normalizedName = normalizedAssetName(asset.fileName)

            if let preservedShortcut = previousShortcutsByFileName[normalizedName],
               !usedShortcuts.contains(preservedShortcut) {
                assignments[asset.id] = preservedShortcut
                usedShortcuts.insert(preservedShortcut)
            }

            if let preservedMode = previousModesByFileName[normalizedName] {
                modes[asset.id] = preservedMode
            }
        }

        // Auto-assign only for truly new filenames.
        for asset in assets where assignments[asset.id] == nil {
            let normalizedName = normalizedAssetName(asset.fileName)
            guard !previousFileNames.contains(normalizedName) else { continue }

            if let auto = KeyChoice.defaultAssignmentOrder.first(where: { !usedShortcuts.contains($0) }) {
                assignments[asset.id] = auto
                usedShortcuts.insert(auto)
            }
        }

        for asset in assets where modes[asset.id] == nil {
            modes[asset.id] = .timed
        }

        configuration.svgAssets = assets
        configuration.hotkeyAssignments = assignments
        configuration.hotkeyModes = modes
    }

    func refreshRepositoryBranches() {
        guard !isLoadingRepositoryBranches else { return }

        guard configuration.svgSourceType == .repository else {
            repositorySyncMessage = "Branches are only available for GitHub repositories."
            return
        }

        let repoURL = configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoURL.isEmpty else {
            repositorySyncMessage = "Enter a GitHub repository URL first."
            return
        }

        let operationID = UUID()
        branchLoadOperationID = operationID
        isLoadingRepositoryBranches = true
        repositorySyncMessage = nil
        let syncService = self.syncService

        Task.detached(priority: .userInitiated) { [weak self, syncService, repoURL, operationID] in
            do {
                let catalog = try await syncService.fetchBranches(repositoryURL: repoURL)
                await self?.finishRepositoryBranches(
                    result: .success(catalog),
                    repositoryURL: repoURL,
                    operationID: operationID
                )
            } catch {
                await self?.finishRepositoryBranches(
                    result: .failure(error),
                    repositoryURL: repoURL,
                    operationID: operationID
                )
            }
        }
    }

    private func finishRepositoryBranches(
        result: Result<RepositoryBranchCatalog, Error>,
        repositoryURL: String,
        operationID: UUID
    ) {
        guard branchLoadOperationID == operationID else {
            return
        }

        defer {
            branchLoadOperationID = nil
            isLoadingRepositoryBranches = false
        }

        guard configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines) == repositoryURL else {
            repositorySyncMessage = nil
            return
        }

        switch result {
        case .success(let catalog):
            availableRepositoryBranches = catalog.branches

            if let selectedBranch = configuration.repositoryBranch,
               !catalog.branches.contains(selectedBranch) {
                configuration.repositoryBranch = nil
            }

            if configuration.repositoryBranch == nil, let preferred = catalog.urlBranch ?? catalog.defaultBranch {
                configuration.repositoryBranch = preferred
            }

            repositorySyncMessage = "Loaded \(catalog.branches.count) branch\(catalog.branches.count == 1 ? "" : "es")."

        case .failure(let error):
            repositorySyncMessage = "Failed to load branches: \(error.localizedDescription)"
        }
    }

    private static func loadConfiguration(defaults: UserDefaults) -> AppConfiguration {
        if let data = defaults.data(forKey: DefaultsKey.configurationV2),
           var decoded = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            decoded.hotkeyAssignments = decoded.hotkeyAssignments.mapValues { shortcut in
                if shortcut == .legacyNavigationLayerSignal {
                    return .navigationLayerSignal
                }
                if shortcut == .legacySymbolLayerSignal {
                    return .symbolLayerSignal
                }
                return shortcut
            }
            if decoded.clearHoldShortcut == nil ||
                decoded.clearHoldShortcut == .legacyFirmwareReleaseSignal ||
                decoded.clearHoldShortcut == .legacyChordFirmwareReleaseSignal {
                decoded.clearHoldShortcut = .firmwareReleaseSignal
            }
            return decoded
        }

        // Legacy migration (single-hotkey setup).
        var config = AppConfiguration.default

        if let durationValue = defaults.object(forKey: DefaultsKey.legacyDuration) as? NSNumber {
            config.overlayDuration = TimeInterval(truncating: durationValue)
        }

        let keyCodeValue = defaults.object(forKey: DefaultsKey.legacyKeyCode) as? NSNumber
        let modifiersValue = defaults.object(forKey: DefaultsKey.legacyModifiers) as? NSNumber

        if let keyCodeValue {
            let keyCode = CGKeyCode(keyCodeValue.uint16Value)
            let modifiers: CGEventFlags
            if let modifiersValue {
                modifiers = CGEventFlags(rawValue: UInt64(truncating: modifiersValue))
            } else {
                modifiers = []
            }

            // Historical migration: old default Cmd+F12 became Left Arrow.
            if keyCode == CGKeyCode(kVK_F12), modifiers == [.maskCommand] {
                // No SVG list yet, but keep this as baseline for future auto-assignment.
            }
        }

        return config
    }

    private func persist(_ config: AppConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else {
            return
        }

        defaults.set(data, forKey: DefaultsKey.configurationV2)
    }
}
