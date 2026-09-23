# Screenshots

**These are real captures of ParkLife running in an iOS simulator.**

They are taken by the `screenshots` job in `.github/workflows/ci.yml`, which builds the app,
boots a simulator, launches it with arguments that put it into a known state and captures the
screen. Nothing in them is drawn or arranged by hand: the park in the images is a simulation that
really ran, so the occupancy grid, the bookings, the guest's needs and the finance figures are
all output from `ParkLifeCore`, not plausible-looking values.

| File | Device | Shows |
|---|---|---|
| `01-ipad-park-and-bookings.png` | iPad Pro 13-inch | Park view, HUD, cottage inspector, bookings panel beside the park |
| `02-ipad-park-panel.png` | iPad Pro 13-inch | Park panel: overview, the six park ratings, and the map overlay picker |
| `03-iphone-build-mode.png` | iPhone 17 Pro | Build mode: the build bar with rotate, undo and redo for the selected cottage |
| `04-iphone-finances.png` | iPhone 17 Pro | Finances as a contextual sheet, with the profit trend |
| `05-iphone-guest-inspector.png` | iPhone 17 Pro | Scenery overlay and a selected guest with needs and their latest thought |

Each shot warms the park up by running the simulation forward 25–40 simulated days before the
first frame, so the park has guests, bookings and a trading history in it.

## Reproducing them

On a Mac with Xcode:

```sh
./Tools/capture_screenshots.sh docs/screenshots
```

The script resolves simulators by name prefix rather than exact name, so a new hardware
generation does not silently break it, and it fails the build if a shot cannot be taken — a
capture job that reports success while producing nothing is worse than one that reports failure.
It also rejects a frame that is too uniform to be a rendered park: the blank launch screen
compresses to about 0.02 bytes per pixel against 0.18–0.39 for a real frame, so a capture that
lands before the app has drawn is retried and ultimately fails the job rather than being
committed as a screenshot.

## History

These replaced a set of design mockups. Until the project could be built on a Mac there was no
simulator capture to show, so the images were generated from the project's real catalog and map
data by `Tools/mockup/` with illustrative guest positions and figures. That is no longer the
case, and the mockup pipeline is kept only for reference.
