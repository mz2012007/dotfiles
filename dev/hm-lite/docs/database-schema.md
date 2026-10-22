# Database schema

The authoritative definition lives in [`db/schema.sql`](../db/schema.sql).
This document explains the tables, the relations and the invariants.

* Schema version: **1** (stored in `PRAGMA user_version`)
* Engine: SQLite, foreign keys enabled on every connection
* File: `<runtime>/db.sqlite`

---

## The tables

### `schema_meta`

Free form metadata about the project itself.

| Column | Type | Notes |
|---|---|---|
| `key` | TEXT | Primary key. |
| `value` | TEXT | Not null. |

Used for `created_at` and `hm_version`.

### `paths`

Every path that HM-Lite knows about. A path is a **location**, never a
content.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key. |
| `path` | TEXT | The absolute, normalised path. Unique. |
| `kind` | TEXT | `file` or `dir`. |
| `created_at` | INTEGER | Unix epoch seconds. |

The uniqueness of `path` is what makes `add` idempotent: adding a path
twice does not create a second row.

### `pending_paths`

The paths that are selected for the next generation.

| Column | Type | Notes |
|---|---|---|
| `path_id` | INTEGER | Primary key, references `paths(id)` with `ON DELETE CASCADE`. |
| `added_at` | INTEGER | Unix epoch seconds. |

A path that is registered but never captured stays pending until the next
`hm gen`.

### `files`

The content objects. One row per unique content, addressed by the SHA-256
of its bytes.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key. |
| `hash` | TEXT | The SHA-256 in lowercase hex. Unique, exactly 64 characters. |
| `size` | INTEGER | The size of the content in bytes. |
| `created_at` | INTEGER | Unix epoch seconds. |

The hash is the identity. Two files with the same bytes share one object
in the store and one row in this table.

### `generations`

The immutable snapshots.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key. The identifier, **not** the order. |
| `name` | TEXT | Optional name. |
| `comment` | TEXT | Optional comment. |
| `created_at` | INTEGER | Unix epoch seconds. |
| `parent_id` | INTEGER | References `generations(id)` with `ON DELETE SET NULL`. |

The order of the generations is always `ORDER BY created_at DESC, id DESC`.
The identifier is never used as an ordering, because two generations can
share the same second.

`parent_id` is the link of the linear history. `hm delete` removes a
generation row, so `ON DELETE SET NULL` clears the parent of its children
and the remaining history stays readable; the entries cascade with the
row. A snapshot is never edited, it is either present or removed as a
whole.

### `generation_entries`

The recorded state of a path inside a generation. One row per path.

| Column | Type | Notes |
|---|---|---|
| `generation_id` | INTEGER | References `generations(id)` with `ON DELETE CASCADE`. |
| `path_id` | INTEGER | References `paths(id)` with `ON DELETE CASCADE`. |
| `file_id` | INTEGER | References `files(id)` with `ON DELETE RESTRICT`. `NULL` for a directory. |
| `entry_type` | TEXT | `file` or `dir`. |
| `mode` | INTEGER | The permission bits, `0 … 4095`. |
| `owner_uid` | INTEGER | The owner of the original file. |
| `group_gid` | INTEGER | The group of the original file. |
| `mtime` | INTEGER | The modification time in epoch seconds. |
| `size` | INTEGER | The size in bytes. |
| | | Primary key `(generation_id, path_id)`. |

The entries of a generation are never updated. A generation is immutable:
a new state is always a new generation.

The `ON DELETE RESTRICT` on `file_id` is the safety net of the garbage
collection: a content object that is still referenced by a generation
cannot be deleted by accident.

### `state`

Small key/value table for the pointers of the project.

| Column | Type | Notes |
|---|---|---|
| `key` | TEXT | Primary key. |
| `value` | TEXT | The value. |

The only key in use is `selected_generation`, the generation that `hm
switch` selected and that `hm apply` uses when no generation is named.

---

## The relations

```
paths ─┬─< pending_paths
       │
       └─< generation_entries >─ generations
                       │
                       └─────── files ───────► store/objects/<2 hex>/<sha256>
```

---

## The indexes

| Index | Table | Columns | Purpose |
|---|---|---|---|
| `idx_paths_kind` | `paths` | `kind` | Filter by kind. |
| `idx_pending_added` | `pending_paths` | `added_at` | Order the pending set. |
| `idx_entries_file` | `generation_entries` | `file_id` | The reference analysis of `hm clean`. |
| `idx_entries_path` | `generation_entries` | `path_id` | The history of one path. |
| `idx_generations_created` | `generations` | `created_at DESC, id DESC` | The default ordering of the generations. |

---

## The invariants

1. `paths.path` is unique. A path is registered once.
2. `files.hash` is unique. A content is stored once.
3. The primary key of `generation_entries` is `(generation_id, path_id)`.
   A path appears at most once per generation.
4. Foreign keys are enabled on every connection. The cascade rules keep the
   database consistent when a generation or a path is removed.
5. A generation entry is never updated, only inserted.
6. The order of the generations is `created_at DESC, id DESC`.
7. `PRAGMA user_version` equals the version of the schema that created the
   database. A newer version is refused, never migrated silently.
8. The metadata of an entry is type, mode, uid, gid, mtime and size.
   ACLs, extended attributes, file capabilities and hard links are **not**
   part of the model.

---

## How the shell code talks to the database

* The SQL is always passed as a single argument to `sqlite3`, never
  interpolated into a shell string.
* Every value that comes from the filesystem is quoted with the SQL
  quoting helper of `lib/database.sh`.
* A path that contains a newline or a quote is stored as the hexadecimal
  encoding of its bytes (`hex(path)`), and decoded again when it is read.
  The hexadecimal form is byte exact and free of any separator problem.
* Every write that belongs together runs inside one transaction
  (`hm_db_tx`), so a failure never leaves a half applied state behind.
* The database is never modified by a text editor. The schema file is the
  only place where a `CREATE TABLE` statement exists.
