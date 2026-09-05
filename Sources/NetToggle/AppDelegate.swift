import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var settingsWindow: SettingsWindowController?

    private var networkOn = false
    private var helperRunning = false
    private var refreshRunning = false

    private var statusLabelItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var hotkeyLabelItem: NSMenuItem?
    private var targetLabelItem: NSMenuItem?
    private var inProfileLabelItem: NSMenuItem?
    private var outProfileLabelItem: NSMenuItem?

    private var inDelayMs = 0
    private var inPacketLoss = 0.90
    private var outDelayMs = 0
    private var outPacketLoss = 0.90
    private var targetMode = "all"

    private var currentRobloxIPs: [String] = []
    private var refreshTimer: Timer?

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

        targetLabelItem = NSMenuItem(title: "Target: All", action: nil, keyEquivalent: "")
        menu.addItem(targetLabelItem!)

        inProfileLabelItem = NSMenuItem(title: "In: 0 ms / 0%", action: nil, keyEquivalent: "")
        menu.addItem(inProfileLabelItem!)

        outProfileLabelItem = NSMenuItem(title: "Out: 0 ms / 0%", action: nil, keyEquivalent: "")
        menu.addItem(outProfileLabelItem!)

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
        statusLabelItem?.title = "Network: \(networkOn ? "On" : "Off")"
        targetLabelItem?.title = "Target: \(targetMode == "roblox" ? "Roblox" : "All")"
        inProfileLabelItem?.title = String(format: "In: %d ms / %.0f%%", inDelayMs, inPacketLoss * 100)
        outProfileLabelItem?.title = String(format: "Out: %d ms / %.0f%%", outDelayMs, outPacketLoss * 100)
        toggleItem?.title = networkOn ? "Turn Network Off" : "Turn Network On"

        if let button = statusItem?.button {
            if statusImage != nil {
                button.title = networkOn ? " On" : " Off"
            } else {
                button.title = networkOn ? "NT On" : "NT Off"
            }
        }

        if let hotkeyManager = hotkeyManager {
            hotkeyLabelItem?.title = "Hotkey: \(formatHotkey(keyCode: UInt16(hotkeyManager.keyCode), flags: hotkeyManager.modifierFlags))"
        }
    }

    private func loadSettings() {
        hotkeyManager = HotkeyManager(delegate: self)

        let defaults = UserDefaults.standard

        // Migrate old single-direction settings.
        if defaults.object(forKey: "delayMs") != nil {
            let oldDelay = defaults.integer(forKey: "delayMs")
            let oldPlr = defaults.double(forKey: "packetLoss")
            if defaults.object(forKey: "inDelayMs") == nil {
                inDelayMs = oldDelay
                outDelayMs = oldDelay
            }
            if defaults.object(forKey: "inPacketLoss") == nil {
                inPacketLoss = oldPlr
                outPacketLoss = oldPlr
            }
            defaults.removeObject(forKey: "delayMs")
            defaults.removeObject(forKey: "packetLoss")
        }

        inDelayMs = defaults.object(forKey: "inDelayMs") != nil
            ? defaults.integer(forKey: "inDelayMs")
            : 0
        if defaults.object(forKey: "inPacketLoss") != nil {
            inPacketLoss = defaults.double(forKey: "inPacketLoss")
        } else {
            inPacketLoss = 0.90
        }

        outDelayMs = defaults.object(forKey: "outDelayMs") != nil
            ? defaults.integer(forKey: "outDelayMs")
            : 0
        if defaults.object(forKey: "outPacketLoss") != nil {
            outPacketLoss = defaults.double(forKey: "outPacketLoss")
        } else {
            outPacketLoss = 0.90
        }

        if defaults.object(forKey: "targetMode") != nil {
            targetMode = defaults.string(forKey: "targetMode") ?? "all"
        }

        inDelayMs = max(0, min(60000, inDelayMs))
        outDelayMs = max(0, min(60000, outDelayMs))
        inPacketLoss = max(0.0, min(1.0, inPacketLoss))
        outPacketLoss = max(0.0, min(1.0, outPacketLoss))
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(inDelayMs, forKey: "inDelayMs")
        defaults.set(inPacketLoss, forKey: "inPacketLoss")
        defaults.set(outDelayMs, forKey: "outDelayMs")
        defaults.set(outPacketLoss, forKey: "outPacketLoss")
        defaults.set(targetMode, forKey: "targetMode")
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

        settingsWindow?.window?.close()

        let settings = SettingsWindowController(
            keyCode: hotkeyManager?.keyCode ?? 37,
            flags: UInt(hotkeyManager?.modifierFlags ?? 0x00100000),
            inDelayMs: inDelayMs,
            inPlr: inPacketLoss,
            outDelayMs: outDelayMs,
            outPlr: outPacketLoss,
            targetMode: targetMode
        )

        settings.onSave = { [weak self] code, flags, inDelay, inPlr, outDelay, outPlr, target in
            self?.hotkeyManager?.updateHotkey(keyCode: code, modifierFlags: flags)
            self?.inDelayMs = inDelay
            self?.inPacketLoss = inPlr
            self?.outDelayMs = outDelay
            self?.outPacketLoss = outPlr
            self?.targetMode = target
            self?.saveSettings()
            self?.updateMenu()
        }

        settings.onDone = { [weak self] in
            self?.settingsWindow = nil
            self?.hotkeyManager?.isPaused = false
        }

        settingsWindow = settings
        settings.show()
    }

    @objc private func toggleNetwork(_ sender: Any?) {
        guard !helperRunning else { return }
        helperRunning = true

        if networkOn {
            HelperRunner.default.run(command: "off") { [weak self] success, message in
                guard let self = self else { return }
                self.helperRunning = false
                if success {
                    self.networkOn = false
                    self.stopRefreshTimer()
                    self.updateMenu()
                } else {
                    self.showError(message)
                }
            }
            return
        }

        if targetMode == "roblox" {
            RobloxTrafficFinder.default.findRemoteIPs { [weak self] ips, error in
                guard let self = self else { return }

                if ips.isEmpty {
                    self.helperRunning = false
                    self.showError(error.isEmpty ? "Could not find Roblox traffic." : error)
                    return
                }

                self.currentRobloxIPs = ips

                HelperRunner.default.run(
                    command: "roblox",
                    inDelayMs: self.inDelayMs,
                    inPacketLoss: self.inPacketLoss,
                    outDelayMs: self.outDelayMs,
                    outPacketLoss: self.outPacketLoss,
                    targetIPs: ips
                ) { [weak self] success, message in
                    guard let self = self else { return }
                    self.helperRunning = false
                    if success {
                        self.networkOn = true
                        self.startRefreshTimer()
                        self.updateMenu()
                    } else {
                        self.showError(message)
                    }
                }
            }
        } else {
            HelperRunner.default.run(
                command: "on",
                inDelayMs: inDelayMs,
                inPacketLoss: inPacketLoss,
                outDelayMs: outDelayMs,
                outPacketLoss: outPacketLoss
            ) { [weak self] success, message in
                guard let self = self else { return }
                self.helperRunning = false
                if success {
                    self.networkOn = true
                    self.startRefreshTimer()
                    self.updateMenu()
                } else {
                    self.showError(message)
                }
            }
        }
    }

    // MARK: - Watchdog refresh

    private func startRefreshTimer() {
        stopRefreshTimer()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshRules()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshRules() {
        guard networkOn && !refreshRunning else { return }

        if targetMode == "roblox" {
            refreshRunning = true

            RobloxTrafficFinder.default.findRemoteIPs { [weak self] newIPs, _ in
                guard let self = self else { return }

                self.currentRobloxIPs = newIPs

                HelperRunner.default.run(
                    command: "roblox-refresh",
                    inDelayMs: self.inDelayMs,
                    inPacketLoss: self.inPacketLoss,
                    outDelayMs: self.outDelayMs,
                    outPacketLoss: self.outPacketLoss,
                    targetIPs: newIPs
                ) { [weak self] success, message in
                    guard let self = self else { return }
                    self.refreshRunning = false

                    if !self.networkOn {
                        HelperRunner.default.run(command: "off", inDelayMs: 0, inPacketLoss: 0, outDelayMs: 0, outPacketLoss: 0) { _, _ in }
                        return
                    }

                    if !success {
                        self.showError(message)
                    }
                }
            }
        } else {
            refreshRunning = true

            HelperRunner.default.run(
                command: "ensure-all",
                inDelayMs: inDelayMs,
                inPacketLoss: inPacketLoss,
                outDelayMs: outDelayMs,
                outPacketLoss: outPacketLoss
            ) { [weak self] success, message in
                guard let self = self else { return }
                self.refreshRunning = false

                if !self.networkOn {
                    HelperRunner.default.run(command: "off", inDelayMs: 0, inPacketLoss: 0, outDelayMs: 0, outPacketLoss: 0) { _, _ in }
                    return
                }

                if !success {
                    self.showError(message)
                }
            }
        }
    }

    @objc private func quit(_ sender: Any?) {
        if networkOn {
            HelperRunner.default.run(command: "off") { [weak self] _, _ in
                self?.networkOn = false
                self?.stopRefreshTimer()
                NSApp.terminate(nil)
            }
        } else {
            stopRefreshTimer()
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
