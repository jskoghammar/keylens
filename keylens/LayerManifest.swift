import Carbon.HIToolbox
import Foundation

/// The generated keymap↔keylens contract, emitted by corne_v4 CI at
/// `keymap-drawer/layers.json` from the same parse that draws the SVGs.
///
///     {"commit": "<sha>", "layers": [
///       {"index": 1, "name": "Sym", "svg": "img/corne-sym.svg", "signal": "F14"}]}
///
/// Layer index N signals as bare `F13+N`; `F13` is reserved for Base/hide.
struct LayerManifest: Decodable, Equatable {
    struct Layer: Decodable, Equatable {
        let index: Int
        let name: String
        let svg: String
        let signal: String
    }

    let commit: String
    let layers: [Layer]

    /// The layer the keyboard rests on. Its signal hides the overlay; see `binding`.
    static let restingLayerIndex = 0

    var shortCommit: String {
        String(commit.prefix(7))
    }
}

enum LayerManifestError: LocalizedError, Equatable {
    case malformedManifest
    case unknownSignal(layer: String, signal: String)

    var errorDescription: String? {
        switch self {
        case .malformedManifest:
            return "keymap-drawer/layers.json could not be parsed."
        case let .unknownSignal(layer, signal):
            return "Layer \"\(layer)\" declares signal \"\(signal)\", which is not a key Keylens can bind."
        }
    }
}

struct ManifestBinding: Equatable {
    /// Asset ID -> shortcut, ready to merge into `AppConfiguration.hotkeyAssignments`.
    let assignments: [String: HotkeyShortcut]
    /// Assets the manifest named, i.e. the held layers. A superset of these is in
    /// `assignments`, which also carries surviving manual bindings -- those must not be
    /// treated as held, since nothing will ever send a hide for them.
    let layerAssetIDs: [String]
    /// The resting layer's signal, which dismisses the overlay rather than drawing one.
    let hideShortcut: HotkeyShortcut?
    /// Layers the repository has no SVG for. Drift worth showing, not worth failing on.
    let unmatchedLayers: [String]
    /// Manual bindings dropped because something else already holds their shortcut.
    let droppedManualBindings: [String]
}

extension LayerManifest {
    static func decode(_ data: Data) throws -> LayerManifest {
        do {
            return try JSONDecoder().decode(LayerManifest.self, from: data)
        } catch {
            throw LayerManifestError.malformedManifest
        }
    }

    /// Resolves a manifest signal ("F14") to a bare, unmodified shortcut.
    ///
    /// Bare is deliberate: issue 04 picked `F13`–`F16` precisely because macOS binds
    /// none of `F13`–`F24`, so no modifier is needed to keep them out of apps' way.
    /// The Ctrl+Opt requirement that replaced bare auto-assignment applies to letters
    /// and arrows, which do fire inside every app.
    static func shortcut(forSignal signal: String) -> HotkeyShortcut? {
        let trimmed = signal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let choice = KeyChoice.all.first(where: {
            $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            return nil
        }

        return HotkeyShortcut(keyCode: choice.keyCode, modifiers: [])
    }

    /// The manifest names SVGs relative to `keymap-drawer` ("img/corne-sym.svg") while
    /// `SVGAsset.id` is the repository path ("keymap-drawer/img/corne-sym.svg"), so the
    /// two never compare equal. Both sides collapse to the file name, which is unique:
    /// sync only ever lists the flat `keymap-drawer/img` directory.
    private static func matchKey(_ path: String) -> String {
        (path as NSString).lastPathComponent.lowercased()
    }

    /// Binds every layer the manifest describes, preserving manual hotkeys for assets
    /// it does not describe.
    ///
    /// Throws on an unrecognized signal rather than skipping the layer: a manifest that
    /// half-binds is the silent drift this whole contract exists to prevent.
    func binding(
        for assets: [SVGAsset],
        manualAssignments: [String: HotkeyShortcut]
    ) throws -> ManifestBinding {
        let assetsByName = Dictionary(
            assets.map { (Self.matchKey($0.id), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var manifestAssignments: [String: HotkeyShortcut] = [:]
        var unmatched: [String] = []
        var hideShortcut: HotkeyShortcut?

        for layer in layers {
            guard let shortcut = Self.shortcut(forSignal: layer.signal) else {
                throw LayerManifestError.unknownSignal(layer: layer.name, signal: layer.signal)
            }

            // Index 0 is the resting layer. Every momentary layer returns to it on
            // release, so its signal is what tells us the hold ended -- it dismisses the
            // overlay instead of drawing one. Its SVG stays bindable by hand for anyone
            // who wants to call the base layout up deliberately.
            guard layer.index != Self.restingLayerIndex else {
                hideShortcut = shortcut
                continue
            }

            guard let asset = assetsByName[Self.matchKey(layer.svg)] else {
                unmatched.append(layer.name)
                continue
            }

            manifestAssignments[asset.id] = shortcut
        }

        // The manifest is authoritative for the assets it names and the signals it claims,
        // so manual entries colliding on either side lose. Surviving manual entries are
        // then deduped against each other: HotkeyTriggerSource keys its map by shortcut,
        // so two assets sharing one shortcut means an arbitrary winner and a binding that
        // silently never fires. Walking sorted asset IDs makes the winner stable, so a
        // re-sync does not shuffle which one survives.
        var merged = manifestAssignments
        var claimedSignals = Set(manifestAssignments.values)
        var dropped: [String] = []

        if let hideShortcut {
            claimedSignals.insert(hideShortcut)
        }

        for assetID in manualAssignments.keys.sorted() {
            guard let shortcut = manualAssignments[assetID] else { continue }
            guard manifestAssignments[assetID] == nil else { continue }

            guard !claimedSignals.contains(shortcut) else {
                dropped.append(assetID)
                continue
            }

            merged[assetID] = shortcut
            claimedSignals.insert(shortcut)
        }

        return ManifestBinding(
            assignments: merged,
            layerAssetIDs: manifestAssignments.keys.sorted(),
            hideShortcut: hideShortcut,
            unmatchedLayers: unmatched,
            droppedManualBindings: dropped
        )
    }
}
