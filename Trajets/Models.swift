import Foundation
import CoreLocation

struct TrackPoint: Codable, Identifiable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let accuracy: Double
    let speed: Double
    var segment: Int? // Optional for V1 archives.

    init(_ location: CLLocation, segment: Int = 0) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        accuracy = location.horizontalAccuracy
        speed = location.speed >= 0 && location.speed < 100 ? location.speed : 0
        self.segment = segment
    }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var points: [TrackPoint] = []
    var distance: Double = 0
    var maxSpeed: Double = 0
    // Optional additions keep the original JSON format readable.
    var name: String?
    var pausedAt: Date?
    var pausedSeconds: Double?
    var segmentNumber: Int?
    var resumedAt: Date?
    var lastRecordedAt: Date?
    var lastObservedAt: Date?
    var category: String?
    var favorite: Bool?
    var autoPaused: Bool?
    var movingSeconds: Double?
    var lastMotionAt: Date?
    var lastMotionSpeed: Double?

    var title: String {
        let text = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? startedAt.formatted(date: .abbreviated, time: .shortened) : text
    }
    var isPaused: Bool { pausedAt != nil }
    func duration(at date: Date = Date()) -> TimeInterval {
        let end = endedAt ?? date
        let currentPause = pausedAt.map { max(0, end.timeIntervalSince($0)) } ?? 0
        return max(0, end.timeIntervalSince(startedAt) - (pausedSeconds ?? 0) - currentPause)
    }
    var averageSpeed: Double { duration() > 0 ? distance / duration() : 0 }

    mutating func pause(at date: Date = Date()) {
        guard endedAt == nil, !isPaused else { return }
        pausedAt = date
        lastRecordedAt = date
        lastMotionAt = nil
        lastMotionSpeed = nil
    }
    mutating func resume(at date: Date = Date()) {
        guard endedAt == nil, let pausedAt else { return }
        pausedSeconds = (pausedSeconds ?? 0) + max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        autoPaused = false
        segmentNumber = (segmentNumber ?? 0) + 1
        resumedAt = date
        lastRecordedAt = date
    }
    mutating func finish(at date: Date = Date()) {
        guard endedAt == nil else { return }
        if let pausedAt {
            pausedSeconds = (pausedSeconds ?? 0) + max(0, date.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        endedAt = date
        autoPaused = false
        lastRecordedAt = date
    }
    mutating func recover() {
        finish(at: lastRecordedAt ?? points.last?.timestamp ?? startedAt)
    }

    // Distance is added only for plausible fixes within one recording segment.
    mutating func append(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard !isPaused, endedAt == nil,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSince(now)) < 15,
              location.timestamp >= (resumedAt ?? startedAt),
              lastObservedAt.map({ location.timestamp > $0 }) ?? true else { return false }
        var segment = segmentNumber ?? 0
        if let last = points.last {
            let seconds = location.timestamp.timeIntervalSince(last.timestamp)
            guard seconds > 0 else { return false }
            let uninterrupted = (last.segment ?? 0) == segment
            let gap = location.timestamp.timeIntervalSince(lastObservedAt ?? last.timestamp)
            let meters = location.distance(from: last.location)
            if uninterrupted && gap < 30 {
                guard meters / seconds < 100 else { return false }
                recordMotion(location)
                lastObservedAt = location.timestamp
                lastRecordedAt = location.timestamp
                maxSpeed = max(maxSpeed, location.speed >= 0 && location.speed < 100 ? location.speed : 0)
                if meters < max(3, min(last.accuracy, location.horizontalAccuracy) * 0.5) {
                    return false
                }
                distance += meters
            } else if uninterrupted {
                segment += 1
                segmentNumber = segment
            }
        }
        points.append(TrackPoint(location, segment: segment))
        recordMotion(location)
        lastObservedAt = location.timestamp
        lastRecordedAt = location.timestamp
        maxSpeed = max(maxSpeed, location.speed >= 0 && location.speed < 100 ? location.speed : 0)
        return true
    }

    private mutating func recordMotion(_ location: CLLocation) {
        if let previous = lastMotionAt, let previousSpeed = lastMotionSpeed {
            let seconds = location.timestamp.timeIntervalSince(previous)
            if seconds > 0 && seconds <= 10 && previousSpeed > 0.8 && location.speed > 0.8 && location.speed < 100 {
                movingSeconds = (movingSeconds ?? 0) + seconds
            }
        }
        if movingSeconds == nil { movingSeconds = 0 }
        lastMotionAt = location.timestamp
        lastMotionSpeed = location.speed
    }

    var segments: [[TrackPoint]] {
        var result: [[TrackPoint]] = []
        for point in points {
            if let previous = result.last?.last,
               (point.segment != nil && point.segment == previous.segment ||
                point.segment == nil && previous.segment == nil && point.timestamp.timeIntervalSince(previous.timestamp) < 30) {
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
    static func distance(_ meters: Double, imperial: Bool = false) -> String {
        (meters / (imperial ? 1609.344 : 1000)).formatted(.number.precision(.fractionLength(2)))
    }
    static func speed(_ metersPerSecond: Double, imperial: Bool = false) -> String {
        (metersPerSecond * (imperial ? 2.2369362921 : 3.6)).formatted(.number.precision(.fractionLength(0)))
    }
    static func time(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}

enum GPX {
    static func escape(_ text: String) -> String {
        // XML 1.0 excludes control characters, including those pasted into names.
        let clean = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0.value == 9 || $0.value == 10 || $0.value == 13 ||
            (0x20...0xD7FF).contains($0.value) ||
            (0xE000...0xFFFD).contains($0.value) ||
            (0x10000...0x10FFFF).contains($0.value)
        }))
        return clean.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    static func document(for trip: Trip) -> String {
        let formatter = ISO8601DateFormatter()
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"Trajets\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(escape(trip.title))</name>"
        for segment in trip.segments {
            xml += "<trkseg>"
            for point in segment {
                xml += "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(formatter.string(from: point.timestamp))</time></trkpt>"
            }
            xml += "</trkseg>"
        }
        return xml + "</trk></gpx>"
    }
}
