import Cocoa
import CoreGraphics
import CoreFoundation

private let relevantModifierMask: UInt64 = 0x001F0000

final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var keyCode: Int = 37 { // Default: 'L'
        didSet { save() }
    }
    var modifierFlags: UInt64 = 0x00100000 { // Default: Command
        didSet { save() }
    }
    var isPaused: Bool = false

    init(delegate: HotkeyManagerDelegate) {
        self.delegate = delegate
        load()
    }

    func load() {
        keyCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        if keyCode == 0 {
            keyCode = 37
            modifierFlags = 0x00100000
        } else {
            modifierFlags = UInt64(UserDefaults.standard.integer(forKey: "hotkeyFlags"))
        }
    }

    func save() {
        UserDefaults.standard.set(keyCode, forKey: "hotkeyCode")
        UserDefaults.standard.set(Int(modifierFlags & relevantModifierMask), forKey: "hotkeyFlags")
    }

    func registerHotkey() {
        guard tap == nil else { return }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            delegate?.hotkeyRegistrationFailed()
            return
        }

        tap = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.runLoopSource = source

        CGEvent.tapEnable(tap: port, enable: true)
    }

    func matches(event: CGEvent) -> Bool {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue & relevantModifierMask
        return code == keyCode && flags == (modifierFlags & relevantModifierMask)
    }

    func updateHotkey(keyCode: Int, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = UInt64(modifierFlags) & relevantModifierMask
    }
}

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyTriggered()
    func hotkeyRegistrationFailed()
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()

    if type == .keyDown && !manager.isPaused && manager.matches(event: event) {
        DispatchQueue.main.async {
            manager.delegate?.hotkeyTriggered()
        }
    }

    return Unmanaged.passUnretained(event)
}
