import Foundation
import Combine
import CoreLocation

@MainActor
final class TripRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var archive = TripArchive()
    @Published private(set) var speed: Double = 0
    @Published private(set) var lastFix: Date?
    @Published private(set) var accuracy: Double?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published var message: String?
    @Published private(set) var waitingForPermission = false
    @Published private(set) var saveFailed = false

    @Published private(set) var liveStatus: String?
    private let liveController = LiveTripController()
    private let manager = CLLocationManager()
    private let file: URL
    private var storageAvailable = true
    private var lastSave = Date.distantPast
    var isRecording: Bool { archive.active != nil }
    var isPaused: Bool { archive.active?.isPaused ?? false }

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("trajets.json")
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                archive = try JSONDecoder().decode(TripArchive.self, from: Data(contentsOf: file))
                // One-time snapshot before V2 writes; never replace this V1 backup.
                let backup = directory.appendingPathComponent("trajets-avant-v2.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: file, to: backup)
                }
            }
            if var interrupted = archive.active {
                interrupted.recover()
                archive.trips.insert(interrupted, at: 0)
                archive.active = nil
                if persist() {
                    message = "Le trajet interrompu a été récupéré dans l’historique jusqu’à la dernière sauvegarde."
                }
            }
        } catch {
            storageAvailable = false
            message = "Impossible de lire les trajets. Les données existantes sont conservées. \(error.localizedDescription)"
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
        liveController.endOrphans()
    }

    private func permissionOK() -> Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            message = "Activez le service de localisation dans les réglages de l’iPhone."
            return false
        }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            message = "Autorisez la localisation dans Réglages > Trajets."
            return false
        }
        return true
    }

    func start() {
        guard !isRecording, storageAvailable else {
            if !storageAvailable { message = "Le stockage est indisponible. Vérifiez l’espace disponible puis relancez l’app." }
            return
        }
        if manager.authorizationStatus == .notDetermined {
            waitingForPermission = true
            manager.requestWhenInUseAuthorization()
            return
        }
        guard permissionOK() else { return }
        let previous = archive
        archive.active = Trip()
        guard persist() else { archive = previous; return }
        clearFix()
        manager.startUpdatingLocation()
        beginLiveActivity()
    }

    func togglePause() {
        guard var trip = archive.active else { return }
        let wasPaused = trip.isPaused
        if wasPaused {
            guard permissionOK() else { return }
            trip.resume()
        } else {
            trip.pause()
        }
        let previous = archive
        archive.active = trip
        guard persist() else { archive = previous; return }
        clearFix()
        if wasPaused { manager.startUpdatingLocation() } else { manager.stopUpdatingLocation() }
        refreshLiveActivity(force: true)
    }

    func stop() {
        guard var trip = archive.active else { return }
        let previous = archive
        trip.finish()
        archive.trips.insert(trip, at: 0)
        archive.active = nil
        guard persist() else {
            archive = previous
            // Keep the unsaved trip in memory, paused, until the user retries saving.
            archive.active?.pause()
            manager.stopUpdatingLocation()
            clearFix()
            refreshLiveActivity(force: true)
            return
        }
        manager.stopUpdatingLocation()
        clearFix()
        liveController.end(liveState(for: trip))
        liveStatus = nil
    }

    func rename(_ id: UUID, name: String) {
        guard let index = archive.trips.firstIndex(where: { $0.id == id }) else { return }
        let previous = archive
        archive.trips[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        if !persist() { archive = previous }
    }

    func delete(_ id: UUID) {
        let previous = archive
        archive.trips.removeAll { $0.id == id }
        if !persist() { archive = previous }
    }

    func retrySave() { if storageAvailable { persist() } }
    func checkpoint() {
        if storageAvailable && isRecording { persist(); refreshLiveActivity(force: true) }
    }

    private var liveEnabled: Bool {
        (UserDefaults.standard.object(forKey: "liveActivities") as? Bool) ?? true
    }
    private func liveState(for trip: Trip) -> LiveTripAttributes.ContentState {
        .snapshot(distance: trip.distance, speed: speed, lastFix: lastFix,
                  activeSeconds: trip.duration(), isPaused: trip.isPaused,
                  isFinished: trip.endedAt != nil,
                  imperial: UserDefaults.standard.bool(forKey: "imperial"))
    }
    private func beginLiveActivity() {
        guard liveEnabled, let trip = archive.active else { return }
        do {
            try liveController.start(tripID: trip.id, state: liveState(for: trip))
            liveStatus = nil
        } catch {
            liveStatus = "Activité en direct indisponible : \(error.localizedDescription)"
        }
    }
    func setLiveActivitiesEnabled(_ enabled: Bool) {
        if enabled { beginLiveActivity() }
        else { liveController.end(); liveStatus = nil }
    }
    func refreshLiveActivity(force: Bool = false) {
        guard liveEnabled, let trip = archive.active else { return }
        liveController.update(liveState(for: trip), force: force)
    }

    private func clearFix() { speed = 0; lastFix = nil; accuracy = nil }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastSave = Date()
            saveFailed = false
            return true
        } catch {
            if !saveFailed { message = "La sauvegarde a échoué. Libérez de l’espace puis utilisez Réessayer. Gardez l’application ouverte. \(error.localizedDescription)" }
            saveFailed = true
            return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if waitingForPermission, authorization != .notDetermined {
            waitingForPermission = false
            start()
        } else if isRecording && (authorization == .denied || authorization == .restricted) {
            stop()
            message = saveFailed ? "Localisation retirée. Le trajet attend une sauvegarde : libérez de l’espace puis réessayez." :
                "Le trajet a été arrêté car l’accès à la localisation a été retiré."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard var trip = archive.active, !trip.isPaused else { return }
        var changed = false
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let before = trip.lastObservedAt
            if trip.append(location) { changed = true }
            if trip.lastObservedAt != before {
                speed = location.speed >= 0 && location.speed < 100 ? location.speed : 0
                lastFix = location.timestamp
                accuracy = location.horizontalAccuracy
            }
        }
        archive.active = trip
        // Moving points are durable immediately; stationary checkpoints every 5 seconds.
        if changed || Date().timeIntervalSince(lastSave) >= 5 { persist() }
        refreshLiveActivity()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown { return }
        message = "GPS indisponible : \(error.localizedDescription)"
    }
}
