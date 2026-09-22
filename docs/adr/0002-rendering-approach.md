# ADR 0002 — Rendering the 2.5D isometric world

* Status: Accepted (Phase 0)
* Date: 2026-09-22

## Context

The world is a colourful 2.5D isometric holiday park: hundreds to thousands of tiles,
buildings, props and animated guests, on iPhone-class GPUs, with pan/zoom/rotate,
tile picking, build previews and data overlays — and it has to stay readable when zoomed out.

## Options considered

1. **Raw Metal renderer.** Maximum control and the best possible batching, but we would have
   to write sprite batching, texture atlasing, a camera, picking and text ourselves before
   any gameplay exists. Violates "gameplay systems first" (Rule 9).
2. **SceneKit / RealityKit with an orthographic camera.** True 3D assets, real rotation. But
   it is heavier per node, the art pipeline cost is enormous for a solo project, and classic
   tycoon readability is easier to hit with 2D sprites than with real 3D at phone size.
3. **SwiftUI `Canvas`.** Fine for overlays, not for thousands of animated sprites.
4. **SpriteKit.** Metal-backed, automatic draw batching per texture atlas, built-in camera
   node, action system, particle effects, and it composes into SwiftUI via `SpriteView`.

## Decision

**SpriteKit**, hosted in SwiftUI via `SpriteView`, drawing pre-rendered isometric sprites.

* Draw order: `zPosition = (wx + wy) * 1000 + layer` — painter's algorithm, the standard
  isometric solution, which also makes guests correctly occlude/be occluded by buildings.
* **Node pooling:** `SpriteNodePool` reuses `SKSpriteNode`s for guests and tiles. Only tiles
  inside the camera viewport (plus a margin) have nodes at all; the world is a data grid,
  not a node tree. This decouples node count from park size.
* **Texture atlases** per layer (`Terrain`, `Buildings`, `Guests`, `Effects`) so a frame is a
  handful of draw calls.
* **Camera rotation** is 4-way (0/90/180/270). Sprites are authored with four facings rather
  than being rotated, keeping the classic tycoon look. Rotation changes the *projection*, not
  the simulation grid.
* **Picking** is analytic, not per-pixel: screen → world inverse projection → candidate tile,
  then a small neighbourhood test against building footprints and elevation. O(1).
* **Overlays** (happiness, cleanliness, congestion …) are a single additive tint layer driven
  by a per-tile scalar array from the snapshot — no extra nodes per tile.

3D/isometric-looking assets are produced offline and shipped as sprites; the brief's "use 3D
assets where appropriate" is satisfied at the art-pipeline level, not the runtime level.

## Consequences

* If SpriteKit ever becomes the bottleneck, the swap point is exactly one file
  (`ParkScene.apply(_:)`), because the renderer only consumes `WorldSnapshot`.
* Placeholder art is trivially replaceable: sprite names come from the JSON catalog's
  `art` field, which is deliberately separate from the simulation `id` (ASSET POLICY §54).
