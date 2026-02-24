import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum UI {
        static let settingsSize = NSSize(width: 620, height: 560)
    }

    private let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "HueSpot") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "HS"
            }
        }

        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About HueSpot", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    @objc private func openAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1.0"
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "HueSpot",
            .applicationVersion: "Version \(version)",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Licensed under GPL 2.0"
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(UI.settingsSize)
        window.isReleasedWhenClosed = false
        return window
    }
}
