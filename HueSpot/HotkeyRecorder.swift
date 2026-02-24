// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import SwiftUI
import AppKit

struct HotkeyRecorder: NSViewRepresentable {
    let onChange: (Hotkey) -> Void

    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = onChange
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onChange = onChange
        nsView.isRecording = isRecording
    }
}

final class RecorderView: NSView {
    var onChange: ((Hotkey) -> Void)?
    var isRecording: Bool = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        let flags = cgFlags(from: event.modifierFlags)
        let hotkey = Hotkey(keyCode: event.keyCode, modifiers: flags)
        onChange?(hotkey)
        isRecording = false
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let keyCode = event.keyCode
        let flags = cgFlags(from: event.modifierFlags)
        guard Hotkey(keyCode: keyCode, modifiers: flags).isModifierOnly else { return }
        let hotkey = Hotkey(keyCode: keyCode, modifiers: flags)
        onChange?(hotkey)
        isRecording = false
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        return result
    }
}
