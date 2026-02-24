import Foundation
import AppKit
import SwiftUI

final class HUDWindowController {
    private let panel: NSPanel
    private var hostingView: NSHostingView<HUDView>
    private let fallbackSize = CGSize(width: 480, height: 190)
    private var pendingFadeTask: DispatchWorkItem?

    init() {
        let view = HUDView(
            color: .clear,
            names: ColorNames(simplified: "", detailed: ""),
            hex: "",
            copyFeedback: "",
            showISCCNABColorName: true,
            showWebColorName: true,
            showHex: true
        )
        hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: fallbackSize.width, height: fallbackSize.height)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: fallbackSize.width, height: fallbackSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView
    }

    func show() {
        cancelPendingFade()
        let point = NSEvent.mouseLocation
        let size = resolvedSize()
        let origin = offsetOrigin(for: point, size: size)
        panel.alphaValue = 1.0
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        cancelPendingFade()
        panel.alphaValue = 1.0
        panel.orderOut(nil)
    }

    func fadeOutAndHide(after delay: TimeInterval, duration: TimeInterval) {
        cancelPendingFade()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                self.panel.animator().alphaValue = 0.0
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1.0
            }
        }
        pendingFadeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func update(
        color: NSColor,
        names: ColorNames,
        hex: String,
        copyFeedback: String,
        showISCCNABColorName: Bool,
        showWebColorName: Bool,
        showHex: Bool,
        at point: CGPoint
    ) {
        hostingView.rootView = HUDView(
            color: color,
            names: names,
            hex: hex,
            copyFeedback: copyFeedback,
            showISCCNABColorName: showISCCNABColorName,
            showWebColorName: showWebColorName,
            showHex: showHex
        )
        let size = resolvedSize()
        let origin = offsetOrigin(for: point, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func resolvedSize() -> CGSize {
        let fitting = hostingView.fittingSize
        let width = max(fitting.width, fallbackSize.width)
        let height = max(fitting.height, fallbackSize.height)
        return CGSize(width: width, height: height)
    }

    private func cancelPendingFade() {
        pendingFadeTask?.cancel()
        pendingFadeTask = nil
    }

    private func offsetOrigin(for point: CGPoint, size: CGSize) -> CGPoint {
        let offset = CGPoint(x: 24, y: -24)
        var x = point.x + offset.x
        var y = point.y + offset.y - size.height

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let minX = screen.frame.minX + 12
            let maxX = screen.frame.maxX - size.width - 12
            let minY = screen.frame.minY + 12
            let maxY = screen.frame.maxY - size.height - 12
            x = min(max(x, minX), maxX)
            y = min(max(y, minY), maxY)
        }

        return CGPoint(x: x, y: y)
    }
}
