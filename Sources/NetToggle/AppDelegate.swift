import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var settingsWindow: SettingsWindowController?

    private var networkOn = false
    private var helperRunning = false

    private var statusLabelItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var hotkeyLabelItem: NSMenuItem?
    private var profileLabelItem: NSMenuItem?

    private var delayMs = 0
    private var packetLoss = 0.90

    private let statusImage: NSImage? = {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        }
        return nil
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        buildStatusItem()

        hotkeyManager = HotkeyManager(delegate: self)

        let trusted = checkAccessibility()
        if trusted {
            hotkeyManager?.registerHotkey()
        }

        updateMenu()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = statusImage {
                button.image = img
                button.imagePosition = .imageLeft
                button.title = " Off"
            } else {
                button.title = "NT Off"
            }
        }

        let menu = NSMenu()

        statusLabelItem = NSMenuItem(title: "Network: Off", action: nil, keyEquivalent: "")
        menu.addItem(statusLabelItem!)

        profileLabelItem = NSMenuItem(title: "Profile: —", action: nil, keyEquivalent: "")
        menu.addItem(profileLabelItem!)

        menu.addItem(NSMenuItem.separator())

        hotkeyLabelItem = NSMenuItem(title: "Hotkey: not set", action: nil, keyEquivalent: "")
        menu.addItem(hotkeyLabelItem!)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        toggleItem = NSMenuItem(title: "Toggle Network", action: #selector(toggleNetwork(_:)), keyEquivalent: "")
        toggleItem?.target = self
        menu.addItem(toggleItem!)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func updateMenu() {
        guard let hotkeyManager = hotkeyManager else { return }

        statusLabelItem?.title = "Network: \(networkOn ? "On" : "Off")"
        profileLabelItem?.title = String(format: "Profile: %d ms / %.0f%% loss", delayMs, packetLoss * 100)
        toggleItem?.title = networkOn ? "Turn Network Off" : "Turn Network On"

        if let button = statusItem?.button {
            if statusImage != nil {
                button.title = networkOn ? " On" : " Off"
            } else {
                button.title = networkOn ? "NT On" : "NT Off"
            }
        }

        hotkeyLabelItem?.title = "Hotkey: \(formatHotkey(keyCode: UInt16(hotkeyManager.keyCode), flags: hotkeyManager.modifierFlags))"
    }

    private func loadSettings() {
        hotkeyManager = HotkeyManager(delegate: self)

        delayMs = UserDefaults.standard.object(forKey: "delayMs") != nil
            ? UserDefaults.standard.integer(forKey: "delayMs")
            : 0

        if UserDefaults.standard.object(forKey: "packetLoss") != nil {
            packetLoss = UserDefaults.standard.double(forKey: "packetLoss")
        } else {
            packetLoss = 0.90
        }

        // Clamp to sensible defaults on first run
        if delayMs < 0 || delayMs > 10000 { delayMs = 0 }
        if packetLoss < 0 || packetLoss > 1 { packetLoss = 0.90 }
    }

    private func saveSettings() {
        UserDefaults.standard.set(delayMs, forKey: "delayMs")
        UserDefaults.standard.set(packetLoss, forKey: "packetLoss")
    }

    private func formatHotkey(keyCode: UInt16, flags: UInt64) -> String {
        var parts: [String] = []
        if flags & 0x00100000 != 0 { parts.append("⌘") }
        if flags & 0x00080000 != 0 { parts.append("⌥") }
        if flags & 0x00040000 != 0 { parts.append("⌃") }
        if flags & 0x00020000 != 0 { parts.append("⇧") }

        let key = NSEvent.specialKeys()[keyCode] ?? "Key \(keyCode)"
        parts.append(key)
        return parts.isEmpty ? key : parts.joined()
    }

    private func checkAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission required"
            alert.informativeText = "NetToggle needs Accessibility access to listen for global hotkeys. Please enable it in System Settings > Privacy & Security > Accessibility, then relaunch the app."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return trusted
    }

    @objc private func openSettings(_ sender: Any?) {
        hotkeyManager?.isPaused = true

        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                keyCode: hotkeyManager?.keyCode ?? 37,
                flags: UInt(hotkeyManager?.modifierFlags ?? 0x00100000),
                delayMs: delayMs,
                plr: packetLoss
            )
            settingsWindow?.onSave = { [weak self] code, flags, delay, plr in
                self?.hotkeyManager?.updateHotkey(keyCode: code, modifierFlags: flags)
                self?.delayMs = delay
                self?.packetLoss = plr
                self?.saveSettings()
                self?.updateMenu()
            }
            settingsWindow?.onDone = { [weak self] in
                self?.hotkeyManager?.isPaused = false
            }
        } else {
            settingsWindow?.window?.close()
            settingsWindow = SettingsWindowController(
                keyCode: hotkeyManager?.keyCode ?? 37,
                flags: UInt(hotkeyManager?.modifierFlags ?? 0x00100000),
                delayMs: delayMs,
                plr: packetLoss
            )
            settingsWindow?.onSave = { [weak self] code, flags, delay, plr in
                self?.hotkeyManager?.updateHotkey(keyCode: code, modifierFlags: flags)
                self?.delayMs = delay
                self?.packetLoss = plr
                self?.saveSettings()
                self?.updateMenu()
            }
            settingsWindow?.onDone = { [weak self] in
                self?.hotkeyManager?.isPaused = false
            }
        }

        settingsWindow?.show()
    }

    @objc private func toggleNetwork(_ sender: Any?) {
        guard !helperRunning else { return }
        helperRunning = true

        let command = networkOn ? "off" : "on"
        HelperRunner.default.run(command: command, delayMs: delayMs, packetLoss: packetLoss) { [weak self] success, message in
            self?.helperRunning = false
            if success {
                self?.networkOn = !(self?.networkOn ?? false)
                self?.updateMenu()
            } else {
                self?.showError(message)
            }
        }
    }

    @objc private func quit(_ sender: Any?) {
        if networkOn {
            HelperRunner.default.run(command: "off", delayMs: delayMs, packetLoss: packetLoss) { _, _ in
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "NetToggle Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyTriggered() {
        toggleNetwork(nil)
    }

    func hotkeyRegistrationFailed() {
        showError("Could not create the global hotkey listener. Make sure NetToggle has Accessibility permission.")
    }
}
