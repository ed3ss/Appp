import XCTest
@testable import Trajets

final class LiveTripTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFreshStateAndTimer() {
        let state = LiveTripAttributes.ContentState.snapshot(distance: 1609.344, speed: 10,
            lastFix: now.addingTimeInterval(-2), activeSeconds: 65, isPaused: false, imperial: true, now: now)
        XCTAssertEqual(state.speedText, "22")
        XCTAssertEqual(state.speedUnit, "mph")
        XCTAssertEqual(state.timerStart, now.addingTimeInterval(-65))
        XCTAssertEqual(state.elapsedText, "00:01:05")
    }
    func testPauseAndFinishFreezeTimerAndHideSpeed() {
        for finished in [false, true] {
            let state = LiveTripAttributes.ContentState.snapshot(distance: 100, speed: 10, lastFix: now,
                activeSeconds: 30, isPaused: !finished, isFinished: finished, imperial: false, now: now)
            XCTAssertNil(state.speed)
            XCTAssertNil(state.timerStart)
            XCTAssertEqual(state.elapsedText, "00:00:30")
        }
    }
    func testOldOrMissingGPSDoesNotDisplayStaleSpeed() {
        for fix in [nil, now.addingTimeInterval(-20), now.addingTimeInterval(20)] as [Date?] {
            let state = LiveTripAttributes.ContentState.snapshot(distance: 0, speed: 100, lastFix: fix,
                activeSeconds: 0, isPaused: false, imperial: false, now: now)
            XCTAssertEqual(state.speedText, "—")
        }
    }
    func testPayloadRoundTripAndSizeBudget() throws {
        let state = LiveTripAttributes.ContentState.snapshot(distance: 1234, speed: 12, lastFix: now,
            activeSeconds: 60, isPaused: false, imperial: false, now: now)
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(LiveTripAttributes.ContentState.self, from: data), state)
    }
}
