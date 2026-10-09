"""Content/schema/migration checks run in a temporary directory."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import mcp_server as server


class ContentChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="atajos-content-tests-")
        self.state = Path(self.directory.name)
        self.path = self.state / "content.json"
        self.patches = [patch.object(server, "STATE_DIR", self.state), patch.object(server, "CONTENT_PATH", self.path)]
        for replacement in self.patches:
            replacement.start()
        self.original = {"title": "Mis atajos", "shortcuts": [{"keys": "fn ⌃ ← / →", "action": "Mis ventanas", "category": "Propios"}]}
        server.atomic_write(self.original)

    def tearDown(self):
        for replacement in reversed(self.patches):
            replacement.stop()
        self.directory.cleanup()

    def test_migration_backups_preserves_and_is_idempotent(self):
        before = self.path.read_bytes()
        result = server.migrate_content()
        migrated = server.read_content()
        self.assertEqual(Path(result["backup"]).read_bytes(), before)
        self.assertEqual(migrated["title"], self.original["title"])
        self.assertEqual(migrated["shortcuts"][0]["action"], "Mis ventanas")
        self.assertEqual(migrated["shortcuts"][0]["category"], "Propios")
        self.assertEqual(migrated["shortcuts"][0]["combinations"], [
            {"modifiers": ["control", "function"], "key": "←"},
            {"modifiers": ["control", "function"], "key": "→"},
        ])
        self.assertEqual(len(migrated["shortcuts"]), 17)
        self.assertFalse(server.migrate_content()["migrated"])
        self.assertEqual(server.read_content(), migrated)
        self.assertEqual(len(list(self.state.glob("content.before-context-*.json"))), 1)

    def test_legacy_updates_and_new_metadata_roundtrip(self):
        updated = server.call_tool("update_shortcuts", {"shortcuts": self.original["shortcuts"]})
        self.assertEqual(updated["content"]["shortcuts"], self.original["shortcuts"])
        row = {"keys": "⌘ T", "action": "Nueva pestaña", "category": "Chrome", "apps": ["com.google.Chrome"],
               "combinations": [{"modifiers": ["shift", "command"], "key": "t"}]}
        result = server.call_tool("update_shortcuts", {"shortcuts": [row]})
        actual = result["content"]["shortcuts"][0]
        self.assertEqual(actual["apps"], row["apps"])
        self.assertEqual(actual["combinations"], [{"modifiers": ["command", "shift"], "key": "T"}])
        self.assertEqual(server.get_widget()["content"]["shortcuts"][0], actual)

    def test_invalid_metadata_does_not_write(self):
        bad_fields = [
            {"apps": ["not a bundle"]}, {"apps": ["com.google.Chrome", "com.google.Chrome"]},
            {"combinations": []}, {"combinations": [{"modifiers": ["capsLock"], "key": "F"}]},
            {"combinations": [{"modifiers": ["function", "function"], "key": "F"}]},
            {"combinations": [{"modifiers": [], "key": "not a key"}]},
            {"combinations": [{"modifiers": [], "key": "⌘"}]},
            {"combinations": [{"modifiers": [], "key": "F", "extra": True}]},
        ]
        before = self.path.read_bytes()
        for fields in bad_fields:
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                server.call_tool("update_shortcuts", {"shortcuts": [dict(self.original["shortcuts"][0], **fields)]})
            self.assertEqual(self.path.read_bytes(), before)

    def test_unsupported_sequence_stays_readable(self):
        self.assertEqual(server.parse_combinations("⌘ K ⌘ S"), [])
        self.assertEqual(server.parse_combinations("⌘ /"), [{"modifiers": ["command"], "key": "/"}])
        self.assertEqual(server.parse_combinations("Cmd + Shift + t"), [{"modifiers": ["command", "shift"], "key": "T"}])
        self.assertEqual(server.parse_combinations("⇧⌘G"), [{"modifiers": ["command", "shift"], "key": "G"}])

    def test_migration_does_not_overwrite_user_profile(self):
        custom = dict(server.APP_SHORTCUTS[0], action="Mi nombre para esta acción")
        self.original["shortcuts"].append(custom)
        server.atomic_write(self.original)
        server.migrate_content()
        rows = server.read_content()["shortcuts"]
        self.assertEqual(len(rows), 17)
        self.assertIn(custom, rows)

    def test_migration_capacity_failure_leaves_original_intact(self):
        rows = [dict(self.original["shortcuts"][0], action=f"Acción {index}") for index in range(40)]
        server.atomic_write({"title": "Lleno", "shortcuts": rows})
        before = self.path.read_bytes()
        with self.assertRaises(ValueError):
            server.migrate_content()
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.state.glob("content.before-context-*.json")), [])

    def test_all_initial_profiles_have_machine_combinations(self):
        content = server.validate_content(server.DEFAULT_CONTENT)
        self.assertEqual(len(content["shortcuts"]), 28)
        for row in server.APP_SHORTCUTS:
            self.assertEqual(len(row["combinations"]), 1)
            self.assertEqual(row["combinations"], server.parse_combinations(row["keys"]))


if __name__ == "__main__":
    unittest.main()
