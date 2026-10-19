import ActivityKit
import Foundation

@MainActor
final class LiveTripController {
    private var activity: Activity<LiveTripAttributes>?
    private var operation: Task<Void, Never>?
    private var lastUpdate = Date.distantPast

    // ActivityKit operations are ordered so a delayed update cannot follow an end.
    private func enqueue(_ action: @escaping @Sendable () async -> Void) {
        let previous = operation
        operation = Task {
            await previous?.value
            await action()
        }
    }

    func endOrphans() {
        let old = Activity<LiveTripAttributes>.activities
        enqueue {
            for activity in old { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start(tripID: UUID, state: LiveTripAttributes.ContentState) throws {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveError.disabled }
        activity = try Activity.request(
            attributes: LiveTripAttributes(tripID: tripID),
            content: content(state),
            pushType: nil
        )
        lastUpdate = Date()
    }

    func update(_ state: LiveTripAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }
        guard force || Date().timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = Date()
        let content = content(state)
        enqueue { await activity.update(content) }
    }

    func end(_ state: LiveTripAttributes.ContentState? = nil) {
        guard let activity else { return }
        self.activity = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        enqueue { await activity.end(content, dismissalPolicy: .immediate) }
    }

    private func content(_ state: LiveTripAttributes.ContentState) -> ActivityContent<LiveTripAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.isPaused || state.isFinished ? nil : Date().addingTimeInterval(15))
    }

    enum LiveError: LocalizedError {
        case disabled
        var errorDescription: String? {
            "Autorisez les activités en direct dans Réglages > Trajets."
        }
    }
}
