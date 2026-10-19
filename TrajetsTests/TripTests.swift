import XCTest
import CoreLocation
@testable import Trajets

final class TripTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(_ latitude: Double, seconds: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 2.35),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: 0, speed: 10, timestamp: start.addingTimeInterval(seconds))
    }

    func testDistanceAndDuplicateRejection() {
        var trip = Trip(startedAt: start)
        XCTAssertTrue(trip.append(fix(48.85, seconds: 0), now: start))
        XCTAssertTrue(trip.append(fix(48.851, seconds: 12), now: start.addingTimeInterval(12)))
        XCTAssertEqual(trip.distance, 111, accuracy: 2)
        XCTAssertFalse(trip.append(fix(48.851, seconds: 12), now: start.addingTimeInterval(12)))
        XCTAssertEqual(trip.points.count, 2)
    }

    func testBadFixAndTeleportRejected() {
        var trip = Trip(startedAt: start)
        XCTAssertFalse(trip.append(fix(48.85, seconds: 0, accuracy: 100), now: start))
        XCTAssertTrue(trip.append(fix(48.85, seconds: 0), now: start))
        XCTAssertFalse(trip.append(fix(49.85, seconds: 1), now: start.addingTimeInterval(1)))
        XCTAssertFalse(trip.append(fix(48.851, seconds: 1), now: start.addingTimeInterval(50)))
    }

    func testOutageDoesNotAddUnknownDistance() {
        var trip = Trip(startedAt: start)
        XCTAssertTrue(trip.append(fix(48.85, seconds: 0), now: start))
        XCTAssertTrue(trip.append(fix(48.86, seconds: 120), now: start.addingTimeInterval(120)))
        XCTAssertEqual(trip.distance, 0)
        XCTAssertEqual(trip.segments.count, 2)
    }

    func testArchiveRoundTripAndDuration() throws {
        var trip = Trip(startedAt: start)
        trip.endedAt = start.addingTimeInterval(65)
        let archive = TripArchive(trips: [trip], active: nil)
        let decoded = try JSONDecoder().decode(TripArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.trips[0].id, trip.id)
        XCTAssertEqual(decoded.trips[0].duration(), 65)
        XCTAssertEqual(Display.time(65), "00:01:05")
    }
}
