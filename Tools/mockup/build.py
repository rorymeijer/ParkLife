#!/usr/bin/env python3
"""
Builds the ParkLife design mockup used for docs/screenshots.

These are *design mockups*, not simulator captures — the container this project is developed in
has no macOS or iOS simulator. To keep them honest rather than decorative they are driven by the
real data:

  * the content catalog JSON that ships inside ParkLifeCore,
  * a JavaScript port of `MapGenerator` using the same SplitMix64 generator and the same map seed,
    so the terrain is the terrain the game generates,
  * the same demo-park layout as `GameSetup.makeDemoPark`,
  * the same isometric projection, tile metrics and placeholder-art colours as the renderer.

Guest and staff positions are illustrative: a real simulation is the only thing that produces
those, and that needs a Swift toolchain.
"""
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Sources/ParkLifeCore/Resources/Catalog"
OUT = pathlib.Path(__file__).resolve().parent / "out"


def load(name):
    return json.load(open(CATALOG / name))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = {
        "buildings": load("buildings.json"),
        "paths": load("paths.json"),
        "maps": load("maps.json"),
        "scenarios": load("scenarios.json"),
        "staffRoles": load("staffRoles.json"),
        "research": load("research.json"),
    }
    here = pathlib.Path(__file__).resolve().parent
    template = (here / "mockup.html").read_text()
    script = (here / "render.js").read_text()
    html = template.replace("/*__CATALOG__*/null", json.dumps(data))
    # Inline the renderer so the mockup is a single self-contained file.
    html = html.replace('<script src="render.js"></script>', f"<script>\n{script}\n</script>")
    (OUT / "mockup.html").write_text(html)
    print(f"wrote {OUT / 'mockup.html'} ({len(html)} bytes)")


if __name__ == "__main__":
    main()
