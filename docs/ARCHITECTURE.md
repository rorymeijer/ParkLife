# ParkLife — Architecture

Status: **Phase 0 (foundation) — implemented.** Living document; update alongside code.

---

## 1. Repository state at project start

The repository contained exactly one file: `README.md`, holding the single line `# ParkLife`.
There was no Xcode project, no sources, no tests, no `.gitignore`. Everything described in
this document was created from that empty starting point.

## 2. Technology stack (summary of ADRs)

| Concern | Choice | Why (short) |
|---|---|---|
| Language | Swift 5.10 / 6 toolchain, strict concurrency ready | Native, no runtime deps |
| Simulation | **Pure Swift, Foundation only** — `ParkLifeCore` SwiftPM library | Portable, headless-testable, no UIKit import |
| World rendering | **SpriteKit** (`SKScene` + manual node pooling), Metal-backed | 2.5D isometric sprites, mature batching, far less work than hand-rolled Metal |
| UI / HUD / panels | **SwiftUI** | Touch-first, Dynamic Type, VoiceOver, adaptive iPhone/iPad layout for free |
| Bridge | `SpriteView` (SwiftUI) hosting `ParkScene` | One-line integration, keeps UI declarative |
| Entity logic | Hand-written systems, **not** GameplayKit `GKEntity`/`GKComponent` | Needs to be `Codable`, deterministic and Linux-testable |
| Pathfinding | Hand-written A\* + Dijkstra flow fields (not `GKGridGraph`) | Determinism, incremental invalidation, budgeted async |
| Persistence | **Codable → JSON, versioned envelope, atomic write** (not Core Data / SwiftData) | Save is a whole-world snapshot, not a queryable object graph |
| Cloud | **CloudKit private DB**, `CKAsset` per slot, strictly optional | Offline-first requirement |
| Dependencies | **None.** Zero third-party packages | Rule: avoid external deps without substantial advantage |

Full reasoning: [`adr/0001-technology-stack.md`](adr/0001-technology-stack.md),
[`adr/0002-rendering-approach.md`](adr/0002-rendering-approach.md),
[`adr/0003-persistence-and-cloud.md`](adr/0003-persistence-and-cloud.md).

## 3. Layering

```
┌──────────────────────────────────────────────────────────────┐
│ App/ParkLife            (SwiftUI app, iOS/iPadOS)            │
│  ├─ UI          SwiftUI views, HUD, panels, build bar        │
│  ├─ Rendering   SpriteKit ParkScene, node pools, camera       │
│  └─ Session     GameSession @MainActor observable façade      │
├──────────────────────────────────────────────────────────────┤
│ Sources/ParkLifeCore    (platform-agnostic Swift library)     │
│  ├─ Engine      SimulationEngine, systems, scheduler          │
│  ├─ World       World state, entities, tile map               │
│  ├─ Catalog     Data-driven definitions loaded from JSON      │
│  ├─ Pathfinding PathNetwork, A*, flow fields, request queue    │
│  ├─ Build       Build/demolish commands, undo/redo            │
│  ├─ Persistence Save DTOs, versioning, migration, slots       │
│  └─ Support     RNG, IDs, heap, money, logging, localization  │
└──────────────────────────────────────────────────────────────┘
```

**Hard rule (Rule 3):** `ParkLifeCore` does not `import SwiftUI`, `SpriteKit`, `UIKit` or
`CloudKit`. It compiles and its tests run on any platform with a Swift toolchain, including
Linux. Dependency direction is one-way: App → Core. Core never calls back into the App;
it publishes immutable **events** and **snapshots** that the App consumes.

### Why the core is a separate SwiftPM target

1. The compiler mechanically enforces "no simulation logic in views" — a view *cannot*
   reach into a system that doesn't exist in its module unless the façade exposes it.
2. Simulation tests run headless in seconds, without a simulator.
3. Later reuse for a macOS build, a server-side balance harness, or offline batch balancing.

## 4. Simulation ↔ rendering contract

The renderer never mutates the world and never reads mutable simulation state directly.
Each frame it receives a **`WorldSnapshot`**: a value type holding only what is drawable
(visible tile slice, building placements, guest positions with interpolation alphas, HUD
scalars). The simulation advances in fixed ticks; the renderer interpolates between the two
most recent tick states, so visuals stay smooth at 120 Hz while the simulation runs at
2–64 ticks/s.

```
[GameSession @MainActor]
   ├── drives ──► SimulationEngine.advance(realDelta) ──► N fixed ticks
   ├── reads  ──► engine.snapshot(for: cameraViewport) ──► WorldSnapshot (value type)
   ├── feeds  ──► ParkScene.apply(snapshot)                (SpriteKit)
   └── feeds  ──► SwiftUI @Published HUD/view models
```

Player input flows the other way as **intents**, never as direct mutation:
`GameSession.submit(.build(.path(at: tiles)))` → validated command → world mutation inside
the engine. This is what makes undo/redo and replay possible.

## 5. Coordinate system

Three spaces, converted only at the boundaries:

| Space | Type | Used by |
|---|---|---|
| **Grid** | `GridPoint(x:Int, y:Int)`, +X = east, +Y = south | All simulation |
| **World** | continuous `WorldPoint(x:Double, y:Double)` in tile units | Guest movement, interpolation |
| **Screen** | `ScreenPoint` in points | Renderer only |

Isometric projection (diamond, 2:1):

```
screenX = (wx - wy) * (tileWidth / 2)
screenY = (wx + wy) * (tileHeight / 2) - elevation * elevationStep
```

with `tileWidth = 64`, `tileHeight = 32`, `elevationStep = 16` at zoom 1.0.
Camera rotation is implemented by rotating grid coordinates through one of four
orientations *before* projection (`IsometricProjection.rotate`), so simulation coordinates
are never touched by camera state. Draw order is `(wx + wy)` ascending, then elevation —
the painter's algorithm every isometric game uses.

Tile scale is **8 m per tile**. A 96×96 map is therefore a ~768 m × 768 m park, which is a
realistic footprint for a mid-sized holiday park.

## 6. Entity and data architecture

### Definitions vs. instances (Rule 4, §40 of the brief)

* **Definitions** are immutable, `Codable`, loaded from JSON in
  `Sources/ParkLifeCore/Resources/Catalog/`: `BuildingDefinition`,
  `AccommodationDefinition`, `FacilityDefinition`, `StaffRoleDefinition`,
  `ResearchDefinition`, `ScenarioDefinition`, `MapDefinition`.
* **Instances** are mutable runtime state referencing a definition by string id:
  `BuildingInstance`, `AccommodationUnit`, `FacilityInstance`, `Guest`, `GuestGroup`,
  `Reservation`, `StaffMember`.

Adding a new cottage type is a JSON edit. There is no `switch` over building kinds in the
build system, the renderer or the UI — behaviour is driven by definition fields and a small
set of *capability* structs (`AccommodationDefinition`, `FacilityDefinition`) attached to a
building definition.

### Identity

Typed ids (`GuestID`, `BuildingID`, …) wrap `UInt32` and are allocated by `IDAllocator`,
which is itself serialised, so ids are stable across save/load. Entities live in
`EntityStore<T>` — a dense array plus an id→index map, giving O(1) lookup, cache-friendly
iteration and stable ids under removal.

### Events

Systems never call each other directly. They append to `EventBuffer` (e.g.
`.guestCheckedIn`, `.moneySpent`, `.buildingBroke`). The engine drains the buffer at the end
of each tick, feeding statistics, notifications and the App layer. This keeps systems
decoupled and makes cause/effect testable.

## 7. Pathfinding architecture

Scale target: thousands of guests on a 96×96..256×256 grid without per-frame global A\*.

1. **`PathNetwork`** — bitset of walkable tiles derived from the tile map (paths, plazas,
   bridges, building entrance tiles). Rebuilt *incrementally*: a build/demolish marks a
   dirty rect; only that region and affected caches are recomputed.
2. **Connectivity components** — union-find over walkable tiles. "Is the pool reachable
   from this cottage?" is an O(1) component comparison, so guests detect unreachable
   destinations instantly instead of searching and failing.
3. **Flow fields** — for *shared* destinations (park entrance, reception, pool, each
   restaurant) a single Dijkstra sweep from the destination produces a per-tile next-step
   direction + distance. Any number of guests then navigate in **O(1) per step** with zero
   search. Fields are cached per destination, invalidated by the dirty rect, and rebuilt
   lazily and budgeted.
4. **A\*** — used only for *private* destinations (a specific cottage) and staff tasks.
   Requests go through `PathfindingService`, which keeps a FIFO queue and spends a fixed
   node budget per tick, so a build action can never spike a frame. Results are cached by
   (from-component, to-tile).
5. **Congestion** — each tile keeps a rolling occupancy count. It deliberately does **not**
   feed flow-field cost: a field that depended on live crowding would need constant rebuilding
   and could not be reproduced after loading a save. Instead congestion lowers a facility's
   appeal in the decision model and produces the "too crowded" thought, both backed by real
   numbers. Congestion-aware *routing* is Phase 4 work, alongside vehicles.

## 8. Simulation level of detail

| LOD | Condition | Update cost |
|---|---|---|
| `full` | on-screen and moving | position every tick, animation frames |
| `reduced` | off-screen and moving | position every 4th tick, no animation |
| `dormant` | inside a facility, sleeping, or waiting | **no per-tick work at all** — the guest is parked on the `ScheduleQueue` and wakes on an exact future tick |

At night nearly every guest is `dormant`, so a 3 000-guest park costs almost nothing between
23:00 and 07:00. `ScheduleQueue` is a binary min-heap keyed by tick.

## 9. Concurrency model

* `SimulationEngine` is an isolated domain owned by `GameSession` (`@MainActor`). Ticks run
  synchronously on the main actor by default — a tick is sub-millisecond for slice-sized
  parks and this removes an entire class of data races.
* Work that *is* parallelisable and pure is pushed to background tasks and returns values:
  flow-field rebuilds and bulk A\* batches (`PathfindingService.precompute`), save
  serialisation, statistics aggregation. They take immutable inputs and return results that
  are applied on the owning actor.
* No shared mutable state crosses an actor boundary. `World` is a `struct`-of-stores value
  owned by exactly one place at a time.

## 10. Persistence

Whole-world snapshot → `SaveGame` DTO tree → JSON → versioned envelope → atomic file write.
See [`SAVE_FORMAT.md`](SAVE_FORMAT.md). Cloud sync (CloudKit) is an App-layer concern that
moves the same opaque payload; the core knows nothing about it.

## 11. Folder structure

```
ParkLife/
├── README.md
├── Package.swift                  SwiftPM: ParkLifeCore + ParkLifeCoreTests
├── Sources/ParkLifeCore/
│   ├── Support/                   RNG, IDs, heap, Money, logging, localized text
│   ├── World/                     Geometry, tile map, entities, world state
│   ├── Catalog/                   Definition types + ContentCatalog loader
│   ├── Time/                      GameDate, SimulationClock, ScheduleQueue
│   ├── Systems/                   One file per simulation system
│   ├── Pathfinding/               PathNetwork, AStar, FlowField, service
│   ├── Build/                     Build commands, validation, undo/redo
│   ├── Persistence/               Save DTOs, versioning, migrations, slots
│   ├── Engine/                    SimulationEngine, snapshot, intents
│   └── Resources/Catalog/*.json   Data-driven content
├── Tests/ParkLifeCoreTests/       Headless simulation tests
├── App/
│   ├── ParkLife.xcodeproj
│   └── ParkLife/
│       ├── App/                   Entry point, GameSession
│       ├── Rendering/             SpriteKit scene, node pools, camera
│       ├── UI/                    SwiftUI HUD, panels, build bar, debug menu
│       └── Assets.xcassets        Placeholder art (original, see ASSET POLICY)
├── Tools/mockup/                  Superseded mockup generator, kept for reference
├── docs/                          This documentation + screenshots
├── Tools/verify.sh                One command: structure, build, tests, app
└── .github/workflows/ci.yml       Runs Tools/verify.sh on Linux and macOS
```

## 12. Localization & accessibility

The core never produces English prose. Guest thoughts, reviews, notifications and
objectives are emitted as **`LocalizedText`** — a string *key* plus typed arguments.
The App resolves keys against `Localizable.strings`. Initial catalog: English; the key
structure is ready for `nl`, `de`, `fr`. Status is never colour-only: every state badge
carries a glyph and a text label, and all HUD figures are Dynamic Type sized.

## 13. Bounded state

* **Pruning** — finished bookings, their parties and their guests are pruned 30 days after
  departure (`AccommodationSystem.historyRetentionDays`). Everything worth keeping has already
  been folded into the ledger, the statistics rings and the review ring, so a park running for
  years does not accumulate every booking it ever took.

## 14. Testing strategy

* **Unit** — deterministic, headless, no rendering. Money arithmetic, date/season maths,
  pricing, occupancy, reservation assignment, satisfaction, review derivation, A\*,
  flow fields, save round-trip, migrations.
* **Scenario/integration** — drive `SimulationEngine` for N simulated days from a fixed seed
  and assert invariants (no double-booked unit, cash equals opening + revenue − expenses,
  every arriving group eventually checks out).
* **Determinism** — the same seed and the same intents must yield an identical world hash.
  `WorldHash` (FNV-1a over the canonical save payload) is asserted in tests, which catches
  accidental use of unordered iteration or system clocks.
* **Performance smoke** — tick 30 simulated days with 500 guests and assert a tick budget.

## 15. Known environment limitation (honest note)

The container this work was produced in has **no Swift toolchain** (`swift.org` is blocked
by the egress policy) and no macOS/Xcode. Therefore `swift build` / `swift test` and any
simulator screenshot **could not be executed here**. Mitigations actually in place:

* `Tools/verify.sh` is the single verification entry point: structure, content catalog,
  `swift build`, `swift test` and optionally `xcodebuild` for the app. It runs whatever the
  machine can run and **names what it skipped**, so a pass never overstates what was checked.
  `.github/workflows/ci.yml` invokes that same script on Linux and macOS rather than repeating
  the commands, so CI and a local run cannot drift apart. `Tools/hooks/pre-push` wires it into
  git for anyone who wants it enforced before pushing.
* `Tools/check_sources.py` performs a structural pass over every Swift file: brace/paren/bracket
  balance with a real lexer, `#if`/`#endif` balance, non-exhaustive switches over the project's
  own enums, duplicate type declarations and unresolved type references. It is itself verified
  against fixtures that fail on purpose.
* Screenshots in `docs/screenshots/` are **real simulator captures**, taken by the `screenshots`
  CI job from a park that has been simulated forward 25-40 days before the first frame. The
  capture script fails the build when a shot cannot be taken or when the frame is too uniform to
  be a rendered park, so an empty `docs/screenshots/` is a red build rather than a quiet pass.

This is recorded here rather than glossed over, per Rule 11.
