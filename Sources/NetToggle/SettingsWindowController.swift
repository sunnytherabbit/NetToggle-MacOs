import Cocoa

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var initialKeyCode: Int
    private var initialFlags: UInt
    private var initialDelayMs: Int
    private var initialPlr: Double

    private let captureView = KeyCaptureView()
    private let infoLabel = NSTextField(labelWithString: "Click below, then press the hotkey you want to use.")
    private let delayField = NSTextField()
    private let plrField = NSTextField()
    private let plrSlider = NSSlider()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    private var capturedKeyCode: Int
    private var capturedFlags: UInt

    var onSave: ((Int, UInt, Int, Double) -> Void)?
    var onDone: (() -> Void)?

    init(keyCode: Int, flags: UInt, delayMs: Int, plr: Double) {
        self.initialKeyCode = keyCode
        self.initialFlags = flags
        self.initialDelayMs = delayMs
        self.initialPlr = plr

        self.capturedKeyCode = keyCode
        self.capturedFlags = flags

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NetToggle Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        infoLabel.frame = NSRect(x: 20, y: 260, width: 440, height: 24)
        infoLabel.alignment = .center

        captureView.frame = NSRect(x: 20, y: 180, width: 440, height: 70)
        captureView.wantsLayer = true
        captureView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        captureView.layer?.borderColor = NSColor.gray.cgColor
        captureView.layer?.borderWidth = 1.0
        captureView.layer?.cornerRadius = 6.0
        captureView.onKey = { [weak self] event in
            self?.handleKey(event)
        }

        let hotkeyNote = NSTextField(labelWithString: "The profile is applied in both directions to all traffic.")
        hotkeyNote.frame = NSRect(x: 20, y: 155, width: 440, height: 18)
        hotkeyNote.alignment = .center
        hotkeyNote.textColor = .secondaryLabelColor
        hotkeyNote.font = NSFont.systemFont(ofSize: 11)

        let delayLabel = NSTextField(labelWithString: "Delay (ms):")
        delayLabel.frame = NSRect(x: 20, y: 125, width: 100, height: 22)
        delayLabel.alignment = .right

        delayField.frame = NSRect(x: 130, y: 123, width: 80, height: 24)
        delayField.stringValue = "\(initialDelayMs)"
        delayField.alignment = .center
        delayField.delegate = self

        let plrLabel = NSTextField(labelWithString: "Packet loss %:")
        plrLabel.frame = NSRect(x: 230, y: 125, width: 100, height: 22)
        plrLabel.alignment = .right

        plrField.frame = NSRect(x: 340, y: 123, width: 80, height: 24)
        plrField.stringValue = String(format: "%.0f", initialPlr * 100)
        plrField.alignment = .center
        plrField.delegate = self

        plrSlider.frame = NSRect(x: 20, y: 85, width: 440, height: 24)
        plrSlider.minValue = 0.0
        plrSlider.maxValue = 100.0
        plrSlider.isContinuous = true
        plrSlider.target = self
        plrSlider.action = #selector(sliderChanged(_:))
        plrSlider.doubleValue = initialPlr * 100

        let plrHint = NSTextField(labelWithString: "0% = no loss, 100% = drop everything")
        plrHint.frame = NSRect(x: 20, y: 62, width: 440, height: 18)
        plrHint.alignment = .center
        plrHint.textColor = .secondaryLabelColor
        plrHint.font = NSFont.systemFont(ofSize: 11)

        saveButton.frame = NSRect(x: 300, y: 18, width: 70, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save(_:))

        cancelButton.frame = NSRect(x: 380, y: 18, width: 80, height: 28)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))

        [infoLabel, captureView, hotkeyNote,
         delayLabel, delayField, plrLabel, plrField,
         plrSlider, plrHint, saveButton, cancelButton].forEach {
            contentView.addSubview($0)
        }

        updateInfoLabel()
    }

    func show() {
        guard let window = window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(captureView)
    }

    private func handleKey(_ event: NSEvent) {
        capturedKeyCode = Int(event.keyCode)
        capturedFlags = event.modifierFlags.rawValue & 0x001F0000
        updateInfoLabel()
    }

    private func updateInfoLabel() {
        let desc = formatHotkey(keyCode: UInt16(capturedKeyCode), flags: capturedFlags)
        infoLabel.stringValue = "Hotkey: \(desc)"
    }

    @objc private func sliderChanged(_ sender: Any?) {
        let pct = plrSlider.doubleValue
        plrField.stringValue = String(format: "%.0f", pct)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            if field === plrField {
                if let pct = Double(plrField.stringValue) {
                    plrSlider.doubleValue = max(0, min(100, pct))
                }
            }
        }
    }

    @objc private func save(_ sender: Any?) {
        guard let delay = Int(delayField.stringValue), delay >= 0, delay <= 10000 else {
            showAlert(message: "Delay must be an integer between 0 and 10000 ms.")
            return
        }
        guard let pct = Double(plrField.stringValue) else {
            showAlert(message: "Packet loss must be a number between 0 and 100.")
            return
        }
        let plr = max(0.0, min(1.0, pct / 100.0))

        onSave?(capturedKeyCode, capturedFlags, delay, plr)
        window?.close()
    }

    @objc private func cancel(_ sender: Any?) {
        window?.close()
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid setting"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        onDone?()
        onSave = nil
        onDone = nil
    }
}

private func formatHotkey(keyCode: UInt16, flags: UInt) -> String {
    var parts: [String] = []
    if flags & 0x00100000 != 0 { parts.append("⌘") }
    if flags & 0x00080000 != 0 { parts.append("⌥") }
    if flags & 0x00040000 != 0 { parts.append("⌃") }
    if flags & 0x00020000 != 0 { parts.append("⇧") }

    let key = NSEvent.specialKeys()[keyCode] ?? "Key \(keyCode)"
    parts.append(key)
    return parts.isEmpty ? key : parts.joined()
}

final class KeyCaptureView: NSView {
    var onKey: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKey?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        // We only need modifiers held when a key goes down.
    }
}

extension NSEvent {
    static func specialKeys() -> [UInt16: String] {
        return [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
            0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2",
            0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x18: "Equal", 0x19: "9", 0x1A: "7", 0x1B: "Minus",
            0x1C: "8", 0x1D: "0", 0x1E: "RightBracket", 0x1F: "O",
            0x20: "U", 0x21: "LeftBracket", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "Quote",
            0x28: "K", 0x29: "Semicolon", 0x2A: "Backslash", 0x2B: "Comma",
            0x2C: "Slash", 0x2D: "N", 0x2E: "M", 0x2F: "Period",
            0x32: "Grave", 0x24: "Return", 0x30: "Tab",
            0x31: "Space", 0x33: "Delete", 0x35: "Escape",
            0x37: "Command", 0x38: "Shift", 0x39: "CapsLock",
            0x3A: "Option", 0x3B: "Control",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
        ]
    }
}
