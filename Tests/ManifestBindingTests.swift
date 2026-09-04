// Standalone checks for the keymap manifest contract. The project has no test
// target (keylens.xcodeproj uses a file-system synchronized group, so anything
// under keylens/ would be compiled into the app), so this runs via swiftc:
//
//   swiftc -o /tmp/manifest-test \
//     keylens/LayerManifest.swift keylens/AppConfiguration.swift \
//     keylens/SVGRepositorySyncService.swift Tests/ManifestBindingTests.swift \
//     && /tmp/manifest-test
//
// Only one @main file can live here, so additional checks belong in this file
// rather than a sibling.
//
// The fixture below is issue 05's specified layers.json schema. When CI starts
// emitting the real file, re-run this against it before trusting the bindings.

import Carbon.HIToolbox
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool) {
    if condition { print("  ok   \(label)") } else { failures += 1; print("  FAIL \(label)") }
}

// SVGAsset.id is the repo path; the manifest names SVGs relative to keymap-drawer.
func asset(_ name: String) -> SVGAsset {
    SVGAsset(id: "keymap-drawer/img/\(name)", fileName: name,
             sourceURL: "https://example.invalid/\(name)", localFilePath: "/tmp/\(name)")
}

@main
struct ManifestBindingTests {
    static func main() throws {
        // Exactly the shape issue 05 specifies CI will emit.
        let json = """
        {"commit": "9f3c1ade7b2145c0be1f0a9d8e77c3b2a1d4e5f6", "layers": [
          {"index": 1, "name": "Sym", "svg": "img/corne-sym.svg", "signal": "F14"},
          {"index": 2, "name": "Nav", "svg": "img/corne-nav.svg", "signal": "F15"},
          {"index": 3, "name": "BT",  "svg": "img/corne-bt.svg",  "signal": "F16"}]}
        """

        print("decode")
        let manifest = try LayerManifest.decode(Data(json.utf8))
        check("commit read", manifest.commit.hasPrefix("9f3c1ad"))
        check("short commit is 7 chars", manifest.shortCommit == "9f3c1ad")
        check("three layers", manifest.layers.count == 3)
        check("layer fields", manifest.layers[0] == .init(index: 1, name: "Sym", svg: "img/corne-sym.svg", signal: "F14"))

        print("signal mapping")
        check("F14 -> kVK_F14, bare", LayerManifest.shortcut(forSignal: "F14")
            == HotkeyShortcut(keyCode: CGKeyCode(kVK_F14), modifiers: []))
        check("F16 -> kVK_F16", LayerManifest.shortcut(forSignal: "F16")?.keyCode == UInt16(kVK_F16))
        check("no modifiers attached", LayerManifest.shortcut(forSignal: "F14")?.cgModifiers.isEmpty == true)
        check("whitespace/case tolerated", LayerManifest.shortcut(forSignal: " f15 ")?.keyCode == UInt16(kVK_F15))
        check("unknown signal -> nil", LayerManifest.shortcut(forSignal: "F99") == nil)

        let assets = [asset("corne-sym.svg"), asset("corne-nav.svg"), asset("corne-bt.svg"), asset("corne-base.svg")]

        print("binding")
        let bound = try manifest.binding(for: assets, manualAssignments: [:])
        check("all three layers matched across the path-prefix mismatch", bound.assignments.count == 3)
        check("sym bound to bare F14",
              bound.assignments["keymap-drawer/img/corne-sym.svg"] == HotkeyShortcut(keyCode: CGKeyCode(kVK_F14), modifiers: []))
        check("nothing bound for the unlisted base SVG", bound.assignments["keymap-drawer/img/corne-base.svg"] == nil)
        check("no unmatched layers", bound.unmatchedLayers.isEmpty)

        print("manual hotkeys")
        let manualOnUnlisted = HotkeyShortcut(keyCode: CGKeyCode(kVK_ANSI_B), modifiers: [.maskControl, .maskShift])
        let merged = try manifest.binding(for: assets, manualAssignments: [
            "keymap-drawer/img/corne-base.svg": manualOnUnlisted,
            // manifest owns this asset -- manual entry must lose
            "keymap-drawer/img/corne-sym.svg": HotkeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Z), modifiers: [.maskCommand]),
            // manual binding squatting a signal the manifest claims -- must lose too
            "keymap-drawer/img/corne-nav.svg": HotkeyShortcut(keyCode: CGKeyCode(kVK_F16), modifiers: [])
        ])
        check("manual binding survives for unlisted asset",
              merged.assignments["keymap-drawer/img/corne-base.svg"] == manualOnUnlisted)
        check("surviving manual binding is not classified as a held layer",
              !merged.layerAssetIDs.contains("keymap-drawer/img/corne-base.svg"))
        check("manifest-named assets are the held ones",
              merged.layerAssetIDs == ["keymap-drawer/img/corne-bt.svg",
                                       "keymap-drawer/img/corne-nav.svg",
                                       "keymap-drawer/img/corne-sym.svg"])
        check("manifest overrides manual on an asset it names",
              merged.assignments["keymap-drawer/img/corne-sym.svg"]?.keyCode == UInt16(kVK_F14))
        check("one shortcut -> one asset preserved", Set(merged.assignments.values).count == merged.assignments.count)

        // HotkeyTriggerSource keys its map by shortcut, so duplicates among the
        // *surviving manual* entries are a silently-dead binding. The manifest-claims-it
        // case above does not cover this one.
        print("duplicate manual shortcuts")
        let symOnly = try LayerManifest.decode(Data("""
        {"commit":"abc1234","layers":[{"index":1,"name":"Sym","svg":"img/corne-sym.svg","signal":"F14"}]}
        """.utf8))
        let shared = HotkeyShortcut(keyCode: CGKeyCode(kVK_ANSI_G), modifiers: [.maskControl, .maskShift])
        let deduped = try symOnly.binding(for: assets, manualAssignments: [
            "keymap-drawer/img/corne-base.svg": shared,
            "keymap-drawer/img/corne-nav.svg": shared
        ])
        check("duplicate manual shortcut dropped",
              Set(deduped.assignments.values).count == deduped.assignments.count)
        check("stable winner is the first sorted asset ID",
              deduped.assignments["keymap-drawer/img/corne-base.svg"] == shared)
        check("loser reported, not silent",
              deduped.droppedManualBindings == ["keymap-drawer/img/corne-nav.svg"])
        check("re-running gives the same winner",
              try symOnly.binding(for: assets, manualAssignments: [
                  "keymap-drawer/img/corne-nav.svg": shared,
                  "keymap-drawer/img/corne-base.svg": shared
              ]).assignments == deduped.assignments)

        // Index 0 is the resting layer: its signal dismisses the overlay rather than
        // drawing one, so it must not appear as an assignment.
        print("resting layer")
        let withBase = try LayerManifest.decode(Data("""
        {"commit":"abc1234","layers":[
          {"index":0,"name":"Base","svg":"img/corne-base.svg","signal":"F13"},
          {"index":1,"name":"Sym","svg":"img/corne-sym.svg","signal":"F14"}]}
        """.utf8))
        let resting = try withBase.binding(for: assets, manualAssignments: [:])
        check("index 0 becomes the hide signal",
              resting.hideShortcut == HotkeyShortcut(keyCode: CGKeyCode(kVK_F13), modifiers: []))
        check("base SVG is not auto-bound to show",
              resting.assignments["keymap-drawer/img/corne-base.svg"] == nil)
        check("only the non-resting layer is bound", resting.assignments.count == 1)
        check("base without an SVG is not reported as drift", resting.unmatchedLayers.isEmpty)

        // Nothing may squat the hide signal, or the overlay becomes undismissable.
        let squatter = try withBase.binding(for: assets, manualAssignments: [
            "keymap-drawer/img/corne-nav.svg": HotkeyShortcut(keyCode: CGKeyCode(kVK_F13), modifiers: [])
        ])
        check("manual binding cannot claim the hide signal",
              squatter.assignments["keymap-drawer/img/corne-nav.svg"] == nil)
        check("the squatter is reported",
              squatter.droppedManualBindings == ["keymap-drawer/img/corne-nav.svg"])

        // The manifest we already decoded has no index 0 at all.
        check("no resting layer means no hide signal", try manifest
              .binding(for: assets, manualAssignments: [:]).hideShortcut == nil)

        print("drift")
        let missingSVG = try manifest.binding(for: [asset("corne-sym.svg")], manualAssignments: [:])
        check("layer without an SVG is reported, not fatal", missingSVG.unmatchedLayers == ["Nav", "BT"])
        check("matched layer still bound", missingSVG.assignments.count == 1)

        let badSignal = """
        {"commit":"abc1234","layers":[{"index":1,"name":"Sym","svg":"img/corne-sym.svg","signal":"RSHFT"}]}
        """
        do {
            _ = try LayerManifest.decode(Data(badSignal.utf8)).binding(for: assets, manualAssignments: [:])
            check("unknown signal throws", false)
        } catch let error as LayerManifestError {
            check("unknown signal throws", error == .unknownSignal(layer: "Sym", signal: "RSHFT"))
            check("error names the layer and signal", error.errorDescription?.contains("RSHFT") == true)
        }

        do {
            _ = try LayerManifest.decode(Data("{\"layers\": []}".utf8))
            check("malformed manifest throws", false)
        } catch let error as LayerManifestError {
            check("malformed manifest throws", error == .malformedManifest)
        }

        // manifestCommit was added to an already-persisted Codable struct. If the
        // whole-struct decode in loadConfiguration ever fails, the user silently falls
        // through to legacy migration and loses their repo URL, branch and hotkeys --
        // so confirm v2 blobs written before this field still decode intact.
        print("backward compatibility")
        let legacyBlob = """
        {"repositoryURL":"https://github.com/jskoghammar/corne_v4","repositoryBranch":"sym",
         "svgAssets":[{"id":"keymap-drawer/img/corne-sym.svg","fileName":"corne-sym.svg",
                       "sourceURL":"https://example.invalid/x","localFilePath":"/tmp/x"}],
         "hotkeyAssignments":{"keymap-drawer/img/corne-sym.svg":{"keyCode":123,"modifiersRawValue":786432}},
         "overlayDuration":1.6}
        """
        let restored = try JSONDecoder().decode(AppConfiguration.self, from: Data(legacyBlob.utf8))
        check("pre-manifest config still decodes", restored.repositoryURL.hasSuffix("corne_v4"))
        check("branch pin survives", restored.repositoryBranch == "sym")
        check("assets survive", restored.svgAssets.count == 1)
        check("manual hotkeys survive", restored.hotkeyAssignments.count == 1)
        check("duration survives", restored.overlayDuration == 1.6)
        check("missing manifestCommit decodes as nil", restored.manifestCommit == nil)
        check("missing layerAssetIDs decodes as empty, not a decode failure",
              restored.layerAssetIDs.isEmpty)
        check("missing hideShortcut decodes as nil", restored.hideShortcut == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
