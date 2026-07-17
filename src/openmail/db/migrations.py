"""Lightweight sequential migration runner for SQLite."""
from __future__ import annotations

import sqlite3
from pathlib import Path
from datetime import datetime, timezone

DB_PATH = Path("emails.db")
# migrations/ lives at repo root, two levels above this file (src/openmail/db -> src/openmail -> repo root)
MIGRATIONS_DIR = Path(__file__).resolve().parent.parent.parent.parent / "migrations"


def _ensure_migrations_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT UNIQUE NOT NULL,
            applied_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )


def _applied_migrations(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute("SELECT filename FROM schema_migrations").fetchall()
    return {r[0] for r in rows}


def _migration_files() -> list[Path]:
    if not MIGRATIONS_DIR.exists():
        return []
    return sorted(p for p in MIGRATIONS_DIR.iterdir() if p.suffix == ".sql")


def run_migrations(db_path: Path | str | None = None) -> list[str]:
    """Apply pending migrations sequentially. Returns list of applied filenames."""
    target = Path(db_path) if db_path else DB_PATH
    conn = sqlite3.connect(str(target))
    conn.row_factory = sqlite3.Row
    try:
        _ensure_migrations_table(conn)
        applied = _applied_migrations(conn)
        applied_new: list[str] = []
        for mig in _migration_files():
            if mig.name in applied:
                continue
            sql = mig.read_text(encoding="utf-8")
            conn.executescript(sql)
            conn.execute(
                "INSERT INTO schema_migrations (filename, applied_at) VALUES (?, ?)",
                (mig.name, datetime.now(timezone.utc).isoformat()),
            )
            conn.commit()
            applied_new.append(mig.name)
        return applied_new
    finally:
        conn.close()


def migration_status(db_path: Path | str | None = None) -> dict:
    target = Path(db_path) if db_path else DB_PATH
    conn = sqlite3.connect(str(target))
    conn.row_factory = sqlite3.Row
    try:
        _ensure_migrations_table(conn)
        applied = _applied_migrations(conn)
        pending = [m.name for m in _migration_files() if m.name not in applied]
        return {"applied": sorted(applied), "pending": pending}
    finally:
        conn.close()


if __name__ == "__main__":
    applied = run_migrations()
    print(f"Applied {len(applied)} migration(s): {applied}")
