import Foundation

enum DashboardMetric: String, CaseIterable, Identifiable {
    case speed, distance, duration, average
    var id: String { rawValue }
    var title: String {
        switch self { case .speed: "Vitesse"; case .distance: "Distance"; case .duration: "Durée active"; case .average: "Moyenne" }
    }
    func unit(imperial: Bool) -> String {
        switch self { case .speed, .average: imperial ? "mph" : "km/h"; case .distance: imperial ? "mi" : "km"; case .duration: "" }
    }
}
