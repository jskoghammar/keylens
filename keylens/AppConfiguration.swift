import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

struct HotkeyShortcut: Codable, Hashable {
    static let supportedModifiers: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
        .maskAlphaShift
    ]

    var keyCode: UInt16
    var modifiersRawValue: UInt64

    init(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        self.keyCode = UInt16(keyCode)
        modifiersRawValue = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    var cgKeyCode: CGKeyCode {
        CGKeyCode(keyCode)
    }

    var cgModifiers: CGEventFlags {
        CGEventFlags(rawValue: modifiersRawValue)
    }

    func hasModifier(_ modifier: CGEventFlags) -> Bool {
        cgModifiers.contains(modifier)
    }

    func withModifier(_ modifier: CGEventFlags, enabled: Bool) -> HotkeyShortcut {
        var modifiers = cgModifiers
        if enabled {
            modifiers.insert(modifier)
        } else {
            modifiers.remove(modifier)
        }
        return HotkeyShortcut(keyCode: cgKeyCode, modifiers: modifiers)
    }
}

struct SVGAsset: Codable, Hashable, Identifiable {
    let id: String
    let fileName: String
    let sourceURL: String
    let localFilePath: String
}

struct AppConfiguration: Codable, Equatable {
    var repositoryURL: String
    var repositoryBranch: String?
    var svgAssets: [SVGAsset]
    var hotkeyAssignments: [String: HotkeyShortcut]
    var overlayDuration: TimeInterval

    static let `default` = AppConfiguration(
        repositoryURL: "",
        repositoryBranch: nil,
        svgAssets: [],
        hotkeyAssignments: [:],
        overlayDuration: 1.2
    )
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

    private let syncService: SVGRepositorySyncService

    private enum DefaultsKey {
        static let configurationV2 = "settings.configuration.v2"

        // Legacy keys for migration from the single-hotkey configuration.
        static let legacyKeyCode = "settings.hotkey.keyCode"
        static let legacyModifiers = "settings.hotkey.modifiers"
        static let legacyDuration = "settings.overlay.duration"
    }

    private init(defaults: UserDefaults, syncService: SVGRepositorySyncService) {
        self.syncService = syncService
        configuration = Self.loadConfiguration(defaults: defaults)
    }

    func updateRepositoryURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.repositoryURL != trimmed else { return }

        configuration.repositoryURL = trimmed
        configuration.repositoryBranch = nil
        availableRepositoryBranches = []
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

    func shortcut(for assetID: String) -> HotkeyShortcut? {
        configuration.hotkeyAssignments[assetID]
    }

    func setShortcut(_ shortcut: HotkeyShortcut?, for assetID: String) {
        var assignments = configuration.hotkeyAssignments

        if let shortcut {
            // Enforce one hotkey -> one SVG mapping to avoid ambiguous triggers.
            assignments = assignments.filter { $0.value != shortcut || $0.key == assetID }
            assignments[assetID] = shortcut
        } else {
            assignments.removeValue(forKey: assetID)
        }

        configuration.hotkeyAssignments = assignments
    }

    func hotkeyDescription(for shortcut: HotkeyShortcut?) -> String {
        guard let shortcut else {
            return "Unassigned"
        }

        var parts: [String] = []
        if shortcut.hasModifier(.maskCommand) { parts.append("Cmd") }
        if shortcut.hasModifier(.maskAlternate) { parts.append("Opt") }
        if shortcut.hasModifier(.maskControl) { parts.append("Ctrl") }
        if shortcut.hasModifier(.maskShift) { parts.append("Shift") }
        if shortcut.hasModifier(.maskSecondaryFn) { parts.append("Fn") }
        if shortcut.hasModifier(.maskAlphaShift) { parts.append("Caps") }

        let keyTitle = KeyChoice.all.first(where: { UInt16($0.keyCode) == shortcut.keyCode })?.title ?? "KeyCode \(shortcut.keyCode)"
        parts.append(keyTitle)

        return parts.joined(separator: " + ")
    }

    func syncSVGRepository() {
        guard !isSyncingRepository else { return }

        let repoURL = configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoURL.isEmpty else {
            repositorySyncMessage = "Enter a GitHub repository URL first."
            return
        }

        isSyncingRepository = true
        repositorySyncMessage = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let syncResult = try await syncService.sync(
                    repositoryURL: repoURL,
                    preferredBranch: configuration.repositoryBranch
                )
                let assets = syncResult.assets
                let knownIDs = Set(assets.map(\.id))

                var assignments = configuration.hotkeyAssignments
                    .filter { knownIDs.contains($0.key) }

                var usedShortcuts = Set(assignments.values)
                for asset in assets {
                    guard assignments[asset.id] == nil else { continue }

                    if let auto = KeyChoice.defaultAssignmentOrder.first(where: { !usedShortcuts.contains($0) }) {
                        assignments[asset.id] = auto
                        usedShortcuts.insert(auto)
                    }
                }

                configuration.svgAssets = assets
                configuration.repositoryBranch = syncResult.branch
                configuration.hotkeyAssignments = assignments
                if !availableRepositoryBranches.contains(syncResult.branch) {
                    availableRepositoryBranches.append(syncResult.branch)
                    availableRepositoryBranches.sort()
                }
                repositorySyncMessage = "Found \(assets.count) SVG file(s) on \(syncResult.branch)."
            } catch {
                repositorySyncMessage = "Failed to sync SVGs: \(error.localizedDescription)"
            }

            isSyncingRepository = false
        }
    }

    func refreshRepositoryBranches() {
        guard !isLoadingRepositoryBranches else { return }

        let repoURL = configuration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoURL.isEmpty else {
            repositorySyncMessage = "Enter a GitHub repository URL first."
            return
        }

        isLoadingRepositoryBranches = true
        repositorySyncMessage = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let catalog = try await syncService.fetchBranches(repositoryURL: repoURL)
                availableRepositoryBranches = catalog.branches

                if let selectedBranch = configuration.repositoryBranch,
                   !catalog.branches.contains(selectedBranch) {
                    configuration.repositoryBranch = nil
                }

                if configuration.repositoryBranch == nil, let preferred = catalog.urlBranch ?? catalog.defaultBranch {
                    configuration.repositoryBranch = preferred
                }

                repositorySyncMessage = "Loaded \(catalog.branches.count) branch\(catalog.branches.count == 1 ? "" : "es")."
            } catch {
                repositorySyncMessage = "Failed to load branches: \(error.localizedDescription)"
            }

            isLoadingRepositoryBranches = false
        }
    }

    private static func loadConfiguration(defaults: UserDefaults) -> AppConfiguration {
        if let data = defaults.data(forKey: DefaultsKey.configurationV2),
           let decoded = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
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

        UserDefaults.standard.set(data, forKey: DefaultsKey.configurationV2)
    }
}
