"""Disposable SQLite experiment using synthetic fixtures and a temporary directory."""

from hashlib import sha256
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


def open_db(path):
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA foreign_keys = ON")
    assert connection.execute("PRAGMA foreign_keys").fetchone() == (1,)
    return connection


def stage_rows(connection, digest):
    connection.execute("INSERT INTO collection VALUES (?, ?)", ("tile-1", "Soins"))
    for key in ("source-row-0", "source-row-1"):
        connection.execute(
            "INSERT INTO entry VALUES (?, ?, ?, ?, ?)",
            (key, "tile-1", "2024-02-29", 75, "Café Δ · सीखना\n第二行"),
        )
    connection.execute("INSERT INTO asset VALUES (?, ?)", ("asset-1", digest))
    connection.executemany(
        "INSERT INTO evidence VALUES (?, ?, ?, ?, ?)",
        [
            ("source-row-0", 0, "asset-1", "managed", "attachments/proof.pdf"),
            ("source-row-0", 1, None, "missing", "attachments/missing.pdf"),
            ("source-row-0", 2, None, "link", "https://example.invalid/proof"),
            ("source-row-1", 0, "asset-1", "managed", "attachments/proof.pdf"),
        ],
    )
    connection.execute("INSERT INTO migration VALUES (?, ?)", ("synthetic-v1", 2))


def migrate_fixture(connection, digest):
    with connection:
        if connection.execute("SELECT id FROM migration").fetchone() is None:
            stage_rows(connection, digest)


class SqliteContractProbe(unittest.TestCase):
    def test_exit_before_commit_retry_and_reopen(self):
        with tempfile.TemporaryDirectory(prefix="cpd-synthetic-probe-") as temp:
            root = Path(temp)
            original = root / "synthetic-original.bin"
            original.write_bytes(b"synthetic evidence bytes\x00\x01")
            digest = sha256(original.read_bytes()).hexdigest()
            database = root / "synthetic.sqlite"
            connection = open_db(database)
            connection.executescript("""
                CREATE TABLE collection (id TEXT PRIMARY KEY, label TEXT NOT NULL);
                CREATE TABLE entry (
                    id TEXT PRIMARY KEY, collection_id TEXT REFERENCES collection(id),
                    day TEXT NOT NULL, minutes INTEGER NOT NULL, details TEXT
                );
                CREATE TABLE asset (id TEXT PRIMARY KEY, digest TEXT NOT NULL);
                CREATE TABLE evidence (
                    record_id TEXT REFERENCES entry(id), ordinal INTEGER,
                    asset_id TEXT REFERENCES asset(id) ON DELETE RESTRICT,
                    kind TEXT NOT NULL, raw_reference TEXT NOT NULL,
                    PRIMARY KEY (record_id, ordinal)
                );
                CREATE TABLE migration (id TEXT PRIMARY KEY, source_count INTEGER);
            """)
            connection.close()

            child = subprocess.run(
                [sys.executable, __file__, "--interrupt", str(database), digest],
                check=False,
            )
            self.assertEqual(child.returncode, 73)

            connection = open_db(database)
            try:
                for table in ("collection", "entry", "asset", "evidence", "migration"):
                    count = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
                    self.assertEqual(count, (0,))
                migrate_fixture(connection, digest)
                migrate_fixture(connection, digest)
            finally:
                connection.close()

            connection = open_db(database)
            try:
                entries = connection.execute(
                    "SELECT day, minutes, details FROM entry ORDER BY id"
                ).fetchall()
                self.assertEqual(
                    entries,
                    [("2024-02-29", 75, "Café Δ · सीखना\n第二行")] * 2,
                )
                markers = connection.execute("SELECT * FROM migration").fetchall()
                self.assertEqual(markers, [("synthetic-v1", 2)])
                self.assertEqual(
                    connection.execute(
                        "SELECT kind, raw_reference FROM evidence WHERE record_id = ? ORDER BY ordinal",
                        ("source-row-0",),
                    ).fetchall(),
                    [
                        ("managed", "attachments/proof.pdf"),
                        ("missing", "attachments/missing.pdf"),
                        ("link", "https://example.invalid/proof"),
                    ],
                )
                with self.assertRaises(sqlite3.IntegrityError), connection:
                    connection.execute("DELETE FROM asset WHERE id = ?", ("asset-1",))
                with connection:
                    connection.execute("DELETE FROM evidence WHERE record_id = ?", ("source-row-0",))
                with self.assertRaises(sqlite3.IntegrityError), connection:
                    connection.execute("DELETE FROM asset WHERE id = ?", ("asset-1",))
                self.assertEqual(connection.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
                self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])
                self.assertEqual(sha256(original.read_bytes()).hexdigest(), digest)
            finally:
                connection.close()

    def test_raw_snapshot_retains_unknown_keys_and_broken_rows(self):
        source = [
            '{"id":4,"date":"2024-02-29","extensions":{"unrecognised":[0,false,null]}}',
            '{malformed',
        ]
        raw_snapshot = json.dumps(source, ensure_ascii=False).encode("utf-8")
        self.assertEqual(json.loads(raw_snapshot), source)
        with self.assertRaises(json.JSONDecodeError):
            json.loads(source[1])


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--interrupt":
        path = Path(sys.argv[2]).resolve()
        temporary_root = Path(tempfile.gettempdir()).resolve()
        if (
            path.name != "synthetic.sqlite"
            or not path.parent.name.startswith("cpd-synthetic-probe-")
            or path.parent.parent != temporary_root
            or not path.is_file()
        ):
            raise SystemExit("The child requires a synthetic database created by this probe.")
        db = open_db(path)
        db.execute("BEGIN IMMEDIATE")
        stage_rows(db, sys.argv[3])
        # Terminate the child before either commit or normal connection cleanup.
        os._exit(73)
    print(f"Host SQLite {sqlite3.sqlite_version}", flush=True)
    unittest.main(verbosity=2)
