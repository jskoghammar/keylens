// Standalone checks for hotkey label rendering. The project has no test target
// (keylens.xcodeproj uses a file-system synchronized group, so anything under
// keylens/ compiles into the app), so this runs via swiftc. Only one @main file
// can live here, so further checks belong in this file rather than a sibling.
//
//   swiftc -o /tmp/label-test \
//     keylens/AppConfiguration.swift keylens/SVGRepositorySyncService.swift \
//     Tests/HotkeyLabelTests.swift && /tmp/label-test

import Carbon.HIToolbox
import CoreGraphics
import Foundation

@main struct LabelTests {
  static func main() {
    var failures = 0
    func check(_ label: String, _ got: String, _ want: String) {
      if got == want { print("  ok   \(label): \"\(got)\"") }
      else { failures += 1; print("  FAIL \(label): got \"\(got)\" want \"\(want)\"") }
    }
    func sc(_ k: Int, _ m: CGEventFlags) -> HotkeyShortcut {
      HotkeyShortcut(keyCode: CGKeyCode(k), modifiers: m)
    }

    // The binding that started this: previously rendered "Ctrl + KeyCode 59".
    check("left control tap", KeyChoice.description(for: sc(kVK_Control, [.maskControl])),
          "Left Control (tap)")
    // The one the firmware actually sends for a layer today.
    check("right control tap", KeyChoice.description(for: sc(kVK_RightControl, [.maskControl])),
          "Right Control (tap)")
    check("right command tap", KeyChoice.description(for: sc(kVK_RightCommand, [.maskCommand])),
          "Right Command (tap)")
    // A held modifier that the tapped key does not itself contribute must survive.
    check("cmd held + right control tapped",
          KeyChoice.description(for: sc(kVK_RightControl, [.maskControl, .maskCommand])),
          "Cmd + Right Control (tap)")
    // Ordinary combinations must be unchanged.
    check("ctrl+opt+left arrow", KeyChoice.description(for: sc(kVK_LeftArrow, [.maskControl, .maskAlternate])),
          "Opt + Ctrl + Left Arrow")
    check("bare F14", KeyChoice.description(for: sc(kVK_F14, [])), "F14")
    check("bare space named", KeyChoice.description(for: sc(kVK_Space, [])), "Space")
    check("ctrl+return", KeyChoice.description(for: sc(kVK_Return, [.maskControl])), "Ctrl + Return")
    check("genuinely unknown key still falls back",
          KeyChoice.description(for: sc(kVK_ANSI_Grave, [])), "KeyCode 50")
    check("shift+A", KeyChoice.description(for: sc(kVK_ANSI_A, [.maskShift])), "Shift + A")

    print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
  }
}
