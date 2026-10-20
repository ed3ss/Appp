import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @Environment(\.scenePhase) private var phase
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("imperial") private var imperial = false
    @State private var selectedTab = 0
    @AppStorage("islandMetric") private var islandMetric = "speed"

    var body: some View {
        TabView(selection: $selectedTab) {
            Dashboard().tabItem { Label("Trajet", systemImage: "speedometer") }.tag(0)
            HistoryView().tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }.tag(1)
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }.tag(2)
        }
        .onOpenURL { url in
            if url.scheme == "trajets" && url.host == "current" { selectedTab = 0 }
        }
        .onChange(of: islandMetric) { _, _ in recorder.refreshLiveActivity(force: true) }
        .onChange(of: imperial) { _, _ in recorder.refreshLiveActivity(force: true) }
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
    @AppStorage("mainMetric") private var mainMetric = "speed"
    @AppStorage("leftMetric") private var leftMetric = "distance"
    @AppStorage("rightMetric") private var rightMetric = "duration"
    @State private var confirmStop = false
    @State private var fullMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(recorder.isPaused ? (recorder.archive.active?.autoPaused == true ? "PAUSE AUTOMATIQUE" : "TRAJET EN PAUSE") : recorder.isRecording ? "ENREGISTREMENT EN COURS" : "PRÊT POUR LE DÉPART",
                          systemImage: recorder.isPaused ? "pause.circle" : recorder.isRecording ? "record.circle" : "location")
                        .font(.caption.weight(.semibold)).foregroundStyle(recorder.isPaused ? .orange : .mint)
                    if let status = recorder.liveStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    if recorder.saveFailed {
                        Button("Sauvegarde en attente · Réessayer") { recorder.retrySave() }
                            .foregroundStyle(.orange).buttonStyle(.bordered)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let fresh = recorder.lastFix.map { context.date.timeIntervalSince($0) < 10 } ?? false
                        VStack(spacing: 4) {
                            Text(metricValue(mainMetric, at: context.date, fresh: fresh))
                                .font(.system(size: 76, weight: .light, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.5).lineLimit(1)
                                .accessibilityLabel((DashboardMetric(rawValue: mainMetric) ?? .speed).title)
                            Text("\((DashboardMetric(rawValue: mainMetric) ?? .speed).title) · \((DashboardMetric(rawValue: mainMetric) ?? .speed).unit(imperial: imperial))").foregroundStyle(.secondary)
                            if recorder.isRecording && !recorder.isPaused {
                                Text(fresh ? "GPS · précision ±\(Int(recorder.accuracy ?? 0)) m" : "Recherche du signal GPS…")
                                    .font(.caption).foregroundStyle(fresh ? .mint : .orange)
                            }
                        }.frame(maxWidth: .infinity)
                        HStack {
                            dashboardMetric(leftMetric, at: context.date, fresh: fresh)
                            dashboardMetric(rightMetric, at: context.date, fresh: fresh)
                        }
                    }
                    RouteMap(trip: recorder.archive.active, showUser: recorder.isRecording && !recorder.isPaused)
                        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(alignment: .bottomTrailing) {
                            Button { fullMap = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(12) }
                                .trajetGlass(radius: 28, interactive: true).padding(12)
                                .accessibilityLabel("Carte plein écran")
                        }
                    if let trip = recorder.archive.active {
                        HStack {
                            Metric(title: "MOYENNE", value: Display.speed(trip.averageSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                            Metric(title: "MAXIMUM", value: Display.speed(trip.maxSpeed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                        }
                    }
                    Text(recorder.isPaused ? (recorder.archive.active?.autoPaused == true ? "Reprise automatique dès que vous repartez. Le GPS reste actif pour détecter le mouvement." : "La pause exclut le temps et les déplacements. Reprenez avant de continuer.") :
                         "Vos trajets restent sur cet iPhone. Le GPS continue écran verrouillé pendant un enregistrement. Ne forcez pas la fermeture de l’app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .background(TrajetBackdrop())
            .navigationTitle("Trajets")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    if recorder.isRecording {
                        Button { recorder.togglePause() } label: {
                            Label(recorder.isPaused ? "Reprendre" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.trajetAction()
                    }
                    Button {
                        if recorder.isRecording { confirmStop = true } else { recorder.start() }
                    } label: {
                        Label(recorder.isRecording ? "Terminer" : "Démarrer le trajet", systemImage: recorder.isRecording ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.trajetAction(prominent: true).foregroundStyle(.black)
                        .disabled(recorder.waitingForPermission)
                }.font(.headline).padding(.horizontal).padding(.vertical, 10)
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
    private func metricValue(_ raw: String, at date: Date, fresh: Bool) -> String {
        let trip = recorder.archive.active
        switch DashboardMetric(rawValue: raw) ?? .speed {
        case .speed: return fresh && !recorder.isPaused ? Display.speed(recorder.speed, imperial: imperial) : "—"
        case .distance: return Display.distance(trip?.distance ?? 0, imperial: imperial)
        case .duration: return Display.time(trip?.duration(at: date) ?? 0)
        case .average: return Display.speed(trip.map { $0.duration(at: date) > 0 ? $0.distance / $0.duration(at: date) : 0 } ?? 0, imperial: imperial)
        }
    }
    private func dashboardMetric(_ raw: String, at date: Date, fresh: Bool) -> some View {
        let metric = DashboardMetric(rawValue: raw) ?? .speed
        return Metric(title: metric.title.uppercased(), value: metricValue(raw, at: date, fresh: fresh), unit: metric.unit(imperial: imperial))
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
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 1) }
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
            }.padding(12).trajetGlass(radius: 22, interactive: true).padding(10)
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
    @State private var period = "all"
    @State private var favoritesOnly = false
    @State private var category = "all"

    private var trips: [Trip] {
        recorder.archive.trips.filter { trip in
            let inPeriod = period == "all" || Calendar.current.isDate(trip.startedAt, equalTo: Date(), toGranularity: period == "month" ? .month : .weekOfYear)
            return inPeriod && (!favoritesOnly || trip.favorite == true) && (category == "all" || trip.activity.rawValue == category) && (query.isEmpty || trip.title.localizedCaseInsensitiveContains(query) || trip.startedAt.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Période", selection: $period) {
                        Text("Tout").tag("all")
                        Text("Semaine").tag("week")
                        Text("Mois").tag("month")
                    }.pickerStyle(.segmented)
                    Toggle("Favoris uniquement", isOn: $favoritesOnly)
                    Picker("Catégorie", selection: $category) {
                        Text("Toutes").tag("all")
                        ForEach(TripCategory.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    NavigationLink("Statistiques par semaine et par mois") {
                        StatisticsView(trips: recorder.archive.trips)
                    }
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
                            HStack {
                                Label(trip.title, systemImage: trip.activity.icon).font(.headline)
                                if trip.favorite == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                            }
                            if trip.name?.isEmpty == false {
                                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(Display.distance(trip.distance, imperial: imperial)) \(imperial ? "mi" : "km") · \(Display.time(trip.duration()))")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                    .swipeActions(edge: .leading) {
                        Button { recorder.toggleFavorite(trip.id) } label: { Label("Favori", systemImage: "star") }.tint(.orange)
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = trip } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TrajetBackdrop())
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
                        Picker("Catégorie", selection: Binding(get: { trip.activity }, set: { recorder.setCategory(id, category: $0) })) {
                            ForEach(TripCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                        }.pickerStyle(.menu)
                        Button { recorder.toggleFavorite(id) } label: {
                            Label(trip.favorite == true ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: trip.favorite == true ? "star.fill" : "star")
                        }
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
                        TripAnalysisView(trip: trip)
                        NavigationLink("Relire le parcours", destination: ReplayView(trip: trip)).disabled(trip.points.isEmpty)
                        NavigationLink("Créer une image à partager", destination: ShareTripView(trip: trip))
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
        .background(TrajetBackdrop())
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
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("liveActivities") private var liveActivities = true
    @AppStorage("imperial") private var imperial = false
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Enregistrement") {
                    AutoPauseSettings()
                }
                Section("Affichage") {
                    NavigationLink("Personnaliser les compteurs", destination: DisplaySettings())
                    Toggle("Utiliser les miles et mph", isOn: $imperial)
                    Toggle("Garder l’écran allumé", isOn: $keepScreenOn)
                    Text("L’écran reste allumé uniquement pendant un enregistrement actif. Cette option consomme davantage de batterie.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Dynamic Island et écran verrouillé") {
                    Toggle("Activités en direct", isOn: $liveActivities)
                        .onChange(of: liveActivities) { _, enabled in recorder.setLiveActivitiesEnabled(enabled) }
                    Text("Vitesse, distance et durée pendant un trajet. Sur un iPhone sans Dynamic Island, le suivi reste disponible sur l’écran verrouillé. Touchez l’activité pour retrouver Pause et Terminer.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("iOS décide du rythme d’actualisation. Après une perte de signal ou une interruption, une valeur ancienne est masquée.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Localisation") {
                    Button("Ouvrir les réglages de l’iPhone", systemImage: "location") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("Activez Position exacte. Le GPS fonctionne sans Internet ; le chargement des cartes peut nécessiter une connexion. La pause manuelle suspend le GPS ; la pause automatique garde le GPS actif pour détecter le départ.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Vos données") {
                    NavigationLink("Sauvegarder et restaurer", destination: BackupView())
                    Text("Trajets conserve vos parcours sur l’iPhone. Vous pouvez exporter chaque parcours en GPX depuis son détail. Les sauvegardes système peuvent inclure vos trajets.")
                    Text("Pour une mise à jour, réinstallez l’IPA avec le même compte AltStore sans supprimer l’app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Trajets", value: "3.0")
                    Text("Durée et vitesse moyenne excluent toutes les pauses. Les arrêts sans pause restent inclus.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden)
                .background(TrajetBackdrop())
                .navigationTitle("Réglages")
        }
    }
}
