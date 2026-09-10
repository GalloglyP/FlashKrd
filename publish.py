#!/usr/bin/env python3
"""Publish a deck directory to the flashcards Postgres database.

Deck layout::

    decks/ochem-101/
      deck.yaml          # id, title, description
      notes.jsonl        # one note per line
      media/             # optional images/figures; paths stored relative to the deck root

Example note::

    {"id": "ochem-101.sn2", "front": "SN2 stereochemistry", "back": "inversion", "tags": ["sn2"]}

Ids must match ^[a-z0-9][a-z0-9._-]*$ and stay stable across publishes so
device FSRS state is kept. Missing notes/files are soft-deleted.

    python publish.py decks/ochem-101
    python publish.py decks/ochem-101 --dry-run
"""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(dotenv_path: str | None = None) -> bool:
        return False

import yaml

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
@dataclass
class DeckMeta:
    id: str
    title: str
    description: str = ""


@dataclass
class Note:
    id: str
    front: str = ""
    back: str = ""
    extra: str = ""
    tags: list[str] = field(default_factory=list)
    sort_index: int = 0
    attrs: dict = field(default_factory=dict)


@dataclass
class FileItem:
    path: str
    sha256: str
    mime: str
    bytes: int
    source: Path


class PublishError(Exception):
    pass


def require_id(value: object, label: str) -> str:
    if not isinstance(value, str) or not ID_RE.fullmatch(value):
        raise PublishError(f"{label} is not a valid id: {value!r}")
    return value


def load_deck_meta(path: Path) -> DeckMeta:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise PublishError(f"{path} must be a mapping")
    deck_id = require_id(raw.get("id"), f"{path} id")
    title = raw.get("title")
    if not isinstance(title, str) or not title.strip():
        raise PublishError(f"{path} needs a non-empty title")
    description = raw.get("description") or ""
    if not isinstance(description, str):
        raise PublishError(f"{path} description must be a string")
    return DeckMeta(id=deck_id, title=title.strip(), description=description.strip())


def load_notes(path: Path) -> list[Note]:
    notes: list[Note] = []
    seen: set[str] = set()
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        try:
            raw = json.loads(line)
        except json.JSONDecodeError as exc:
            raise PublishError(f"{path}:{line_no}: {exc}") from exc
        if not isinstance(raw, dict):
            raise PublishError(f"{path}:{line_no}: note must be an object")
        note_id = require_id(raw.get("id"), f"{path}:{line_no} id")
        if note_id in seen:
            raise PublishError(f"{path}:{line_no}: duplicate note id {note_id}")
        seen.add(note_id)
        tags = raw.get("tags") or []
        if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
            raise PublishError(f"{path}:{line_no}: tags must be a list of strings")
        attrs = raw.get("attrs") or {}
        if not isinstance(attrs, dict):
            raise PublishError(f"{path}:{line_no}: attrs must be an object")
        sort_index = raw.get("sort_index", line_no)
        if not isinstance(sort_index, int):
            raise PublishError(f"{path}:{line_no}: sort_index must be an integer")
        notes.append(
            Note(
                id=note_id,
                front=str(raw.get("front") or ""),
                back=str(raw.get("back") or ""),
                extra=str(raw.get("extra") or ""),
                tags=tags,
                sort_index=sort_index,
                attrs=attrs,
            )
        )
    return notes


def iter_media(deck_dir: Path) -> list[FileItem]:
    media_root = deck_dir / "media"
    if not media_root.exists():
        return []
    if not media_root.is_dir():
        raise PublishError(f"{media_root} exists but is not a directory")
    files: list[FileItem] = []
    for file_path in sorted(media_root.rglob("*")):
        if not file_path.is_file():
            continue
        rel = file_path.relative_to(deck_dir).as_posix()
        if rel.startswith("/") or ".." in Path(rel).parts:
            raise PublishError(f"refusing path {rel}")
        data = file_path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        mime, _ = mimetypes.guess_type(file_path.name)
        files.append(
            FileItem(
                path=rel,
                sha256=digest,
                mime=mime or "application/octet-stream",
                bytes=len(data),
                source=file_path,
            )
        )
    return files


def load_source(deck_dir: Path) -> tuple[DeckMeta, list[Note], list[FileItem]]:
    deck_dir = deck_dir.resolve()
    if not deck_dir.is_dir():
        raise PublishError(f"not a directory: {deck_dir}")
    meta_path = deck_dir / "deck.yaml"
    if not meta_path.exists():
        meta_path = deck_dir / "deck.yml"
    notes_path = deck_dir / "notes.jsonl"
    if not meta_path.exists():
        raise PublishError(f"missing deck.yaml in {deck_dir}")
    if not notes_path.exists():
        raise PublishError(f"missing notes.jsonl in {deck_dir}")
    meta = load_deck_meta(meta_path)
    if meta.id != deck_dir.name:
        raise PublishError(
            f"deck id {meta.id!r} does not match directory name {deck_dir.name!r}"
        )
    notes = load_notes(notes_path)
    files = iter_media(deck_dir)
    for note in notes:
        if not note.id.startswith(f"{meta.id}."):
            raise PublishError(
                f"note {note.id} must be prefixed with {meta.id}."
            )
    return meta, notes, files


def conninfo_from_env() -> str:
    host = os.environ.get("FLASHCARDS_PG_HOST") or os.environ.get("PGHOST")
    port = os.environ.get("FLASHCARDS_PG_PORT") or os.environ.get("PGPORT") or "5432"
    user = os.environ.get("FLASHCARDS_PG_USER") or os.environ.get("PGUSER")
    password = os.environ.get("FLASHCARDS_PG_PASSWORD") or os.environ.get("PGPASSWORD")
    database = (
        os.environ.get("FLASHCARDS_PG_DATABASE")
        or os.environ.get("PGDATABASE")
        or "flashcards"
    )
    missing = [name for name, value in (("host", host), ("user", user), ("password", password)) if not value]
    if missing:
        raise PublishError(
            "missing connection settings: "
            + ", ".join(missing)
            + " (set FLASHCARDS_PG_* or a .env file)"
        )
    return (
        f"host={host} port={port} user={user} password={password} "
        f"dbname={database} connect_timeout=10"
    )


def copy_media(files: list[FileItem], deck_id: str, media_root: Path) -> int:
    dest_root = media_root / deck_id
    copied = 0
    for item in files:
        dest = dest_root / Path(item.path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == item.sha256:
            continue
        shutil.copy2(item.source, dest)
        copied += 1
    return copied


def publish(
    meta: DeckMeta,
    notes: list[Note],
    files: list[FileItem],
    *,
    dry_run: bool,
    media_root: Path | None,
) -> int:
    note_ids = [n.id for n in notes]
    file_ids = [f"{meta.id}/{f.path}" for f in files]
    print(f"deck {meta.id}: {len(notes)} notes, {len(files)} files")
    if dry_run:
        print("dry-run: not writing to the database")
        for note in notes:
            print(f"  note {note.id}")
        for item in files:
            print(f"  file {item.path} ({item.bytes} bytes)")
        return 0

    with psycopg.connect(conninfo_from_env()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO decks (id, title, description, rev)
                VALUES (%s, %s, %s, 1)
                ON CONFLICT (id) DO UPDATE SET
                    title = EXCLUDED.title,
                    description = EXCLUDED.description,
                    rev = decks.rev + 1
                RETURNING rev
                """,
                (meta.id, meta.title, meta.description),
            )
            rev = cur.fetchone()[0]

            for note in notes:
                cur.execute(
                    """
                    INSERT INTO notes (
                        id, deck_id, front, back, extra, tags, sort_index, attrs, rev, deleted_at
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, NULL)
                    ON CONFLICT (id) DO UPDATE SET
                        deck_id = EXCLUDED.deck_id,
                        front = EXCLUDED.front,
                        back = EXCLUDED.back,
                        extra = EXCLUDED.extra,
                        tags = EXCLUDED.tags,
                        sort_index = EXCLUDED.sort_index,
                        attrs = EXCLUDED.attrs,
                        rev = EXCLUDED.rev,
                        deleted_at = NULL
                    """,
                    (
                        note.id,
                        meta.id,
                        note.front,
                        note.back,
                        note.extra,
                        note.tags,
                        note.sort_index,
                        Jsonb(note.attrs),
                        rev,
                    ),
                )

            if note_ids:
                cur.execute(
                    """
                    UPDATE notes
                    SET deleted_at = now(), rev = %s
                    WHERE deck_id = %s
                      AND deleted_at IS NULL
                      AND NOT (id = ANY(%s))
                    """,
                    (rev, meta.id, note_ids),
                )
            else:
                cur.execute(
                    """
                    UPDATE notes
                    SET deleted_at = now(), rev = %s
                    WHERE deck_id = %s AND deleted_at IS NULL
                    """,
                    (rev, meta.id),
                )
            notes_removed = cur.rowcount

            for item, file_id in zip(files, file_ids):
                if not SHA256_RE.fullmatch(item.sha256):
                    raise PublishError(f"bad sha256 for {item.path}")
                cur.execute(
                    """
                    INSERT INTO files (
                        id, deck_id, path, sha256, mime, bytes, rev, deleted_at
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, NULL)
                    ON CONFLICT (id) DO UPDATE SET
                        deck_id = EXCLUDED.deck_id,
                        path = EXCLUDED.path,
                        sha256 = EXCLUDED.sha256,
                        mime = EXCLUDED.mime,
                        bytes = EXCLUDED.bytes,
                        rev = EXCLUDED.rev,
                        deleted_at = NULL
                    """,
                    (
                        file_id,
                        meta.id,
                        item.path,
                        item.sha256,
                        item.mime,
                        item.bytes,
                        rev,
                    ),
                )

            if file_ids:
                cur.execute(
                    """
                    UPDATE files
                    SET deleted_at = now(), rev = %s
                    WHERE deck_id = %s
                      AND deleted_at IS NULL
                      AND NOT (id = ANY(%s))
                    """,
                    (rev, meta.id, file_ids),
                )
            else:
                cur.execute(
                    """
                    UPDATE files
                    SET deleted_at = now(), rev = %s
                    WHERE deck_id = %s AND deleted_at IS NULL
                    """,
                    (rev, meta.id),
                )
            files_removed = cur.rowcount

        conn.commit()

    copied = 0
    if media_root is not None:
        copied = copy_media(files, meta.id, media_root)
    elif files:
        print("warning: FLASHCARDS_MEDIA_ROOT is unset; file rows written, blobs not copied")

    print(
        f"published {meta.id} rev {rev}: "
        f"{len(notes)} notes, {notes_removed} notes removed, "
        f"{len(files)} files, {files_removed} files removed, "
        f"{copied} blobs copied"
    )
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument("deck_dir", type=Path, help="path to a deck directory")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print the deck without writing",
    )
    parser.add_argument("--media-root", type=Path, help="copy media under this directory")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    script_dir = Path(__file__).resolve().parent
    load_dotenv(script_dir / ".env")
    args = parse_args(argv)
    try:
        meta, notes, files = load_source(args.deck_dir)
        media_root = args.media_root
        if media_root is None and os.environ.get("FLASHCARDS_MEDIA_ROOT"):
            media_root = Path(os.environ["FLASHCARDS_MEDIA_ROOT"])
        return publish(
            meta,
            notes,
            files,
            dry_run=args.dry_run,
            media_root=media_root,
        )
    except PublishError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except psycopg.Error as exc:
        print(f"database error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
