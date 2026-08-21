import Cocoa

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var initialKeyCode: Int
    private var initialFlags: UInt
    private var initialInDelayMs: Int
    private var initialInPlr: Double
    private var initialOutDelayMs: Int
    private var initialOutPlr: Double

    private let captureView = KeyCaptureView()
    private let infoLabel = NSTextField(labelWithString: "Click below, then press the hotkey you want to use.")

    private let inDelayField = NSTextField()
    private let inPlrField = NSTextField()
    private let inPlrSlider = NSSlider()

    private let outDelayField = NSTextField()
    private let outPlrField = NSTextField()
    private let outPlrSlider = NSSlider()

    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    private var capturedKeyCode: Int
    private var capturedFlags: UInt

    var onSave: ((Int, UInt, Int, Double, Int, Double) -> Void)?
    var onDone: (() -> Void)?

    init(
        keyCode: Int,
        flags: UInt,
        inDelayMs: Int,
        inPlr: Double,
        outDelayMs: Int,
        outPlr: Double
    ) {
        self.initialKeyCode = keyCode
        self.initialFlags = flags
        self.initialInDelayMs = inDelayMs
        self.initialInPlr = inPlr
        self.initialOutDelayMs = outDelayMs
        self.initialOutPlr = outPlr

        self.capturedKeyCode = keyCode
        self.capturedFlags = flags

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
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

        infoLabel.frame = NSRect(x: 20, y: 420, width: 520, height: 24)
        infoLabel.alignment = .center

        captureView.frame = NSRect(x: 20, y: 345, width: 520, height: 70)
        captureView.wantsLayer = true
        captureView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        captureView.layer?.borderColor = NSColor.gray.cgColor
        captureView.layer?.borderWidth = 1.0
        captureView.layer?.cornerRadius = 6.0
        captureView.onKey = { [weak self] event in
            self?.handleKey(event)
        }

        let note = NSTextField(labelWithString: "Traffic can be shaped differently for each direction.")
        note.frame = NSRect(x: 20, y: 320, width: 520, height: 18)
        note.alignment = .center
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: 11)

        // Inbound column
        let inTitle = sectionTitle("Inbound", y: 300)
        let inDelayLabel = label("Delay (ms):", y: 270, align: .right)
        inDelayField.frame = NSRect(x: 130, y: 268, width: 80, height: 24)
        inDelayField.stringValue = "\(initialInDelayMs)"
        inDelayField.alignment = .center
        inDelayField.delegate = self

        let inPlrLabel = label("Loss %:", y: 240, align: .right)
        inPlrField.frame = NSRect(x: 130, y: 238, width: 80, height: 24)
        inPlrField.stringValue = String(format: "%.0f", initialInPlr * 100)
        inPlrField.alignment = .center
        inPlrField.delegate = self

        inPlrSlider.frame = NSRect(x: 20, y: 205, width: 240, height: 24)
        inPlrSlider.minValue = 0.0
        inPlrSlider.maxValue = 100.0
        inPlrSlider.isContinuous = true
        inPlrSlider.target = self
        inPlrSlider.action = #selector(inPlrSliderChanged(_:))
        inPlrSlider.doubleValue = initialInPlr * 100

        // Outbound column
        let outTitle = sectionTitle("Outbound", y: 300, x: 290)
        let outDelayLabel = label("Delay (ms):", y: 270, x: 290, align: .right)
        outDelayField.frame = NSRect(x: 400, y: 268, width: 80, height: 24)
        outDelayField.stringValue = "\(initialOutDelayMs)"
        outDelayField.alignment = .center
        outDelayField.delegate = self

        let outPlrLabel = label("Loss %:", y: 240, x: 290, align: .right)
        outPlrField.frame = NSRect(x: 400, y: 238, width: 80, height: 24)
        outPlrField.stringValue = String(format: "%.0f", initialOutPlr * 100)
        outPlrField.alignment = .center
        outPlrField.delegate = self

        outPlrSlider.frame = NSRect(x: 300, y: 205, width: 240, height: 24)
        outPlrSlider.minValue = 0.0
        outPlrSlider.maxValue = 100.0
        outPlrSlider.isContinuous = true
        outPlrSlider.target = self
        outPlrSlider.action = #selector(outPlrSliderChanged(_:))
        outPlrSlider.doubleValue = initialOutPlr * 100

        let hint = NSTextField(labelWithString: "0% = no loss, 100% = drop everything")
        hint.frame = NSRect(x: 20, y: 170, width: 520, height: 18)
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)

        saveButton.frame = NSRect(x: 380, y: 18, width: 70, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save(_:))

        cancelButton.frame = NSRect(x: 460, y: 18, width: 80, height: 28)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))

        [infoLabel, captureView, note,
         inTitle, inDelayLabel, inDelayField, inPlrLabel, inPlrField, inPlrSlider,
         outTitle, outDelayLabel, outDelayField, outPlrLabel, outPlrField, outPlrSlider,
         hint, saveButton, cancelButton].forEach {
            contentView.addSubview($0)
        }

        updateInfoLabel()
    }

    private func label(_ string: String, y: CGFloat, x: CGFloat = 20, align: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.frame = NSRect(x: x, y: y, width: 100, height: 22)
        field.alignment = align
        return field
    }

    private func sectionTitle(_ string: String, y: CGFloat, x: CGFloat = 20) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.frame = NSRect(x: x, y: y, width: 240, height: 24)
        field.alignment = .center
        field.font = NSFont.boldSystemFont(ofSize: 13)
        return field
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

    @objc private func inPlrSliderChanged(_ sender: Any?) {
        let pct = inPlrSlider.doubleValue
        inPlrField.stringValue = String(format: "%.0f", pct)
    }

    @objc private func outPlrSliderChanged(_ sender: Any?) {
        let pct = outPlrSlider.doubleValue
        outPlrField.stringValue = String(format: "%.0f", pct)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            if field === inPlrField {
                if let pct = Double(inPlrField.stringValue) {
                    inPlrSlider.doubleValue = max(0, min(100, pct))
                }
            } else if field === outPlrField {
                if let pct = Double(outPlrField.stringValue) {
                    outPlrSlider.doubleValue = max(0, min(100, pct))
                }
            }
        }
    }

    @objc private func save(_ sender: Any?) {
        let inDelay = parseDelay(inDelayField)
        let inPlr = parsePlr(inPlrField)
        let outDelay = parseDelay(outDelayField)
        let outPlr = parsePlr(outPlrField)

        guard let inD = inDelay, let inP = inPlr, let outD = outDelay, let outP = outPlr else {
            return
        }

        onSave?(capturedKeyCode, capturedFlags, inD, inP, outD, outP)
        window?.close()
    }

    @objc private func cancel(_ sender: Any?) {
        window?.close()
    }

    private func parseDelay(_ field: NSTextField) -> Int? {
        guard let value = Int(field.stringValue), value >= 0, value <= 10000 else {
            showAlert(message: "Delay must be an integer between 0 and 10000 ms.")
            return nil
        }
        return value
    }

    private func parsePlr(_ field: NSTextField) -> Double? {
        guard let pct = Double(field.stringValue) else {
            showAlert(message: "Packet loss must be a number between 0 and 100.")
            return nil
        }
        return max(0.0, min(1.0, pct / 100.0))
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
