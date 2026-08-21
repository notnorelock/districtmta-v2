# Database Contract

This document specifies the `Database.*` contract every adapter must
satisfy, and the small Active Record ORM built on top of it. MySQL is this
project's committed database backend (via MTA's native `dbConnect`/
`dbQuery`/`dbExec`/`dbPoll` functions) - `MySqlAdapter.lua` is the real,
first-party implementation, not a stand-in for someone else's future work.
A migration to a different database is possible later but is not planned
or scaffolded for.

## Where this lives

```
core/server/
├── database/
│   ├── DatabaseAdapter.lua              Database.* public API + adapter registration
│   ├── models/
│   │   ├── Account.lua                  Active Record model (accounts table)
│   │   ├── Character.lua                Active Record model (characters table)
│   │   ├── AccountPenalty.lua           Active Record model (account_penalties table)
│   │   ├── Report.lua                   Active Record model (reports table)
│   │   └── Vehicle.lua                  Active Record model (vehicles table)
│   ├── repositories/
│   │   ├── AccountRepository.lua        thin facade over Account
│   │   ├── CharacterRepository.lua      thin facade over Character
│   │   ├── AccountPenaltyRepository.lua thin facade over AccountPenalty
│   │   ├── ReportRepository.lua         thin facade over Report
│   │   └── VehicleRepository.lua        thin facade over Vehicle (+ JSON column encode/decode)
│   ├── VehicleService.lua               event bridge exposing VehicleRepository to gm_vehicles - see "Vehicles table" below
│   └── adapters/
│       ├── MySqlAdapter.lua                  real MySQL adapter
│       └── MySqlAdapterBootstrap.lua         connects + registers MySqlAdapter + runs Schema.migrate()
└── orm/
    ├── Uuid.lua           UUIDv4 generator (for the "uuid" column type only, not primary keys)
    ├── QueryBuilder.lua   fluent, `?`-parameterized SQL builder
    ├── Schema.lua         declarative table/column definitions + auto-migration
    └── Model.lua          Active Record base class
```

## Connecting to MySQL

`core/meta.xml`'s `<settings>` block:

```xml
<setting name="MYSQL_HOST" value="127.0.0.1" />
<setting name="MYSQL_PORT" value="3306" />
<setting name="MYSQL_DATABASE" value="district" />
<setting name="MYSQL_USERNAME" value="root" />
<setting name="MYSQL_PASSWORD" value="" />
<setting name="MYSQL_CHARSET" value="utf8mb4" />
```

On resource start, `MySqlAdapterBootstrap.lua` calls `MySqlAdapter.connect()`
(builds a `dbConnect("mysql", "dbname=...;host=...;port=...;charset=...",
username, password, "autoreconnect=1;log=1")` connection string from those
settings) and, on success, `Database.registerAdapter(MySqlAdapter)` followed
by `Schema.migrate()`, which creates/updates every registered model's table.

## The ORM

### Defining a model

```lua
Account = Model:extend("accounts", {
    { name = "id", type = "id", primaryKey = true },
    { name = "login", type = "string", length = 24, unique = true, nullable = false },
    { name = "email", type = "string", length = 254, unique = true, nullable = false },
    { name = "password_hash", type = "string", length = 60, nullable = false },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})
```

`Model:extend(tableName, columns)` both defines the model class and calls
`Schema.define(tableName, columns)` - the table/column definition is a
single source of truth read by both the ORM (for building queries) and the
migrator (for creating/updating the physical table).

### Column type DSL (`Schema.lua`)

Deliberately small - not a general-purpose schema language, just enough
for this project's tables:

| Type | MySQL column | Notes |
|---|---|---|
| `"id"` | `BIGINT AUTO_INCREMENT` | Use for primary keys (`primaryKey = true`). This project's primary keys are sequential integers, not UUIDs. |
| `"reference"` | `BIGINT` | For a column pointing at an `"id"`-type primary key - matches `"id"`'s exact SQL type (MySQL requires a FOREIGN KEY column's type to match the referenced column's type exactly, or table creation fails with errno 150). Pair with `references = { table = "...", column = "id" }` to actually create the FOREIGN KEY constraint - the type alone doesn't; see `AccountPenalty.issued_by_account_id` for a `"reference"` column deliberately used WITHOUT `references`, for a BIGINT-typed audit column that should NOT get a FK constraint. |
| `"uuid"` | `VARCHAR(36)` | For a plain (non-primary-key) app-generated identifier, e.g. a future public share id - generate the value with `Uuid.generate()`. Not used for account/character primary keys. |
| `"string"` | `VARCHAR(length)` | `length` defaults to 255. Supports `unique = true`. |
| `"text"` | `TEXT` | |
| `"integer"` | `INT` | Plain integer column. Use `"reference"` instead for a column pointing at an `"id"`-type primary key - `"integer"` (`INT`) does not match `"id"`'s `BIGINT`. |
| `"boolean"` | `TINYINT(1)` | Supports `default = true/false`. |
| `"timestamp"` | `TIMESTAMP` | Supports `default = "CURRENT_TIMESTAMP"`; defaults to nullable unless `nullable = false` is set, avoiding MySQL's implicit "first TIMESTAMP column" default behavior. |
| `"enum"` | `ENUM('a','b',...)` | Requires `values = {...}`, a fixed array of developer-controlled strings (e.g. `Enums.PenaltyType`'s values - see `AccountPenalty.type`) - never user input, since values are spliced directly into the `CREATE TABLE`/`ALTER TABLE` SQL (each is asserted to match `^[%w_]+$` first). Adding a new value to an already-migrated enum column needs a manual `ALTER TABLE ... MODIFY COLUMN` - `Schema.migrate()` never alters an existing column (see below). |

Every column supports `nullable` (default `true` unless `primaryKey` is
set) and `default`.

### Migration (`Schema.migrate()`)

Runs once, right after `MySqlAdapter` connects. For every registered model:
issues `CREATE TABLE IF NOT EXISTS`, then `SHOW COLUMNS FROM` to diff
against the model's declared columns, then `ALTER TABLE ... ADD COLUMN`
for anything missing. **Never drops or alters an existing column** - a
destructive schema change (renaming/retyping/dropping a column) is a
deliberate, reviewed action a developer performs directly against the
database, not something that happens silently because a model definition
changed. Tables are migrated in a fixed (alphabetical) order, sequentially,
so a later table's foreign key can safely reference an earlier one that's
guaranteed to already exist.

**Migration is asynchronous and does NOT finish by the time `core`'s files
finish loading or `onResourceStart` fires** - it's a real sequential chain
of MySQL round trips (one `CREATE TABLE`/`ALTER TABLE` at a time). Any code
that queries a table on startup (e.g. closing orphaned sessions, restoring
already-logged-in players after a restart) must not assume the schema is
ready just because `core` has started - a table sorted late alphabetically
can still be mid-creation. Two ways to wait for the real completion:

- `Events.DATABASE_READY` - fired once by `MySqlAdapterBootstrap.lua` after
  `Schema.migrate`'s `onComplete` callback runs.
- `Schema.isMigrated()` - synchronous flag, `true` once migration has
  already finished. Needed because a listener that registers for
  `Events.DATABASE_READY` *after* migration already completed would
  otherwise wait forever for an event that already fired; check this first
  and skip straight to "ready" logic if already `true` (see
  `PlayerService.lua`'s `reconnectAlreadyLoggedInPlayers` and
  `AdminDutyStatsService.lua`'s `closeOrphanedSessions` for the pattern).

This was found live: a fresh `admin_duty_sessions` table (added late,
sorts near the end of the alphabetical migration order) was queried by an
`onResourceStart` handler before `CREATE TABLE` for it had actually run,
producing `Table 'district.admin_duty_sessions' doesn't exist` on every
single boot even though the table existed moments later.

### Using a model

```lua
-- Find by primary key
Account:find(accountId, function(ok, account) ... end)

-- Filtered lookup
Account:where("login", normalizedLogin):first(function(ok, account) ... end)

-- Create (omit the primary key - MySQL assigns it via AUTO_INCREMENT)
Account:create({ login = "...", email = "...", password_hash = "..." }, function(ok, account) ... end)

-- Update an existing instance
account.email = "new@email.com"
account:save(function(ok, saved) ... end)

-- Relations (declared once via Model:hasMany/Model:belongsTo)
account:characters(function(ok, characters) ... end)
character:account(function(ok, account) ... end)

-- Writing/matching SQL NULL explicitly (a bare Lua `nil` can't do this -
-- a nil table value is indistinguishable from the key never having been
-- set, so there'd be nothing for pairs() to iterate over)
Account:query():where("id", id):update({ premium_expires_at = Model.NULL }, function(ok, affected) ... end)
AccountPenalty:where("revoked_at", "IS", Model.NULL):get(function(ok, activePenalties) ... end)
```

Every method is asynchronous/callback-based - there is no synchronous
save/find anywhere in this ORM, matching `Database.*`'s contract end to
end (see "Callback timing" below).

## Required `Database.*` adapter functions

All five functions are **asynchronous and callback-based** - none of them
return a value directly. This is intentional: it forces every caller in
this codebase to already handle the latency of a real network round trip
to MySQL, so the mock and the real adapter are interchangeable without
surfacing a "we assumed this was synchronous" bug.

### `adapter.query(sql, parameters, callback)`

Runs a query expected to return zero or more rows.

- `sql: string` - SQL text. Placeholders are `?` (positional, MySQL-style -
  `?` values are automatically quoted/escaped by MTA's `dbQuery`, this is
  real parameterization, not naive string substitution).
- `parameters: table` - an array of parameter values, positionally
  matching the placeholders. Always a table (possibly empty), never `nil`
  - `Database.query` normalizes a `nil` parameters argument to `{}` before
    calling the adapter.
- `callback: function(ok: boolean, rowsOrError: table | string)`
  - On success: `ok = true`, second argument is an array of row tables
    (each row a table keyed by column name). An empty result set is `{}`,
    not `nil`.
  - On failure: `ok = false`, second argument is a string describing the
    error. Never expose raw driver/connection internals in this string if
    it might reach the browser - callers are responsible for mapping this
    to a safe `ErrorCodes.*` value before it can leave the server.

### `adapter.queryOne(sql, parameters, callback)`

Same as `query`, but expected to return zero or one row.

- `callback: function(ok: boolean, rowOrError: table | nil | string)`
  - On success with a matching row: `ok = true`, second argument is the
    row table.
  - On success with no matching row: `ok = true`, second argument is
    `nil`. This is not an error - "not found" is a normal, valid outcome
    for a lookup.
  - On failure: same shape as `query`.

### `adapter.execute(sql, parameters, callback)`

Runs a statement that does not return rows (`UPDATE`, `DELETE`, DDL).

- `callback: function(ok: boolean, affectedRowsOrError: number | string)`
  - On success: `ok = true`, second argument is the number of affected
    rows (`0` is valid - e.g. an `UPDATE` that matched nothing).
  - On failure: same shape as above.

### `adapter.insert(sql, parameters, callback)`

Runs an `INSERT`.

- `callback: function(ok: boolean, affectedRowsOrError: number | string, lastInsertId: number | nil)`
  - On success: `ok = true`, second argument is the affected row count,
    third argument is the `AUTO_INCREMENT` id MySQL assigned (via
    `LAST_INSERT_ID()`, surfaced as `dbPoll`'s third return value) -
    `Model.save()` reads this to populate the new instance's primary key.
    `lastInsertId` is only meaningful for tables with an `"id"`-type
    (`AUTO_INCREMENT`) primary key; it's `nil`/unused for tables without one.
  - On failure (e.g. a unique constraint violation): `ok = false`, second
    argument is a string. Repositories/services are expected to interpret
    a failed insert against a table with unique constraints (login, email)
    as a conflict and surface `ErrorCodes.ACCOUNT_ALREADY_EXISTS`, not a
    generic internal error - see `AccountService.register`.

### `adapter.transaction(operations, callback)`

Runs a sequence of operations atomically.

- `operations: function(tx)` - a function that receives a transaction-
  scoped handle exposing `query`/`queryOne`/`execute`/`insert` with the
  exact same signatures as above, all operating within the transaction.
- `callback: function(ok: boolean, resultOrError: any)`
  - On success: `ok = true`, second argument is whatever `operations`
    returned.
  - On failure (including any error raised inside `operations`, or an
    explicit rollback): `ok = false`, second argument describes the error.

`MySqlAdapter.transaction` issues manual `START TRANSACTION`/`COMMIT`/
`ROLLBACK` statements over the shared connection - MTA has no dedicated
transaction API. `operations` is wrapped in `pcall` so a thrown error still
produces a well-formed `(false, error)` callback instead of crashing the
resource.

## Callback timing

Nothing in this project assumes callbacks fire synchronously or on the
same tick. `MySqlAdapter`'s callbacks fire whenever `dbPoll` reports the
query as ready (polled every 15ms via `setTimer`, never blocking the
server with `dbPoll(handle, -1)`) - callers must not rely on ordering
across independent calls beyond what they explicitly chain via nested
callbacks or the `transaction` API.

**Two MTA-specific gotchas found while building `MySqlAdapter.lua`'s poll
loop, worth knowing before touching it again:**

- `setTimer`'s `arguments...` parameters silently drop functions/function
  references ("metatables and functions/function references... will get
  lost" per MTA's own docs) - the same closure-across-a-boundary
  limitation this project already works around for exports/`triggerEvent`.
  Passing the poll callback that way read back as `nil` on the first
  retry, since `dbPoll`'s first attempt almost never has a result ready
  yet (guaranteeing at least one retry for every real query). Fix: capture
  the callback in a closure instead (the retry timer calls the polling
  function itself, with no extra arguments).
- `dbPoll`'s 2nd/3rd return values are overloaded depending on the 1st:
  on success they're `(numAffectedRows, lastInsertId)`; on failure
  (`result == false`) they're `(errorCode, errorMessage)`. Read the error
  off that SAME call - a second `dbPoll` on an already-resolved handle
  throws `"Bad usage @ 'dbPoll' [Previous dbPoll already returned
  result]"`, which silently swallowed the real error message before this
  was fixed.

## Password hashing

Not part of `Database.*` - handled directly by `AccountService.lua` using
MTA's native `passwordHash`/`passwordVerify` (bcrypt, `"$2y$"` format, see
https://wiki.multitheftauto.com/wiki/PasswordHash). Both are used in their
async/callback form (`passwordHash(password, "bcrypt", {cost=10}, callback)`)
deliberately - the synchronous form blocks the entire server process for
the duration of the bcrypt computation, which MTA's own documentation
warns against for exactly this reason. `password_hash` is never included
in `AccountService.toPublic`'s DTO sent to the browser.

## Models built on this contract

### Accounts table

```
accounts
  id             BIGINT AUTO_INCREMENT primary key
  mta_serial     VARCHAR(32) nullable    -- MTA's own getPlayerSerial(), "recognize this client" convenience only, NOT a credential
  login          VARCHAR(24) unique not null   -- stored normalized (lowercase)
  email          VARCHAR(254) unique not null  -- stored normalized (lowercase)
  password_hash  VARCHAR(60) not null    -- bcrypt hash ("$2y$..."), never the plaintext password
  created_at     TIMESTAMP default CURRENT_TIMESTAMP
  updated_at     TIMESTAMP default CURRENT_TIMESTAMP
  last_seen_at   TIMESTAMP nullable
```

The password is the real authentication credential - see
`Architecture.md`'s account lifecycle section for the full register/login
flow. `mta_serial` is rebound to whichever client last logged in
successfully; it is deliberately nullable and non-unique (a player might
never have logged in from a recognized client yet, or might switch
machines) and is never trusted as sufficient proof of identity on its own.

### Characters table (conceptual, placeholder only)

```
characters
  id            BIGINT AUTO_INCREMENT primary key
  account_id    INT not null references accounts(id)
  name          VARCHAR(24) not null
  created_at    TIMESTAMP default CURRENT_TIMESTAMP
  updated_at    TIMESTAMP default CURRENT_TIMESTAMP
```

Only `CharacterRepository.findByAccountId` and the `Account:hasMany("characters", ...)`/
`Character:belongsTo("account", ...)` relation exist today, to prove the
account/character split at the data layer without building the character
system itself.

### Vehicles table

```
vehicles
  id                 BIGINT AUTO_INCREMENT primary key
  purpose            ENUM('private') not null   -- only PRIVATE is ever written here, see below
  model              INT not null
  position           TEXT not null              -- toJSON({x,y,z})
  rotation           TEXT not null              -- toJSON({rx,ry,rz})
  health             INT not null default 1000
  mileage            INT not null default 0
  fuel               INT not null default 100
  max_fuel           INT not null default 100
  owner_account_id   BIGINT not null references accounts(id)
  locked             TINYINT(1) not null default 1
  handbrake          TINYINT(1) not null default 0   -- manual handbrake (setElementFrozen), see VehicleInteractionService.lua
  upgrades           TEXT nullable   -- toJSON({parts, neons, paintjob, engine})
  doors              TEXT nullable   -- toJSON({[0..5] -> state})
  lights             TEXT nullable   -- toJSON({state={[0..3]->state}, color={r,g,b}, override=getVehicleOverrideLights})
  panels             TEXT nullable   -- toJSON({[0..6] -> state})
  wheels             TEXT nullable   -- toJSON({fl,fr,rl,rr})
  color              TEXT nullable   -- toJSON({r1,g1,b1, r2,g2,b2, r3,g3,b3, r4,g4,b4}), matches getVehicleColor(v, true)
  plate              VARCHAR(8) nullable
  interior           INT not null default 0
  dimension          INT not null default 0
  last_drivers       TEXT nullable   -- toJSON({ {name=...}, ... }), most recent last, capped
  created_at         TIMESTAMP default CURRENT_TIMESTAMP
  updated_at         TIMESTAMP default CURRENT_TIMESTAMP
```

Owned by `gm_vehicles` (a `[gameplay]/` resource), NOT `core` - `core` only
holds the model/repository (`Vehicle.lua`/`VehicleRepository.lua`, same
"every model lives in `core`" convention as `Account`/`Character`), since a
callback can never cross a resource boundary (see `Architecture.md`'s "The
one hard rule for extending the project"). `gm_vehicles` reaches
`VehicleRepository` through `core/server/database/VehicleService.lua`, a
requestId-correlated event bridge mirroring `FetchBridge`'s own pattern
across the `core`/`core_ui` boundary - see `Architecture.md`'s "FetchBridge
across the core/core_ui boundary" for the shape this copies
(`gm_vehicles/server/VehicleBridge.lua` is the calling side).

`purpose` only ever has one real value today: `Enums.VehiclePurpose.PRIVATE`
(owner = an `accounts.id`, persisted, spawned back into the world on every
`gm_vehicles` start). `Enums.VehiclePurpose.PUBLIC` vehicles are a
deliberately separate, purely scripted concept (a fixed list of spawn
points in `gm_vehicles/server/PublicVehicles.lua`) and are never written to
this table at all - see that file and `Enums.lua`'s own module comment.
`GROUP`/`EVENT`/`EXCHANGE`/`SHOP`/`RENT` purposes, vehicle tuning
workshops, the vehicle exchange, and vehicle sharing all existed in the
reference implementation this was ported from but have no backing system
in this project yet and were deliberately not carried over - add them only
once the system each depends on actually exists (a faction/group system,
a workshop, a shop/economy system), per `Architecture.md`'s "Adding a new
system" section.

`owner_account_id` points at `accounts.id`, not a character - this project
has no working character-select system yet (`characters` above is a
placeholder only), so vehicle ownership is account-wide for now.

### Items table

```
items
  id                 BIGINT AUTO_INCREMENT primary key
  owner_account_id   BIGINT nullable references accounts(id)   -- NULL = lying in the world, not carried
  scheme_key         VARCHAR(64) not null   -- gm_items/shared/ItemSchemes.lua key, e.g. "Mała ryba"
  amount             INT not null default 1
  item_values        TEXT nullable   -- toJSON(...), per-instance data the scheme alone can't hold (e.g. a vehicle key's {vehicleId})
  flags              TEXT nullable   -- toJSON(...), per-instance behavior flags
  favorite           TINYINT(1) not null default 0
  position           TEXT nullable   -- toJSON({x,y,z}), only meaningful while owner_account_id is NULL
  interior           INT not null default 0
  dimension          INT not null default 0
  created_at         TIMESTAMP default CURRENT_TIMESTAMP
  updated_at         TIMESTAMP default CURRENT_TIMESTAMP
```

Owned by `gm_items` (a `[gameplay]/` resource), NOT `core` - same
"`core` only holds the model/repository, the owning resource reaches it
through an event bridge" split `vehicles` above uses. `core/server/
ItemService.lua` is the bridge dispatcher (mirrors `core/server/
VehicleService.lua` exactly); `gm_items/server/ItemBridge.lua` is the
calling side.

A single row is either a player's carried item (`owner_account_id` set,
`position` NULL) or a world-dropped item (`owner_account_id` NULL,
`position` set) - never both, and the two are the SAME table rather than
separate ones, so picking an item up or dropping it is just flipping
which half of the row is populated (see `ItemService.lua`'s `drop`/
`pickup`). This mirrors the reference implementation this was ported
from, which used an `owner = -1` sentinel for the same "lying in the
world" state on a single `items` table - translated here into a real
nullable FK instead of a magic number.

`scheme_key`'s corresponding row in `ItemSchemes.lua` (name shown to the
player is the key itself, type, category, weight, stack limit, world
object model) is never duplicated into this table - scheme data is
static/code-defined so a balance change is a code change, not a
migration, exactly like `Enums.VehiclePurpose`'s own reasoning for why
`GROUP`/`EVENT`/etc. aren't in this project's `vehicles` table yet. Only
`Enums.ItemType.PLAIN` (plain stackables) and `VEHICLE_KEY` (integrates
with the existing `gm_vehicles`) exist today - a fishing-rod-style
`USABLE` item type from the reference implementation was deliberately not
ported since it depended on a job/fishing system this project doesn't
have, per `Architecture.md`'s "Adding a new system" section.

## What a new adapter must NOT do (if the backend ever changes again)

- Must not change any repository/model's SQL expectations (`?`-style
  positional placeholders, MySQL identifier quoting via backticks).
- Must not return rows as anything other than plain Lua tables keyed by
  column name.
- Must not call back synchronously in a way that breaks re-entrancy (i.e.
  don't call the callback before `adapter.query(...)` itself returns, to
  avoid surprising ordering if a caller relies on scheduling their own
  code right after the call).
- Must not leak connection strings, credentials, or raw driver exceptions
  into the string returned on failure - log those server-side only (see
  `Logger.error` in `core/server/Logger.lua`) and return a short,
  descriptive-but-safe string.
