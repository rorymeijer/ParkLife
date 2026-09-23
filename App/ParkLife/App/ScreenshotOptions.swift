import Foundation
import ParkLifeCore

#if DEBUG
/// Launch-argument driven setup for automated screenshot runs.
///
/// The `screenshots` CI job boots a simulator, launches the real app with these arguments and
/// captures the result. That is what makes the images in `docs/screenshots/` the actual game
/// rather than a mockup — the park in them is a simulation that really ran.
///
/// DEBUG only, so none of it exists in a release build.
enum ScreenshotOptions {

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-parklife-screenshot")
    }

    /// Simulated days to run before the first frame, so the park has guests in it.
    static var warmupDays: Int {
        Int(value(for: "-parklife-warmup-days") ?? "") ?? 0
    }

    static var panel: String? { value(for: "-parklife-panel") }

    static var overlay: MapOverlay? {
        guard let raw = value(for: "-parklife-overlay") else { return nil }
        return MapOverlay(rawValue: raw)
    }

    /// `cottage`, `pool` or `guest` — what the inspector should be showing.
    static var selection: String? { value(for: "-parklife-select") }

    static var buildDefinition: String? { value(for: "-parklife-build") }

    /// Camera zoom for the shot; smaller shows more of the park.
    static var zoom: Double? {
        Double(value(for: "-parklife-zoom") ?? "")
    }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
