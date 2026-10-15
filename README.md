# Atajos — macOS keyboard shortcut overlay and trainer

Atajos is a native floating macOS panel for a curated list of keyboard shortcuts,
with a local stdio MCP server for reading and updating that list. It shows
shortcuts for the active app alongside general shortcuts, previews held keys, and
lets you practice a combination without sending it to another app. The list is
maintained in local JSON; Atajos does not automatically discover every shortcut
in an installed app.

The source is available under the [MIT license](LICENSE).

## Build from source

You need macOS, Xcode Command Line Tools (`swiftc` and `codesign`), and Python 3.
Clone the repository, then run these commands from its directory:

```sh
bash build.sh
open "$HOME/Applications/Atajos.app"
```

The build creates `~/Applications/Atajos.app`, signs it locally, and seeds
`~/Library/Application Support/AtajosWidget/content.json` only if it does not
already exist. It preserves existing shortcut content. There is no packaged or
notarized download in this repository. macOS compatibility has not been checked
across releases.

## Panel

Drag its background to move it, use the size button to cycle through compact,
normal, and full-height modes, and use the X to hide it. Full-height mode spans
the available height of the panel's current screen, excluding the menu bar and
Dock. The menu-bar command icon reopens the panel, changes its size, or quits the
app. The selected mode and normal position survive a restart; leaving full-height
mode restores the normal placement. Moving between displays or changing the
screen layout keeps the panel inside the available area.

## App shortcuts

The active app's shortcuts appear before general shortcuts. The initial profiles
cover Finder, Chrome, Cursor, and Ghostty; other apps show general shortcuts.
These profiles are examples rather than a scan of each app's live menu. You can
replace or extend them through the local MCP server.
The panel does not take keyboard focus from the active app. App detection uses
`NSWorkspace` without requiring Accessibility.

## Practice

Click a shortcut row to start practicing. Practice requires Input Monitoring and
Accessibility; if Accessibility is missing, clicking a row opens its permission
request instead. The menu also provides `Permitir práctica con teclas bloqueadas…`.
Practice never silently falls back to observing shortcuts that execute their actions.

The `PRACTICAR` card appears below `TECLAS PRESIONADAS`. Once previously held keys
have been released, practice consumes keyboard events so attempts do not reach
other apps. The first exact match is also consumed and shows `Correcto` for two
seconds. Normal input resumes immediately after that match. Repeats and releases
belonging to already consumed keys remain suppressed until those keys are released.

Escape or the card's X cancels practice and restores normal input. Escape can
still be practiced when it is the target combination. Hiding or collapsing the
panel, changing to an incompatible app, editing/removing the target, losing the
required permissions, or an event-tap interruption also cancels practice.

Matching requires the exact key and modifiers, supports alternatives such as
left/right, and ignores repeats. Multi-step sequences remain reference-only.
Confirmation verifies the combination, not the action's result in another app.

## Live keys and permissions

`Teclas en vivo` shows Command, Option, Control, Shift, and macOS Fn/Globe.
The preview shows only currently held keys; it keeps no typing history.
Key names follow the selected keyboard reference. With the Keychron mapping,
Fn appears as `Bloq Mayús` in the preview, shortcut list, and practice card.
The menu offers Mac (the initial reference) and Keychron B6 Pro. Mapping preferences are read
every two seconds; the app does not change system keyboard mappings.

Enable **Atajos** under **System Settings → Privacy & Security**:

- **Input Monitoring** enables letters, arrows, and shortcut detection. The menu's
  `Habilitar detección de atajos…` requests it.
- **Accessibility** enables blocking during practice. The menu's
  `Permitir práctica con teclas bloqueadas…` requests it.

Outside practice, events pass through unchanged. The monitor uses an active
`CGEvent` tap when Accessibility permits it and a passive listener otherwise.
If macOS requests a restart after granting access, close and reopen Atajos.

The build preserves the designated requirement `identifier "local.nacho.atajos-widget"`.
A permission granted to an older hash-bound build can remain visibly enabled
while macOS rejects the current app. Recreate only that app's affected permission
through System Settings or a targeted `tccutil` reset, then grant it again.
Do not reset unrelated apps' permissions.

### Fn on Keychron B6 Pro

The factory Fn key activates a firmware layer (`MO(1)` in Mac mode); it does not
emit macOS Fn on its own. The preview shows the events that actually reach macOS.
Mapping Caps Lock to Fn/Globe in macOS provides that modifier.

Fn detection accepts the global modifier flag even when querying key code 63
returns false. Intrinsic function flags on arrow/F-key events are not treated as
physical Fn presses. During interception, reconciliation uses HID state so dropped
events do not leave the key preview dependent on application delivery.

## MCP updates

Configure an MCP client to start `python3` with the absolute path to
`mcp_server.py` as its argument. The server uses stdio, runs locally, and needs
no extra packages or API keys. Client registration varies; see your client's MCP
documentation. Reconnect the client after changing the server source. Existing
processes keep their previous version until restarted. Servers predating 1.1
discard the `apps` and `combinations` fields and must not be used to update
contextual shortcuts.

- `get_shortcuts` reads the full list and panel state.
- `update_shortcuts` replaces the full list, preserving the title if omitted.
- `show_widget` opens or shows the panel without changing its content.

Read the list before updating it. Preserve existing `apps` and `combinations`.
Updates are atomic and reload every 750 ms.

Example `update_shortcuts` arguments:

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

`apps` is optional: missing or empty means general. Otherwise it contains up to
eight exact bundle identifiers. `combinations` accepts up to eight alternatives,
using `command`, `option`, `control`, `shift`, and `function`. Physical names affect
presentation only. Without explicit combinations, simple `keys` labels are parsed.

Content lives in `~/Library/Application Support/AtajosWidget/content.json`.
`runtime.json` includes the active app, counts, keyboard reference, window state,
Input Monitoring and Accessibility permission state, and `can_block_shortcuts`.
`size_mode` is `compact`, `normal`, or `full-height`; `collapsed` remains true only
in compact mode.
Its `practice` object publishes only `active`, `blocking`, and `succeeded` booleans.
Neither files nor MCP responses contain pressed keys or typing history.

`python3 mcp_server.py --migrate` adds initial app profiles to older content,
preserves custom entries, and backs up the original content. Repeating it does
not duplicate profiles.

## Contributing

Bug reports and focused changes are welcome. Open an issue with the macOS version,
affected app, and expected behavior. Send code changes against `develop` and
describe how you checked them on macOS, especially when changing keyboard event
handling or permissions. Keep personal shortcut lists and captured input out of
issues and pull requests.

## Development verification

The build stages the binary in the app bundle, replaces it atomically,
and signs it with the stable designated requirement. A pre-existing staging file
is rejected so another build's output is not overwritten.

Use a focused native smoke check for interception: a wrong attempt and the first
correct attempt must be absent downstream; input after success and after Escape
must pass through. Use a controlled foreground app. Release held keys before
starting. Do not send verification shortcuts to the user's working terminal.

Existing verification commands:

```sh
python3 test_mcp.py
python3 -m unittest discover -s . -p test_content.py -v
```

The MCP check temporarily edits content and restores it. Swift checks in
`test_keyboard.swift` and `test_shortcuts.swift` cover modifier parsing, context,
matching, release gating, cancellation, and feedback duration. They do not prove
global event interception; that requires the app's macOS permissions and a native
event-delivery check.

## Sources

Shortcuts: [Apple keyboard shortcuts](https://support.apple.com/en-us/102650),
[window tiling](https://support.apple.com/en-gb/guide/mac-help/mchl9674d0b0/26/mac/26),
[Chrome](https://support.google.com/chrome/answer/157179?hl=en),
[Cursor](https://cursor.com/docs/reference/keyboard-shortcuts),
[VS Code for Mac](https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf),
and [Ghostty](https://ghostty.org/docs/config/keybind).

Input handling: [CGEvent taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[Input Monitoring](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()),
and [Accessibility](https://support.apple.com/guide/mac-help/mh43185/mac).
Keychron: [manual](https://www.keychron.com/pages/keychron-b6-pro-user-manual) and
[factory keymap](https://github.com/Keychron/zmk/blob/keychron_bpro/app/boards/shields/keychron/b6/us/keychron_b6_us.keymap).

For Codex, [the MCP setup guide](https://developers.openai.com/codex/mcp)
explains how to register or remove a local stdio server.
The app starts manually; no login service is installed.
