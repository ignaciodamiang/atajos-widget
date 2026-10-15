import AppKit

struct ShortcutCombination: Codable, Equatable, Hashable {
    let modifiers: [ModifierKey]
    let key: String

    var normalized: ShortcutCombination? {
        guard Set(modifiers).count == modifiers.count, let key = Self.normalizeKey(key) else { return nil }
        return ShortcutCombination(modifiers: ModifierKey.allCases.filter { modifiers.contains($0) }, key: key)
    }

    static func normalizeKey(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = [
            "space": "Espacio", "espacio": "Espacio", "tab": "Tab", "enter": "Enter", "return": "Enter",
            "esc": "Esc", "escape": "Esc", "backspace": "Borrar", "borrar": "Borrar",
            "delete": "Suprimir", "suprimir": "Suprimir", "home": "Inicio", "inicio": "Inicio",
            "end": "Fin", "fin": "Fin", "pageup": "Re Pág", "re pág": "Re Pág",
            "pagedown": "Av Pág", "av pág": "Av Pág", "left": "←", "right": "→", "up": "↑", "down": "↓",
        ]
        if let key = aliases[value.lowercased()] { return key }
        if let number = Int(value.dropFirst()), value.first?.uppercased() == "F", (1...12).contains(number) {
            return "F\(number)"
        }
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespacesAndNewlines.contains(scalar),
              !"⌘⌥⌃⇧🌐".contains(value) else { return nil }
        let key = value.uppercased()
        return key.unicodeScalars.count == 1 ? key : nil
    }

    // Legacy labels support one chord or alternatives sharing a modifier prefix.
    // A slash key ("⌘ /") is distinct from the " / " separator between alternatives.
    static func parse(_ label: String) -> [ShortcutCombination] {
        let symbols: [Character: ModifierKey] = ["⌘": .command, "⌥": .option, "⌃": .control, "⇧": .shift, "🌐": .function]
        let words: [(String, ModifierKey)] = [
            ("command", .command), ("control", .control), ("option", .option), ("function", .function),
            ("shift", .shift), ("cmd", .command), ("ctrl", .control), ("alt", .option), ("fn", .function),
        ]
        var result: [ShortcutCombination] = []
        var inherited: [ModifierKey] = []
        for part in label.components(separatedBy: " / ") {
            var rest = part.trimmingCharacters(in: .whitespaces)
            var modifiers: [ModifierKey] = []
            while !rest.isEmpty {
                let modifier: ModifierKey?
                if let first = rest.first, let found = symbols[first] {
                    modifier = found
                    rest.removeFirst()
                } else if let (word, found) = words.first(where: { word, _ in
                    guard rest.lowercased().hasPrefix(word) else { return false }
                    let suffix = rest.dropFirst(word.count)
                    return suffix.isEmpty || suffix.first == " " || suffix.first == "+" || suffix.first.map({ symbols[$0] != nil }) == true
                }) {
                    modifier = found
                    rest = String(rest.dropFirst(word.count))
                } else { break }
                if let modifier = modifier, !modifiers.contains(modifier) { modifiers.append(modifier) }
                rest = rest.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "+")))
            }
            if modifiers.isEmpty && !result.isEmpty { modifiers = inherited }
            guard let chord = ShortcutCombination(modifiers: modifiers, key: rest).normalized else { return [] }
            if result.isEmpty { inherited = chord.modifiers }
            result.append(chord)
        }
        return result
    }

    func matches(_ press: ShortcutKeyPress) -> Bool {
        guard !press.isRepeat, let normalized = normalized,
              press.heldKeys.count == 1, let actualKey = Self.normalizeKey(press.key),
              Self.normalizeKey(press.heldKeys[0]) == actualKey else { return false }
        return Set(normalized.modifiers) == press.modifiers && normalized.key == actualKey
    }
}

struct Shortcut: Codable, Equatable, Hashable {
    let keys: String
    let action: String
    let category: String
    let apps: [String]?
    let combinations: [ShortcutCombination]?

    init(keys: String, action: String, category: String, apps: [String]? = nil, combinations: [ShortcutCombination]? = nil) {
        self.keys = keys; self.action = action; self.category = category
        self.apps = apps; self.combinations = combinations
    }

    var isAppSpecific: Bool { !(apps ?? []).isEmpty }
    func applies(to bundleIdentifier: String?) -> Bool {
        !isAppSpecific || bundleIdentifier.map { apps!.contains($0) } == true
    }
    var resolvedCombinations: [ShortcutCombination] {
        guard let combinations = combinations else { return ShortcutCombination.parse(keys) }
        let normalized = combinations.compactMap(\.normalized)
        return !normalized.isEmpty && normalized.count == combinations.count ? normalized : []
    }
    static func visible(_ shortcuts: [Shortcut], for bundleIdentifier: String?) -> [Shortcut] {
        let applicable = shortcuts.filter { $0.applies(to: bundleIdentifier) }
        return applicable.filter(\.isAppSpecific) + applicable.filter { !$0.isAppSpecific }
    }
}

struct Content: Codable { let title: String; let shortcuts: [Shortcut] }

struct ApplicationContext: Equatable {
    let bundleIdentifier: String?
    let name: String
    static let general = ApplicationContext(bundleIdentifier: nil, name: "Atajos generales")
    static func resolved(_ candidate: ApplicationContext?, ownBundleIdentifier: String, previous: ApplicationContext) -> ApplicationContext {
        guard let candidate = candidate, candidate.bundleIdentifier != ownBundleIdentifier else { return previous }
        return candidate
    }
}

struct ShortcutKeyPress {
    let key: String
    let modifiers: Set<ModifierKey>
    let heldKeys: [String]
    let isRepeat: Bool
}

struct PracticeSession: Equatable {
    let shortcut: Shortcut
    var waitingForRelease: Bool
    var succeeded = false

    mutating func reconcile(modifiers: Set<ModifierKey>, keys: [String]) {
        if modifiers.isEmpty && keys.isEmpty { waitingForRelease = false }
    }
    mutating func receive(_ press: ShortcutKeyPress) -> Bool {
        guard !waitingForRelease, !succeeded, shortcut.resolvedCombinations.contains(where: { $0.matches(press) }) else { return false }
        succeeded = true
        return true
    }
}

final class ShortcutPractice: ObservableObject {
    @Published private(set) var session: PracticeSession?
    private var completion: DispatchWorkItem?
    var onChange: (() -> Void)?
    var isBlocking: Bool { session.map { !$0.waitingForRelease && !$0.succeeded } ?? false }

    @discardableResult func begin(_ shortcut: Shortcut, isListening: Bool, modifiers: Set<ModifierKey>, keys: [String]) -> Bool {
        guard isListening, !shortcut.resolvedCombinations.isEmpty else { return false }
        cancel()
        session = PracticeSession(shortcut: shortcut, waitingForRelease: !modifiers.isEmpty || !keys.isEmpty)
        onChange?()
        return true
    }
    func reconcile(modifiers: Set<ModifierKey>, keys: [String]) {
        guard var current = session else { return }
        current.reconcile(modifiers: modifiers, keys: keys)
        if current != session { session = current; onChange?() }
    }
    func receive(_ press: ShortcutKeyPress) {
        guard var current = session, current.receive(press) else { return }
        session = current
        onChange?()
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    func validate(content: Content, context: ApplicationContext, isListening: Bool) {
        guard let current = session else { return }
        if !isListening || !content.shortcuts.contains(current.shortcut) || !current.shortcut.applies(to: context.bundleIdentifier) { cancel() }
    }
    func cancel() {
        completion?.cancel(); completion = nil
        guard session != nil else { return }
        session = nil; onChange?()
    }
}

enum KeyboardReference: String, CaseIterable {
    case keychron, mac
    var title: String { self == .keychron ? "Keychron B6 Pro" : "Teclado Mac" }
    var preferenceSuffix: String { self == .keychron ? "13364-1889-0" : "0-0-0" }
}

struct KeyboardLabels: Equatable {
    var functionName = ModifierKey.function.name
    static func fromMappings(_ mappings: [[String: UInt64]]) -> KeyboardLabels {
        let physicalNames: [UInt64: String] = [
            0x700000039: "Bloq Mayús", 0x7000000e0: "Control izquierdo", 0x7000000e4: "Control derecho",
            0x7000000e1: "Shift izquierdo", 0x7000000e5: "Shift derecho",
            0x7000000e2: "Option izquierdo", 0x7000000e6: "Option derecho",
            0x7000000e3: "Command izquierdo", 0x7000000e7: "Command derecho",
        ]
        for mapping in mappings where mapping["HIDKeyboardModifierMappingDst"] == 0xff00000003 {
            if let source = mapping["HIDKeyboardModifierMappingSrc"], let name = physicalNames[source] {
                return KeyboardLabels(functionName: name)
            }
        }
        return KeyboardLabels()
    }
    func name(_ modifier: ModifierKey) -> String { modifier == .function ? functionName : modifier.name }
    func symbol(_ modifier: ModifierKey) -> String {
        modifier == .function && functionName != ModifierKey.function.name ? functionName : modifier.symbol
    }
    func combination(modifiers: Set<ModifierKey>, keys: [String]) -> [String] {
        ModifierKey.allCases.filter { modifiers.contains($0) }.map { name($0) } + keys
    }
    func text(for shortcut: Shortcut, fullNames: Bool = false) -> String {
        let chords = shortcut.resolvedCombinations
        guard let first = chords.first else { return shortcut.keys }
        let separator = fullNames ? " + " : " "
        func prefix(_ chord: ShortcutCombination) -> [String] { chord.modifiers.map { fullNames ? name($0) : symbol($0) } }
        if chords.allSatisfy({ $0.modifiers == first.modifiers }) {
            return (prefix(first) + [chords.map(\.key).joined(separator: " / ")]).joined(separator: separator)
        }
        return chords.map { (prefix($0) + [$0.key]).joined(separator: separator) }.joined(separator: " / ")
    }
}

final class KeyboardNaming: ObservableObject {
    @Published private(set) var reference: KeyboardReference
    @Published private(set) var labels = KeyboardLabels()
    var onChange: (() -> Void)?
    private var timer: Timer?

    init() {
        reference = KeyboardReference(rawValue: UserDefaults.standard.string(forKey: "KeyboardReference") ?? "") ?? .mac
    }
    func start() {
        reload()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func select(_ reference: KeyboardReference) {
        self.reference = reference
        UserDefaults.standard.set(reference.rawValue, forKey: "KeyboardReference")
        reload()
        onChange?()
    }
    func reload() {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        func read(_ suffix: String) -> [[String: UInt64]]? {
            let key = "com.apple.keyboard.modifiermapping.\(suffix)" as CFString
            guard let rows = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? [[String: NSNumber]] else { return nil }
            return rows.map { $0.mapValues(\.uint64Value) }
        }
        let updated = KeyboardLabels.fromMappings(read(reference.preferenceSuffix) ?? read("0-0-0") ?? [])
        if updated != labels { labels = updated; onChange?() }
    }
    func stop() { timer?.invalidate(); timer = nil }
}
