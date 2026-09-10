-- flashcards: published decks for the Boox reviewer.
-- Content lives here; FSRS review state stays on the device, keyed by notes.id.

CREATE TABLE decks (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    rev         BIGINT NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT decks_id_format CHECK (id ~ '^[a-z0-9][a-z0-9._-]*$'),
    CONSTRAINT decks_rev_positive CHECK (rev >= 1)
);

CREATE TABLE notes (
    id          TEXT PRIMARY KEY,
    deck_id     TEXT NOT NULL REFERENCES decks (id) ON DELETE CASCADE,
    front       TEXT NOT NULL DEFAULT '',
    back        TEXT NOT NULL DEFAULT '',
    extra       TEXT NOT NULL DEFAULT '',
    tags        TEXT[] NOT NULL DEFAULT '{}',
    sort_index  INTEGER NOT NULL DEFAULT 0,
    attrs       JSONB NOT NULL DEFAULT '{}',
    rev         BIGINT NOT NULL,
    deleted_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT notes_id_format CHECK (id ~ '^[a-z0-9][a-z0-9._-]*$'),
    CONSTRAINT notes_rev_positive CHECK (rev >= 1)
);

CREATE INDEX notes_deck_id_idx ON notes (deck_id);
CREATE INDEX notes_deck_rev_idx ON notes (deck_id, rev);
CREATE INDEX notes_tags_idx ON notes USING gin (tags);
CREATE INDEX notes_alive_idx ON notes (deck_id) WHERE deleted_at IS NULL;

CREATE TABLE files (
    id          TEXT PRIMARY KEY,
    deck_id     TEXT NOT NULL REFERENCES decks (id) ON DELETE CASCADE,
    path        TEXT NOT NULL,
    sha256      TEXT NOT NULL,
    mime        TEXT NOT NULL,
    bytes       INTEGER NOT NULL,
    rev         BIGINT NOT NULL,
    deleted_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT files_path_relative CHECK (path !~ '^[/\\]' AND path !~ '\.\.'),
    CONSTRAINT files_bytes_nonneg CHECK (bytes >= 0),
    CONSTRAINT files_sha256_format CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT files_rev_positive CHECK (rev >= 1),
    CONSTRAINT files_deck_path UNIQUE (deck_id, path)
);

CREATE INDEX files_deck_id_idx ON files (deck_id);
CREATE INDEX files_deck_rev_idx ON files (deck_id, rev);
CREATE INDEX files_alive_idx ON files (deck_id) WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER decks_set_updated_at
    BEFORE UPDATE ON decks
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER notes_set_updated_at
    BEFORE UPDATE ON notes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER files_set_updated_at
    BEFORE UPDATE ON files
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE decks IS 'Published deck metadata. rev increments on each publish.';
COMMENT ON TABLE notes IS 'Rich notes (markdown + $math$). Device FSRS keys off notes.id.';
COMMENT ON COLUMN notes.attrs IS 'Optional extras (cloze, figure roles) without a migration.';
COMMENT ON TABLE files IS 'Blob inventory for a Unraid share. Markdown references path.';
COMMENT ON COLUMN files.path IS 'Path relative to the deck root, e.g. media/sn2.png';
COMMENT ON COLUMN files.id IS 'Stable id, typically {deck_id}/{path}';
