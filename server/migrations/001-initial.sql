CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    disabled INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE devices (
    user_id TEXT NOT NULL REFERENCES users(id),
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    cursor INTEGER NOT NULL DEFAULT 0,
    last_seen INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);
CREATE TABLE sessions (
    refresh_hash TEXT PRIMARY KEY,
    access_hash TEXT NOT NULL UNIQUE,
    user_id TEXT NOT NULL REFERENCES users(id),
    device_id TEXT NOT NULL,
    access_expires INTEGER NOT NULL,
    refresh_expires INTEGER NOT NULL
);
CREATE TABLE books (
    user_id TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    book_id TEXT NOT NULL,
    revision INTEGER NOT NULL,
    document BLOB NOT NULL,
    PRIMARY KEY (user_id, entity_id)
);
CREATE TABLE progress (
    user_id TEXT NOT NULL, entity_id TEXT NOT NULL, book_id TEXT NOT NULL,
    revision INTEGER NOT NULL, document BLOB NOT NULL, PRIMARY KEY (user_id, entity_id)
);
CREATE TABLE bookmarks (
    user_id TEXT NOT NULL, entity_id TEXT NOT NULL, book_id TEXT NOT NULL,
    revision INTEGER NOT NULL, document BLOB NOT NULL, PRIMARY KEY (user_id, entity_id)
);
CREATE TABLE annotations (
    user_id TEXT NOT NULL, entity_id TEXT NOT NULL, book_id TEXT NOT NULL,
    revision INTEGER NOT NULL, document BLOB NOT NULL, PRIMARY KEY (user_id, entity_id)
);
CREATE TABLE reading_events (
    user_id TEXT NOT NULL, entity_id TEXT NOT NULL, book_id TEXT NOT NULL,
    revision INTEGER NOT NULL, document BLOB NOT NULL, PRIMARY KEY (user_id, entity_id)
);
CREATE TABLE changes (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    document BLOB NOT NULL
);
CREATE INDEX changes_user_sequence ON changes(user_id, sequence);
CREATE TABLE accepted_changes (
    user_id TEXT NOT NULL, change_id TEXT NOT NULL, digest TEXT NOT NULL,
    PRIMARY KEY (user_id, change_id)
);
CREATE TABLE files (
    user_id TEXT NOT NULL, book_id TEXT NOT NULL, kind TEXT NOT NULL,
    digest TEXT NOT NULL, size INTEGER NOT NULL,
    PRIMARY KEY (user_id, book_id, kind)
);
