import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey dispatcher backed by Carbon hotkey registration plus
/// state polling as a reliability fallback (especially for modifier-only keys).
final class HotkeyManager {
    private enum Timing {
        static let pollInterval = DispatchTimeInterval.milliseconds(16)
        static let pollLeeway = DispatchTimeInterval.milliseconds(4)
    }

    private var currentHotkey: Hotkey?
    private var onPressed: (() -> Void)?
    private var onReleased: (() -> Void)?
    private var isDown = false

    private var eventHandlerRef: EventHandlerRef?
    private var eventHotKeyRef: EventHotKeyRef?
    private let eventHotKeyID: UInt32 = 1
    private let eventHotKeySignature = OSType(UInt32(ascii: "H", "U", "E", "S"))

    private var pollTimer: DispatchSourceTimer?

    deinit {
        stop()
    }

    func start(hotkey: Hotkey, onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.onPressed = onPressed
        self.onReleased = onReleased
        register(hotkey)
    }

    func updateHotkey(_ hotkey: Hotkey) {
        setDown(false)
        register(hotkey)
    }

    func stop() {
        setDown(false)
        stopPolling()
        unregisterCarbonHotKey()
        removeCarbonEventHandler()
        currentHotkey = nil
        onPressed = nil
        onReleased = nil
    }

    private func register(_ hotkey: Hotkey) {
        currentHotkey = hotkey

        // Modifier-only keys are unreliable with Carbon hotkeys; poll them directly.
        if hotkey.isModifierOnly {
            unregisterCarbonHotKey()
            startPolling()
            return
        }

        installCarbonEventHandlerIfNeeded()
        _ = registerCarbonHotKey(hotkey)
        // Keep polling active even with Carbon so we still work if Carbon events are unreliable.
        startPolling()
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        let handler = down ? onPressed : onReleased
        guard let handler else { return }
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async {
                handler()
            }
        }
    }

    private func pollHotkeyState() {
        guard let hotkey = currentHotkey else {
            setDown(false)
            return
        }

        if hotkey.isModifierOnly {
            setDown(isModifierOnlyHotkeyPressed(hotkey))
            return
        }

        let keyCode = CGKeyCode(hotkey.keyCode)
        let keyIsPressed =
            CGEventSource.keyState(.combinedSessionState, key: keyCode) ||
            CGEventSource.keyState(.hidSystemState, key: keyCode)
        guard keyIsPressed else {
            setDown(false)
            return
        }

        let combinedFlags = CGEventSource.flagsState(.combinedSessionState)
        let hidFlags = CGEventSource.flagsState(.hidSystemState)
        let mergedFlags = CGEventFlags(rawValue: combinedFlags.rawValue | hidFlags.rawValue)
        setDown(hotkey.modifiers.isEmpty || mergedFlags.contains(hotkey.modifiers))
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Timing.pollInterval, leeway: Timing.pollLeeway)
        timer.setEventHandler { [weak self] in
            self?.pollHotkeyState()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            eventTypes.count,
            &eventTypes,
            userData,
            &eventHandlerRef
        )
    }

    private func registerCarbonHotKey(_ hotkey: Hotkey) -> Bool {
        unregisterCarbonHotKey()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: eventHotKeySignature, id: eventHotKeyID)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers(from: hotkey.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            eventHotKeyRef = hotKeyRef
            return true
        }
        return false
    }

    private func unregisterCarbonHotKey() {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }
    }

    private func removeCarbonEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }
        guard hotKeyID.signature == eventHotKeySignature, hotKeyID.id == eventHotKeyID else { return }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            setDown(true)
        case UInt32(kEventHotKeyReleased):
            // Ignore Carbon release if polling still sees the key down.
            if !isCurrentHotkeyPressed() {
                setDown(false)
            }
        default:
            break
        }
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else { return noErr }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleCarbonHotKeyEvent(eventRef)
        return noErr
    }

    private func isCurrentHotkeyPressed() -> Bool {
        guard let hotkey = currentHotkey else { return false }

        if hotkey.isModifierOnly {
            return isModifierOnlyHotkeyPressed(hotkey)
        }

        let keyCode = CGKeyCode(hotkey.keyCode)
        let keyIsPressed =
            CGEventSource.keyState(.combinedSessionState, key: keyCode) ||
            CGEventSource.keyState(.hidSystemState, key: keyCode)
        guard keyIsPressed else { return false }

        let combinedFlags = CGEventSource.flagsState(.combinedSessionState)
        let hidFlags = CGEventSource.flagsState(.hidSystemState)
        let mergedFlags = CGEventFlags(rawValue: combinedFlags.rawValue | hidFlags.rawValue)
        return hotkey.modifiers.isEmpty || mergedFlags.contains(hotkey.modifiers)
    }

    private func isModifierOnlyHotkeyPressed(_ hotkey: Hotkey) -> Bool {
        let combinedRaw = CGEventSource.flagsState(.combinedSessionState).rawValue
        let hidRaw = CGEventSource.flagsState(.hidSystemState).rawValue
        let rawFlags = combinedRaw | hidRaw

        if let sideSpecificMask = sideSpecificModifierMask(for: hotkey.keyCode) {
            return (rawFlags & sideSpecificMask) != 0
        }

        if hotkey.keyCode == Hotkey.KeyCode.capsLock {
            // Caps Lock is latched; accept either stateful or stateless alpha-shift bits.
            return (rawFlags & ModifierMask.alphaShiftMask) != 0
                || (rawFlags & ModifierMask.deviceAlphaShiftMask) != 0
        }

        if hotkey.keyCode == Hotkey.KeyCode.function {
            return (rawFlags & CGEventFlags.maskSecondaryFn.rawValue) != 0
        }

        if hotkey.modifiers.isEmpty {
            return false
        }
        return CGEventFlags(rawValue: rawFlags).contains(hotkey.modifiers)
    }

    private func sideSpecificModifierMask(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case Hotkey.KeyCode.rightCommand:
            return ModifierMask.deviceRightCommand
        case Hotkey.KeyCode.leftCommand:
            return ModifierMask.deviceLeftCommand
        case Hotkey.KeyCode.leftShift:
            return ModifierMask.deviceLeftShift
        case Hotkey.KeyCode.leftOption:
            return ModifierMask.deviceLeftOption
        case Hotkey.KeyCode.leftControl:
            return ModifierMask.deviceLeftControl
        case Hotkey.KeyCode.rightShift:
            return ModifierMask.deviceRightShift
        case Hotkey.KeyCode.rightOption:
            return ModifierMask.deviceRightOption
        case Hotkey.KeyCode.rightControl:
            return ModifierMask.deviceRightControl
        default:
            return nil
        }
    }
}

private extension UInt32 {
    init(ascii a: Character, _ b: Character, _ c: Character, _ d: Character) {
        let scalarA = a.asciiValue ?? 0
        let scalarB = b.asciiValue ?? 0
        let scalarC = c.asciiValue ?? 0
        let scalarD = d.asciiValue ?? 0
        self =
            (UInt32(scalarA) << 24) |
            (UInt32(scalarB) << 16) |
            (UInt32(scalarC) << 8) |
            UInt32(scalarD)
    }
}

private enum ModifierMask {
    static let alphaShiftMask: UInt64 = 0x0001_0000
    static let deviceLeftControl: UInt64 = 0x0000_0001
    static let deviceLeftShift: UInt64 = 0x0000_0002
    static let deviceRightShift: UInt64 = 0x0000_0004
    static let deviceLeftCommand: UInt64 = 0x0000_0008
    static let deviceRightCommand: UInt64 = 0x0000_0010
    static let deviceLeftOption: UInt64 = 0x0000_0020
    static let deviceRightOption: UInt64 = 0x0000_0040
    static let deviceAlphaShiftMask: UInt64 = 0x0000_0080
    static let deviceRightControl: UInt64 = 0x0000_2000
}
