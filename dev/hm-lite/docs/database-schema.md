# Database schema

The authoritative definition lives in [`db/schema.sql`](../db/schema.sql).
This document explains the tables, the relations and the invariants.

* Schema version: **3** (stored in `PRAGMA user_version`)
* Engine: SQLite, foreign keys enabled on every connection
* File: `<runtime>/db.sqlite`

The version 2 migration ([`db/migrations/0002_profiles.sql`](../db/migrations/0002_profiles.sql))
introduced the profiles. Every project has a profile named `default`, and
the data of an earlier version 1 database is migrated into it.

The version 3 migration ([`db/migrations/0003_profile_roots.sql`](../db/migrations/0003_profile_roots.sql))
adds the per-profile root directory, the per-profile generation sequence
and the local generation number. Existing profiles and generations are
backfilled: a migrated profile gets root `/`, and its generations are
numbered `1…n` in their historical order.

---

## The tables

### `schema_meta`

Free form metadata about the project itself.

| Column | Type | Notes |
|---|---|---|
| `key` | TEXT | Primary key. |
| `value` | TEXT | Not null. |

Used for `created_at` and `hm_version`.

### `profiles`

The independent namespaces of the project.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key. |
| `name` | TEXT | Unique. `[A-Za-z0-9][A-Za-z0-9._-]*`. |
| `root` | TEXT | Absolute normalised root directory. Not null, defaults to `/`. |
| `next_generation_number` | INTEGER | The next local generation number, starts at `1`. |
| `created_at` | INTEGER | Unix epoch seconds. |

`hm init` creates `default` with root `/`. `hm profile create NAME ROOT`
creates a rooted profile with its own sequence; `hm profile add NAME` and
`hm add --profile NAME` are legacy creation paths whose root is `/`. The
other commands require an existing profile. The tracked paths, the pending
set, the generations, their local numbers and the selections are profile
scoped; the content store (`files` and `store/objects/`) is shared by every
profile. Renaming a profile updates its row and the state keys; deletion is
refused for `default` and for the effective or persisted active context,
and `--force` is required while generations exist.

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
twice does not create a second row. The membership in a profile lives in
`path_profiles`, so the same path can be tracked by two profiles while it
still has one row here.

### `path_profiles`

The membership of a path in a profile.

| Column | Type | Notes |
|---|---|---|
| `path_id` | INTEGER | References `paths(id)` with `ON DELETE CASCADE`. |
| `profile_id` | INTEGER | References `profiles(id)` with `ON DELETE CASCADE`. |
| `added_at` | INTEGER | Unix epoch seconds. |
| | | Primary key `(path_id, profile_id)`. |

A path that belongs to several profiles is carried forward into the
generations of each of them, independently.

### `pending_paths`

The paths that are selected for the next generation of a profile.

| Column | Type | Notes |
|---|---|---|
| `path_id` | INTEGER | References `paths(id)` with `ON DELETE CASCADE`. |
| `profile_id` | INTEGER | References `profiles(id)` with `ON DELETE CASCADE`. |
| `added_at` | INTEGER | Unix epoch seconds. |
| | | Primary key `(path_id, profile_id)`. |

A path that is registered but never captured stays pending in its profile
until the next `hm gen` of that profile.

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
| `id` | INTEGER | Primary key. Internal global identifier, **not** the user-visible number and **not** the order. |
| `number` | INTEGER | Local generation number of the profile, starts at `1`, unique per profile. |
| `name` | TEXT | Optional name. |
| `comment` | TEXT | Optional comment. |
| `created_at` | INTEGER | Unix epoch seconds. |
| `parent_id` | INTEGER | References `generations(id)` with `ON DELETE SET NULL`. |
| `profile_id` | INTEGER | References `profiles(id)` with `ON DELETE CASCADE`. The owning profile. |

The local `number` is what every command accepts and prints. It is
allocated from `profiles.next_generation_number` and is monotonic: a
deleted number is never reused. The internal `id` stays global and is
never displayed.

The order of the generations is always `ORDER BY created_at DESC, id DESC`.
The identifier is never used as an ordering, because two generations can
share the same second.

`parent_id` is the link of the linear history **inside a profile**: the
parent of a new generation is the newest generation of the same profile.
`hm delete` removes a generation row, so `ON DELETE SET NULL` clears the
parent of its children and the remaining history stays readable; the
entries cascade with the row. A snapshot is never edited, it is either
present or removed as a whole.

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

The keys in use:

* `active_profile` — the persisted profile context selected by
  `hm profile use NAME`. It is overwritten by a later `use`, followed by
  `profile rename`, and protected by `profile delete`.
* `selected_generation:<profile>` — the internal id of the generation that
  `hm switch` selected in that profile.
* `selected_generation` — the global selection, the last generation that
  any `hm switch` selected. `hm discard` uses it. `hm apply` always uses
  the effective profile's selection, or the selection of `--profile`.

`hm delete` refuses a generation that appears in any of these selection
keys. The `active_profile` key is not a generation pointer, but it is the
reason `profile delete` refuses the stored active profile even when
`HM_PROFILE` temporarily names another one: the persisted context must
never become a dangling name.

---

## The relations

```
profiles ─┬─< path_profiles >─ paths ─┬─< pending_paths
          │                            │
          │                            └─< generation_entries >─ generations
          │                                                       │
          └───────────────────────────────────────────────────────┘
                                                                  │
                                                     files ───────┘
                                                       └──────► store/objects/<2 hex>/<sha256>
```

---

## The indexes

| Index | Table | Columns | Purpose |
|---|---|---|---|
| `idx_paths_kind` | `paths` | `kind` | Filter by kind. |
| `idx_path_profiles_profile` | `path_profiles` | `profile_id` | The paths of a profile. |
| `idx_pending_added` | `pending_paths` | `added_at` | Order the pending set. |
| `idx_pending_profile` | `pending_paths` | `profile_id` | The pending set of a profile. |
| `idx_entries_file` | `generation_entries` | `file_id` | The reference analysis of `hm clean`. |
| `idx_entries_path` | `generation_entries` | `path_id` | The history of one path. |
| `idx_generations_created` | `generations` | `created_at DESC, id DESC` | The default ordering of the generations. |
| `idx_generations_profile` | `generations` | `profile_id, created_at DESC, id DESC` | The generations of a profile. |
| `UNIQUE (profile_id, number)` | `generations` | `profile_id, number` | Local generation numbers are unique inside their profile. |

---

## The invariants

1. `paths.path` is unique. A path is registered once, in the `paths` table,
   however many profiles track it.
2. `profiles.name` is unique. A profile name is validated by the shell code
   before it reaches the database. `profiles.root` is absolute and bounds
   every path of the profile; `next_generation_number` is at least `1` and
   never decreases.
3. `files.hash` is unique. A content is stored once, shared by all profiles.
4. The primary key of `path_profiles` is `(path_id, profile_id)` and the
   primary key of `pending_paths` is `(path_id, profile_id)`: a path
   belongs to a profile at most once and is pending in it at most once.
5. The primary key of `generation_entries` is `(generation_id, path_id)`.
   A path appears at most once per generation.
6. `(profile_id, number)` is unique and `number >= 1`: every profile has
   its own `1…n` sequence. The internal generation `id` is unrelated to it.
7. Foreign keys are enabled on every connection. The cascade rules keep the
   database consistent when a generation, a path or a profile is removed.
8. A generation entry is never updated, only inserted.
9. The order of the generations is `created_at DESC, id DESC`.
10. `PRAGMA user_version` equals the version of the schema that created the
    database. A newer version is refused, never migrated silently.
11. The metadata of an entry is type, mode, uid, gid, mtime and size.
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
