import Foundation
import CoreLocation

struct TrackPoint: Codable, Identifiable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let accuracy: Double
    let speed: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        accuracy = location.horizontalAccuracy
        speed = max(0, location.speed)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var points: [TrackPoint] = []
    var distance: Double = 0
    var maxSpeed: Double = 0

    func duration(at date: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }
    var averageSpeed: Double {
        let seconds = duration()
        return seconds > 0 ? distance / seconds : 0
    }

    // Reject stale/inaccurate fixes and implausible jumps; never bridge GPS outages.
    mutating func append(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSince(now)) < 15,
              location.timestamp >= startedAt else { return false }
        if let last = points.last {
            let seconds = location.timestamp.timeIntervalSince(last.timestamp)
            guard seconds > 0 else { return false }
            let meters = location.distance(from: last.location)
            guard meters / seconds < 100 else { return false }
            if seconds < 30, meters >= max(3, min(last.accuracy, location.horizontalAccuracy) * 0.5) {
                distance += meters
            } else if seconds < 30 {
                return false
            }
        }
        points.append(TrackPoint(location))
        if location.speed >= 0, location.speed < 100 {
            maxSpeed = max(maxSpeed, location.speed)
        }
        return true
    }

    var segments: [[TrackPoint]] {
        var result: [[TrackPoint]] = []
        for point in points {
            if let previous = result.last?.last,
               point.timestamp.timeIntervalSince(previous.timestamp) < 30 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }
}

struct TripArchive: Codable {
    var trips: [Trip] = []
    var active: Trip?
}

enum Display {
    static func distance(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
    static func speed(_ metersPerSecond: Double) -> String {
        String(format: "%.0f", metersPerSecond * 3.6)
    }
    static func time(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
