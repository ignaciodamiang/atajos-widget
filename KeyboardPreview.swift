import AppKit
import ApplicationServices
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

struct PracticeEventFilter {
    private(set) var consumedKeys: Set<UInt16> = []
    private var drainingModifiers = false

    mutating func consumes(_ type: CGEventType, code: UInt16, modifiers: Set<ModifierKey>, blocking: Bool) -> Bool {
        switch type {
        case .keyDown:
            if blocking { consumedKeys.insert(code) }
            return consumedKeys.contains(code)
        case .keyUp:
            return consumedKeys.remove(code) != nil
        case .flagsChanged:
            let consume = blocking || drainingModifiers
            if consume { drainingModifiers = !modifiers.isEmpty }
            return consume
        default:
            return false
        }
    }
    mutating func reconcile(heldCodes: Set<UInt16>, modifiers: Set<ModifierKey>) {
        consumedKeys.formIntersection(heldCodes)
        if modifiers.isEmpty { drainingModifiers = false }
    }
}

final class KeyboardPreview: ObservableObject {
    @Published private(set) var modifiers: Set<ModifierKey> = []
    @Published private(set) var keys: [String] = []
    @Published private(set) var hasInputPermission = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var isListening = false
    @Published private(set) var canIntercept = false
    private var preview = ShortcutPreview()
    private var filter = PracticeEventFilter()
    private var requestedInterception = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierTimer: Timer?
    private var permissionTimer: Timer?
    var onStatusChange: (() -> Void)?
    var onStateChange: (() -> Void)?
    var onKeyDown: ((ShortcutKeyPress) -> Void)?
    var shouldBlock: (() -> Bool)?
    var onCancelPractice: (() -> Void)?
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
    func requestInterceptionPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if hasAccessibilityPermission && !canIntercept { removeTap() }
        updatePermission()
        if !hasAccessibilityPermission,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    private func pollModifiers() {
        let previousModifiers = modifiers
        let previousKeys = keys
        let flags = canIntercept ? NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue)) : NSEvent.modifierFlags
        let current = ModifierKey.live(sessionFlags: flags,
                                       functionKeyDown: hasInputPermission && CGEventSource.keyState(.hidSystemState, key: 63))
        if current != modifiers { modifiers = current }
        if hasInputPermission && !keys.isEmpty {
            // Some apps consume shortcut key-up events. Reconcile only held
            // keys so that the preview still clears when those keys are released.
            for code in preview.heldOrder where !CGEventSource.keyState(.hidSystemState, key: code) {
                preview.keyUp(code: code)
            }
            if keys != preview.keyLabels { keys = preview.keyLabels }
        }
        let heldCodes = Set(filter.consumedKeys.filter { CGEventSource.keyState(.hidSystemState, key: $0) })
        filter.reconcile(heldCodes: heldCodes, modifiers: current)
        if previousModifiers != modifiers || previousKeys != keys { onStateChange?() }
    }
    private func updatePermission() {
        let permitted = CGPreflightListenEventAccess()
        let previousPermission = hasInputPermission
        let previousListening = isListening
        let previousAccessibility = hasAccessibilityPermission
        let previousInterception = canIntercept
        hasInputPermission = permitted
        hasAccessibilityPermission = AXIsProcessTrusted()
        if tap != nil && requestedInterception != hasAccessibilityPermission { removeTap() }
        if permitted && tap == nil { installTap(intercept: hasAccessibilityPermission) }
        if !permitted && tap != nil { removeTap() }
        if previousPermission != hasInputPermission || previousListening != isListening || previousAccessibility != hasAccessibilityPermission || previousInterception != canIntercept { onStatusChange?() }
    }
    private func installTap(intercept: Bool) {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardPreview>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.onCancelPractice?()
                monitor.filter = PracticeEventFilter()
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let blocking = monitor.canIntercept && (monitor.shouldBlock?() ?? false)
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let pressed = ModifierKey.pressed(in: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
            let consumed = monitor.canIntercept && monitor.filter.consumes(type, code: code, modifiers: pressed, blocking: blocking)
            monitor.receive(type: type, event: event)
            if blocking && type == .keyDown && code == 53 && (monitor.shouldBlock?() ?? false) { monitor.onCancelPractice?() }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        requestedInterception = intercept
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: intercept ? .defaultTap : .listenOnly,
                               eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        canIntercept = intercept && tap != nil
        if tap == nil && intercept {
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                   eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        }
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
        canIntercept = false; filter = PracticeEventFilter()
        preview.releaseAll(); keys = []
        onStateChange?()
    }
    private func receive(type: CGEventType, event: CGEvent) {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp { preview.keyUp(code: code); keys = preview.keyLabels; onStateChange?(); return }
        if type == .flagsChanged { pollModifiers(); return }
        guard type == .keyDown, let native = NSEvent(cgEvent: event) else { return }
        let flags = canIntercept ? NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue)) : NSEvent.modifierFlags
        let pressed = ModifierKey.keyEvent(eventFlags: native.modifierFlags, sessionFlags: flags,
                                          functionKeyDown: CGEventSource.keyState(.hidSystemState, key: 63))
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
