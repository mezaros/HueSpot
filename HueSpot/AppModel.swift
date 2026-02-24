import Foundation
import AppKit
import Combine
import ServiceManagement

/// Central application state and orchestration for hotkey handling,
/// screen sampling, overlay updates, and clipboard export.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - Clipboard Format

    enum ClipboardFormat: String, CaseIterable, Identifiable {
        case rgbHexadecimal
        case rgbHexadecimalWithHash
        case rgbHexadecimalWith0x
        case rgbHexadecimalWithSpaces
        case minimalColorName
        case isccNBSColorName
        case webColorOrWikipediaName = "webColorOrCustomName"
        case cssRGBIntegers
        case cssRGBPercentages
        case cssRGBAIntegers
        case cssRGBAPercentages
        case nsColorSRGBSwift
        case nsColorSRGBObjC
        case uiColorRGBSwift
        case uiColorRGBObjC

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rgbHexadecimal:
                return "RGB Hexadecimal"
            case .rgbHexadecimalWithHash:
                return "RGB Hexadecimal with #"
            case .rgbHexadecimalWith0x:
                return "RGB Hexadecimal with 0x"
            case .rgbHexadecimalWithSpaces:
                return "RGB Hexadecimal with spaces"
            case .minimalColorName:
                return "Simple Color Name"
            case .isccNBSColorName:
                return "ISSC-NAB Extended Color Name"
            case .webColorOrWikipediaName:
                return "Web Color or Wikipedia Name"
            case .cssRGBIntegers:
                return "CSS rgb() with integers"
            case .cssRGBPercentages:
                return "CSS rgb() with percentages"
            case .cssRGBAIntegers:
                return "CSS rgba() with integers"
            case .cssRGBAPercentages:
                return "CSS rgba() with percentages"
            case .nsColorSRGBSwift:
                return "NSColor sRGB (Swift)"
            case .nsColorSRGBObjC:
                return "NSColor sRGB (Objective-C)"
            case .uiColorRGBSwift:
                return "UIColor RGB (Swift)"
            case .uiColorRGBObjC:
                return "UIColor RGB (Objective-C)"
            }
        }
    }

    enum ClipboardFormatSection: CaseIterable, Identifiable {
        case hexadecimal
        case name
        case cssRGB
        case cssRGBA
        case nsColor
        case uiColor

        var id: String {
            switch self {
            case .hexadecimal: return "hexadecimal"
            case .name: return "name"
            case .cssRGB: return "css-rgb"
            case .cssRGBA: return "css-rgba"
            case .nsColor: return "nscolor"
            case .uiColor: return "uicolor"
            }
        }

        var formats: [ClipboardFormat] {
            switch self {
            case .hexadecimal:
                return [.rgbHexadecimal, .rgbHexadecimalWithHash, .rgbHexadecimalWith0x, .rgbHexadecimalWithSpaces]
            case .name:
                return [.minimalColorName, .isccNBSColorName, .webColorOrWikipediaName]
            case .cssRGB:
                return [.cssRGBIntegers, .cssRGBPercentages]
            case .cssRGBA:
                return [.cssRGBAIntegers, .cssRGBAPercentages]
            case .nsColor:
                return [.nsColorSRGBSwift, .nsColorSRGBObjC]
            case .uiColor:
                return [.uiColorRGBSwift, .uiColorRGBObjC]
            }
        }
    }

    // MARK: - Published State

    @Published var isActive: Bool = false
    @Published var colorNames: ColorNames = ColorNames(simplified: "", detailed: "")
    @Published var hex: String = ""
    @Published var lastSampleColor: NSColor = .clear
    @Published var copyFeedback: String = ""
    @Published var copyOnDoublePress: Bool {
        didSet {
            UserDefaults.standard.set(copyOnDoublePress, forKey: Self.copyOnDoublePressKey)
        }
    }
    @Published var clipboardFormat: ClipboardFormat {
        didSet {
            UserDefaults.standard.set(clipboardFormat.rawValue, forKey: Self.clipboardFormatKey)
        }
    }
    @Published var showISCCNABColorNameInOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showISCCNABColorNameInOverlay, forKey: Self.showISCCNABColorNameInOverlayKey)
        }
    }
    @Published var showWebColorNameInOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showWebColorNameInOverlay, forKey: Self.showWebColorNameInOverlayKey)
        }
    }
    @Published var showHexInOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showHexInOverlay, forKey: Self.showHexInOverlayKey)
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
            configureLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: - Runtime State

    private var hotkeyManager: HotkeyManager?
    private var timer: DispatchSourceTimer?
    private var hudController: HUDWindowController?
    private var samplingInFlight = false
    private var consecutiveSampleMisses = 0
    private var blockSamplingUntilPermissionRefresh = false
    private var lastHotkeyPressAt: Date?
    private var copyFeedbackResetTask: DispatchWorkItem?
    private var fadeOutHUDOnNextStop = false
    private var hotkeyCaptureInProgress = false
    private var suppressHotkeyUntil = Date.distantPast

    // MARK: - Persistence Keys

    private static let hotkeyKey = "Hotkey"
    private static let copyOnDoublePressKey = "CopyOnDoublePress"
    private static let clipboardFormatKey = "ClipboardFormat"
    private static let showISCCNABColorNameInOverlayKey = "ShowISCCNABColorNameInOverlay"
    private static let showWebColorNameInOverlayKey = "ShowWebColorNameInOverlay"
    private static let showHexInOverlayKey = "ShowHexInOverlay"
    private static let launchAtLoginKey = "LaunchAtLogin"
    private let doublePressInterval: TimeInterval = 0.45
    private let hotkeyRearmDelayAfterRecording: TimeInterval = 0.45
    private var isUpdatingLaunchAtLogin = false

    // MARK: - Init

    private init() {
        if UserDefaults.standard.object(forKey: Self.copyOnDoublePressKey) == nil {
            copyOnDoublePress = true
        } else {
            copyOnDoublePress = UserDefaults.standard.bool(forKey: Self.copyOnDoublePressKey)
        }
        clipboardFormat = ClipboardFormat(
            rawValue: UserDefaults.standard.string(forKey: Self.clipboardFormatKey) ?? ""
        ) ?? .rgbHexadecimal
        showISCCNABColorNameInOverlay = Self.defaultedBool(for: Self.showISCCNABColorNameInOverlayKey)
        showWebColorNameInOverlay = Self.defaultedBool(for: Self.showWebColorNameInOverlayKey)
        showHexInOverlay = Self.defaultedBool(for: Self.showHexInOverlayKey)
        launchAtLogin = Self.defaultedBool(for: Self.launchAtLoginKey, defaultValue: false)
        configureLaunchAtLogin(launchAtLogin)
    }

    // MARK: - Public API

    var hotkey: Hotkey {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.hotkeyKey),
               let value = try? JSONDecoder().decode(Hotkey.self, from: data) {
                return value
            }
            return .rightControl
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.hotkeyKey)
            }
            hotkeyManager?.updateHotkey(newValue)
        }
    }

    func start() {
        if hudController == nil {
            hudController = HUDWindowController()
        }

        evaluateScreenCapturePermissionAtLaunch()

        if hotkeyManager == nil {
            hotkeyManager = HotkeyManager()
        }
        hotkeyManager?.start(hotkey: hotkey, onPressed: { [weak self] in
            guard let self = self else { return }
            guard !self.hotkeyCaptureInProgress else { return }
            guard Date() >= self.suppressHotkeyUntil else { return }
            self.handleDoublePressCopyIfNeeded()
            if self.blockSamplingUntilPermissionRefresh {
                return
            }
            self.beginSampling()
        }, onReleased: { [weak self] in
            guard let self = self else { return }
            guard !self.hotkeyCaptureInProgress else { return }
            guard Date() >= self.suppressHotkeyUntil else { return }
            self.stopSampling()
        })
    }

    func stop() {
        stopSampling()
        copyFeedbackResetTask?.cancel()
        copyFeedbackResetTask = nil
        hotkeyManager?.stop()
    }

    func requestScreenCapturePermissionIfNeeded(userInitiated: Bool = true) {
        if userInitiated {
            blockSamplingUntilPermissionRefresh = false
        }

        if CGPreflightScreenCaptureAccess() {
            blockSamplingUntilPermissionRefresh = false
            return
        }

        guard userInitiated else {
            return
        }

        let granted = CGRequestScreenCaptureAccess()

        if granted {
            blockSamplingUntilPermissionRefresh = false
        } else {
            blockSamplingUntilPermissionRefresh = true
        }
    }

    func setHotkeyCaptureInProgress(_ inProgress: Bool) {
        hotkeyCaptureInProgress = inProgress
        lastHotkeyPressAt = nil
        if inProgress {
            suppressHotkeyUntil = Date().addingTimeInterval(0.20)
            stopSampling()
        } else {
            suppressHotkeyUntil = Date().addingTimeInterval(hotkeyRearmDelayAfterRecording)
            stopSampling()
        }
    }

    // MARK: - Sampling

    private func beginSampling() {
        guard !isActive else { return }

        if blockSamplingUntilPermissionRefresh {
            if CGPreflightScreenCaptureAccess() {
                blockSamplingUntilPermissionRefresh = false
            } else {
                return
            }
        }
        startSamplingLoop()
    }

    private func startSamplingLoop() {
        consecutiveSampleMisses = 0
        isActive = true
        hudController?.show()
        updateHUD(
            color: .clear,
            names: ColorNames(simplified: "Sampling...", detailed: ""),
            hex: "",
            at: NSEvent.mouseLocation
        )

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(66))
        timer.setEventHandler { [weak self] in
            self?.sampleNow()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopSampling() {
        isActive = false
        consecutiveSampleMisses = 0
        timer?.cancel()
        timer = nil
        if fadeOutHUDOnNextStop {
            fadeOutHUDOnNextStop = false
            hudController?.fadeOutAndHide(after: 0.45, duration: 0.35)
        } else {
            hudController?.hide()
        }
    }

    private func evaluateScreenCapturePermissionAtLaunch() {
        blockSamplingUntilPermissionRefresh = !CGPreflightScreenCaptureAccess()
    }

    private func sampleNow() {
        guard !samplingInFlight else { return }
        samplingInFlight = true

        let point = NSEvent.mouseLocation
        Task { [weak self] in
            guard let self = self else { return }
            let result = await ScreenCaptureSampler.shared.sample(at: point)
            await MainActor.run {
                switch result {
                case let .color(sample):
                    self.consecutiveSampleMisses = 0
                    self.lastSampleColor = sample.color
                    self.hex = sample.hex
                    self.colorNames = ColorNamer.names(for: sample.color, sampledHex: sample.hex)
                    self.refreshHUD(at: point)
                    self.blockSamplingUntilPermissionRefresh = false
                case .noFrame:
                    self.consecutiveSampleMisses += 1
                    if self.consecutiveSampleMisses >= 120 {
                        self.stopSampling()
                    }
                case let .failure(reason):
                    self.consecutiveSampleMisses += 1
                    let permissionLikeFailure =
                        reason.hasSuffix(":-3801") ||
                        reason.hasSuffix(":-3803") ||
                        reason.hasSuffix(":-3817")
                    if permissionLikeFailure || !CGPreflightScreenCaptureAccess() {
                        self.blockSamplingUntilPermissionRefresh = true
                        self.stopSampling()
                    }
                    if self.consecutiveSampleMisses >= 120 {
                        self.stopSampling()
                    }
                case .permissionDenied:
                    self.blockSamplingUntilPermissionRefresh = true
                    self.stopSampling()
                }
                self.samplingInFlight = false
            }
        }
    }

    // MARK: - Clipboard

    private func handleDoublePressCopyIfNeeded() {
        guard copyOnDoublePress else { return }
        let now = Date()
        defer { lastHotkeyPressAt = now }
        guard let previous = lastHotkeyPressAt else { return }
        guard now.timeIntervalSince(previous) <= doublePressInterval else { return }
        copyCurrentHexToClipboard()
    }

    private func copyCurrentHexToClipboard() {
        guard let value = formattedClipboardValue() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        fadeOutHUDOnNextStop = true

        let compactValue = value.count > 48 ? "\(value.prefix(45))..." : value
        showCopyFeedback("Copied \(compactValue)")
    }

    private func showCopyFeedback(_ message: String) {
        copyFeedbackResetTask?.cancel()
        copyFeedback = message
        if isActive {
            refreshHUD()
        }

        let resetTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.copyFeedback = ""
            if self.isActive {
                self.refreshHUD()
            }
        }
        copyFeedbackResetTask = resetTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: resetTask)
    }

    private func formattedClipboardValue() -> String? {
        let normalizedHex = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "#", with: "")
        guard normalizedHex.count == 6 else { return nil }
        guard let value = Int(normalizedHex, radix: 16) else { return nil }

        let red = (value >> 16) & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = value & 0xFF

        let redUnit = Double(red) / 255.0
        let greenUnit = Double(green) / 255.0
        let blueUnit = Double(blue) / 255.0
        let alphaUnit = Double((lastSampleColor.usingColorSpace(.sRGB) ?? lastSampleColor).alphaComponent)

        switch clipboardFormat {
        case .rgbHexadecimal:
            return normalizedHex
        case .rgbHexadecimalWithHash:
            return "#\(normalizedHex)"
        case .rgbHexadecimalWith0x:
            return "0x\(normalizedHex)"
        case .rgbHexadecimalWithSpaces:
            return "\(normalizedHex.prefix(2)) \(normalizedHex.dropFirst(2).prefix(2)) \(normalizedHex.suffix(2))"
        case .minimalColorName:
            return colorNames.simplified.isEmpty ? "Unknown" : colorNames.simplified
        case .isccNBSColorName:
            let iscc = colorNames.isccExtended.isEmpty ? "Unknown" : colorNames.isccExtended
            return iscc
        case .webColorOrWikipediaName:
            let web = colorNames.detailed.isEmpty ? "Unknown" : colorNames.detailed
            return web
        case .cssRGBIntegers:
            return "rgb(\(red), \(green), \(blue))"
        case .cssRGBPercentages:
            return "rgb(\(percentString(redUnit)), \(percentString(greenUnit)), \(percentString(blueUnit)))"
        case .cssRGBAIntegers:
            return "rgba(\(red), \(green), \(blue), \(trimmedNumberString(alphaUnit)))"
        case .cssRGBAPercentages:
            return "rgba(\(percentString(redUnit)), \(percentString(greenUnit)), \(percentString(blueUnit)), \(percentString(alphaUnit)))"
        case .nsColorSRGBSwift:
            return "NSColor(srgbRed: \(trimmedNumberString(redUnit)), green: \(trimmedNumberString(greenUnit)), blue: \(trimmedNumberString(blueUnit)), alpha: \(trimmedNumberString(alphaUnit)))"
        case .nsColorSRGBObjC:
            return "[NSColor colorWithSRGBRed:\(trimmedNumberString(redUnit)) green:\(trimmedNumberString(greenUnit)) blue:\(trimmedNumberString(blueUnit)) alpha:\(trimmedNumberString(alphaUnit))]"
        case .uiColorRGBSwift:
            return "UIColor(red: \(trimmedNumberString(redUnit)), green: \(trimmedNumberString(greenUnit)), blue: \(trimmedNumberString(blueUnit)), alpha: \(trimmedNumberString(alphaUnit)))"
        case .uiColorRGBObjC:
            return "[UIColor colorWithRed:\(trimmedNumberString(redUnit)) green:\(trimmedNumberString(greenUnit)) blue:\(trimmedNumberString(blueUnit)) alpha:\(trimmedNumberString(alphaUnit))]"
        }
    }

    private func percentString(_ unitValue: Double) -> String {
        "\(trimmedNumberString(unitValue * 100.0))%"
    }

    private func trimmedNumberString(_ value: Double, decimals: Int = 3) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    // MARK: - HUD

    private func refreshHUD(at point: CGPoint = NSEvent.mouseLocation) {
        updateHUD(
            color: lastSampleColor,
            names: colorNames,
            hex: hex,
            at: point
        )
    }

    private func updateHUD(color: NSColor, names: ColorNames, hex: String, at point: CGPoint) {
        hudController?.update(
            color: color,
            names: names,
            hex: hex,
            copyFeedback: copyFeedback,
            showISCCNABColorName: showISCCNABColorNameInOverlay,
            showWebColorName: showWebColorNameInOverlay,
            showHex: showHexInOverlay,
            at: point
        )
    }

    // MARK: - Launch At Login

    private func configureLaunchAtLogin(_ enable: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isUpdatingLaunchAtLogin = true
            launchAtLogin = !enable
            isUpdatingLaunchAtLogin = false
        }
    }

    // MARK: - Utilities

    private static func defaultedBool(for key: String, defaultValue: Bool = true) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
