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
}
