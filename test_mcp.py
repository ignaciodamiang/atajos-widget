"""End-to-end check: real MCP subprocess, atomic updates, live Swift reload."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time

server_path = Path(__file__).with_name("mcp_server.py")
runtime_path = Path.home() / "Library/Application Support/AtajosWidget/runtime.json"
client = subprocess.Popen([sys.executable, str(server_path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
sequence = 0

def request(method, params):
    global sequence
    sequence += 1
    client.stdin.write(json.dumps({"jsonrpc": "2.0", "id": sequence, "method": method, "params": params}) + "\n")
    client.stdin.flush()
    ready, _, _ = select.select([client.stdout], [], [], 5)
    assert ready, "El servidor MCP no respondió."
    reply = json.loads(client.stdout.readline())
    assert reply["id"] == sequence and "result" in reply, reply
    return reply["result"]

def tool(name, args=None):
    return request("tools/call", {"name": name, "arguments": args or {}})

def wait_for_title(title):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        state = json.loads(runtime_path.read_text())
        if state["title"] == title:
            assert state["visible"] and state["floating"], state
            os.kill(state["pid"], 0)
            return state
        time.sleep(0.1)
    raise AssertionError("El widget no recargó el título actualizado.")

original = None
try:
    initialized = request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke-test", "version": "1.0"}})
    assert initialized["protocolVersion"] == "2025-06-18"
    client.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
    client.stdin.flush()
    tools = request("tools/list", {})["tools"]
    assert {entry["name"] for entry in tools} == {"get_shortcuts", "update_shortcuts", "show_widget"}
    update_schema = next(entry for entry in tools if entry["name"] == "update_shortcuts")["inputSchema"]["properties"]["shortcuts"]["items"]["properties"]
    assert "apps" in update_schema and "combinations" in update_schema
    original = tool("get_shortcuts")["structuredContent"]["content"]
    assert not tool("show_widget")["isError"]
    invalid = tool("update_shortcuts", {"shortcuts": []})
    assert invalid["isError"]
    for fields in [{"apps": ["not a bundle"]}, {"combinations": [{"modifiers": ["function", "function"], "key": "F"}]}]:
        invalid = tool("update_shortcuts", {"shortcuts": [dict(original["shortcuts"][0], **fields)]})
        assert invalid["isError"]
    assert tool("get_shortcuts")["structuredContent"]["content"] == original
    active = tool("get_shortcuts")["structuredContent"]["widget"]["active_app"]["bundle_identifier"]
    test_row = {"keys": "⇧ F12", "action": "Prueba de contexto MCP", "category": "Prueba", "apps": [active or "com.atajos.test"], "combinations": [{"modifiers": ["shift"], "key": "F12"}]}
    test_rows = original["shortcuts"] + [test_row]
    updated = tool("update_shortcuts", {"title": "Atajos · prueba MCP", "shortcuts": test_rows})
    assert not updated["isError"]
    state = wait_for_title("Atajos · prueba MCP")
    assert state["shortcut_count"] == len(test_rows)
    app = state["active_app"]["bundle_identifier"]
    assert state["visible_shortcut_count"] == sum(not row.get("apps") or app in row["apps"] for row in test_rows)
    assert tool("get_shortcuts")["structuredContent"]["content"]["shortcuts"] == test_rows
    assert "fn_key_name" in state and "keyboard_reference" in state
    assert not tool("update_shortcuts", {"title": original["title"], "shortcuts": original["shortcuts"]})["isError"]
    wait_for_title(original["title"])
    print("OK: MCP, validación, contexto/combinaciones, recarga nativa y restauración del contenido.")
finally:
    if original is not None and client.poll() is None:
        tool("update_shortcuts", {"title": original["title"], "shortcuts": original["shortcuts"]})
    client.stdin.close()
    try:
        client.wait(timeout=5)
    except subprocess.TimeoutExpired:
        client.kill()
        client.wait()
