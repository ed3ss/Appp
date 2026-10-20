import XCTest
import CoreLocation
import SwiftUI
@testable import Trajets

final class V3Tests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func fix(_ seconds: Double, speed: Double = 4, accuracy: Double = 5, latitude: Double = 48.85) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: 2.35), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed,
                   timestamp: start.addingTimeInterval(seconds))
    }
    func completed() -> Trip {
        var trip = Trip(startedAt: start)
        _ = trip.append(fix(0), now: start)
        _ = trip.append(fix(5, latitude: 48.8502), now: start.addingTimeInterval(5))
        trip.finish(at: start.addingTimeInterval(10))
        return trip
    }
    func observe(_ detector: inout AutoPauseDetector, _ time: Double, speed: Double = 0, paused: Bool = false) -> AutoPauseDetector.Decision? {
        let location = fix(time, speed: speed)
        return detector.observe(location, autoPaused: paused, now: location.timestamp)
    }
    func testAutomaticPauseRequiresSustainedStop() {
        var detector = AutoPauseDetector()
        for second in [0.0, 5, 10] { XCTAssertNil(observe(&detector, second)) }
        XCTAssertEqual(observe(&detector, 15), .pause)
    }
    func testAutomaticResumeRequiresSustainedMovement() {
        var detector = AutoPauseDetector()
        XCTAssertNil(observe(&detector, 0, speed: 1.4, paused: true))
        XCTAssertNil(observe(&detector, 2, speed: 1.4, paused: true))
        XCTAssertEqual(observe(&detector, 3, speed: 1.4, paused: true), .resume)
    }
    func testNoiseAndGPSGapResetStopCandidate() {
        var detector = AutoPauseDetector()
        XCTAssertNil(observe(&detector, 0))
        XCTAssertNil(observe(&detector, 8, speed: 0.8))
        XCTAssertNil(observe(&detector, 10))
        XCTAssertNil(observe(&detector, 25)) // gap cannot imply stationary time
        XCTAssertNil(observe(&detector, 30))
    }
    func testInvalidFixesCannotPauseOrResume() {
        for location in [fix(0, speed: -1), fix(0, accuracy: 60), fix(30)] {
            var detector = AutoPauseDetector()
            XCTAssertNil(detector.observe(location, autoPaused: false, now: start))
        }
        var detector = AutoPauseDetector()
        XCTAssertNil(observe(&detector, 0))
        XCTAssertNil(observe(&detector, 0))
        XCTAssertNil(detector.observe(fix(1), autoPaused: false, now: start.addingTimeInterval(20)))
    }
    func testAutoPauseFlagClearedOnResumeAndFinish() {
        var trip = completed()
        trip.endedAt = nil
        trip.pause(at: start.addingTimeInterval(12)); trip.autoPaused = true
        trip.resume(at: start.addingTimeInterval(20))
        XCTAssertEqual(trip.autoPaused, false)
        trip.pause(at: start.addingTimeInterval(22)); trip.autoPaused = true
        trip.finish(at: start.addingTimeInterval(30))
        XCTAssertEqual(trip.autoPaused, false)
        XCTAssertEqual(trip.duration(), 14)
    }
    func testMovingTimeExcludesStopsGapsAndPauses() {
        var trip = Trip(startedAt: start)
        for (time, speed) in [(0.0, 4.0), (5, 4), (10, 0), (15, 0), (20, 4), (25, 4), (50, 4)] {
            _ = trip.append(fix(time, speed: speed), now: start.addingTimeInterval(time))
        }
        trip.pause(at: start.addingTimeInterval(51))
        trip.resume(at: start.addingTimeInterval(60))
        _ = trip.append(fix(61), now: start.addingTimeInterval(61))
        trip.finish(at: start.addingTimeInterval(65))
        XCTAssertEqual(trip.movingSeconds, 10)
        XCTAssertEqual(trip.movingDuration, 10)
    }
    func testOlderTripMovementIsEstimated() {
        var trip = completed()
        trip.movingSeconds = nil
        XCTAssertEqual(trip.movingDuration, 5)
    }
    func testBackupRoundTripPreservesMetadataAndPoints() throws {
        var trip = completed()
        trip.favorite = true; trip.category = "bicycle"; trip.name = "Ma balade"
        let restored = try BackupStore.decode(BackupStore.encode(TripArchive(trips: [trip])))
        XCTAssertEqual(restored.trips[0].favorite, true)
        XCTAssertEqual(restored.trips[0].activity, .bicycle)
        XCTAssertEqual(restored.trips[0].name, "Ma balade")
        XCTAssertEqual(restored.trips[0].points.count, 2)
        XCTAssertEqual(restored.trips[0].id, trip.id)
    }
    func testRestoreMergeIsIdempotentAndKeepsCurrentData() {
        let trip = completed()
        var existing = trip; existing.name = "Nom local"
        var other = completed(); other.id = UUID()
        let current = TripArchive(trips: [existing], active: Trip())
        let incoming = TripArchive(trips: [trip, other])
        let first = BackupStore.merging(incoming, into: current)
        XCTAssertEqual(first.added, 1)
        XCTAssertEqual(first.archive.trips.first { $0.id == trip.id }?.name, "Nom local")
        XCTAssertEqual(first.archive.active?.id, current.active?.id)
        XCTAssertEqual(BackupStore.merging(incoming, into: first.archive).added, 0)
    }
    func testBackupOfActiveTripDoesNotMutateRecording() throws {
        var active = Trip(startedAt: Date().addingTimeInterval(-30))
        active.pause(at: Date().addingTimeInterval(-10))
        let current = TripArchive(active: active)
        let restored = try BackupStore.decode(BackupStore.encode(current))
        XCTAssertNotNil(current.active?.pausedAt)
        XCTAssertNil(current.active?.endedAt)
        XCTAssertNil(restored.active)
        XCTAssertEqual(restored.trips.count, 1)
        XCTAssertEqual(restored.trips[0].duration(), 20, accuracy: 0.1)
    }
    func testRejectsInvalidOrFutureBackup() throws {
        XCTAssertThrowsError(try BackupStore.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try BackupStore.decode(Data("{\"trips\":null}".utf8)))
        let future = TripBackup(version: 99, archive: TripArchive())
        XCTAssertThrowsError(try BackupStore.decode(JSONEncoder().encode(future)))
        var invalid = completed(); invalid.distance = -1
        XCTAssertThrowsError(try BackupStore.decode(JSONEncoder().encode(TripArchive(trips: [invalid]))))
    }
    func testRejectsDuplicateIDsAndInvalidCoordinates() throws {
        let trip = completed()
        XCTAssertThrowsError(try BackupStore.decode(JSONEncoder().encode(TripArchive(trips: [trip, trip]))))
        var invalid = trip
        invalid.points.append(TrackPoint(fix(6, latitude: 999)))
        XCTAssertThrowsError(try BackupStore.decode(JSONEncoder().encode(TripArchive(trips: [invalid]))))
    }
    func testOldRawArchiveCanBeImported() throws {
        let restored = try BackupStore.decode(JSONEncoder().encode(TripArchive(trips: [completed()])))
        XCTAssertEqual(restored.trips.count, 1)
    }
    func testReplayNearestPointHandlesBoundsAndGap() {
        let trip = completed()
        XCTAssertEqual(trip.pointIndex(nearest: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(trip.pointIndex(nearest: start.addingTimeInterval(4)), 1)
        XCTAssertEqual(trip.pointIndex(nearest: start.addingTimeInterval(100)), 1)
        XCTAssertNil(Trip().pointIndex(nearest: start))
    }
    func testMonthlyTotalsIncludeEmptyMonthsAndBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        var current = completed()
        current.startedAt = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        current.endedAt = current.startedAt.addingTimeInterval(60); current.distance = 1000
        var previous = current; previous.id = UUID()
        previous.startedAt = current.startedAt.addingTimeInterval(-1)
        previous.endedAt = previous.startedAt.addingTimeInterval(60)
        let totals = TripStatistics.totals([current, previous], monthly: true, now: now, calendar: calendar)
        XCTAssertEqual(totals.count, 6)
        XCTAssertEqual(totals.last?.count, 1)
        XCTAssertEqual(totals[4].count, 1)
        XCTAssertEqual(totals.first?.count, 0)
    }
    func testPersonalizedLiveActivityPayload() throws {
        var state = LiveTripAttributes.ContentState.snapshot(distance: 1000, speed: 10, lastFix: start,
            activeSeconds: 100, isPaused: false, imperial: false, now: start)
        state.primaryMetric = "average"
        XCTAssertEqual(state.primaryText, "36")
        state.primaryMetric = "duration"
        XCTAssertEqual(state.primaryText, "00:01:40")
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(LiveTripAttributes.ContentState.self, from: data).metric, .duration)
    }
    @MainActor func testSharePosterRendersOffline() throws {
        let renderer = ImageRenderer(content: RoutePoster(trip: completed(), imperial: false))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 390)
        XCTAssertGreaterThan(image.size.height, 400)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
    }
}
