import AppKit

@main
struct ShortcutChecks {
    static func main() throws {
        let oldJSON = #"{"title":"Viejos","shortcuts":[{"keys":"fn ⌃ F","action":"Maximizar","category":"Ventanas"}]}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(Content.self, from: oldJSON)
        let maximize = old.shortcuts[0]
        let globals = [maximize, Shortcut(keys: "⌘ Tab", action: "Cambiar app", category: "Sistema")]
        let chrome = Shortcut(keys: "⌘ T", action: "Nueva pestaña", category: "Chrome", apps: ["com.google.Chrome"])
        let ghostty = Shortcut(keys: "⌘ T", action: "Nueva pestaña", category: "Ghostty", apps: ["com.mitchellh.ghostty"])
        let all = globals + [chrome, ghostty]
        assert(Shortcut.visible(all, for: "com.google.Chrome") == [chrome] + globals)
        assert(Shortcut.visible(all, for: "com.mitchellh.ghostty") == [ghostty] + globals)
        assert(Shortcut.visible(all, for: "com.example.unknown") == globals)
        assert(Shortcut.visible(all, for: nil) == globals)
        let context = ApplicationContext(bundleIdentifier: "com.google.Chrome", name: "Chrome")
        let own = ApplicationContext(bundleIdentifier: "local.nacho.atajos-widget", name: "Atajos")
        assert(ApplicationContext.resolved(own, ownBundleIdentifier: own.bundleIdentifier!, previous: context) == context)
        assert(ApplicationContext.resolved(nil, ownBundleIdentifier: own.bundleIdentifier!, previous: context) == context)

        assert(maximize.resolvedCombinations == [ShortcutCombination(modifiers: [.control, .function], key: "F")])
        let halves = Shortcut(keys: "fn ⌃ ← / →", action: "Mitades", category: "Ventanas")
        assert(halves.resolvedCombinations == [ShortcutCombination(modifiers: [.control, .function], key: "←"), ShortcutCombination(modifiers: [.control, .function], key: "→")])
        assert(ShortcutCombination.parse("⇧⌘G") == [ShortcutCombination(modifiers: [.command, .shift], key: "G")])
        assert(ShortcutCombination.parse("Cmd + Shift + t")[0].key == "T")
        assert(ShortcutCombination.parse("⌘ /")[0].key == "/")
        assert(ShortcutCombination.parse("⌘ K ⌘ S").isEmpty)
        assert(ShortcutCombination.parse("fn").isEmpty)
        assert(ShortcutCombination.parse("⌘ Re Pág")[0].key == "Re Pág")
        assert(ShortcutCombination.parse("⇧ F12")[0].key == "F12")
        let explicit = Shortcut(keys: "Teclas personalizadas", action: "Prueba", category: "Prueba", combinations: [ShortcutCombination(modifiers: [.shift, .command], key: "t")])
        assert(explicit.resolvedCombinations == chrome.resolvedCombinations.map { ShortcutCombination(modifiers: $0.modifiers + [.shift], key: $0.key) })

        let labels = KeyboardLabels.fromMappings([["HIDKeyboardModifierMappingSrc": 0x700000039, "HIDKeyboardModifierMappingDst": 0xff00000003]])
        assert(labels.name(.function) == "Bloq Mayús")
        assert(labels.name(.command) == "Command")
        assert(labels.text(for: maximize, fullNames: true) == "Control + Bloq Mayús + F")
        assert(labels.text(for: halves) == "⌃ Bloq Mayús ← / →")
        assert(labels.combination(modifiers: [.function], keys: []) == ["Bloq Mayús"])
        assert(KeyboardLabels.fromMappings([]).name(.function) == "Fn / 🌐")
        assert(KeyboardLabels.fromMappings([["HIDKeyboardModifierMappingSrc": 0x700000039, "HIDKeyboardModifierMappingDst": 0x700000039]]).name(.function) == "Fn / 🌐")

        func press(_ key: String, _ modifiers: Set<ModifierKey>, held: [String]? = nil, repeatKey: Bool = false) -> ShortcutKeyPress {
            ShortcutKeyPress(key: key, modifiers: modifiers, heldKeys: held ?? [key], isRepeat: repeatKey)
        }
        let chord = maximize.resolvedCombinations[0]
        assert(chord.matches(press("f", [.function, .control])))
        assert(!chord.matches(press("F", [.control])))
        assert(!chord.matches(press("F", [.function, .control, .shift])))
        assert(!chord.matches(press("G", [.function, .control])))
        assert(!chord.matches(press("F", [.function, .control], held: ["A", "F"])))
        assert(!chord.matches(press("F", [.function, .control], repeatKey: true)))
        assert(halves.resolvedCombinations.contains { $0.matches(press("→", [.function, .control])) })

        var waiting = PracticeSession(shortcut: maximize, waitingForRelease: true)
        assert(!waiting.receive(press("F", [.function, .control])))
        waiting.reconcile(modifiers: [.control], keys: [])
        assert(waiting.waitingForRelease)
        waiting.reconcile(modifiers: [], keys: [])
        assert(!waiting.waitingForRelease)
        assert(waiting.receive(press("F", [.function, .control])))
        assert(!waiting.receive(press("F", [.function, .control])))

        let practice = ShortcutPractice()
        assert(!practice.begin(maximize, isListening: false, modifiers: [], keys: []))
        let unknown = Shortcut(keys: "⌘ K ⌘ S", action: "Secuencia", category: "Referencia")
        assert(!practice.begin(unknown, isListening: true, modifiers: [], keys: []))
        assert(practice.begin(chrome, isListening: true, modifiers: [], keys: []))
        practice.validate(content: Content(title: "Atajos", shortcuts: all.reversed()), context: context, isListening: true)
        assert(practice.session != nil, "Reordenar no debe cancelar una práctica que sigue siendo válida.")
        practice.validate(content: Content(title: "Atajos", shortcuts: all), context: ApplicationContext(bundleIdentifier: "com.mitchellh.ghostty", name: "Ghostty"), isListening: true)
        assert(practice.session == nil)
        practice.begin(maximize, isListening: true, modifiers: [], keys: [])
        practice.validate(content: Content(title: "Atajos", shortcuts: all), context: context, isListening: true)
        assert(practice.session != nil, "Un atajo general sigue siendo válido al cambiar de app.")
        practice.validate(content: Content(title: "Atajos", shortcuts: [chrome]), context: context, isListening: true)
        assert(practice.session == nil, "Eliminar o editar el objetivo cancela la práctica.")
        practice.begin(chrome, isListening: true, modifiers: [], keys: [])
        practice.validate(content: Content(title: "Atajos", shortcuts: all), context: context, isListening: false)
        assert(practice.session == nil)

        practice.begin(maximize, isListening: true, modifiers: [], keys: [])
        practice.receive(press("F", [.function, .control]))
        assert(practice.session?.succeeded == true)
        RunLoop.main.run(until: Date().addingTimeInterval(2.1))
        assert(practice.session == nil, "La confirmación debe finalizar después de dos segundos.")
        practice.begin(maximize, isListening: true, modifiers: [], keys: [])
        practice.receive(press("F", [.function, .control]))
        practice.begin(chrome, isListening: true, modifiers: [], keys: [])
        RunLoop.main.run(until: Date().addingTimeInterval(2.1))
        assert(practice.session?.shortcut == chrome, "Un temporizador anterior no debe cancelar una nueva práctica.")
        practice.cancel()

        let naming = KeyboardNaming()
        naming.reload()
        print("OK: contenido antiguo, contexto, alternativas, nombres físicos, práctica exacta, cancelación y confirmación temporal.")
        print("Teclado de referencia: \(naming.reference.title); Fn: \(naming.labels.functionName).")
    }
}
