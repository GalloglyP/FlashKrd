# FlashKrd

Agent-published flashcard decks for a color e-ink reviewer. You ask for a deck (or a change); notes are written as files here, then published to Postgres. The device syncs by deck revision and keeps FSRS state keyed to stable note ids.

## Layout

```
decks/<id>/
  deck.yaml       # id, title, description (id must match the folder name)
  notes.jsonl     # one JSON object per line
  media/          # optional images and figures
```

Note ids must be `{deck-id}.{rest}` and stay stable across publishes.

```json
{"id": "ochem-101.sn2", "front": "SN2 stereochemistry", "back": "inversion", "tags": ["sn2"]}
```

Front/back/extra are Markdown. Use `$...$` / `$$...$$` for math. Figures are files under `media/` referenced from the Markdown.

## Database

Apply `schema.sql` to an empty PostgreSQL database named `flashcards`:

```bash
psql -d flashcards -v ON_ERROR_STOP=1 -f schema.sql
```

Tables: `decks`, `notes`, `files`. Review history is not stored here.

## Publish

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env   # fill in connection settings
.venv/bin/python publish.py decks/sample --dry-run
.venv/bin/python publish.py decks/sample
```

Republishing upserts by id, increments `decks.rev`, and soft-deletes notes and files that disappeared from the source tree. Set `FLASHCARDS_MEDIA_ROOT` (or `--media-root`) to copy blobs onto a share.

Do not commit `.env`.
