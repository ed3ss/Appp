import Foundation
import CoreLocation

enum TripCategory: String, CaseIterable, Identifiable {
    case other, car, bicycle, walking
    var id: String { rawValue }
    var title: String {
        switch self { case .other: "Autre"; case .car: "Voiture"; case .bicycle: "Vélo"; case .walking: "Marche" }
    }
    var icon: String {
        switch self { case .other: "location"; case .car: "car.fill"; case .bicycle: "bicycle"; case .walking: "figure.walk" }
    }
}

extension Trip {
    var activity: TripCategory { TripCategory(rawValue: category ?? "") ?? .other }
    var movingDuration: Double {
        if let movingSeconds { return min(max(0, movingSeconds), duration()) }
        // Older archives only contain retained GPS points: this is an estimate.
        return min(duration(), segments.reduce(0) { sum, segment in
            sum + zip(segment, segment.dropFirst()).reduce(0) { value, pair in
                let dt = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
                return value + (dt > 0 && dt < 30 && pair.0.speed > 0.8 && pair.1.speed > 0.8 ? dt : 0)
            }
        })
    }
    var stoppedDuration: Double { max(0, duration() - movingDuration) }
    var movingAverage: Double { movingDuration > 0 ? distance / movingDuration : 0 }
    var chartPoints: [TrackPoint] {
        let step = max(1, Int(ceil(Double(points.count) / 600)))
        return points.enumerated().compactMap { index, point in
            index % step == 0 || index == points.count - 1 ? point : nil
        }
    }
    func pointIndex(nearest date: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < date { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return 0 }
        if low == points.count { return points.count - 1 }
        return abs(points[low].timestamp.timeIntervalSince(date)) <
            abs(points[low - 1].timestamp.timeIntervalSince(date)) ? low : low - 1
    }
}

/// Hysteresis avoids alternating between pause and resume in GPS noise.
/// No decision is made from a stale, inaccurate, unordered or unknown-speed fix.
struct AutoPauseDetector {
    enum Decision: Equatable { case pause, resume }
    private var candidateSince: Date?
    private var lastDate: Date?
    mutating func reset() { candidateSince = nil; lastDate = nil }
    mutating func observe(_ fix: CLLocation, autoPaused: Bool, now: Date) -> Decision? {
        guard CLLocationCoordinate2DIsValid(fix.coordinate),
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 25,
              fix.speed >= 0, fix.speed < 100,
              now.timeIntervalSince(fix.timestamp) >= 0,
              now.timeIntervalSince(fix.timestamp) < 10 else { reset(); return nil }
        if let lastDate {
            guard fix.timestamp > lastDate else { return nil }
            if fix.timestamp.timeIntervalSince(lastDate) > 10 { candidateSince = nil }
        }
        lastDate = fix.timestamp
        let matches = autoPaused ? fix.speed >= 1.2 : fix.speed <= 0.5
        guard matches else { candidateSince = nil; return nil }
        if candidateSince == nil { candidateSince = fix.timestamp }
        guard fix.timestamp.timeIntervalSince(candidateSince!) >= (autoPaused ? 3 : 15) else { return nil }
        candidateSince = nil
        return autoPaused ? .resume : .pause
    }
}

struct PeriodTotal: Identifiable {
    let start: Date
    let distance: Double
    let duration: Double
    let count: Int
    var id: Date { start }
}

enum TripStatistics {
    static func totals(_ trips: [Trip], monthly: Bool, now: Date = Date(),
                       calendar: Calendar = .current) -> [PeriodTotal] {
        let component: Calendar.Component = monthly ? .month : .weekOfYear
        guard let current = calendar.dateInterval(of: component, for: now)?.start else { return [] }
        return (0..<(monthly ? 6 : 8)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: component, value: -offset, to: current),
                  let end = calendar.date(byAdding: component, value: 1, to: start) else { return nil }
            let matches = trips.filter { $0.startedAt >= start && $0.startedAt < end }
            return PeriodTotal(start: start, distance: matches.reduce(0) { $0 + $1.distance },
                               duration: matches.reduce(0) { $0 + $1.duration() }, count: matches.count)
        }
    }
}

struct TripBackup: Codable {
    var format = "Trajets"
    var version = 1
    var createdAt = Date()
    var archive: TripArchive
}

enum BackupError: LocalizedError {
    case invalid, tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .invalid: "Ce fichier ne contient pas une sauvegarde Trajets valide. Aucun trajet n’a été modifié."
        case .tooLarge: "Cette sauvegarde dépasse la limite d’import (30 Mo, 10 000 trajets ou 500 000 positions)."
        case .unsupported: "Cette sauvegarde utilise un format plus récent que cette version de Trajets."
        }
    }
}

enum BackupStore {
    static let maximumBytes = 30 * 1024 * 1024
    static func decode(_ data: Data) throws -> TripArchive {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        var archive: TripArchive
        if let backup = try? JSONDecoder().decode(TripBackup.self, from: data) {
            guard backup.format == "Trajets", backup.version == 1 else { throw BackupError.unsupported }
            archive = backup.archive
        } else {
            // Also accept original on-device V1/V2 archives.
            guard let old = try? JSONDecoder().decode(TripArchive.self, from: data) else { throw BackupError.invalid }
            archive = old
        }
        if var active = archive.active {
            active.recover()
            archive.trips.append(active)
            archive.active = nil
        }
        guard archive.trips.count <= 10_000,
              archive.trips.reduce(0, { $0 + $1.points.count }) <= 500_000 else { throw BackupError.tooLarge }
        var ids = Set<UUID>()
        for trip in archive.trips {
            guard ids.insert(trip.id).inserted, valid(trip) else { throw BackupError.invalid }
        }
        return archive
    }
    private static func valid(_ trip: Trip) -> Bool {
        guard let end = trip.endedAt,
              trip.startedAt.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end >= trip.startedAt,
              trip.startedAt.timeIntervalSince1970 >= -2_208_988_800,
              end.timeIntervalSince1970 <= 7_258_118_400,
              end.timeIntervalSince(trip.startedAt) <= 315_576_000,
              trip.distance.isFinite, trip.distance >= 0,
              trip.distance <= 10_000_000_000,
              trip.maxSpeed.isFinite, (0...100).contains(trip.maxSpeed),
              (trip.pausedSeconds ?? 0).isFinite,
              (trip.pausedSeconds ?? 0) >= 0,
              (trip.pausedSeconds ?? 0) <= end.timeIntervalSince(trip.startedAt),
              (trip.movingSeconds ?? 0).isFinite, (trip.movingSeconds ?? 0) >= 0,
              trip.pausedAt == nil,
              (trip.name?.count ?? 0) <= 1000 else { return false }
        var last: Date?
        var ids = Set<UUID>()
        for point in trip.points {
            guard ids.insert(point.id).inserted,
                  point.latitude.isFinite, point.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(point.coordinate),
                  point.timestamp.timeIntervalSince1970.isFinite,
                  point.timestamp >= trip.startedAt, point.timestamp <= end,
                  last.map({ point.timestamp > $0 }) ?? true,
                  point.speed.isFinite, (0...100).contains(point.speed),
                  point.accuracy.isFinite, (0...50).contains(point.accuracy) else { return false }
            last = point.timestamp
        }
        return true
    }
    static func merging(_ incoming: TripArchive, into current: TripArchive) -> (archive: TripArchive, added: Int) {
        var result = current
        var ids = Set(current.trips.map(\.id))
        if let active = current.active { ids.insert(active.id) }
        let additions = incoming.trips.filter { ids.insert($0.id).inserted }
        result.trips.append(contentsOf: additions)
        result.trips.sort { $0.startedAt > $1.startedAt }
        return (result, additions.count)
    }
    static func encode(_ archive: TripArchive) throws -> Data {
        // Snapshot a running trip as completed at export time without changing the recording.
        var snapshot = archive
        if var active = snapshot.active {
            active.finish()
            snapshot.trips.insert(active, at: 0)
            snapshot.active = nil
        }
        let data = try JSONEncoder().encode(TripBackup(archive: snapshot))
        _ = try decode(data) // Never create a backup this version cannot restore.
        return data
    }
}
