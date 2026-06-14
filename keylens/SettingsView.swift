import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var recorder = HotkeyRecorderController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageSourceCard
                overlayCard
                hotkeyCard
                permissionsCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 700, minHeight: 700)
        .onDisappear {
            recorder.stopRecording()
        }
    }

    private var imageSourceCard: some View {
        SettingsCard(
            title: "Image Source",
            subtitle: imageSourceSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("Source") {
                    Picker("", selection: svgSourceTypeBinding) {
                        ForEach(SVGSourceType.allCases) { sourceType in
                            Text(sourceType.title).tag(sourceType)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                if settings.configuration.svgSourceType == .repository {
                    settingRow("Repository") {
                        TextField("https://github.com/<owner>/<repo>", text: repositoryURLBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    settingRow("Branch") {
                        HStack(spacing: 10) {
                            Picker("", selection: repositoryBranchBinding) {
                                Text("Default").tag(String?.none)
                                ForEach(branchOptions, id: \.self) { branch in
                                    Text(branch).tag(Optional(branch))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220, alignment: .leading)

                            Button(settings.isLoadingRepositoryBranches ? "Loading…" : "Load Branches") {
                                settings.refreshRepositoryBranches()
                            }
                            .disabled(settings.isLoadingRepositoryBranches || settings.configuration.repositoryURL.isEmpty)

                            if settings.isLoadingRepositoryBranches {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                } else {
                    settingRow("Directory") {
                        HStack(spacing: 10) {
                            TextField("/path/to/svg-directory", text: localDirectoryPathBinding)
                                .textFieldStyle(.roundedBorder)

                            Button("Choose…") {
                                chooseLocalDirectory()
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(settings.isSyncingRepository ? "Syncing…" : "Sync SVGs") {
                        settings.syncSVGRepository()
                    }
                    .disabled(settings.isSyncingRepository)

                    if settings.isSyncingRepository {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 14) {
                    Text("SVGs found: \(settings.configuration.svgAssets.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if settings.configuration.svgSourceType == .repository {
                        if let branch = settings.configuration.repositoryBranch {
                            Text("Branch: \(branch)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Branch: Default")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Source: Local Directory")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = settings.repositorySyncMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var overlayCard: some View {
        SettingsCard(title: "Overlay") {
            VStack(alignment: .leading, spacing: 10) {
                settingRow("Show time") {
                    Slider(
                        value: durationBinding,
                        in: 0.2 ... 10.0,
                        step: 0.1
                    )
                }

                settingRow("Location") {
                    Picker("", selection: overlayPlacementBinding) {
                        ForEach(OverlayPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)
                }

                Text("\(settings.configuration.overlayDuration, specifier: "%.1f") seconds")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hotkeyCard: some View {
        SettingsCard(title: "Hotkeys") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("End Active Hold")
                                .font(.headline)

                            Text("Use this for the firmware release sentinel, currently Right Shift. It only hides the current hold overlay and keeps latched toggles intact.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            globalClearHotkeyRecorderButton()

                            Button("Clear") {
                                settings.setClearHoldShortcut(nil)
                                if recorder.recordingTarget == .clearHold {
                                    recorder.stopRecording()
                                }
                            }
                            .disabled(settings.clearHoldShortcut() == nil)
                        }
                    }

                    if !settings.configuration.svgAssets.isEmpty {
                        Divider()
                    }
                }

                if settings.configuration.svgAssets.isEmpty {
                    Text("No SVG files synced yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.configuration.svgAssets) { asset in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.fileName)
                                        .font(.headline)

                                    Picker("Behavior", selection: activationModeBinding(for: asset.id)) {
                                        ForEach(HotkeyActivationMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 360)

                                    if settings.activationMode(for: asset.id) == .tapHold {
                                        Text("Tap toggles. Hold for 0.5 seconds to show while pressed.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 12)

                                HStack(spacing: 10) {
                                    hotkeyRecorderButton(for: asset.id)

                                    Button("Clear") {
                                        settings.setShortcut(nil, for: asset.id)
                                        if recorder.recordingTarget == .asset(asset.id) {
                                            recorder.stopRecording()
                                        }
                                    }
                                    .disabled(settings.shortcut(for: asset.id) == nil)
                                }
                            }

                            if asset.id != settings.configuration.svgAssets.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var permissionsCard: some View {
        SettingsCard(title: "Hotkey Permissions") {
            Text("Keylens needs Input Monitoring permission for global hotkeys. If hotkeys stop while typing in terminal apps, disable Secure Keyboard Entry in that app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var branchOptions: [String] {
        var options = settings.availableRepositoryBranches
        if let selectedBranch = settings.configuration.repositoryBranch,
           !selectedBranch.isEmpty,
           !options.contains(selectedBranch) {
            options.insert(selectedBranch, at: 0)
        }
        return options
    }

    private var imageSourceSubtitle: String {
        switch settings.configuration.svgSourceType {
        case .repository:
            return "Repository must contain keymap-drawer/img with SVG files."
        case .localDirectory:
            return "Choose a local directory containing SVG files."
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            content()
        }
    }

    private func hotkeyRecorderButton(for assetID: String) -> some View {
        let isRecording = recorder.recordingTarget == .asset(assetID)
        let title = isRecording
            ? "Press keys…"
            : settings.hotkeyDescription(for: settings.shortcut(for: assetID))

        return Button {
            recorder.startRecording(for: .asset(assetID)) { shortcut in
                settings.setShortcut(shortcut, for: assetID)
            }
        } label: {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 230, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isRecording ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func globalClearHotkeyRecorderButton() -> some View {
        let isRecording = recorder.recordingTarget == .clearHold
        let title = isRecording
            ? "Press keys…"
            : settings.hotkeyDescription(for: settings.clearHoldShortcut())

        return Button {
            recorder.startRecording(for: .clearHold) { shortcut in
                settings.setClearHoldShortcut(shortcut)
            }
        } label: {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 230, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isRecording ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"

        let currentPath = settings.configuration.localDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentPath.isEmpty {
            let expanded = NSString(string: currentPath).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.updateLocalDirectoryPath(selectedURL.path)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }
}

@MainActor
private final class HotkeyRecorderController: ObservableObject {
    enum RecordingTarget: Equatable {
        case asset(String)
        case clearHold
    }

    @Published private(set) var recordingTarget: RecordingTarget?

    private var localMonitor: Any?
    private var onCapture: ((HotkeyShortcut?) -> Void)?

    func startRecording(for target: RecordingTarget, onCapture: @escaping (HotkeyShortcut?) -> Void) {
        stopRecording()

        recordingTarget = target
        self.onCapture = onCapture

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        localMonitor = nil
        recordingTarget = nil
        onCapture = nil
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recordingTarget != nil else {
            return event
        }

        switch event.type {
        case .keyDown:
            let keyCode = event.keyCode

            if keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
                onCapture?(nil)
                stopRecording()
                return nil
            }

            let shortcut = HotkeyShortcut(
                keyCode: CGKeyCode(keyCode),
                modifiers: Self.cgFlags(from: event.modifierFlags)
            )

            onCapture?(shortcut)
            stopRecording()
            return nil

        case .flagsChanged:
            let keyCode = event.keyCode

            guard let changedModifier = Self.modifierFlag(for: keyCode) else {
                return nil
            }

            let flags = Self.cgFlags(from: event.modifierFlags)
            guard flags.contains(changedModifier) else {
                // Modifier key-up events should not arm shortcuts.
                return nil
            }

            let shortcut = HotkeyShortcut(
                keyCode: CGKeyCode(keyCode),
                modifiers: flags
            )

            onCapture?(shortcut)
            stopRecording()
            return nil

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            stopRecording()
            return event

        default:
            return event
        }
    }

    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        let relevant = flags.intersection([.command, .option, .control, .shift, .function, .capsLock])
        var cgFlags: CGEventFlags = []

        if relevant.contains(.command) {
            cgFlags.insert(.maskCommand)
        }
        if relevant.contains(.option) {
            cgFlags.insert(.maskAlternate)
        }
        if relevant.contains(.control) {
            cgFlags.insert(.maskControl)
        }
        if relevant.contains(.shift) {
            cgFlags.insert(.maskShift)
        }
        if relevant.contains(.function) {
            cgFlags.insert(.maskSecondaryFn)
        }
        if relevant.contains(.capsLock) {
            cgFlags.insert(.maskAlphaShift)
        }

        return cgFlags
    }

    private static func modifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand:
            return .maskCommand
        case kVK_Option, kVK_RightOption:
            return .maskAlternate
        case kVK_Control, kVK_RightControl:
            return .maskControl
        case kVK_Shift, kVK_RightShift:
            return .maskShift
        case kVK_Function:
            return .maskSecondaryFn
        case kVK_CapsLock:
            return .maskAlphaShift
        default:
            return nil
        }
    }
}

extension SettingsView {
    private var svgSourceTypeBinding: Binding<SVGSourceType> {
        Binding(
            get: { settings.configuration.svgSourceType },
            set: { settings.updateSVGSourceType($0) }
        )
    }

    private var repositoryURLBinding: Binding<String> {
        Binding(
            get: { settings.configuration.repositoryURL },
            set: { settings.updateRepositoryURL($0) }
        )
    }

    private var repositoryBranchBinding: Binding<String?> {
        Binding(
            get: { settings.configuration.repositoryBranch },
            set: { settings.updateRepositoryBranch($0) }
        )
    }

    private var localDirectoryPathBinding: Binding<String> {
        Binding(
            get: { settings.configuration.localDirectoryPath },
            set: { settings.updateLocalDirectoryPath($0) }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { settings.configuration.overlayDuration },
            set: { settings.updateOverlayDuration($0) }
        )
    }

    private var overlayPlacementBinding: Binding<OverlayPlacement> {
        Binding(
            get: { settings.configuration.overlayPlacement },
            set: { settings.updateOverlayPlacement($0) }
        )
    }

    private func activationModeBinding(for assetID: String) -> Binding<HotkeyActivationMode> {
        Binding(
            get: { settings.activationMode(for: assetID) },
            set: { settings.setActivationMode($0, for: assetID) }
        )
    }
}
