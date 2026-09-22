# ADR 0003 — Persistence, save versioning and optional CloudKit

* Status: Accepted (Phase 0)
* Date: 2026-09-22

## Context

A ParkLife save is a *complete world snapshot*: tiles, buildings, accommodation, reservations,
guests mid-holiday, staff tasks, ledger history and statistics. It is written wholesale on
autosave and read wholesale on load. It must survive app updates (migration), survive
interruption (no corrupted slot), and optionally sync to iCloud — while remaining fully
playable with iCloud switched off or unavailable.

## Options considered

* **Core Data / SwiftData.** Designed for incremental, queryable, partially-loaded object
  graphs with a managed object context. We never query a save; we load all of it or none of
  it. In exchange we would accept a managed-object lifecycle in the middle of a deterministic
  simulation, a migration system tied to a `.xcdatamodeld` GUI file, and a framework import
  in the core (killing Linux tests). Rejected.
* **`NSKeyedArchiver`.** Opaque, Apple-only, awkward to diff or hand-inspect. Rejected.
* **`Codable` → JSON.** Transparent, diffable, testable, portable, trivially versioned.
  Larger on disk than binary — acceptable, and compressible at the App layer.

## Decision

`Codable` DTO tree → JSON → versioned envelope → **atomic** write.

```
SaveEnvelope { formatVersion, gameVersion, createdAt, checksum, metadata, payload }
```

* `formatVersion` is an integer bumped on every breaking payload change.
* `SaveMigrator` holds an ordered list of `Migration` steps (`from → to`) applied to the raw
  JSON object *before* decoding, so old saves keep loading. Unknown *newer* versions are
  refused with a clear error rather than being half-decoded.
* `checksum` is FNV-1a 64 over the canonical payload bytes; a mismatch reports corruption
  instead of crashing.
* Writes go to `slot.tmp` then `rename()` — an interrupted write can never destroy the
  previous good save. A `.bak` copy of the previous payload is kept per slot.
* Slots: 6 manual + 1 rotating autosave, each with sidecar metadata (park name, in-game date,
  cash, guest count, play time, thumbnail) so the load screen never has to parse full saves.

## CloudKit (optional, App layer only)

* Container: private database, record type `SaveSlot`, payload as `CKAsset`, plus
  `deviceID`, `modifiedAt`, `formatVersion`, `inGameDate`.
* **Local-first:** the game always reads and writes the local file. Sync is a background
  reconciliation. If iCloud is unavailable, signed out, or fails, the game is unaffected and
  simply reports "not synced".
* Conflicts are resolved by newest `inGameDate`, and the loser is preserved as a
  "Conflicted copy" slot — never silently discarded.
* `ParkLifeCore` has no CloudKit knowledge whatsoever; the sync engine moves opaque bytes.

## Consequences

* Save files are human-readable, which makes bug reports and balance debugging far easier.
* Migration tests are cheap: keep a fixture JSON per historic version in
  `Tests/ParkLifeCoreTests/Fixtures/` and assert it still loads.
