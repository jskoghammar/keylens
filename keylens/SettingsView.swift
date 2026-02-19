import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Form {
                    Section("Image Source") {
                        TextField("https://github.com/<owner>/<repo>", text: repositoryURLBinding)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Button(settings.isSyncingRepository ? "Syncing…" : "Sync SVGs") {
                                settings.syncSVGRepository()
                            }
                            .disabled(settings.isSyncingRepository)

                            if settings.isSyncingRepository {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Text("Repository must contain keymap-drawer/img with SVG files.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("SVGs found: \(settings.configuration.svgAssets.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let message = settings.repositorySyncMessage, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Overlay") {
                        Slider(
                            value: durationBinding,
                            in: 0.2 ... 10.0,
                            step: 0.1
                        )

                        Text("Show time: \(settings.configuration.overlayDuration, specifier: "%.1f") seconds")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Hotkey Permissions") {
                        Text("Keylens needs Input Monitoring permission for global hotkeys. If hotkeys stop while typing in terminal apps, disable Secure Keyboard Entry in that app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                hotkeyAssignmentSection
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    @ViewBuilder
    private var hotkeyAssignmentSection: some View {
        GroupBox("Per-SVG Hotkeys") {
            VStack(alignment: .leading, spacing: 14) {
                if settings.configuration.svgAssets.isEmpty {
                    Text("No SVG files synced yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(settings.configuration.svgAssets) { asset in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(asset.fileName)
                                .font(.headline)

                            HStack(spacing: 10) {
                                Picker("Key", selection: keySelectionBinding(for: asset.id)) {
                                    Text("Unassigned").tag(-1)
                                    ForEach(KeyChoice.all) { choice in
                                        Text(choice.title).tag(Int(choice.id))
                                    }
                                }
                                .frame(width: 180)

                                Toggle("Cmd", isOn: modifierBinding(for: asset.id, modifier: .maskCommand))
                                    .disabled(settings.shortcut(for: asset.id) == nil)
                                Toggle("Opt", isOn: modifierBinding(for: asset.id, modifier: .maskAlternate))
                                    .disabled(settings.shortcut(for: asset.id) == nil)
                                Toggle("Ctrl", isOn: modifierBinding(for: asset.id, modifier: .maskControl))
                                    .disabled(settings.shortcut(for: asset.id) == nil)
                                Toggle("Shift", isOn: modifierBinding(for: asset.id, modifier: .maskShift))
                                    .disabled(settings.shortcut(for: asset.id) == nil)
                            }

                            Text("Current: \(settings.hotkeyDescription(for: settings.shortcut(for: asset.id)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                    }
                }
            }
            .padding(12)
        }
    }

    private var repositoryURLBinding: Binding<String> {
        Binding(
            get: { settings.configuration.repositoryURL },
            set: { settings.updateRepositoryURL($0) }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { settings.configuration.overlayDuration },
            set: { settings.updateOverlayDuration($0) }
        )
    }

    private func keySelectionBinding(for assetID: String) -> Binding<Int> {
        Binding(
            get: {
                if let shortcut = settings.shortcut(for: assetID) {
                    return Int(shortcut.keyCode)
                }
                return -1
            },
            set: { newValue in
                if newValue < 0 {
                    settings.setShortcut(nil, for: assetID)
                    return
                }

                let keyCode = CGKeyCode(UInt16(newValue))
                let modifiers = settings.shortcut(for: assetID)?.cgModifiers ?? []
                settings.setShortcut(HotkeyShortcut(keyCode: keyCode, modifiers: modifiers), for: assetID)
            }
        )
    }

    private func modifierBinding(for assetID: String, modifier: CGEventFlags) -> Binding<Bool> {
        Binding(
            get: {
                settings.shortcut(for: assetID)?.hasModifier(modifier) ?? false
            },
            set: { enabled in
                guard let shortcut = settings.shortcut(for: assetID) else { return }
                settings.setShortcut(shortcut.withModifier(modifier, enabled: enabled), for: assetID)
            }
        )
    }
}
