import AppKit
import CoreGraphics

enum ModifierKey: String, CaseIterable, Identifiable, Codable {
    case command, option, control, shift, function
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .function: return "fn"
        }
    }
    var name: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        case .function: return "Fn / 🌐"
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        case .function: return .function
        }
    }
    static func pressed(in flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        Set(allCases.filter { flags.contains($0.flag) })
    }
    static func live(sessionFlags: NSEvent.ModifierFlags, functionKeyDown: Bool) -> Set<ModifierKey> {
        var result = pressed(in: sessionFlags)
        // Fn is a modifier event on macOS. keyState(63) can be false even when
        // its session modifier flag is present; a negative query must not veto it.
        if functionKeyDown { result.insert(.function) }
        return result
    }
    static func keyEvent(eventFlags: NSEvent.ModifierFlags, sessionFlags: NSEvent.ModifierFlags, functionKeyDown: Bool) -> Set<ModifierKey> {
        var result = pressed(in: eventFlags)
        // Arrow/F-key events can set function intrinsically, so verify Fn
        // against the session state instead of treating that event bit as a press.
        if live(sessionFlags: sessionFlags, functionKeyDown: functionKeyDown).contains(.function) { result.insert(.function) }
        else { result.remove(.function) }
        return result
    }
}

// The preview contains only keys currently held; it keeps no typing history.
struct ShortcutPreview {
    private(set) var heldKeys: [UInt16: String] = [:]
    private(set) var heldOrder: [UInt16] = []
    mutating func keyDown(code: UInt16, label: String) {
        if heldKeys[code] == nil { heldOrder.append(code) }
        heldKeys[code] = label
    }
    mutating func keyUp(code: UInt16) {
        heldKeys.removeValue(forKey: code)
        heldOrder.removeAll { $0 == code }
    }
    mutating func releaseAll() {
        heldKeys.removeAll()
        heldOrder.removeAll()
    }
    var keyLabels: [String] { heldOrder.compactMap { heldKeys[$0] } }
    func combination(modifiers: Set<ModifierKey>) -> [String] {
        ModifierKey.allCases.filter { modifiers.contains($0) }.map(\.name) + keyLabels
    }
}

final class KeyboardPreview: ObservableObject {
    @Published private(set) var modifiers: Set<ModifierKey> = []
    @Published private(set) var keys: [String] = []
    @Published private(set) var hasInputPermission = false
    @Published private(set) var isListening = false
    private var preview = ShortcutPreview()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierTimer: Timer?
    private var permissionTimer: Timer?
    var onStatusChange: (() -> Void)?
    var onStateChange: (() -> Void)?
    var onKeyDown: ((ShortcutKeyPress) -> Void)?
    var combination: [String] { preview.combination(modifiers: modifiers) }

    func start() {
        pollModifiers()
        updatePermission()
        modifierTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.pollModifiers() }
        permissionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updatePermission() }
        RunLoop.main.add(modifierTimer!, forMode: .common)
        RunLoop.main.add(permissionTimer!, forMode: .common)
    }
    func requestPermission() {
        CGRequestListenEventAccess()
        updatePermission()
        if !hasInputPermission,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    private func pollModifiers() {
        let previousModifiers = modifiers
        let previousKeys = keys
        let current = ModifierKey.live(sessionFlags: NSEvent.modifierFlags,
                                       functionKeyDown: hasInputPermission && CGEventSource.keyState(.combinedSessionState, key: 63))
        if current != modifiers { modifiers = current }
        if hasInputPermission && !keys.isEmpty {
            // Some apps consume shortcut key-up events. Reconcile only held
            // keys so that the preview still clears when those keys are released.
            for code in preview.heldOrder where !CGEventSource.keyState(.combinedSessionState, key: code) {
                preview.keyUp(code: code)
            }
            if keys != preview.keyLabels { keys = preview.keyLabels }
        }
        if previousModifiers != modifiers || previousKeys != keys { onStateChange?() }
    }
    private func updatePermission() {
        let permitted = CGPreflightListenEventAccess()
        let previousPermission = hasInputPermission
        let previousListening = isListening
        hasInputPermission = permitted
        if permitted && tap == nil { installTap() }
        if !permitted && tap != nil { removeTap() }
        if previousPermission != hasInputPermission || previousListening != isListening { onStatusChange?() }
    }
    private func installTap() {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardPreview>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else { monitor.receive(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { isListening = false; return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
    }
    private func removeTap() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        tap = nil; runLoopSource = nil; isListening = false
        preview.releaseAll(); keys = []
        onStateChange?()
    }
    private func receive(type: CGEventType, event: CGEvent) {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp { preview.keyUp(code: code); keys = preview.keyLabels; onStateChange?(); return }
        if type == .flagsChanged { pollModifiers(); return }
        guard type == .keyDown, let native = NSEvent(cgEvent: event) else { return }
        let pressed = ModifierKey.keyEvent(eventFlags: native.modifierFlags, sessionFlags: NSEvent.modifierFlags,
                                          functionKeyDown: CGEventSource.keyState(.combinedSessionState, key: 63))
        let label = Self.keyLabel(native)
        preview.keyDown(code: code, label: label)
        if modifiers != pressed { modifiers = pressed }
        if keys != preview.keyLabels { keys = preview.keyLabels }
        onStateChange?()
        onKeyDown?(ShortcutKeyPress(key: label, modifiers: pressed, heldKeys: preview.keyLabels, isRepeat: native.isARepeat))
    }
    static func keyLabel(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "Enter", 48: "Tab", 49: "Espacio", 51: "Borrar", 53: "Esc",
            76: "Enter", 115: "Inicio", 116: "Re Pág", 117: "Suprimir", 119: "Fin", 121: "Av Pág",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let label = special[event.keyCode] { return label }
        // AppKit applies the user's current keyboard layout, including Spanish keyboards.
        if let text = event.characters(byApplyingModifiers: []), !text.isEmpty,
           text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return text.uppercased()
        }
        return "Tecla \(event.keyCode)"
    }
    func stop() {
        modifierTimer?.invalidate(); permissionTimer?.invalidate()
        removeTap()
    }
}
