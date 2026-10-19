import ActivityKit
import Foundation

struct LiveTripAttributes: ActivityAttributes {
    let tripID: UUID
    struct ContentState: Codable, Hashable {
        var distance: Double
        var speed: Double?
        var activeSeconds: Double
        var timerStart: Date?
        var isPaused: Bool
        var isFinished: Bool
        var imperial: Bool

        static func snapshot(distance: Double, speed: Double, lastFix: Date?,
                             activeSeconds: Double, isPaused: Bool, isFinished: Bool = false,
                             imperial: Bool, now: Date = Date()) -> Self {
            let fresh = lastFix.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 10 } ?? false
            return Self(distance: max(0, distance),
                        speed: fresh && !isPaused && !isFinished && speed.isFinite ? max(0, speed) : nil,
                        activeSeconds: max(0, activeSeconds),
                        timerStart: isPaused || isFinished ? nil : now.addingTimeInterval(-max(0, activeSeconds)),
                        isPaused: isPaused, isFinished: isFinished, imperial: imperial)
        }
        var speedText: String {
            guard let speed else { return "—" }
            return (speed * (imperial ? 2.2369362921 : 3.6)).formatted(.number.precision(.fractionLength(0)))
        }
        var distanceText: String {
            (distance / (imperial ? 1609.344 : 1000)).formatted(.number.precision(.fractionLength(2)))
        }
        var speedUnit: String { imperial ? "mph" : "km/h" }
        var distanceUnit: String { imperial ? "mi" : "km" }
        var elapsedText: String {
            let seconds = Int(max(0, activeSeconds))
            return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
    }
}
