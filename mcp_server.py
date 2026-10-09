#!/usr/bin/env python3
"""Local, dependency-free stdio MCP server for the Atajos macOS panel."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

STATE_DIR = Path.home() / "Library/Application Support/AtajosWidget"
CONTENT_PATH = STATE_DIR / "content.json"
APP_PATH = Path.home() / "Applications/Atajos.app"
PROTOCOLS = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}

DEFAULT_CONTENT = {
    "title": "Atajos útiles",
    "shortcuts": [
        {"keys": "fn ⌃ F", "action": "Maximizar ventana", "category": "Ventanas"},
        {"keys": "fn ⌃ ← / →", "action": "Mitad izquierda / derecha", "category": "Ventanas"},
        {"keys": "⌃ ⌘ F", "action": "Pantalla completa", "category": "Ventanas"},
        {"keys": "⌘ M", "action": "Minimizar ventana", "category": "Ventanas"},
        {"keys": "⌘ Tab", "action": "Cambiar de app", "category": "Navegación"},
        {"keys": "⌘ Espacio", "action": "Buscar con Spotlight", "category": "Navegación"},
        {"keys": "⌘ W", "action": "Cerrar ventana o pestaña", "category": "Navegación"},
        {"keys": "⌘ ,", "action": "Ajustes de la app", "category": "Navegación"},
        {"keys": "⇧ ⌘ 4", "action": "Capturar un área", "category": "Capturas"},
        {"keys": "⇧ ⌘ 5", "action": "Capturar o grabar", "category": "Capturas"},
        {"keys": "⇧ ⌘ Z", "action": "Rehacer", "category": "Edición"},
        {"keys": "⌥ ← / →", "action": "Saltar entre palabras", "category": "Edición"},
    ],
}

MODIFIERS = ("command", "option", "control", "shift", "function")
MODIFIER_SYMBOLS = {"⌘": "command", "⌥": "option", "⌃": "control", "⇧": "shift", "🌐": "function"}
MODIFIER_WORDS = {
    "command": "command", "cmd": "command", "option": "option", "alt": "option",
    "control": "control", "ctrl": "control", "shift": "shift", "function": "function", "fn": "function",
}
KEY_ALIASES = {
    "space": "Espacio", "espacio": "Espacio", "tab": "Tab", "enter": "Enter", "return": "Enter",
    "esc": "Esc", "escape": "Esc", "backspace": "Borrar", "borrar": "Borrar", "delete": "Suprimir",
    "suprimir": "Suprimir", "home": "Inicio", "inicio": "Inicio", "end": "Fin", "fin": "Fin",
    "pageup": "Re Pág", "re pág": "Re Pág", "pagedown": "Av Pág", "av pág": "Av Pág",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
}

def normalize_key(value):
    if not isinstance(value, str):
        return None
    value = value.strip()
    if value.lower() in KEY_ALIASES:
        return KEY_ALIASES[value.lower()]
    if re.fullmatch(r"F([1-9]|1[0-2])", value, re.IGNORECASE):
        return value.upper()
    if len(value) == 1 and value.isprintable() and not value.isspace() and value not in MODIFIER_SYMBOLS:
        key = value.upper()
        return key if len(key) == 1 else None
    return None

def parse_combinations(label):
    result = []
    inherited = []
    for part in label.split(" / "):
        remaining = part.strip()
        modifiers = []
        while remaining:
            if remaining[0] in MODIFIER_SYMBOLS:
                modifier = MODIFIER_SYMBOLS[remaining[0]]
                remaining = remaining[1:]
            else:
                match = next((word for word in MODIFIER_WORDS if remaining.lower().startswith(word)
                              and (len(remaining) == len(word) or remaining[len(word)] in " +⌘⌥⌃⇧🌐")), None)
                if match is None:
                    break
                modifier = MODIFIER_WORDS[match]
                remaining = remaining[len(match):]
            if modifier not in modifiers:
                modifiers.append(modifier)
            remaining = remaining.strip(" +\t")
        if not modifiers and result:
            modifiers = inherited
        key = normalize_key(remaining)
        if key is None:
            return []
        modifiers = [modifier for modifier in MODIFIERS if modifier in modifiers]
        if not result:
            inherited = modifiers
        result.append({"modifiers": modifiers, "key": key})
    return result

def app_shortcut(keys, action, category, bundle_identifier):
    return {"keys": keys, "action": action, "category": category, "apps": [bundle_identifier], "combinations": parse_combinations(keys)}

APP_SHORTCUTS = [
    app_shortcut("⌘ N", "Nueva ventana", "Finder", "com.apple.finder"),
    app_shortcut("⇧ ⌘ N", "Nueva carpeta", "Finder", "com.apple.finder"),
    app_shortcut("⇧ ⌘ G", "Ir a una carpeta", "Finder", "com.apple.finder"),
    app_shortcut("⌘ ↑", "Carpeta superior", "Finder", "com.apple.finder"),
    app_shortcut("⌘ L", "Barra de direcciones", "Chrome", "com.google.Chrome"),
    app_shortcut("⌘ T", "Nueva pestaña", "Chrome", "com.google.Chrome"),
    app_shortcut("⇧ ⌘ T", "Recuperar pestaña cerrada", "Chrome", "com.google.Chrome"),
    app_shortcut("⌘ F", "Buscar en la página", "Chrome", "com.google.Chrome"),
    app_shortcut("⌘ P", "Abrir archivo", "Cursor", "com.todesktop.230313mzl4w4u92"),
    app_shortcut("⇧ ⌘ P", "Paleta de comandos", "Cursor", "com.todesktop.230313mzl4w4u92"),
    app_shortcut("⌘ B", "Mostrar / ocultar barra lateral", "Cursor", "com.todesktop.230313mzl4w4u92"),
    app_shortcut("⌘ K", "Edición con IA en el editor", "Cursor", "com.todesktop.230313mzl4w4u92"),
    app_shortcut("⌘ T", "Nueva pestaña", "Ghostty", "com.mitchellh.ghostty"),
    app_shortcut("⌘ N", "Nueva ventana", "Ghostty", "com.mitchellh.ghostty"),
    app_shortcut("⌘ D", "Dividir a la derecha", "Ghostty", "com.mitchellh.ghostty"),
    app_shortcut("⇧ ⌘ D", "Dividir hacia abajo", "Ghostty", "com.mitchellh.ghostty"),
]
DEFAULT_CONTENT["shortcuts"].extend(APP_SHORTCUTS)

def validate_combinations(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 8:
        raise ValueError("combinations debe contener entre 1 y 8 alternativas.")
    result = []
    for combination in value:
        if not isinstance(combination, dict) or set(combination) != {"modifiers", "key"}:
            raise ValueError("Cada combinación necesita únicamente modifiers y key.")
        modifiers = combination["modifiers"]
        if (not isinstance(modifiers, list) or len(modifiers) > 5
                or any(not isinstance(modifier, str) or modifier not in MODIFIERS for modifier in modifiers)
                or len(set(modifiers)) != len(modifiers)):
            raise ValueError("modifiers debe contener modificadores válidos sin repetir.")
        key = normalize_key(combination["key"])
        if key is None:
            raise ValueError("key debe ser una tecla: letra, número, símbolo, flecha, F1–F12 o tecla especial.")
        result.append({"modifiers": [modifier for modifier in MODIFIERS if modifier in modifiers], "key": key})
    return result

def text_field(value, name, max_length):
    if not isinstance(value, str) or not value.strip() or len(value) > max_length:
        raise ValueError(f"{name} debe ser texto de 1 a {max_length} caracteres.")
    if any(ord(c) < 32 for c in value):
        raise ValueError(f"{name} no permite caracteres de control.")
    return value.strip()

def validate_content(value):
    if not isinstance(value, dict):
        raise ValueError("El contenido debe ser un objeto.")
    title = text_field(value.get("title"), "title", 60)
    rows = value.get("shortcuts")
    if not isinstance(rows, list) or not 1 <= len(rows) <= 40:
        raise ValueError("shortcuts debe contener entre 1 y 40 atajos.")
    shortcuts = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("Cada atajo debe ser un objeto.")
        if set(row) - {"keys", "action", "category", "apps", "combinations"}:
            raise ValueError("Campos de atajo desconocidos.")
        shortcut = {
            "keys": text_field(row.get("keys"), "keys", 35),
            "action": text_field(row.get("action"), "action", 100),
            "category": text_field(row.get("category"), "category", 40),
        }
        if "apps" in row:
            apps = row["apps"]
            if (not isinstance(apps, list) or len(apps) > 8
                    or any(not isinstance(app, str) or len(app) > 200 or not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+", app) for app in apps)
                    or len(set(apps)) != len(apps)):
                raise ValueError("apps debe contener hasta 8 identificadores de apps válidos sin repetir; una lista vacía significa general.")
            shortcut["apps"] = apps
        if "combinations" in row:
            shortcut["combinations"] = validate_combinations(row["combinations"])
        shortcuts.append(shortcut)
    return {"title": title, "shortcuts": shortcuts}

def atomic_write(content):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=STATE_DIR, delete=False) as handle:
            temporary = handle.name
            json.dump(content, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, CONTENT_PATH)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)

def read_content():
    with CONTENT_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)

def migrate_content():
    """Back up and extend an existing list once; never overwrite user-edited rows."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with (STATE_DIR / "content.lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        previous = read_content()
        rows = []
        for row in previous["shortcuts"]:
            row = dict(row)
            if "combinations" not in row:
                combinations = parse_combinations(row["keys"])
                if combinations:
                    row["combinations"] = combinations
            rows.append(row)
        for shortcut in APP_SHORTCUTS:
            if not any(row.get("apps") == shortcut["apps"] and row["keys"] == shortcut["keys"] for row in rows):
                rows.append(shortcut)
        content = validate_content({"title": previous["title"], "shortcuts": rows})
        if content == {"title": previous["title"], "shortcuts": previous["shortcuts"]}:
            return {"migrated": False}
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = STATE_DIR / f"content.before-context-{stamp}.json"
        backup.write_bytes(CONTENT_PATH.read_bytes())
        content["updated_at"] = datetime.now(timezone.utc).isoformat()
        atomic_write(content)
        return {"migrated": True, "backup": str(backup), "shortcut_count": len(rows)}

def get_widget():
    content = read_content()
    runtime = {}
    try:
        runtime = json.loads((STATE_DIR / "runtime.json").read_text(encoding="utf-8"))
        os.kill(runtime["pid"], 0)
        runtime["running"] = True
    except (OSError, ValueError, KeyError):
        runtime = {"running": False}
    return {"content": content, "widget": runtime}

SHORTCUT_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "properties": {
        "keys": {"type": "string", "minLength": 1, "maxLength": 35},
        "action": {"type": "string", "minLength": 1, "maxLength": 100},
        "category": {"type": "string", "minLength": 1, "maxLength": 40},
        "apps": {"type": "array", "maxItems": 8, "uniqueItems": True, "items": {"type": "string", "maxLength": 200, "pattern": "^[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)+$"}, "description": "Identificadores bundle de las apps donde aparece el atajo. Ausente o vacío: general."},
        "combinations": {"type": "array", "minItems": 1, "maxItems": 8, "items": {
            "type": "object", "additionalProperties": False,
            "properties": {
                "modifiers": {"type": "array", "maxItems": 5, "uniqueItems": True, "items": {"type": "string", "enum": list(MODIFIERS)}},
                "key": {"type": "string", "minLength": 1, "maxLength": 20},
            }, "required": ["modifiers", "key"],
        }, "description": "Alternativas para practicar. Usa modificadores semánticos, incluido function aunque la tecla física sea Bloq Mayús. Si se omite, se interpreta keys cuando es una combinación simple."},
    }, "required": ["keys", "action", "category"],
}
TOOLS = [
    {
        "name": "get_shortcuts",
        "description": "Lee todos los atajos (generales y por app), sus combinaciones y el estado del widget, incluida la app activa. No devuelve pulsaciones.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
    },
    {
        "name": "update_shortcuts",
        "description": "Reemplaza la lista de atajos. Lee get_shortcuts primero y conserva apps y combinations para mantener contexto y práctica. El widget recarga el contenido en menos de un segundo.",
        "inputSchema": {
            "type": "object", "additionalProperties": False,
            "properties": {
                "title": {"type": "string", "minLength": 1, "maxLength": 60},
                "shortcuts": {"type": "array", "minItems": 1, "maxItems": 40, "items": SHORTCUT_SCHEMA},
            }, "required": ["shortcuts"],
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
    },
    {
        "name": "show_widget",
        "description": "Abre o vuelve a mostrar el widget flotante Atajos sin cambiar su contenido.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
    },
]

def call_tool(name, args):
    if not isinstance(args, dict):
        raise ValueError("arguments debe ser un objeto.")
    if name == "get_shortcuts":
        if args:
            raise ValueError("get_shortcuts no recibe argumentos.")
        return get_widget()
    if name == "update_shortcuts":
        if set(args) - {"title", "shortcuts"}:
            raise ValueError("Argumentos desconocidos.")
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with (STATE_DIR / "content.lock").open("a") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            previous = read_content()
            content = validate_content({"title": args.get("title", previous["title"]), "shortcuts": args.get("shortcuts")})
            content["updated_at"] = datetime.now(timezone.utc).isoformat()
            atomic_write(content)
        return {"updated": True, "content": content}
    if name == "show_widget":
        if args:
            raise ValueError("show_widget no recibe argumentos.")
        subprocess.run(["/usr/bin/open", "-g", str(APP_PATH)], check=True, capture_output=True, timeout=10)
        return {"opened": True}
    raise ValueError(f"Herramienta desconocida: {name}")

def dispatch(request):
    method = request.get("method")
    params = request.get("params", {})
    if method == "initialize":
        requested = params.get("protocolVersion")
        return {
            "protocolVersion": requested if requested in PROTOCOLS else "2025-06-18",
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "atajos-widget", "version": "1.1.0"},
            "instructions": "Gestiona una chuleta de atajos flotante en la Mac del usuario. Conserva los atajos existentes, incluidos apps y combinations, salvo que solicite reemplazarlos. Verifica combinaciones nuevas con la documentación de la app. La práctica compara pulsaciones sin bloquear sus acciones; function representa Fn/Globo de macOS, aunque se muestre Bloq Mayús por el mapa del Keychron.",
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        try:
            result = call_tool(params.get("name"), params.get("arguments", {}))
            return {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "structuredContent": result, "isError": False}
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            return {"content": [{"type": "text", "text": str(error)}], "isError": True}
    raise LookupError("Método no soportado")

def serve():
    for line in sys.stdin:
        if not line.strip():
            continue
        request_id = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
                raise ValueError("Petición JSON-RPC inválida")
            if "id" not in request:
                continue
            request_id = request["id"]
            params = request.get("params", {})
            if not isinstance(params, dict):
                raise ValueError("params debe ser un objeto")
            response = {"jsonrpc": "2.0", "id": request_id, "result": dispatch(request)}
        except json.JSONDecodeError:
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "JSON inválido"}}
        except LookupError as error:
            response = {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32601, "message": str(error)}}
        except (ValueError, TypeError, AttributeError) as error:
            response = {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32602, "message": str(error)}}
        except Exception as error:
            print(f"atajos-widget: {error}", file=sys.stderr)
            response = {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32603, "message": "Error interno"}}
        print(json.dumps(response, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    if sys.argv[1:] == ["--seed"]:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        if not CONTENT_PATH.exists():
            atomic_write(validate_content(DEFAULT_CONTENT))
        print(str(CONTENT_PATH))
    elif sys.argv[1:] == ["--migrate"]:
        print(json.dumps(migrate_content(), ensure_ascii=False))
    else:
        serve()
