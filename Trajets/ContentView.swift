import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject private var recorder: TripRecorder

    var body: some View {
        TabView {
            Dashboard()
                .tabItem { Label("Trajet", systemImage: "speedometer") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
        }
        .alert("Trajets", isPresented: Binding(
            get: { recorder.message != nil },
            set: { if !$0 { recorder.message = nil } }
        )) {
            Button("OK", role: .cancel) { recorder.message = nil }
        } message: {
            Text(recorder.message ?? "")
        }
    }
}

struct Dashboard: View {
    @EnvironmentObject private var recorder: TripRecorder
    @State private var confirmStop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(recorder.isRecording ? "ENREGISTREMENT EN COURS" : "PRÊT POUR LE DÉPART",
                          systemImage: recorder.isRecording ? "record.circle" : "location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let fresh = recorder.lastFix.map { context.date.timeIntervalSince($0) < 10 } ?? false
                        VStack(spacing: 4) {
                            Text(fresh && recorder.isRecording ? Display.speed(recorder.speed) : "—")
                                .font(.system(size: 88, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .accessibilityLabel("Vitesse en kilomètres par heure")
                            Text("km/h").foregroundStyle(.secondary)
                            if recorder.isRecording && !fresh {
                                Text("Recherche du signal GPS…").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        HStack {
                            Metric(title: "DISTANCE", value: Display.distance(recorder.archive.active?.distance ?? 0), unit: "km")
                            Metric(title: "DURÉE", value: Display.time(recorder.archive.active?.duration(at: context.date) ?? 0), unit: "")
                        }
                    }
                    RouteMap(trip: recorder.archive.active, showUser: recorder.isRecording)
                        .frame(height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    Button {
                        if recorder.isRecording { confirmStop = true } else { recorder.start() }
                    } label: {
                        Label(recorder.isRecording ? "Terminer le trajet" : "Démarrer le trajet",
                              systemImage: recorder.isRecording ? "stop.fill" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
                    .disabled(recorder.waitingForPermission)
                    Text("Les trajets restent sur cet iPhone. Pendant un trajet, la localisation continue lorsque l’écran est verrouillé. Ne forcez pas la fermeture de l’app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Trajets")
            .confirmationDialog("Terminer et enregistrer ce trajet ?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Enregistrer le trajet") { recorder.stop() }
                Button("Continuer", role: .cancel) {}
            }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().weight(.semibold)).minimumScaleFactor(0.65).lineLimit(1)
            Text(unit.isEmpty ? " " : unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct RouteMap: View {
    let trip: Trip?
    var showUser = false

    var body: some View {
        Map {
            if showUser { UserAnnotation() }
            if let trip {
                ForEach(Array(trip.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(.mint, lineWidth: 5)
                }
                if let first = trip.points.first {
                    Marker("Départ", systemImage: "flag.fill", coordinate: first.coordinate).tint(.green)
                }
                if trip.endedAt != nil, let last = trip.points.last {
                    Marker("Arrivée", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.orange)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls { MapCompass(); MapUserLocationButton() }
        .overlay(alignment: .bottomLeading) {
            if (trip?.points.isEmpty ?? true) && !showUser {
                Text("Votre parcours apparaîtra ici")
                    .font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @State private var pendingDelete: Trip?

    var body: some View {
        NavigationStack {
            Group {
                if recorder.archive.trips.isEmpty {
                    ContentUnavailableView("Votre premier trajet vous attend", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                           description: Text("Démarrez un enregistrement pour retrouver ici votre parcours et vos statistiques."))
                } else {
                    List {
                        ForEach(recorder.archive.trips) { trip in
                            NavigationLink {
                                TripDetail(trip: trip)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                    Text("\(Display.distance(trip.distance)) km · \(Display.time(trip.duration()))")
                                        .foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                            .swipeActions {
                                Button(role: .destructive) { pendingDelete = trip } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .confirmationDialog("Supprimer définitivement ce trajet ?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let trip = pendingDelete { recorder.delete(trip.id) }
                    pendingDelete = nil
                }
                Button("Annuler", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}

struct TripDetail: View {
    let trip: Trip
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(trip.startedAt.formatted(date: .long, time: .shortened))
                    .font(.headline)
                RouteMap(trip: trip)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                HStack {
                    Metric(title: "DISTANCE", value: Display.distance(trip.distance), unit: "km")
                    Metric(title: "DURÉE", value: Display.time(trip.duration()), unit: "")
                }
                HStack {
                    Metric(title: "MOYENNE", value: Display.speed(trip.averageSpeed), unit: "km/h")
                    Metric(title: "MAXIMUM", value: Display.speed(trip.maxSpeed), unit: "km/h")
                }
                if trip.points.isEmpty {
                    Text("Aucune position GPS n’a été reçue pendant ce trajet.").foregroundStyle(.secondary)
                }
            }.padding()
        }
        .navigationTitle("Parcours")
        .navigationBarTitleDisplayMode(.inline)
    }
}
