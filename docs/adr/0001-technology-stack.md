# ADR 0001 — Native Apple technology stack

* Status: Accepted (Phase 0)
* Date: 2026-09-22

## Context

ParkLife is a management/tycoon game for iPhone and iPadOS, built in Xcode, free, offline-first,
with optional iCloud sync and no advertising. The brief lists Swift, SwiftUI, SpriteKit/Metal,
GameplayKit, Core Data/SwiftData and CloudKit as *candidates* and explicitly asks not to adopt
them blindly.

## Decision

| Layer | Chosen | Rejected alternative | Reason |
|---|---|---|---|
| Language | Swift | Objective-C, C++ core | Value types + `Codable` + actors map directly onto a deterministic, serialisable simulation |
| Simulation | Plain Swift library, Foundation only | GameplayKit entity/component system | `GKEntity`/`GKComponent` are reference types that are not `Codable`, not deterministic across OS versions, and unavailable on Linux. We need save/replay/testability more than we need their convenience. `GKGridGraph` A\* likewise cannot do incremental invalidation or budgeted async searches. |
| World rendering | SpriteKit | Raw Metal; SceneKit/RealityKit; SwiftUI Canvas | See ADR 0002 |
| UI | SwiftUI | UIKit | Touch-first layout, Dynamic Type, VoiceOver, size-class adaptation and state binding come free; a tycoon HUD is a data-driven form, which is SwiftUI's strength |
| Persistence | Codable JSON snapshot | Core Data / SwiftData | See ADR 0003 |
| Cloud | CloudKit (`CKAsset`, private DB) | iCloud Drive documents; custom backend | No account server, free, private, and optional |
| Dependencies | none | SpriteKit helpers, logging libs, ECS libs | Nothing on offer beats ~300 lines of purpose-built code; every dep is an App Store review and Swift-version risk |

`OSLog` (`os.Logger`) is used **only in the App layer**; the core defines a tiny
`ParkLog` protocol with categories (`SIM`, `PATH`, `ECONOMY`, `GUEST`, `STAFF`, `SAVE`,
`RENDER`, `CLOUD`) that the App binds to `os.Logger`. This keeps the core free of Apple
imports while still giving Instruments-visible signposts on device.

## Consequences

* The simulation compiles and tests on Linux → fast feedback, no simulator needed for logic tests.
* We write our own A\*, heap, RNG and ECS-lite storage (~600 lines total, fully tested).
* We cannot use GameplayKit's `GKAgent` steering; guest movement is hand-written path
  following, which we need anyway for deterministic replay.
* Swift 6 strict concurrency is achievable because the core has one owner per world.
