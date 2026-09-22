# ParkLife — Roadmap

Legend: `[x]` done · `[~]` partially done, with the gap named · `[ ]` not started.

**Where we are:** Phase 0 is complete. Phase 1 — the playable vertical slice — is complete in the
simulation core and written but uncompiled in the app layer. See
[Blocked / carried forward](#blocked--carried-forward) for everything deliberately postponed, so
that nothing is silently dropped (Rule 12).

---

## Completed

### Phase 0 — Architecture

- [x] Inspect the repository and record its starting state (one `README.md`, one line)
- [x] Choose the Apple technology stack, with reasoning — [ADR 0001](adr/0001-technology-stack.md)
- [x] Decide how the 2.5D isometric world is rendered — [ADR 0002](adr/0002-rendering-approach.md)
- [x] Decide persistence, save versioning and optional CloudKit — [ADR 0003](adr/0003-persistence-and-cloud.md)
- [x] Define the coordinate system (grid / world / screen, 8 m tiles, 2:1 diamond, 4-way rotation)
- [x] Define the simulation architecture: fixed one-minute ticks, ordered systems, event bus, LOD
- [x] Define the entity/data architecture: definitions vs. instances, typed ids, `EntityStore`
- [x] Design scalable pathfinding: flow fields, budgeted A\*, union-find connectivity
- [x] Design the save format: versioned envelope, checksum, migrations, atomic write, slots
- [x] Define the project folder structure
- [x] `README.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/SIMULATION.md`, `docs/SAVE_FORMAT.md`
- [x] Save the master brief in the repository (`docs/MASTER_PROMPT.md`)
- [x] Create the Xcode project and the SwiftPM package
- [x] Add `.gitignore` that excludes build output and signing material
- [x] Add tests from the very beginning
- [x] `Tools/verify.sh` — one command for structure, catalog, core build, core tests and
      optionally the app, with an opt-in git pre-push hook
- [x] CI (`.github/workflows/ci.yml`) that invokes that same script on Linux and macOS, so a
      green CI run and a green local run mean the same thing

### Phase 1 — Playable vertical slice

- [x] One small Dutch map (`De Zandheuvel`, 96×96, deterministic generation from a seed)
- [x] Isometric world: projection, 4-way rotation, elevation, painter's-algorithm depth
- [x] Camera: pan, pinch zoom, rotation, analytic tile picking
- [x] Basic terrain: grass, sand, water, forest, rock, paved, with elevation and cliff faces
- [x] Path construction (footpath, plaza, cycle path, bridge) with drag-to-draw
- [x] Cottage construction, plus reception, restaurant, café, snack bar, supermarket, shop,
      swimming pool, playground, mini golf, toilets, decorations
- [x] Park entrance
- [x] Build system: validation, placement preview, rotation, cost, demolition, undo/redo
- [x] Money: integer cents, ledger with pre-aggregated daily/weekly/monthly totals
- [x] Game clock: minutes → years, paused/1×/2×/4×/max, fixed-step, frame-rate independent
- [x] Reservation generation: a real demand model and a booking engine that cannot double-book
- [x] Arriving families: parties spawn at the gate on their arrival day
- [x] Check-in, including what happens when the cottage is not ready
- [x] Pathfinding in the live park: flow fields, budgeted A\*, unreachable detection
- [x] Cottage assignment over the whole date range
- [x] Guest needs: hunger, thirst, tiredness, boredom, bladder, with personality and interests
- [x] Guests visiting facilities: queueing, service, payment from the party's budget
- [x] Sleeping, with dormant level-of-detail driven by a tick scheduler
- [x] Checkout, packing and departure
- [x] Reviews derived from recorded moments, feeding reputation, feeding demand
- [x] Income and expenses: wages, utilities, maintenance, insurance, interest, tax
- [x] Save and load: versioned, checksummed, atomic, with slots, metadata and backup recovery
- [x] 219 headless tests across 33 suites, including a determinism check and a full-loop test

### Brought forward from later phases (small, and the slice needed them)

- [x] Housekeeping staff with shifts, a task queue and real consequences for shortages (Phase 2)
- [x] Prioritised, aggregated, rate-limited notifications (Phase 2)
- [x] Loans and interest; seasonal and last-minute pricing; financial dashboards (Phase 3)
- [x] Weather with seasonal temperature, persistence and gameplay effects (Phase 8)
- [x] Data-driven research and objectives (Phase 10)
- [x] Map overlays: scenery, crowding, occupancy, cleanliness (Phase 11)
- [x] Localisation architecture: the core emits keys, never prose; full English catalogue (Phase 11)
- [x] Accessibility: Dynamic Type, VoiceOver labels, never colour-only status (Phase 11)

---

## Current

- [~] **Verify the build.** The development container has no Swift toolchain and no Xcode, so
      nothing here has been compiled. `./Tools/verify.sh --quick` passes, including switch
      exhaustiveness over every enum in the project. **Next action: run `./Tools/verify.sh --app`
      on a Mac with Xcode 16, or read the CI result, and fix whatever the compiler finds.**
      Note: CI cannot run yet. Every job so far failed in seconds with zero steps, annotated by
      GitHub as *"The job was not started because recent account payments have failed or your
      spending limit needs to be increased."* That block is account-wide and is not lifted by the
      repository being public. Nothing in the workflow file is implicated.
- [~] **App layer.** SwiftUI + SpriteKit is written — scene, node pools, camera, HUD, build bar,
      inspector and ten panels — but unverified for the same reason.
- [~] **Screenshots.** `docs/screenshots/` holds design mockups generated from the real catalog and
      the real map generator. Replace with simulator captures once the project builds on a Mac.

## Next

- [ ] Phase 2 — Park operations: litter and bins, facility cleanliness decay, breakdowns and
      repair tasks, per-facility opening hours the player can set, complaints as first-class events
- [ ] Phase 2 — Maintenance staff loop, matching the housekeeping loop that already works
- [ ] Phase 3 — Marketing campaigns targeting specific guest segments, not a global multiplier
- [ ] Phase 3 — Inventory and deliveries for shops and restaurants
- [ ] Phase 3 — Occupancy and revenue forecasting beyond the current three-week view
- [ ] Replace the guest-thought aggregation in the Guests panel with a proper complaints feed

## Later

- [ ] Phase 4 — Terrain tools (raise, lower, flatten, paint, water, plant), roads and vehicles,
      congestion-aware routing (deferred from Phase 1 on purpose — see below)
- [ ] Phase 5 — The wider facility catalogue: bowling, arcade, tennis, padel, fitness, spa, sauna,
      petting zoo, fishing, indoor playground, nature activities
- [ ] Phase 6 — The modular water-park builder: pools, wave pools, lazy rivers, slide towers and
      slide sections, changing rooms, lifeguard posts, plant rooms
- [ ] Phase 7 — Deeper guests: family dynamics, planning, memories, repeat visits, loyalty
- [ ] Phase 8 — School and public holidays per country, seasonal events, climate differences
- [ ] Phase 9 — The company layer: multiple parks, Netherlands → Belgium → Germany → France,
      land purchase, company research, shared marketing
- [ ] Phase 10 — Career progression, more scenarios, unlocks, achievements
- [ ] Phase 11 — Animation, sound and music architecture, effects, tutorial and onboarding,
      Dutch/German/French translations, balancing, battery profiling
- [ ] Phase 12 — App Store preparation: crash, memory, performance and battery review, privacy,
      save migration rehearsal, iCloud and offline behaviour

---

## Blocked / carried forward

Everything below is in the brief and is **not** implemented yet. It is listed here rather than
quietly dropped.

| Item | Brief | Why not yet | Where it lands |
|---|---|---|---|
| Compiled, verified build | Rule 7 | No Swift toolchain or Xcode in the development container; swift.org is blocked by network policy | First green CI run, or `./Tools/verify.sh --app` on a Mac |
| Congestion-aware routing | §10 | Flow fields are deliberately static so they rebuild identically after a load; making them crowd-aware needs periodic rebuilds and a different determinism story | Phase 4, with vehicles |
| Terrain editing | §9 | The brief says not to build it before the core is stable | Phase 4 |
| Utilities as a network (electricity, water, sewage) | §20 | Currently billed as aggregate daily consumption, which is the "meaningful decisions without micromanagement" half of the requirement | Phase 3/4 |
| Transport: bicycles, golf carts, shuttles, boats | §11 | Needs roads and vehicle routing | Phase 4 |
| Water-park builder | §13 | The brief explicitly excludes it from the MVP; the pool is a working facility today | Phase 6 |
| Inventory and logistics | §17 | Variable cost per sale is modelled; stock and deliveries are not | Phase 3 |
| Litter, bins, facility cleaning tasks | §18 | Cleanliness is tracked and decays; nobody cleans it but housekeeping in cottages | Phase 2 |
| Breakdowns and repairs | §19, §23 | Condition decays and gates operation; nothing breaks suddenly and no repair task is generated | Phase 2 |
| Safety incidents | §24 | Safety is rated (supervision, condition) but nothing happens | Phase 2 |
| Sustainability upgrades (solar, heat pumps, LED) | §25 | Rated and researched; the upgrades themselves are not buildable | Phase 3 |
| Marketing campaigns | §28 | Pricing and discounts exist; campaigns do not | Phase 3 |
| Multi-park company layer | §29, §30 | The world models one park; `Company` fields are on `World` | Phase 9 |
| Sandbox and career mode UI | §32 | Scenario data and objective evaluation exist; there is no mode selection flow | Phase 10 |
| Custom difficulty | §34 | Relaxed/Normal/Hard are implemented; `custom` currently mirrors normal | Phase 10 |
| Underground / infrastructure camera views | §2 | Nothing underground to show yet | Phase 4 |
| Dutch, German and French translations | §49 | The architecture is ready and English is complete; the other catalogues are not written | Phase 11 |
| Swift 6 language mode and full `Sendable` adoption | §44 | The core is written for Swift 5 mode with one owner per world; strict-concurrency annotation is a mechanical pass best done against a compiler | Phase 11 |
| CloudKit sync wired into the UI | §39 | `CloudSaveService` is written; the save screen explains the behaviour but does not yet drive it | Phase 11 |
| Sound and music | §11 polish | Gameplay first (Rule 9) | Phase 11 |
