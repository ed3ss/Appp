import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @Environment(\.scenePhase) private var phase
    @AppStorage("keepScreenOn") private var keepScreenOn = false

    var body: some View {
        TabView {
            Dashboard().tabItem { Label("Trajet", systemImage: "speedometer") }
            HistoryView().tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .onChange(of: keepScreenOn) { _, _ in updateScreen() }
        .onChange(of: recorder.isRecording) { _, _ in updateScreen() }
        .onChange(of: recorder.isPaused) { _, _ in updateScreen() }
        .onChange(of: phase) { _, newPhase in
            updateScreen()
            if newPhase == .background { recorder.checkpoint() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("Trajets", isPresented: Binding(
            get: { recorder.message != nil },
            set: { if !$0 { recorder.message = nil } }
        )) {
            Button("OK", role: .cancel) { recorder.message = nil }
        } message: { Text(recorder.message ?? "") }
    }
    private func updateScreen() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && recorder.isRecording && !recorder.isPaused && phase == .active
    }
}

struct Dashboard: View {
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("imperial") private var imperial = false
    @State private var confirmStop = false
    @State private var fullMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(recorder.isPaused ? "TRAJET EN PAUSE" : recorder.isRecording ? "ENREGISTREMENT EN COURS" : "PRÊT POUR LE DÉPART",
                          systemImage: recorder.isPaused ? "pause.circle" : recorder.isRecording ? "record.circle" : "location")
                        .font(.caption.weight(.semibold)).foregroundStyle(recorder.isPaused ? .orange : .mint)
                    if recorder.saveFailed {
                        Button("Sauvegarde en attente · Réessayer") { recorder.retrySave() }
                            .foregroundStyle(.orange).buttonStyle(.bordered)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let fresh = recorder.lastFix.map { context.date.timeIntervalSince($0) < 10 } ?? false
                        VStack(spacing: 4) {
                            Text(fresh && !recorder.isPaused ? Display.speed(recorder.speed, imperial: imperial) : "—")
                                .font(.system(size: 76, weight: .light, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.5).lineLimit(1)
                                .accessibilityLabel("Vitesse")
                            Text(imperial ? "mph" : "km/h").foregroundStyle(.secondary)
                            if recorder.isRecording && !recorder.isPaused {
                                Text(fresh ? "GPS · précision ±\(Int(recorder.accuracy ?? 0)) m" : "Recherche du signal GPS…")
                                    .font(.caption).foregroundStyle(fresh ? .mint : .orange)
                            }
                        }.frame(maxWidth: .infinity)
                        HStack {
                            Metric(title: "DISTANCE", value: Display.distance(recorder.archive.active?.distance ?? 0, imperial: imperial), unit: imperial ? "mi" : "km")
                            Metric(title: "DURÉE ACTIVE", value: Display.time(recorder.archive.active?.duration(at: context.date) ?? 0), unit: "")
                        }
                    }
                    RouteMap(trip: recorder.archive.active, showUser: recorder.isRecording && !recorder.isPaused)
                        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(alignment: .bottomTrailing) {
                            Button { fullMap = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(12) }
                                .background(.regularMaterial, in: Circle()).padding(12)
                                .accessibilityLabel("Carte plein écran")
                        }
                    if let trip = recorder.archive.active {
                        HStack {
                            Metric(title: "MOYENNE", value: Display.speed(trip.averageSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                            Metric(title: "MAXIMUM", value: Display.speed(trip.maxSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                        }
                    }
                    Text(recorder.isPaused ? "La pause exclut le temps et les déplacements. Reprenez avant de continuer." :
                         "Vos trajets restent sur cet iPhone. Le GPS continue écran verrouillé pendant un enregistrement. Ne forcez pas la fermeture de l’app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Trajets")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    if recorder.isRecording {
                        Button { recorder.togglePause() } label: {
                            Label(recorder.isPaused ? "Reprendre" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.bordered)
                    }
                    Button {
                        if recorder.isRecording { confirmStop = true } else { recorder.start() }
                    } label: {
                        Label(recorder.isRecording ? "Terminer" : "Démarrer le trajet", systemImage: recorder.isRecording ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                        .disabled(recorder.waitingForPermission)
                }.font(.headline).padding().background(.regularMaterial)
            }
            .confirmationDialog("Terminer et enregistrer ce trajet ?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Enregistrer le trajet") { recorder.stop() }
                Button("Continuer", role: .cancel) {}
            }
            .sheet(isPresented: $fullMap) {
                NavigationStack {
                    RouteMap(trip: recorder.archive.active, showUser: recorder.isRecording && !recorder.isPaused)
                        .navigationTitle("Votre parcours").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Fermer") { fullMap = false } }
                }
            }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().weight(.semibold)).minimumScaleFactor(0.5).lineLimit(1)
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct RouteMap: View {
    let trip: Trip?
    var showUser = false
    @State private var position: MapCameraPosition = .automatic
    @State private var satellite = false

    var body: some View {
        Map(position: $position) {
            if showUser { UserAnnotation() }
            if let trip {
                ForEach(Array(trip.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate)).stroke(.mint, lineWidth: 5)
                }
                if let first = trip.points.first {
                    Marker("Départ", systemImage: "flag.fill", coordinate: first.coordinate).tint(.green)
                }
                if trip.endedAt != nil, let last = trip.points.last {
                    Marker("Arrivée", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.orange)
                }
            }
        }
        .mapStyle(satellite ? .hybrid : .standard(elevation: .flat))
        .mapControls { MapCompass(); MapScaleView() }
        .onAppear { if showUser { position = .userLocation(followsHeading: false, fallback: .automatic) } }
        .onChange(of: showUser) { _, value in position = value ? .userLocation(followsHeading: false, fallback: .automatic) : .automatic }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Button { position = showUser ? .userLocation(followsHeading: false, fallback: .automatic) : .automatic } label: {
                    Image(systemName: showUser ? "location.fill" : "arrow.up.left.and.arrow.down.right")
                }.accessibilityLabel(showUser ? "Suivre ma position" : "Voir tout le parcours")
                Button { satellite.toggle() } label: { Image(systemName: satellite ? "map" : "globe.europe.africa.fill") }
                    .accessibilityLabel(satellite ? "Carte standard" : "Carte satellite")
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            if (trip?.points.isEmpty ?? true) && !showUser {
                Text("Votre parcours apparaîtra ici").font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule()).padding(12)
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("imperial") private var imperial = false
    @State private var pendingDelete: Trip?
    @State private var query = ""
    @State private var weekOnly = false

    private var trips: [Trip] {
        recorder.archive.trips.filter { trip in
            let inWeek = Calendar.current.isDate(trip.startedAt, equalTo: Date(), toGranularity: .weekOfYear)
            return (!weekOnly || inWeek) && (query.isEmpty || trip.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Période", selection: $weekOnly) {
                        Text("Tout").tag(false)
                        Text("Cette semaine").tag(true)
                    }.pickerStyle(.segmented)
                    HStack {
                        Metric(title: "\(trips.count) TRAJETS", value: Display.distance(trips.reduce(0) { $0 + $1.distance }, imperial: imperial), unit: imperial ? "mi au total" : "km au total")
                        Metric(title: "TEMPS ACTIF", value: Display.time(trips.reduce(0) { $0 + $1.duration() }), unit: "")
                    }.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if trips.isEmpty {
                    ContentUnavailableView("Aucun trajet", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                           description: Text(recorder.archive.trips.isEmpty ? "Démarrez votre premier enregistrement." : "Essayez une autre recherche ou période."))
                }
                ForEach(trips) { trip in
                    NavigationLink { TripDetail(id: trip.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.title).font(.headline)
                            if trip.name?.isEmpty == false {
                                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(Display.distance(trip.distance, imperial: imperial)) \(imperial ? "mi" : "km") · \(Display.time(trip.duration()))")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = trip } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Historique")
            .searchable(text: $query, prompt: "Nom ou date du trajet")
            .confirmationDialog("Supprimer définitivement ce trajet ?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
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

struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct TripDetail: View {
    let id: UUID
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("imperial") private var imperial = false
    @State private var editing = false
    @State private var draftName = ""
    @State private var shareFile: ShareFile?
    @State private var fullMap = false
    private var trip: Trip? { recorder.archive.trips.first { $0.id == id } }

    var body: some View {
        Group {
            if let trip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(trip.title).font(.title2.bold())
                        Text(trip.startedAt.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                        RouteMap(trip: trip).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                        Button("Ouvrir la carte en plein écran", systemImage: "arrow.up.left.and.arrow.down.right") { fullMap = true }
                        HStack {
                            Metric(title: "DISTANCE", value: Display.distance(trip.distance, imperial: imperial), unit: imperial ? "mi" : "km")
                            Metric(title: "DURÉE ACTIVE", value: Display.time(trip.duration()), unit: "")
                        }
                        HStack {
                            Metric(title: "MOYENNE", value: Display.speed(trip.averageSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                            Metric(title: "MAXIMUM", value: Display.speed(trip.maxSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                        }
                        if (trip.pausedSeconds ?? 0) > 0 {
                            Text("Temps en pause : \(Display.time(trip.pausedSeconds ?? 0))").foregroundStyle(.secondary)
                        }
                        Button("Exporter le parcours GPX", systemImage: "square.and.arrow.up") { export(trip) }
                            .buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(trip.points.isEmpty)
                        Text(trip.points.isEmpty ? "Aucune position GPS enregistrée." : "Le fichier GPX contient les positions et horaires du parcours.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding()
                }
                .toolbar {
                    Button("Renommer", systemImage: "pencil") { draftName = trip.name ?? ""; editing = true }
                }
                .sheet(isPresented: $fullMap) {
                    NavigationStack {
                        RouteMap(trip: trip).navigationTitle("Parcours").navigationBarTitleDisplayMode(.inline)
                            .toolbar { Button("Fermer") { fullMap = false } }
                    }
                }
            } else { ContentUnavailableView("Trajet indisponible", systemImage: "map") }
        }
        .navigationTitle("Parcours").navigationBarTitleDisplayMode(.inline)
        .alert("Nom du trajet", isPresented: $editing) {
            TextField("Ex. Balade du dimanche", text: $draftName)
            Button("Enregistrer") { recorder.rename(id, name: draftName) }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Laissez vide pour utiliser la date.") }
        .sheet(item: $shareFile) { file in ShareSheet(url: file.url) }
    }

    private func export(_ trip: Trip) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Trajet-\(trip.id.uuidString).gpx")
            try GPX.document(for: trip).write(to: url, atomically: true, encoding: .utf8)
            shareFile = ShareFile(url: url)
        } catch { recorder.message = "Export impossible : \(error.localizedDescription)" }
    }
}

struct SettingsView: View {
    @AppStorage("imperial") private var imperial = false
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Affichage") {
                    Toggle("Utiliser les miles et mph", isOn: $imperial)
                    Toggle("Garder l’écran allumé", isOn: $keepScreenOn)
                    Text("L’écran reste allumé uniquement pendant un enregistrement actif. Cette option consomme davantage de batterie.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Localisation") {
                    Button("Ouvrir les réglages de l’iPhone", systemImage: "location") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("Activez Position exacte. Le GPS fonctionne sans Internet ; le chargement des cartes peut nécessiter une connexion. La pause suspend le GPS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Vos données") {
                    Text("Trajets conserve vos parcours sur l’iPhone. Vous pouvez exporter chaque parcours en GPX depuis son détail. Les sauvegardes système peuvent inclure vos trajets.")
                    Text("Pour une mise à jour, réinstallez l’IPA avec le même compte AltStore sans supprimer l’app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Trajets", value: "2.0")
                    Text("Durée et vitesse moyenne excluent les pauses manuelles. Les arrêts sans pause restent inclus.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Réglages")
        }
    }
}
