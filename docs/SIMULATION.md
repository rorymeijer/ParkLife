# ParkLife — Simulation Design

This document specifies the simulation model. Numbers here are the *authoritative tuning
values*; the code reads them from `SimulationTuning` and the JSON catalog, and the tests
assert them.

---

## 1. Time

* **Tick = 1 simulated minute.** Everything in the simulation is expressed in ticks; the
  simulation never reads a wall clock.
* **Speeds** (ticks per real second):

  | Speed | Ticks/s | 1 game day takes | Note |
  |---|---|---|---|
  | Paused | 0 | — | |
  | 1× | 2 | 12 min | default |
  | 2× | 4 | 6 min | |
  | 4× | 8 | 3 min | |
  | Max | up to 64 | ≤ 22 s | budget-limited, see below |

* **Fixed-step accumulator.** `SimulationEngine.advance(realSeconds:)` accumulates real time
  and runs whole ticks. It will never run more than `maxTicksPerFrame` (64) or spend more
  than `tickBudgetMillis` (8 ms) in one call — if the device cannot keep up, simulated time
  slows down rather than the frame rate collapsing. Rendering FPS therefore never changes
  simulation outcomes.
* **Calendar.** Proleptic Gregorian, epoch `Year 1 Jan 1 = 2026-01-01 (Thursday)`.
  `GameDate` exposes minute/hour/day/weekday/week/month/season/year and is pure arithmetic
  over `minutesSinceEpoch: Int`.
* **Seasons.** Spring Mar–May, Summer Jun–Aug, Autumn Sep–Nov, Winter Dec–Feb.
* **School holidays / public holidays** are data (`Resources/Catalog/calendar.json`) per
  region, so Belgium/Germany/France can differ in Phase 9 without code changes.

## 2. Determinism

* A single master `seed: UInt64` is stored in the save.
* `RandomStreams` derives **independent** SplitMix64 streams per subsystem
  (`.demand`, `.guestSpawn`, `.guestBehaviour`, `.weather`, `.incidents`, `.reviews`).
  Independent streams mean adding a weather roll cannot shift guest behaviour — which is
  what makes balance changes safely comparable.
* No `Date()`, no `Dictionary` iteration order, no `Set` iteration, and no floating-point
  accumulation of money anywhere in the simulation. Money is integer cents.
* `WorldHash` = FNV-1a 64 over the canonical save payload. Two runs from the same seed and
  the same intent log must produce the same hash — asserted by `DeterminismTests`.

## 3. Space and movement

* Tile = **8 m**. Slice map `De Zandheuvel` is 96 × 96 tiles (~768 m across).
* Walking speed in tiles/minute: adult **1.4**, teenager 1.5, child 1.15, senior 1.0.
  A 30-tile walk (240 m) therefore takes ≈ 21 game minutes. Speeds are tuned for
  *readability and pacing*, not for physical realism.
* Guests move along a tile path with continuous interpolation (`WorldPoint`), with a small
  per-guest lateral offset so crowds do not overlap exactly.

## 4. Guests

### Attributes

Identity: `firstName`, `age`, `ageBand` (child/teen/adult/senior), `groupID`.
Personality (0…1, sampled per guest from the group archetype): `sociability`,
`adventurousness`, `patience`, `frugality`, `tidiness`, `activityLevel`.
Interests (0…1): `swimming`, `nature`, `sport`, `food`, `shopping`, `entertainment`.

### Needs

Two kinds, both `0…1`:

* **Pressures** — higher is worse: `hunger`, `thirst`, `tiredness`, `boredom`, `bladder`.
* **States** — higher is better: `happiness`, `comfort`, `energy` (= 1 − tiredness).

Baseline drift per game hour (scaled by age band and activity):

| Pressure | Rise / h | Seek threshold | Urgent |
|---|---|---|---|
| hunger | +0.140 | 0.62 | 0.85 |
| thirst | +0.200 | 0.60 | 0.88 |
| tiredness | +0.055 awake, −0.160 asleep | 0.72 | 0.92 |
| boredom | +0.100 | 0.55 | 0.90 |
| bladder | +0.130 | 0.70 | 0.93 (Phase 2) |

### Decision model — utility scoring, not scripted behaviour

Every time a guest becomes idle, `GuestAISystem` scores each *available* action:

```
score(action) = needMatch × appeal × affordability × proximity × weatherFit × openNow × interest
```

* `needMatch` — how strongly the action relieves the guest's dominant pressures (a quadratic
  ramp so urgent needs dominate).
* `appeal` — facility quality × cleanliness × (1 − crowding), from live instance state.
* `affordability` — price vs. the group's *remaining* budget and the guest's frugality.
  Expensive is only penalised when quality does not justify it (brief §16).
* `proximity` — real network distance from the path graph, not Euclidean. This is what makes
  "our cottage is too far from the pool" a genuine emergent complaint.
* `weatherFit` — outdoor actions are suppressed in rain/cold; the indoor pool is boosted.
* `openNow` — facility opening hours and capacity.

The winner is picked from the top candidates with a small softmax jitter from the guest's own
RNG stream, so identical guests do not stampede to the same restaurant.

### Holiday lifecycle

```
offPark → travellingToPark → atEntrance → walkingToReception → checkingIn
        → walkingToUnit → unpacking → idle ⇄ {eating, swimming, shopping, activity,
          relaxing, walking} → sleeping → (next day) idle … → packing
        → checkingOut → leavingPark → offPark(+review)
```

Sleeping and "inside a facility" are `dormant` LOD states scheduled on the tick heap.

### Thoughts

`GuestThought` is `(kind, subject, magnitude, tick)` where `kind` is an enum and the App
renders it via `LocalizedText`. **Every thought is produced by a measured condition**, e.g.

| Thought | Emitted when |
|---|---|
| `cottageTooFarFromPool` | network distance unit→nearest pool > 55 tiles |
| `queueTooLong` | expected wait > guest patience × 12 min |
| `expensive` | price > perceivedValue(quality) × (1 + frugality) |
| `beautifulPark` | local scenery score of visited tiles > 0.75 |
| `notEnoughForChildren` | group has children and child-suitable open facilities < 2 |
| `cottageWasDirty` | unit cleanliness at check-in < 0.5 |
| `tooCrowded` | congestion on the last 10 traversed tiles > 0.8 |
| `cantFindToilet` | bladder urgent and no reachable toilet within 40 tiles |

No thought is emitted from a bare random roll.

## 5. Groups and reservations

Group archetypes (`Resources/Catalog/groupArchetypes.json`): `couple`, `youngFamily`,
`familyWithTeens`, `friendGroup`, `seniorCouple`, `multiGenerational`. Each defines size
range, age distribution, budget per person per night, interest biases, preferred stay length
and weekday bias.

### Reservation lifecycle

```
enquiry → booked → paid → arriving → checkedIn → checkedOut
                 ↘ cancelled          ↘ noShow
```

### Demand model (per day, per accommodation class)

```
demand = baseInterest(class)
       × seasonFactor(date)          0.35 … 1.75
       × weekdayFactor(arrivalDay)   Fri/Sat 1.6, Mon 0.65
       × schoolHolidayFactor         1.0 … 1.9 (family archetypes only)
       × reputationFactor            0.4 + 1.2 × reputation
       × facilityFactor              variety & quality of open facilities
       × valueFactor(price, quality) elastic, see below
       × marketingFactor(segment)    Phase 3 — per-segment, not a global multiplier
       × weatherOutlookFactor        Phase 8
```

`valueFactor` uses perceived value `v = quality / normalisedPrice`; demand falls off as
`clamp(v^1.6, 0.05, 1.6)`. Raising prices on a high-quality park is therefore viable, which
is the behaviour the brief asks for.

The resulting expected count is sampled with a Poisson draw (Knuth) from the `.demand`
stream, then each enquiry is matched to a free unit over the whole requested date range by
`ReservationSystem.assign`, which **cannot double-book**: availability is an interval check
against that unit's existing reservations, and it is the single code path that creates
bookings.

## 6. Accommodation

Definition fields: capacity, bedrooms, bathrooms, kitchen, tier (basic/comfort/premium/vip),
baseQuality, footprint, construction cost, base nightly price, daily operating cost, energy
and water consumption.
Instance state: `cleanliness`, `condition`, `occupancyState`, `currentReservation`,
`nightlyPriceOverride`, `lastCleanedTick`.

Check-in requires `cleanliness ≥ 0.5` *and* `state == .ready`. On checkout the unit becomes
`.dirty`; in Phase 1 it self-cleans after a fixed turnaround; in Phase 2 a housekeeping task
is generated instead and **staff shortage genuinely blocks check-in**.

## 7. Facilities

Definition: category (food/retail/activity/pool/service), capacity, service duration range,
base price, opening hours, staff requirement, appeal, child suitability, indoor/outdoor,
operating cost, queue capacity.
Instance: `queue`, `occupants`, `cleanliness`, `condition`, `priceOverride`, `isOpen`,
`revenueToday`.

A visit is: arrive → join queue (if space) → be served for `serviceDuration` → pay →
satisfaction moment → leave. Payment is deducted from the *group* budget in integer cents
and booked to the ledger under the facility's revenue category.

## 8. Economy

* `Money` = `Int` cents, euros. No floating point anywhere in financial code.
* `Ledger` records every transaction as `(tick, category, amount, reference)` and maintains
  running daily/weekly/monthly aggregates so dashboards never rescan history (brief §37).
* Revenue categories: accommodation, food, retail, activities, rentals, extras.
* Expense categories: construction, wages, maintenance, electricity, water, waste,
  ingredients, inventory, marketing, insurance, tax, interest, repairs.
* Daily settlement at 03:00: operating costs, wages, utilities, then statistics rollup.
* Park valuation = Σ(building construction cost × condition × 0.6) + land value + 3 × trailing
  12-week profit.

## 9. Satisfaction, reviews, reputation

During the stay every notable event appends a **satisfaction moment**
`(category, delta, reason)` to the group. Categories match the review categories:
accommodation, cleanliness, facilities, food, staff, value, location, activities.

At checkout:

```
categoryScore = clamp(3.0 + Σ deltas in category, 1, 5)          (stars)
overall       = weighted mean, weights from the group archetype
```

The review text is **assembled from the two strongest positive and the two strongest negative
moments** as localisation keys — never from a random phrase bank. A group with no strong
signals produces a neutral review; a group whose stay was uneventful and pleasant produces a
short positive one.

Park reputation is an exponentially weighted moving average of recent review scores
(half-life 60 reviews), with sub-ratings for cleanliness, safety, service and sustainability
fed by the same moments. Reputation feeds straight back into `demand`.

## 10. Weather

Daily generation from the `.weather` stream:

* temperature = seasonal sinusoid(dayOfYear) + AR(1) anomaly + diurnal cycle
* condition sampled from a season-conditioned transition matrix
  (clear, partlyCloudy, cloudy, lightRain, rain, storm, fog, snow)
* wind and precipitation intensity derived from condition

Effects: outdoor action utility ×0.2…×1.2, indoor pool demand +40 % in rain, restaurant
demand +15 % in cold, energy consumption rises with |temperature − 20 °C|, storms can close
outdoor facilities (Phase 2 incident).

## 11. Systems and tick order

Systems are ordered and each is a separate file. Order matters and is asserted in tests:

1. `TimeSystem` — advance clock, emit hour/day/season boundary events
2. `WeatherSystem` — daily weather, hourly interpolation
3. `DemandSystem` — daily enquiry generation (03:30)
4. `ReservationSystem` — assignment, payment, cancellation, no-shows
5. `ArrivalSystem` — spawn arriving groups at the entrance on their arrival day
6. `GuestAISystem` — needs drift, decisions (idle guests only)
7. `MovementSystem` — path following for `full`/`reduced` guests
8. `FacilitySystem` — queues, service, spending
9. `AccommodationSystem` — check-in/out, cleanliness, turnaround
10. `StaffSystem` — task queue and assignment (Phase 2)
11. `EconomySystem` — daily settlement, wages, utilities
12. `ReviewSystem` — reviews at checkout
13. `ReputationSystem` — rolling ratings
14. `StatisticsSystem` — aggregated time series (never rescans entities)
15. `NotificationSystem` — prioritised, aggregated, rate-limited alerts

`ScheduleQueue` is drained at the start of the tick, waking dormant entities whose scheduled
tick has arrived.

## 12. Performance strategy

* Per tick, only guests in `full`/`reduced` LOD do work; dormant guests cost zero.
* Flow fields give O(1) navigation for shared destinations. They are built from the *static*
  walkable network only, never from live crowding — that keeps them a pure function of the map,
  so they rebuild identically after loading a save and do not need refreshing as crowds move.
* Tile congestion is a plain `[UInt8]` grid, updated by delta, not recomputed. It feeds facility
  appeal and the "too crowded" thought rather than routing.
* The tick loop walks `World.activeGroupIDs` — the parties actually in the park — not every group
  that has ever booked, so per-tick cost is proportional to occupancy, not to play time.
* Finished bookings, their parties and their guests are pruned 30 days after departure. Revenue,
  occupancy and reviews have already been folded into the ledger, statistics and review ring.
* Statistics are incremental accumulators, flushed into fixed-size ring buffers
  (hourly 7 days, daily 2 years, weekly 20 years).
* Target budget: **≤ 2 ms per tick with 3 000 guests** on A15-class hardware.
