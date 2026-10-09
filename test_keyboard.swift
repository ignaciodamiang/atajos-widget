import AppKit

@main
struct KeyboardChecks {
    static func main() {
        assert(ModifierKey.pressed(in: [.command, .control]) == [.command, .control])
        assert(ModifierKey.pressed(in: [.capsLock, .numericPad]).isEmpty)
        assert(ModifierKey.pressed(in: [.option, .shift, .function]) == [.option, .shift, .function])
        assert(ModifierKey.live(sessionFlags: [.control, .function], functionKeyDown: false) == [.control, .function],
               "Fn debe reconocerse por su estado modificador aunque keyState(63) sea falso.")
        assert(ModifierKey.live(sessionFlags: [], functionKeyDown: true) == [.function])
        assert(ModifierKey.keyEvent(eventFlags: [.control, .function], sessionFlags: .control, functionKeyDown: false) == [.control],
               "La marca function de una flecha no debe simular que Fn está presionada.")
        assert(ModifierKey.keyEvent(eventFlags: [.control, .function], sessionFlags: [.control, .function], functionKeyDown: false) == [.control, .function])

        var state = ShortcutPreview()
        state.keyDown(code: 0, label: "A")
        assert(state.combination(modifiers: []) == ["A"], "Una letra sola aparece mientras está presionada.")
        state.keyDown(code: 1, label: "S")
        assert(state.combination(modifiers: [.shift]) == ["Shift", "A", "S"])
        state.keyUp(code: 0)
        assert(state.keyLabels == ["S"], "Soltar una tecla conserva las otras que siguen presionadas.")
        state.keyUp(code: 1)
        assert(state.combination(modifiers: []).isEmpty, "El preview se vacía al soltar todas las teclas.")

        state.keyDown(code: 3, label: "F")
        assert(state.combination(modifiers: [.control, .function]) == ["Control", "Fn / 🌐", "F"])
        assert(state.keyLabels == ["F"])
        state.keyDown(code: 3, label: "F")
        assert(state.keyLabels == ["F"], "La repetición de tecla no duplica la combinación.")
        state.keyUp(code: 3)
        assert(state.keyLabels.isEmpty)
        assert(state.combination(modifiers: [.control]) == ["Control"], "Solo se muestra el modificador que sigue presionado.")

        state.keyDown(code: 6, label: "Z")
        assert(state.combination(modifiers: [.command, .shift]) == ["Command", "Shift", "Z"])
        assert(state.combination(modifiers: []) == ["Z"], "Soltar los modificadores no borra una letra aún presionada.")
        state.releaseAll()
        assert(state.keyLabels.isEmpty)

        for (code, name) in [(UInt16(123), "←"), (UInt16(49), "Espacio"), (UInt16(48), "Tab"), (UInt16(122), "F1")] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: "", charactersIgnoringModifiers: "",
                                        isARepeat: false, keyCode: code)!
            assert(KeyboardPreview.keyLabel(event) == name)
        }
        print("OK: modificadores, teclas solas, combinaciones simultáneas, repetición, liberación y teclas especiales.")
    }
}
