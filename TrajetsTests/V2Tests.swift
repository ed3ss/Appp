import XCTest
import CoreLocation
@testable import Trajets

final class V2Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    private func fix(_ seconds: Double, latitude: Double = 48.85) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: 2.35),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   course: 0, speed: 4, timestamp: date(seconds))
    }
    func testV1ArchiveStillLoads() throws {
        // Literal V1 fixture: no keys added by V2, including on TrackPoint.
        let json = """
        {"trips":[{"id":"F9E774E3-B5E3-4936-8B71-E869911C95CB","startedAt":700000000,"endedAt":700000065,"points":[{"id":"C7C87A42-2446-46BC-9925-45120722E5CA","latitude":48.85,"longitude":2.35,"timestamp":700000000,"accuracy":5,"speed":4}],"distance":123,"maxSpeed":4}]}
        """
        let archive = try JSONDecoder().decode(TripArchive.self, from: Data(json.utf8))
        let trip = try XCTUnwrap(archive.trips.first)
        XCTAssertEqual(trip.duration(), 65)
        XCTAssertEqual(trip.distance, 123)
        XCTAssertEqual(trip.segments.count, 1)
        XCTAssertFalse(trip.isPaused)
        let restored = try JSONDecoder().decode(TripArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.trips.first?.points.first?.latitude, 48.85)
    }
    func testPauseResumeExcludesTimeAndDistance() {
        var trip = Trip(startedAt: start)
        XCTAssertTrue(trip.append(fix(0), now: date(0)))
        trip.pause(at: date(10))
        XCTAssertFalse(trip.append(fix(15, latitude: 48.86), now: date(15)))
        XCTAssertEqual(trip.duration(at: date(20)), 10)
        trip.resume(at: date(30))
        XCTAssertTrue(trip.append(fix(31, latitude: 48.86), now: date(31)))
        XCTAssertEqual(trip.distance, 0)
        XCTAssertEqual(trip.segments.count, 2)
        trip.finish(at: date(40))
        XCTAssertEqual(trip.duration(), 20)
        XCTAssertEqual(trip.pausedSeconds, 20)
    }
    func testStopWhilePausedAndRepeatedCalls() {
        var trip = Trip(startedAt: start)
        trip.pause(at: date(10))
        trip.pause(at: date(15))
        trip.finish(at: date(30))
        trip.finish(at: date(50))
        trip.resume(at: date(60))
        XCTAssertEqual(trip.duration(), 10)
        XCTAssertEqual(trip.endedAt, date(30))
        XCTAssertFalse(trip.isPaused)
    }
    func testSeveralPausesAndDelayedFixRejected() {
        var trip = Trip(startedAt: start)
        trip.pause(at: date(10)); trip.resume(at: date(20))
        trip.pause(at: date(30)); trip.resume(at: date(45))
        XCTAssertFalse(trip.append(fix(40), now: date(46)))
        trip.finish(at: date(60))
        XCTAssertEqual(trip.duration(), 35)
    }
    func testRecoveryEndsAtCheckpointNotRelaunch() throws {
        var trip = Trip(startedAt: start)
        _ = trip.append(fix(0), now: date(0))
        _ = trip.append(fix(10), now: date(10)) // stationary fix still advances checkpoint
        var restored = try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip))
        restored.recover()
        XCTAssertEqual(restored.duration(), 10)
        XCTAssertEqual(restored.points.count, 1)
    }
    func testPausedRecoveryPreservesActiveTime() throws {
        var trip = Trip(startedAt: start)
        trip.pause(at: date(20))
        var restored = try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip))
        restored.recover()
        XCTAssertEqual(restored.duration(), 20)
        XCTAssertFalse(restored.isPaused)
    }
    func testStationaryGPSDoesNotCreateFalseGap() {
        var trip = Trip(startedAt: start)
        _ = trip.append(fix(0), now: date(0))
        for second in stride(from: 5, through: 60, by: 5) {
            _ = trip.append(fix(Double(second)), now: date(Double(second)))
        }
        _ = trip.append(fix(65, latitude: 48.851), now: date(65))
        XCTAssertEqual(trip.segments.count, 1)
        XCTAssertEqual(trip.distance, 111, accuracy: 2)
    }
    func testGPXEscapingAndPauseSegments() {
        var trip = Trip(startedAt: start)
        trip.name = "A & B <balade> \"été\"\u{0001}"
        _ = trip.append(fix(0), now: date(0))
        trip.pause(at: date(1)); trip.resume(at: date(2))
        _ = trip.append(fix(3, latitude: 48.86), now: date(3))
        let xml = GPX.document(for: trip)
        XCTAssertTrue(xml.contains("A &amp; B &lt;balade&gt; &quot;été&quot;"))
        XCTAssertFalse(xml.contains("\u{0001}"))
        XCTAssertEqual(xml.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertTrue(xml.contains("2023-11-14T22:13:20Z"))
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "\(String(describing: parser.parserError))")
    }
    func testEmptyGPXAndUnitConversions() {
        let xml = GPX.document(for: Trip(startedAt: start))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
        XCTAssertEqual(Display.speed(10), "36")
        XCTAssertEqual(Display.speed(10, imperial: true), "22")
        XCTAssertEqual(Display.time(-5), "00:00:00")
    }
}
