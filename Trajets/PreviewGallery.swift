#if DEBUG
import SwiftUI
import CoreLocation

enum PreviewGallery {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-gallery"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var trip: Trip {
        let start = Date(timeIntervalSince1970: 1_792_411_200)
        var trip = Trip(id: UUID(uuidString: "F9E774E3-B5E3-4936-8B71-E869911C95CB")!, startedAt: start)
        for index in 0..<180 {
            let angle = Double(index) / 179 * .pi * 1.8
            let location = CLLocation(coordinate: .init(latitude: 48.855 + sin(angle) * 0.008,
                                                       longitude: 2.335 + cos(angle) * 0.013),
                                      altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                      course: 0, speed: 4 + 2 * sin(angle * 3),
                                      timestamp: start.addingTimeInterval(Double(index) * 5))
            _ = trip.append(location, now: location.timestamp)
        }
        trip.finish(at: start.addingTimeInterval(900))
        trip.name = "Boucle des quais"
        trip.category = "bicycle"
        trip.favorite = true
        return trip
    }
}

struct PreviewGalleryView: View {
    let screen: String
    @ViewBuilder var body: some View {
        switch screen {
        case "history": HistoryView()
        case "detail": NavigationStack { TripDetail(id: PreviewGallery.trip.id) }
        case "replay": NavigationStack { ReplayView(trip: PreviewGallery.trip) }
        case "share": NavigationStack { ShareTripView(trip: PreviewGallery.trip) }
        case "statistics": NavigationStack { StatisticsView(trips: [PreviewGallery.trip]) }
        case "backup": NavigationStack { BackupView() }
        default: NavigationStack { DisplaySettings() }
        }
    }
}
#endif
