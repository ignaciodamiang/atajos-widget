# Atajos

Panel nativo flotante para macOS, instalado en `~/Applications/Atajos.app`.
Se mueve arrastrando el fondo, se pliega con la flecha y se oculta con la X.
El menú ⌘ de la barra superior permite volver a mostrarlo o salir.
La posición y el estado plegado se conservan al reiniciar.

## Atajos según la app

El panel muestra el nombre de la app activa. Sus atajos aparecen primero,
seguidos de los generales. La lista inicial tiene 12 atajos generales y cuatro
para cada una de estas apps: Finder, Chrome, Cursor y Ghostty.
Las demás apps muestran los generales. Interactuar con el panel no cambia el
foco de la otra app; la detección usa `NSWorkspace` y no requiere Accesibilidad.

## Practicar

Hacer clic en una fila inicia la práctica de ese atajo cuando la detección de
teclas está habilitada. El panel muestra el objetivo y permite cancelar.
Una combinación correcta muestra **Correcto** en verde durante dos segundos.
El atajo también ejecuta su acción habitual en la app: el monitor solo observa.
La confirmación indica que se detectaron las teclas correctas, sin comprobar
el resultado de la acción en la otra app.

La comparación exige la tecla y los modificadores exactos; admite alternativas
como izquierda/derecha e ignora repeticiones. Si ya hay teclas presionadas,
hay que soltarlas antes de empezar. Ocultar o plegar el widget, cambiar a una
app incompatible, editar/eliminar el objetivo o perder el permiso cancela la práctica.
Las secuencias de varios pasos se conservan como referencia y no admiten práctica.

## Ver las teclas que presionás

La sección **Teclas en vivo** muestra los nombres de Command, Option, Control,
Shift y Fn/Globo; cada tecla se ilumina mientras está presionada.
Los nombres se adaptan al teclado de referencia: con la asignación actual del
Keychron, Fn aparece como **Bloq Mayús** en el visor, la lista y la práctica.
El submenú **Teclado de referencia** permite elegir Keychron B6 Pro o teclado Mac.
Las asignaciones de modificadores se leen cada dos segundos; el widget no las cambia.
El preview muestra las teclas que están presionadas en ese momento, incluyendo
letras solas, flechas y teclas especiales; se vacía al soltarlas.
Para recibir letras y flechas de otras apps, se necesita el permiso de
**Privacidad y seguridad → Monitoreo de entrada → Atajos**.
El menú ⌘ de la barra superior conserva **Habilitar detección de atajos…**
para solicitar ese permiso; el panel no muestra un botón de habilitación.
El monitor observa eventos sin alterar los atajos de otras apps.

Las teclas activas se mantienen en memoria, sin historial: no se guardan en archivos ni se
incluyen en las respuestas MCP. `runtime.json` publica si el permiso y
la detección están activos, la app actual, el teclado de referencia y el estado del panel.

Si macOS solicita salir y reabrir Atajos después de habilitar el permiso,
volver a abrir `~/Applications/Atajos.app`.

### Fn en teclados Keychron B6 Pro

El visor muestra Fn/Globo de macOS. En el mapa de fábrica del B6 Pro, la Fn
física activa otra capa dentro del teclado (`MO(1)` en modo Mac); no envía
por sí sola el modificador Fn de macOS. Las combinaciones transformadas por el
teclado se muestran según las teclas que efectivamente llegan a macOS.

La detección de Fn utiliza el estado global de los modificadores y no descarta
una señal válida si la consulta del código de tecla 63 devuelve falso.
Las marcas `function` intrínsecas de eventos de flechas o F1–F12 tampoco se
interpretan como una pulsación física de Fn.

## Actualizar mediante MCP

El servidor local `atajos-widget` está registrado en `~/.codex/config.toml`.
Reiniciar el cliente de Codex permite cargar la nueva conexión.
Después de esta actualización, reiniciar la conexión o el cliente también carga
el esquema nuevo: los servidores que ya estaban abiertos siguen ejecutando la
versión anterior hasta reiniciarse. Evitar escrituras con esa versión anterior,
que descarta los campos nuevos `apps` y `combinations`.

- `get_shortcuts`: lee la lista completa, metadatos y el estado del panel.
- `update_shortcuts`: reemplaza la lista completa; conserva el título si se omite.
- `show_widget`: abre la app o vuelve a mostrar el panel oculto.

Leer los atajos antes de modificarlos para conservar los que el usuario no pidió cambiar.
Conservar también `apps` y `combinations` al reenviar filas existentes.
Las categorías se muestran en el orden de cada grupo (app y generales).
Los cambios se guardan de forma atómica y el panel los carga cada 750 ms.
La conexión utiliza stdio local y no requiere paquetes adicionales ni API keys.

Ejemplo de argumentos para `update_shortcuts`:

```json
{
  "title": "Atajos útiles",
  "shortcuts": [
    {
      "keys": "fn ⌃ F", "action": "Maximizar ventana", "category": "Ventanas",
      "combinations": [{"modifiers": ["control", "function"], "key": "F"}]
    },
    {
      "keys": "⌘ T", "action": "Nueva pestaña", "category": "Chrome",
      "apps": ["com.google.Chrome"],
      "combinations": [{"modifiers": ["command"], "key": "T"}]
    }
  ]
}
```

`apps` es opcional: ausente o vacío significa general. Una lista no vacía
contiene hasta ocho identificadores bundle exactos. `combinations` es opcional
y contiene hasta ocho alternativas con `modifiers` y `key`. Los modificadores
son `command`, `option`, `control`, `shift` y `function`; los nombres físicos
solo afectan la presentación, no estos valores. La tecla puede ser una letra,
número, símbolo, flecha, F1–F12 o tecla especial como `Tab`, `Enter` o `Espacio`.
Si se omite, el widget interpreta la notación simple de `keys`, incluidas
alternativas con ` / `. Con combinaciones explícitas, la presentación se genera
desde ellas para que el objetivo mostrado coincida con lo que se verifica.

`runtime.json` incorpora `active_app` (`bundle_identifier`, `name`),
`visible_shortcut_count`, `keyboard_reference` y `fn_key_name`.
`shortcut_count` sigue siendo el total de la lista; no se publican pulsaciones.

Para migrar una lista anterior, `python3 mcp_server.py --migrate` agrega los
perfiles iniciales, conserva las filas personalizadas y crea un respaldo
`content.before-context-*.json`. Repetir la migración no duplica los perfiles.

Para registrar de nuevo la conexión:

```sh
codex mcp add atajos-widget -- /usr/bin/python3 /Users/nachogonzalez/source/atajos-widget/mcp_server.py
```

El contenido está en `~/Library/Application Support/AtajosWidget/content.json`.
El estado de la app está en `runtime.json` dentro de la misma carpeta.

## Compilar y verificar

```sh
zsh /Users/nachogonzalez/source/atajos-widget/build.sh
open /Users/nachogonzalez/Applications/Atajos.app
python3 /Users/nachogonzalez/source/atajos-widget/test_mcp.py
python3 -m unittest discover -s /Users/nachogonzalez/source/atajos-widget -p test_content.py -v
swiftc /Users/nachogonzalez/source/atajos-widget/Shortcuts.swift /Users/nachogonzalez/source/atajos-widget/KeyboardPreview.swift /Users/nachogonzalez/source/atajos-widget/test_keyboard.swift -o /tmp/atajos-keyboard-checks
/tmp/atajos-keyboard-checks
swiftc /Users/nachogonzalez/source/atajos-widget/Shortcuts.swift /Users/nachogonzalez/source/atajos-widget/KeyboardPreview.swift /Users/nachogonzalez/source/atajos-widget/test_shortcuts.swift -o /tmp/atajos-shortcut-checks
/tmp/atajos-shortcut-checks
```

La prueba verifica el protocolo MCP, las herramientas, la validación de cambios
y la recarga real del widget; al terminar restaura el título y los atajos previos.
Las pruebas de contenido/migración usan un directorio temporal. Las pruebas Swift
verifican contexto, nombres, comparación, liberación, cancelación y duración del feedback.
La comprobación de pulsaciones globales reales requiere el permiso de Monitoreo
de entrada y el teclado físico; las pruebas no solicitan permisos ni envían teclas a otras apps.

## Fuentes

Atajos verificados en [Apple: atajos de teclado](https://support.apple.com/en-us/102650)
y [Apple: mosaico de ventanas](https://support.apple.com/en-gb/guide/mac-help/mchl9674d0b0/26/mac/26).
Perfiles: [Chrome](https://support.google.com/chrome/answer/157179?hl=en),
[Cursor](https://cursor.com/docs/reference/keyboard-shortcuts), su base de
[VS Code para Mac](https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf)
y [Ghostty](https://ghostty.org/docs/config/keybind). Los atajos de Ghostty se
comprobaron con `ghostty +list-keybinds --default` en la instalación local.
Registro de MCP según la [documentación oficial de OpenAI](https://developers.openai.com/codex/mcp).
La detección usa un [CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
con la opción `listenOnly` y [Monitoreo de entrada](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()).
El comportamiento de Fn del B6 Pro está documentado en el
[manual de Keychron](https://www.keychron.com/pages/keychron-b6-pro-user-manual)
y en su [mapa de fábrica](https://github.com/Keychron/zmk/blob/keychron_bpro/app/boards/shields/keychron/b6/us/keychron_b6_us.keymap).

Para quitar la conexión: `codex mcp remove atajos-widget`.
La app se inicia manualmente; no se instaló un servicio de inicio de sesión.
