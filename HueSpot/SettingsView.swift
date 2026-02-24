// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Layout {
        static let windowWidth: CGFloat = 620
        static let horizontalPaddingLeading: CGFloat = 20
        static let horizontalPaddingTrailing: CGFloat = 14
        static let clipboardLabelWidth: CGFloat = 106
        static let clipboardPickerWidth: CGFloat = 300
    }

    private static let screenRecordingSettingsURLs: [URL] = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCaptureAndSystemAudio",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCaptureAndSystemAudio",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.preference.security",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    ].compactMap(URL.init(string:))

    @ObservedObject var model: AppModel

    @State private var isRecordingHotkey = false
    @State private var showWebInfoPinned = false
    private let webInfoText = "Standard CSS/HTML web color names, plus additional names derived from Wikipedia's list of colors."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            generalSection
            Divider()
            activationKeySection
            Divider()
            overlaySection
            Divider()
            clipboardSection
        }
        .padding(.top, 20)
        .padding(.leading, Layout.horizontalPaddingLeading)
        .padding(.trailing, Layout.horizontalPaddingTrailing)
        .padding(.bottom, 16)
        .frame(width: Layout.windowWidth)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
        .onDisappear { model.setHotkeyCaptureInProgress(false) }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.headline)

            Toggle("Launch automatically at login", isOn: $model.launchAtLogin)
                .toggleStyle(.checkbox)

            Text("HueSpot needs Screen Recording permission to sample colors.\nUse the buttons below to request access or open the right settings page.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Request Screen Recording") {
                    model.requestScreenCapturePermissionIfNeeded()
                }
                Button("Open Screen Recording Settings") {
                    openScreenRecordingSettings()
                }
            }
        }
    }

    private var activationKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activation Key")
                .font(.headline)

            Text("Pressing the activation key will show the HueSpot overlay\nwith information about the color at the current mouse position.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(model.hotkey.displayString())
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minWidth: 180, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button(isRecordingHotkey ? "Press a key..." : "Change") {
                    let shouldRecord = !isRecordingHotkey
                    model.setHotkeyCaptureInProgress(shouldRecord)
                    isRecordingHotkey = shouldRecord
                }
            }
            .background(
                HotkeyRecorder(onChange: { newHotkey in
                    model.hotkey = newHotkey
                    model.setHotkeyCaptureInProgress(false)
                    isRecordingHotkey = false
                }, isRecording: $isRecordingHotkey)
            )
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overlay")
                .font(.headline)

            Text("Simple Color Name is always shown.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("ISSC-NAB Extended Color Name", isOn: $model.showISCCNABColorNameInOverlay)
                .toggleStyle(.checkbox)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Toggle("Web Color or Wikipedia Name", isOn: $model.showWebColorNameInOverlay)
                    .toggleStyle(.checkbox)
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        showWebInfoPinned.toggle()
                    }
                    .help(webInfoText)
                    .popover(isPresented: $showWebInfoPinned, arrowEdge: .top) {
                        Text(webInfoText)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .frame(width: 420)
                    }
            }

            Toggle("RGB Hexadecimal", isOn: $model.showHexInOverlay)
                .toggleStyle(.checkbox)
        }
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clipboard")
                .font(.headline)

            Toggle("Copy color when double-pressing activation key", isOn: $model.copyOnDoublePress)
                .toggleStyle(.checkbox)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Clipboard format:")
                    .frame(width: Layout.clipboardLabelWidth, alignment: .leading)

                Picker("Clipboard format:", selection: $model.clipboardFormat) {
                    ForEach(AppModel.ClipboardFormatSection.allCases) { section in
                        Section {
                            ForEach(section.formats) { format in
                                Text(format.label).tag(format)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: Layout.clipboardPickerWidth, alignment: .leading)
            }
        }
    }

    private func openScreenRecordingSettings() {
        for url in Self.screenRecordingSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }
}
