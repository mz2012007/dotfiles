# Schema migrations

`db/schema.sql` is the authoritative definition of the **current** schema.
It is applied when the database is created.

This directory holds the migrations that move an **existing** database from
one schema version to the next one. Every file is applied in the order of
its name and inside its own transaction, so a failing migration leaves the
database unchanged.

## Naming convention

```
00NN_<description>.sql
```

The number is the schema version that the migration produces. The file
must end with the version it sets:

```sql
PRAGMA user_version = 2;
```

## Rules

* A migration only ever moves the database **forward**. The version in the
  file name and the version in the `PRAGMA` must be the same.
* A migration is applied at most once. The version of the database decides
  what is still missing.
* A migration never rewrites the rows of a previous version in a way that
  loses data. If a migration needs a data conversion, it converts.
* `hm init` applies the pending migrations, and it refuses to run when the
  database is newer than the code.
