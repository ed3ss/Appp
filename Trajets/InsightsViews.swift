import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

struct AutoPauseSettings: View {
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("autoPause") private var enabled = false
    @AppStorage("defaultCategory") private var category = "other"
    var body: some View {
        Toggle("Pause automatique", isOn: $enabled)
            .onChange(of: enabled) { _, value in recorder.setAutoPauseEnabled(value) }
        Text("Pause après 15 s sous 1,8 km/h ; reprise après 3 s à partir de 4,3 km/h. Le GPS reste actif. Une pause manuelle se reprend manuellement. Désactivez cette option pour une marche lente.")
            .font(.footnote).foregroundStyle(.secondary)
        Picker("Catégorie des nouveaux trajets", selection: $category) {
            ForEach(TripCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
        }
    }
}

struct DisplaySettings: View {
    @AppStorage("mainMetric") private var main = "speed"
    @AppStorage("leftMetric") private var left = "distance"
    @AppStorage("rightMetric") private var right = "duration"
    @AppStorage("islandMetric") private var island = "speed"
    var body: some View {
        Form {
            Section("Compteur") {
                picker("Information principale", value: $main)
                picker("Carte de gauche", value: $left)
                picker("Carte de droite", value: $right)
            }
            Section("Activité en direct") {
                picker("Information principale", value: $island)
                Text("Choix appliqué à la Dynamic Island et à l’écran verrouillé, y compris pendant un trajet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Rétablir l’affichage par défaut") {
                main = "speed"; left = "distance"; right = "duration"; island = "speed"
            }
        }.navigationTitle("Mes compteurs")
    }
    private func picker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            ForEach(DashboardMetric.allCases) { Text($0.title).tag($0.rawValue) }
        }
    }
}

struct SpeedChart: View {
    let trip: Trip
    @Binding var selection: Date?
    @AppStorage("imperial") private var imperial = false
    var body: some View {
        Chart {
            ForEach(trip.chartPoints) { point in
                LineMark(x: .value("Heure", point.timestamp),
                         y: .value(imperial ? "mph" : "km/h", point.speed * (imperial ? 2.2369362921 : 3.6)),
                         series: .value("Portion", point.segment ?? 0))
                    .foregroundStyle(.mint)
            }
            if let selection {
                RuleMark(x: .value("Position", selection)).foregroundStyle(.orange)
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXSelection(value: $selection)
        .frame(height: 170)
        .accessibilityLabel("Évolution de la vitesse en \(imperial ? "miles par heure" : "kilomètres par heure")")
    }
}

struct TripAnalysisView: View {
    let trip: Trip
    @AppStorage("imperial") private var imperial = false
    @State private var selectedDate: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Votre bilan").font(.title3.bold())
            HStack {
                Metric(title: "EN MOUVEMENT", value: Display.time(trip.movingDuration), unit: "")
                Metric(title: "ARRÊTS HORS PAUSE", value: Display.time(trip.stoppedDuration), unit: "")
            }
            Metric(title: "MOYENNE EN MOUVEMENT", value: Display.speed(trip.movingAverage, imperial: imperial), unit: imperial ? "mph" : "km/h")
            Text("Mouvement estimé au-delà de 2,9 km/h entre positions fiables rapprochées. Les pertes de GPS ne comptent pas comme mouvement ; les anciens trajets sont estimés depuis leurs points conservés.")
                .font(.caption).foregroundStyle(.secondary)
            if trip.points.count > 1 {
                SpeedChart(trip: trip, selection: $selectedDate)
                if let selectedDate, let index = trip.pointIndex(nearest: selectedDate) {
                    let point = trip.points[index]
                    Text("\(point.timestamp.formatted(date: .omitted, time: .standard)) · \(Display.speed(point.speed, imperial: imperial)) \(imperial ? "mph" : "km/h")")
                        .font(.callout.monospacedDigit())
                }
            }
        }
    }
}

struct ReplayView: View {
    let trip: Trip
    @AppStorage("imperial") private var imperial = false
    @State private var cursor = 0.0
    @State private var selectedDate: Date?
    @State private var playing = false
    @State private var position: MapCameraPosition = .automatic
    private var index: Int { min(max(0, Int(cursor)), max(0, trip.points.count - 1)) }
    private var point: TrackPoint? { trip.points.isEmpty ? nil : trip.points[index] }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Map(position: $position) {
                    ForEach(Array(trip.segments.enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment.map(\.coordinate)).stroke(.mint.opacity(0.7), lineWidth: 4)
                    }
                    if let point {
                        Annotation("Position", coordinate: point.coordinate) {
                            Image(systemName: "location.circle.fill").font(.largeTitle)
                                .foregroundStyle(.orange).background(.black, in: Circle())
                        }
                    }
                }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 24))
                if let point {
                    HStack {
                        Metric(title: "HEURE", value: point.timestamp.formatted(date: .omitted, time: .standard), unit: "")
                        Metric(title: "VITESSE", value: Display.speed(point.speed, imperial: imperial), unit: imperial ? "mph" : "km/h")
                    }
                    Slider(value: $cursor, in: 0...Double(max(1, trip.points.count - 1)), step: 1)
                        .disabled(trip.points.count < 2)
                        .accessibilityLabel("Position dans le parcours")
                    HStack {
                        Button(playing ? "Pause" : "Lire", systemImage: playing ? "pause.fill" : "play.fill") {
                            if !playing && index == trip.points.count - 1 { cursor = 0 }
                            playing.toggle()
                        }.buttonStyle(.borderedProminent).disabled(trip.points.count < 2)
                        Button("Tout voir", systemImage: "map") { position = .automatic }
                    }
                    Text("Lecture accélérée des positions enregistrées. Le curseur saute les pauses et les périodes sans GPS.")
                        .font(.caption).foregroundStyle(.secondary)
                    SpeedChart(trip: trip, selection: $selectedDate)
                }
            }.padding()
        }
        .background(TrajetBackdrop()).navigationTitle("Relecture")
        .onChange(of: cursor) { _, _ in
            guard let point else { return }
            selectedDate = point.timestamp
            position = .region(.init(center: point.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
        .onChange(of: selectedDate) { _, date in
            if let date, let index = trip.pointIndex(nearest: date), index != self.index { cursor = Double(index) }
        }
        .task(id: playing) {
            while playing && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard !Task.isCancelled else { return }
                if index < trip.points.count - 1 { cursor += Double(max(1, trip.points.count / 300)) }
                else { playing = false }
                cursor = min(cursor, Double(max(0, trip.points.count - 1)))
            }
        }
        .onDisappear { playing = false }
    }
}

struct StatisticsView: View {
    let trips: [Trip]
    @State private var monthly = false
    @AppStorage("imperial") private var imperial = false
    private var totals: [PeriodTotal] { TripStatistics.totals(trips, monthly: monthly) }
    var body: some View {
        List {
            Picker("Regroupement", selection: $monthly) {
                Text("8 semaines").tag(false)
                Text("6 mois").tag(true)
            }.pickerStyle(.segmented)
            Chart(totals) { period in
                BarMark(x: .value("Période", period.start, unit: monthly ? .month : .weekOfYear),
                        y: .value(imperial ? "mi" : "km", period.distance / (imperial ? 1609.344 : 1000)))
                    .foregroundStyle(.mint.gradient).cornerRadius(5)
            }.frame(height: 220)
            ForEach(totals.reversed()) { total in
                VStack(alignment: .leading, spacing: 6) {
                    Text(monthly ? total.start.formatted(.dateTime.month(.wide).year()) : "Semaine du \(total.start.formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline)
                    Text("\(total.count) trajets · \(Display.distance(total.distance, imperial: imperial)) \(imperial ? "mi" : "km") · \(Display.time(total.duration))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Statistiques")
    }
}

struct BackupView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @State private var importing = false
    @State private var imported: TripArchive?
    @State private var confirm = false
    @State private var shareFile: ShareFile?
    @State private var errorText: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section("Une copie de tous vos trajets") {
                Text("La sauvegarde JSON contient les parcours, noms, catégories et favoris. Enregistrez-la dans Fichiers, iCloud Drive ou sur votre PC. Les préférences d’affichage ne sont pas incluses.")
                Button("Exporter une sauvegarde", systemImage: "square.and.arrow.up") { export() }
                    .disabled(busy)
                Text("Un trajet en cours est exporté comme un instantané terminé ; son enregistrement continue.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Restaurer une sauvegarde Trajets") {
                Button("Choisir un fichier JSON", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(busy)
                Text("Aperçu avant import. Les nouveaux trajets sont ajoutés, les identifiants déjà présents sont ignorés. Rien n’est supprimé ou remplacé. Les fichiers GPX ne sont pas importés ici.")
                    .font(.footnote).foregroundStyle(.secondary)
                if busy { ProgressView("Lecture de la sauvegarde…") }
            }
            Section {
                Text("Le fichier contient vos positions et horaires. Partagez-le uniquement avec les personnes de votre choix.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sauvegarde")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                busy = true
                Task {
                    do {
                        let archive = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= BackupStore.maximumBytes else { throw BackupError.tooLarge }
                            return try BackupStore.decode(Data(contentsOf: url))
                        }.value
                        imported = archive
                        confirm = true
                    } catch { errorText = error.localizedDescription }
                    busy = false
                }
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .confirmationDialog("Restaurer cette sauvegarde ?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Ajouter les trajets") {
                if let imported { recorder.restore(imported) }
                imported = nil
            }
            Button("Annuler", role: .cancel) { imported = nil }
        } message: {
            let incoming = imported ?? TripArchive()
            let count = BackupStore.merging(incoming, into: recorder.archive).added
            Text("\(incoming.trips.count) trajets dans le fichier : \(count) nouveaux, \(incoming.trips.count - count) déjà présents. Une copie locale de sécurité est créée avant l’import.")
        }
        .sheet(item: $shareFile) { ShareSheet(url: $0.url) }
        .alert("Sauvegarde", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }
    private func export() {
        busy = true
        let archive = recorder.archive
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let data = try BackupStore.encode(archive)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trajets-sauvegarde-\(UUID().uuidString.prefix(8)).json")
                    try data.write(to: url, options: .atomic)
                    return url
                }.value
                shareFile = ShareFile(url: url)
            } catch { errorText = error.localizedDescription }
            busy = false
        }
    }
}

/// A vector route poster: offline, no missing map tiles in exported images.
struct RoutePoster: View {
    let trip: Trip
    let imperial: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("TRAJETS", systemImage: "location.fill").font(.headline).tracking(3).foregroundStyle(.mint)
                Spacer()
                Image(systemName: trip.activity.icon).foregroundStyle(.mint)
            }
            Text(trip.title).font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(2)
            Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            RouteDrawing(trip: trip).frame(height: 260)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
            HStack {
                posterMetric(Display.distance(trip.distance, imperial: imperial), label: imperial ? "MILES" : "KILOMÈTRES")
                Spacer()
                posterMetric(Display.time(trip.duration()), label: "DURÉE ACTIVE")
            }
            HStack {
                Text("Moyenne \(Display.speed(trip.averageSpeed, imperial: imperial)) \(imperial ? "mph" : "km/h")")
                Spacer()
                Text(trip.activity.title)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 390)
            .background(LinearGradient(colors: [Color(red: 0.02, green: 0.16, blue: 0.17), .black, Color(red: 0.04, green: 0.07, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
    private func posterMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.mint)
        }
    }
}

struct RouteDrawing: View {
    let trip: Trip
    var body: some View {
        Canvas { context, size in
            let segments = trip.segments.map { $0.map { MKMapPoint($0.coordinate) } }
            let points = segments.flatMap { $0 }
            guard let first = points.first else { return }
            // Unwrap around the departure longitude for routes crossing the date line.
            let width = MKMapRect.world.size.width
            func x(_ p: MKMapPoint) -> Double {
                var delta = p.x - first.x
                if delta > width / 2 { delta -= width }
                if delta < -width / 2 { delta += width }
                return delta
            }
            let minX = points.map { x($0) }.min() ?? 0
            let maxX = points.map { x($0) }.max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            let scale = min((size.width - 48) / max(1, maxX - minX), (size.height - 48) / max(1, maxY - minY))
            func project(_ p: MKMapPoint) -> CGPoint {
                CGPoint(x: size.width / 2 + (x(p) - (minX + maxX) / 2) * scale,
                        y: size.height / 2 + (p.y - (minY + maxY) / 2) * scale)
            }
            for segment in segments {
                var path = Path()
                for (index, p) in segment.enumerated() {
                    if index == 0 { path.move(to: project(p)) } else { path.addLine(to: project(p)) }
                }
                context.stroke(path, with: .color(.mint.opacity(0.15)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(.mint), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            for (p, color) in [(first, Color.white), (points.last ?? first, Color.orange)] {
                let center = project(p)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(color))
            }
        }
        .overlay {
            if trip.points.isEmpty { Text("Aucun tracé GPS").foregroundStyle(.secondary) }
        }
        .accessibilityLabel("Tracé du parcours, départ blanc et arrivée orange")
    }
}

struct ShareTripView: View {
    let trip: Trip
    @AppStorage("imperial") private var imperial = false
    @State private var file: ShareFile?
    @State private var errorText: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RoutePoster(trip: trip, imperial: imperial)
                    .scaleEffect(0.85).frame(width: 332, height: 530)
                    .accessibilityLabel("Aperçu de la fiche à partager")
                Text("Le tracé et le nom seront visibles dans l’image. Sans fond de carte, la fiche se crée aussi hors ligne.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Partager l’image", systemImage: "square.and.arrow.up") { render() }
                    .buttonStyle(.borderedProminent)
            }.padding()
        }.navigationTitle("Fiche du trajet")
            .sheet(item: $file) { ShareSheet(url: $0.url) }
            .alert("Export impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
    }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: RoutePoster(trip: trip, imperial: imperial))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { errorText = "L’image n’a pas pu être créée."; return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trajet-\(trip.id.uuidString).png")
            try data.write(to: url, options: .atomic)
            file = ShareFile(url: url)
        } catch { errorText = error.localizedDescription }
    }
}
