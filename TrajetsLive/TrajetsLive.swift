import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrajetsLiveBundle: WidgetBundle {
    var body: some Widget { TrajetsLiveActivity() }
}

struct TrajetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveTripAttributes.self) { context in
            LockScreenTrip(context: context)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.mint)
                .widgetURL(URL(string: "trajets://current"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Trajets", systemImage: context.state.isPaused ? "pause.fill" : "location.fill")
                        .font(.headline).foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        LivePrimary(state: context.state, stale: context.isStale)
                            .font(.title2.monospacedDigit().bold())
                        Text(context.state.metric.unit(imperial: context.state.imperial)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(context.state.distanceText) \(context.state.distanceUnit)").font(.headline.monospacedDigit())
                            Text(status(context)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        LiveTimer(state: context.state, stale: context.isStale)
                            .font(.headline.monospacedDigit()).frame(maxWidth: 115, alignment: .trailing)
                    }.padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "location.fill").foregroundStyle(.mint)
            } compactTrailing: {
                LivePrimary(state: context.state, stale: context.isStale)
                    .font(.caption.monospacedDigit().bold())
                    .frame(maxWidth: context.state.metric == .duration ? 64 : 48)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel(context.state.metric.title)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "location.fill").foregroundStyle(.mint)
            }
            .widgetURL(URL(string: "trajets://current"))
            .keylineTint(.mint)
        }
    }
}

private func status(_ context: ActivityViewContext<LiveTripAttributes>) -> String {
    if context.state.isFinished { return "Trajet terminé" }
    if context.state.isPaused { return "En pause" }
    if context.isStale { return "Actualisation en attente" }
    return context.state.speed == nil ? "Recherche GPS" : "Enregistrement"
}

struct LiveTimer: View {
    let state: LiveTripAttributes.ContentState
    let stale: Bool
    var body: some View {
        if let start = state.timerStart, !stale {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(state.elapsedText)
        }
    }
}

struct LockScreenTrip: View {
    let context: ActivityViewContext<LiveTripAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trajets", systemImage: "location.fill").font(.headline).foregroundStyle(.mint)
                Spacer()
                Text(status(context)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    LivePrimary(state: context.state, stale: context.isStale).font(.title.monospacedDigit().bold())
                    Text(context.state.metric.unit(imperial: context.state.imperial)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(context.state.distanceText) \(context.state.distanceUnit)").font(.headline.monospacedDigit())
                    LiveTimer(state: context.state, stale: context.isStale)
                        .font(.subheadline.monospacedDigit()).frame(maxWidth: 130, alignment: .trailing)
                }
            }
            Text("Touchez pour ouvrir les commandes").font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
    }
}

struct LivePrimary: View {
    let state: LiveTripAttributes.ContentState
    let stale: Bool
    var body: some View {
        if state.metric == .duration {
            LiveTimer(state: state, stale: stale)
        } else {
            Text(stale ? "—" : state.primaryText)
        }
    }
}
