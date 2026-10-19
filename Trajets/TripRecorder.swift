import Foundation
import Combine
import CoreLocation

@MainActor
final class TripRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var archive = TripArchive()
    @Published private(set) var speed: Double = 0
    @Published private(set) var lastFix: Date?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published var message: String?
    @Published private(set) var waitingForPermission = false

    private let manager = CLLocationManager()
    private let file: URL
    private var storageAvailable = true
    var isRecording: Bool { archive.active != nil }

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("trajets.json")
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                archive = try JSONDecoder().decode(TripArchive.self, from: Data(contentsOf: file))
            }
            if var interrupted = archive.active {
                interrupted.endedAt = interrupted.points.last?.timestamp ?? interrupted.startedAt
                archive.trips.insert(interrupted, at: 0)
                archive.active = nil
                persist()
                message = "Le trajet interrompu a été récupéré dans l’historique. Démarrez un nouveau trajet pour reprendre."
            }
        } catch {
            storageAvailable = false
            message = "Impossible de lire les trajets. Les données existantes sont conservées. \(error.localizedDescription)"
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    func start() {
        guard !isRecording, storageAvailable else {
            if !storageAvailable { message = "Le stockage est indisponible. Relancez l’application après avoir vérifié l’espace disponible." }
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            message = "Activez le service de localisation dans les réglages de l’iPhone."
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            waitingForPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            archive.active = Trip()
            speed = 0
            lastFix = nil
            guard persist() else {
                archive.active = nil
                return
            }
            manager.startUpdatingLocation()
        default:
            message = "Autorisez la localisation dans Réglages > Trajets pour enregistrer un trajet."
        }
    }

    func stop() {
        guard var trip = archive.active else { return }
        manager.stopUpdatingLocation()
        trip.endedAt = Date()
        archive.trips.insert(trip, at: 0)
        archive.active = nil
        speed = 0
        persist()
    }

    func delete(_ id: UUID) {
        let previous = archive
        archive.trips.removeAll { $0.id == id }
        if !persist() { archive = previous }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            message = "La sauvegarde a échoué. Libérez de l’espace et gardez l’application ouverte. \(error.localizedDescription)"
            return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if waitingForPermission, authorization != .notDetermined {
            waitingForPermission = false
            start()
        } else if isRecording,
                  authorization == .denied || authorization == .restricted {
            stop()
            message = "Le trajet a été arrêté car l’accès à la localisation a été retiré."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard var trip = archive.active else { return }
        var changed = false
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            if location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
               abs(location.timestamp.timeIntervalSinceNow) < 15 {
                speed = location.speed >= 0 && location.speed < 100 ? location.speed : 0
                lastFix = location.timestamp
            }
            if trip.append(location) { changed = true }
        }
        if changed {
            archive.active = trip
            persist()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown { return }
        message = "GPS indisponible : \(error.localizedDescription)"
    }
}
