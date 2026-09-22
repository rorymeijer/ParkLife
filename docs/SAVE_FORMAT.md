# ParkLife — Save Format

Format version: **1** · Encoding: UTF-8 JSON · Extension: `.parklife`

---

## 1. Goals

1. Offline saving must always work, with no account and no network.
2. An interrupted write must never destroy a previous good save.
3. Old saves must keep loading after the game is updated (migration).
4. Corruption must be *detected and reported*, never silently loaded or crashed on.
5. The same bytes must be syncable to iCloud without the core knowing anything about iCloud.

## 2. On-disk layout

```
<Application Support>/ParkLife/
├── saves/
│   ├── slot-0.parklife          manual slot 1
│   ├── slot-0.parklife.bak      previous payload for slot 1
│   ├── slot-0.meta.json         sidecar metadata (fast list screen)
│   ├── …
│   ├── slot-5.parklife
│   └── autosave.parklife        rotating autosave
└── logs/
```

Writing a slot:

```
1. serialise → Data
2. write to  slot-N.parklife.tmp        (fsync)
3. move      slot-N.parklife → slot-N.parklife.bak   (if it exists)
4. rename    slot-N.parklife.tmp → slot-N.parklife   (atomic)
5. write     slot-N.meta.json
```

A crash at any step leaves either the old save or the new save intact — never a half file.

## 3. Envelope

```jsonc
{
  "formatVersion": 1,          // integer, bumped on breaking payload change
  "gameVersion": "0.2.0",      // informational
  "createdAt": "2026-09-22T10:31:00Z",
  "checksum": "fnv1a64:9a3c1f0b7d2e4456",
  "metadata": { … },           // duplicated in the .meta.json sidecar
  "payload": { … }             // SaveGame
}
```

* `checksum` is FNV-1a 64 over the canonical (sorted-keys) JSON encoding of `payload`. The
  envelope is assembled *around* those exact bytes rather than re-serialised, so the checksum
  describes what is actually on disk. On load the payload is decoded and re-encoded canonically
  and the two digests are compared; a mismatch raises `SaveError.corrupted` and the loader offers
  the `.bak`. **After a migration the stored checksum describes the old payload shape, so it is
  not verified** — `DecodedSave.checksumVerified` reports this honestly rather than implying a
  check that did not happen.
* A `formatVersion` **newer** than the running build raises
  `SaveError.unsupportedVersion(found:supported:)` — we refuse rather than mangle.

### Metadata (sidecar `slot-N.meta.json`)

```jsonc
{
  "slot": 0, "parkName": "De Zandheuvel", "companyName": "Meijer Recreatie",
  "inGameDate": "Year 1, 14 June 09:20", "inGameMinutes": 236120,
  "cashCents": 41250000, "guestCount": 184, "occupancyPercent": 73,
  "reputation": 0.68, "playTimeSeconds": 5321,
  "formatVersion": 1, "gameVersion": "0.2.0", "savedAt": "2026-09-22T10:31:00Z",
  "thumbnailPNGBase64": null
}
```

The load screen reads only sidecars, so listing saves is instant regardless of save size.

## 4. Payload (`SaveGame`)

```jsonc
{
  "seed": 8123456789012345678,
  "idAllocator": { "guest": 5121, "group": 903, "building": 412, … },
  "clock":   { "minutesSinceEpoch": 236120, "speed": "x2" },
  "settings":{ "difficulty": "normal", "autosaveIntervalMinutes": 10 },
  "company": { "name": "…", "cashCents": 41250000, "loans": [ … ],
               "unlockedRegions": ["nl"], "research": { … } },
  "park": {
    "id": "nl-zandheuvel", "name": "De Zandheuvel", "mapID": "nl-zandheuvel",
    "size": { "width": 96, "height": 96 },
    "terrain":  { "encoding": "rle-v1", "elevation": [ … ], "type": [ … ], "surface": [ … ] },
    "buildings": [ { "id": 12, "def": "cottage_comfort_4", "origin": {"x":34,"y":51},
                     "rotation": 2, "condition": 0.97, "builtTick": 100 } ],
    "accommodation": [ { "buildingID": 12, "state": "occupied", "cleanliness": 0.82,
                         "reservationID": 77, "priceOverrideCents": null } ],
    "facilities":  [ … ],
    "reservations":[ … ],
    "groups":      [ … ],
    "guests":      [ … ],
    "staff":       [ … ],
    "reviews":     [ … ],          // capped ring, newest 500
    "reputation":  { … },
    "weather":     { … },
    "schedule":    [ { "tick": 236400, "kind": "guestWake", "entity": 4412 } ],
    "notifications": [ … ]
  },
  "ledger": { "entries": [ … ],    // capped ring, newest 5 000
              "dailyTotals": [ … ], "weeklyTotals": [ … ], "monthlyTotals": [ … ] },
  "statistics": { "hourly": { … }, "daily": { … }, "weekly": { … } }
}
```

### Size control

* Terrain grids are **run-length encoded** (`"rle-v1"`: alternating `[value, runLength]`),
  which collapses a 96×96 map of mostly-grass to a few hundred numbers.
* `reviews`, `ledger.entries` and `notifications` are **capped rings**; long-term history
  lives in the pre-aggregated `statistics` block, which is bounded by construction.
* Transient state that can be recomputed is **never saved**: flow fields, the path network
  bitset, connectivity components, the world index, snapshot caches. They are rebuilt on load by
  `World.rebuildDerivedState()`.
* **Congestion is the exception** and *is* saved (run-length encoded). It is accumulated state,
  not derived: it cannot be recomputed from anything else, and dropping it would make a reloaded
  game diverge from the one that was saved. `DeterminismTests` asserts that it does not.
* Finished bookings and their parties are pruned from the world 30 days after departure, so the
  payload is bounded by occupancy and retention rather than by total play time.

## 5. Versioning and migration

```swift
protocol SaveMigration {
    var from: Int { get }          // applies to a payload at this version
    var to: Int { get }            // produces this version
    func migrate(_ json: inout [String: Any]) throws
}
```

`SaveMigrator` sorts migrations and applies them in sequence to the raw JSON object before
`JSONDecoder` ever sees it, so decoding always targets the *current* model. Rules:

* Every breaking change ships a migration **in the same commit** as the model change.
* Every historic version keeps a fixture in `Tests/ParkLifeCoreTests/Fixtures/saves/` and a
  test asserting it still loads and produces a sane world.
* Additive, optional fields do **not** need a version bump (decoders default them).

## 6. Error handling

| Case | Behaviour |
|---|---|
| File missing | `SaveError.notFound` — slot shown as empty |
| Not JSON / truncated | `SaveError.corrupted` — offer `.bak`, keep the bad file for support |
| Checksum mismatch | `SaveError.corrupted` — same |
| `formatVersion` > supported | `SaveError.unsupportedVersion` — "update ParkLife to load this save" |
| Migration throws | `SaveError.migrationFailed(from:to:)` — original file left untouched |
| Disk full | write fails at the `.tmp` stage; existing save is intact |

## 7. iCloud (optional, App layer)

Record type `SaveSlot` in the **private** database:
`slot`, `payload` (`CKAsset`), `formatVersion`, `inGameMinutes`, `savedAt`, `deviceID`,
`metadata` (JSON string).

* The game reads and writes **local files only**. Sync runs afterwards, in the background.
* iCloud unavailable / signed out / throttled ⇒ status badge only; gameplay is unaffected.
* Conflict resolution: higher `inGameMinutes` wins; the loser is written back as a local
  slot named "Conflicted copy (device, date)" — nothing is ever silently discarded.
