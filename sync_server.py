#!/usr/bin/env python3
"""LAN read API for the FlashKrd client. Does not expose Postgres to the tablet.

    GET /health
    GET /decks
    GET /decks/<id>
    GET /files/<deck_id>/<path>

Optional FLASHCARDS_SYNC_TOKEN: require header Authorization: Bearer <token>
or X-FlashKrd-Token.
"""

from __future__ import annotations

import json
import mimetypes
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

import psycopg
from psycopg.rows import dict_row

try:
    from dotenv import load_dotenv
except ImportError:

    def load_dotenv(dotenv_path: str | None = None) -> bool:
        return False

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
PATH_RE = re.compile(r"^[a-zA-Z0-9._/-]+$")


def conninfo() -> str:
    host = os.environ.get("FLASHCARDS_PG_HOST") or os.environ.get("PGHOST")
    port = os.environ.get("FLASHCARDS_PG_PORT") or os.environ.get("PGPORT") or "5432"
    user = os.environ.get("FLASHCARDS_PG_USER") or os.environ.get("PGUSER")
    password = os.environ.get("FLASHCARDS_PG_PASSWORD") or os.environ.get("PGPASSWORD")
    database = (
        os.environ.get("FLASHCARDS_PG_DATABASE")
        or os.environ.get("PGDATABASE")
        or "flashcards"
    )
    if not host or not user or not password:
        raise SystemExit("set FLASHCARDS_PG_HOST, FLASHCARDS_PG_USER, FLASHCARDS_PG_PASSWORD")
    return (
        f"host={host} port={port} user={user} password={password} "
        f"dbname={database} connect_timeout=10"
    )


def iso(value: object) -> object:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


class Handler(BaseHTTPRequestHandler):
    server_version = "FlashKrdSync/1.0"

    def log_message(self, format: str, *args: object) -> None:
        print("%s - %s" % (self.address_string(), format % args))

    def _token_ok(self) -> bool:
        expected = os.environ.get("FLASHCARDS_SYNC_TOKEN") or ""
        if not expected:
            return True
        auth = self.headers.get("Authorization") or ""
        header = self.headers.get("X-FlashKrd-Token") or ""
        if auth.startswith("Bearer "):
            return auth[7:] == expected
        return header == expected

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: object) -> None:
        data = json.dumps(payload, default=str).encode("utf-8")
        self._send(code, data, "application/json; charset=utf-8")

    def do_GET(self) -> None:
        if not self._token_ok():
            self._json(401, {"error": "unauthorized"})
            return
        path = unquote(self.path.split("?", 1)[0])
        if path == "/health":
            self._json(200, {"ok": True})
            return
        if path == "/decks":
            self._json(200, {"decks": list_decks()})
            return
        if path.startswith("/decks/"):
            deck_id = path[len("/decks/") :].strip("/")
            if not ID_RE.fullmatch(deck_id):
                self._json(400, {"error": "bad deck id"})
                return
            deck = get_deck(deck_id)
            if deck is None:
                self._json(404, {"error": "not found"})
                return
            self._json(200, deck)
            return
        if path.startswith("/files/"):
            rest = path[len("/files/") :]
            parts = rest.split("/", 1)
            if len(parts) != 2 or not ID_RE.fullmatch(parts[0]) or not PATH_RE.fullmatch(parts[1]):
                self._json(400, {"error": "bad file path"})
                return
            if ".." in parts[1]:
                self._json(400, {"error": "bad file path"})
                return
            send_file(self, parts[0], parts[1])
            return
        self._json(404, {"error": "not found"})


def list_decks() -> list[dict]:
    with psycopg.connect(conninfo(), row_factory=dict_row) as conn:
        rows = conn.execute(
            "SELECT id, title, description, rev, updated_at FROM decks ORDER BY title"
        ).fetchall()
    return [
        {
            "id": row["id"],
            "title": row["title"],
            "description": row["description"],
            "rev": row["rev"],
            "updated_at": iso(row["updated_at"]),
        }
        for row in rows
    ]


def get_deck(deck_id: str) -> dict | None:
    with psycopg.connect(conninfo(), row_factory=dict_row) as conn:
        deck = conn.execute(
            "SELECT id, title, description, rev, updated_at FROM decks WHERE id = %s",
            (deck_id,),
        ).fetchone()
        if deck is None:
            return None
        notes = conn.execute(
            """
            SELECT id, deck_id, front, back, extra, tags, sort_index, attrs, rev, deleted_at
            FROM notes
            WHERE deck_id = %s
            ORDER BY sort_index, id
            """,
            (deck_id,),
        ).fetchall()
        files = conn.execute(
            """
            SELECT id, deck_id, path, sha256, mime, bytes, rev, deleted_at
            FROM files
            WHERE deck_id = %s
            ORDER BY path
            """,
            (deck_id,),
        ).fetchall()
    return {
        "id": deck["id"],
        "title": deck["title"],
        "description": deck["description"],
        "rev": deck["rev"],
        "updated_at": iso(deck["updated_at"]),
        "notes": [
            {
                "id": n["id"],
                "deck_id": n["deck_id"],
                "front": n["front"],
                "back": n["back"],
                "extra": n["extra"],
                "tags": list(n["tags"] or []),
                "sort_index": n["sort_index"],
                "attrs": n["attrs"] or {},
                "rev": n["rev"],
                "deleted_at": iso(n["deleted_at"]),
            }
            for n in notes
        ],
        "files": [
            {
                "id": f["id"],
                "deck_id": f["deck_id"],
                "path": f["path"],
                "sha256": f["sha256"],
                "mime": f["mime"],
                "bytes": f["bytes"],
                "rev": f["rev"],
                "deleted_at": iso(f["deleted_at"]),
            }
            for f in files
        ],
    }


def send_file(handler: Handler, deck_id: str, rel_path: str) -> None:
    root = os.environ.get("FLASHCARDS_MEDIA_ROOT")
    if not root:
        handler._json(404, {"error": "media root not configured"})
        return
    with psycopg.connect(conninfo(), row_factory=dict_row) as conn:
        row = conn.execute(
            """
            SELECT path, mime, sha256, deleted_at
            FROM files
            WHERE deck_id = %s AND path = %s
            """,
            (deck_id, rel_path),
        ).fetchone()
    if row is None or row["deleted_at"] is not None:
        handler._json(404, {"error": "not found"})
        return
    full = (Path(root) / deck_id / rel_path).resolve()
    base = (Path(root) / deck_id).resolve()
    if base not in full.parents and full != base:
        handler._json(400, {"error": "bad file path"})
        return
    if not full.is_file():
        handler._json(404, {"error": "blob missing"})
        return
    data = full.read_bytes()
    mime = row["mime"] or mimetypes.guess_type(rel_path)[0] or "application/octet-stream"
    handler._send(200, data, mime)


def main() -> None:
    load_dotenv(Path(__file__).resolve().parent / ".env")
    host = os.environ.get("FLASHCARDS_SYNC_HOST", "0.0.0.0")
    port = int(os.environ.get("FLASHCARDS_SYNC_PORT", "8787"))
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"FlashKrd sync listening on {host}:{port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
