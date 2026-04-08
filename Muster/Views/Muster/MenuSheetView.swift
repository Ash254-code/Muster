import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MenuSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var showMissingMapSetPrompt = false
    @State private var showMapSetsSheet = false
    @State private var sessionPendingDeletion: MusterSession? = nil

    private var previousSessions: [MusterSession] {
        app.muster.previousSessions
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Map Visibility") {
                    Toggle(isOn: previousTracksVisibleBinding) {
                        Label("Show Previous Tracks", systemImage: "eye")
                    }

                    if previousSessions.isEmpty == false {
                        HStack(spacing: 12) {
                            Button {
                                app.muster.showAllPreviousSessionsOnMap()
                            } label: {
                                Label("Show All", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                app.muster.hideAllPreviousSessionsOnMap()
                            } label: {
                                Label("Hide All", systemImage: "eye.slash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Previous Tracks") {
                    if previousSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No previous tracks")
                                .font(.headline)

                            Text("Start a new track and it will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(previousSessions) { session in
                            HStack(spacing: 12) {
                                Button {
                                    app.muster.activeSessionID = session.id
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(session.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(
                                            session.startedAt.formatted(
                                                date: .abbreviated,
                                                time: .shortened
                                            )
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                        if let detail = sessionDetailText(for: session) {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    app.muster.toggleSessionVisibilityOnMap(sessionID: session.id)
                                } label: {
                                    Image(systemName: session.isVisibleOnMap ? "eye.fill" : "eye.slash.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(
                                            app.muster.showPreviousTracksOnMap
                                            ? (session.isVisibleOnMap ? .blue : .secondary)
                                            : .secondary
                                        )
                                        .frame(width: 34, height: 34)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(session.isVisibleOnMap ? "Hide track on map" : "Show track on map")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    sessionPendingDeletion = session
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        if app.muster.startSmartSession() {
                            dismiss()
                        } else {
                            showMissingMapSetPrompt = true
                        }
                    } label: {
                        Label("New Track", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Previous Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .confirmationDialog(
            "Map Set Required",
            isPresented: $showMissingMapSetPrompt,
            titleVisibility: .visible
        ) {
            Button("Create New Map Set") {
                _ = app.muster.createMapSet()
            }
            Button("Select Map Set From List") {
                showMapSetsSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New Muster or track can’t be started without a Map Set selected.")
        }
        .confirmationDialog(
            "Delete Previous Muster?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let sessionID = sessionPendingDeletion?.id else { return }
                app.muster.deleteSession(sessionID: sessionID)
                sessionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDeletion = nil
            }
        } message: {
            if let sessionPendingDeletion {
                Text("Delete \"\(sessionPendingDeletion.name)\"? This cannot be undone.")
            } else {
                Text("This cannot be undone.")
            }
        }
        .sheet(isPresented: $showMapSetsSheet) {
            MapSetsSheetView()
                .environmentObject(app)
        }
    }

    private var previousTracksVisibleBinding: Binding<Bool> {
        Binding(
            get: { app.muster.showPreviousTracksOnMap },
            set: { app.muster.setPreviousTracksVisible($0) }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDeletion != nil },
            set: { isPresented in
                if isPresented == false {
                    sessionPendingDeletion = nil
                }
            }
        )
    }

    private func sessionDetailText(for session: MusterSession) -> String? {
        let minutes = Int(session.duration / 60)
        guard minutes > 0 else { return nil }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "Duration: \(hours)h \(remainingMinutes)m"
        } else {
            return "Duration: \(remainingMinutes)m"
        }
    }
}

struct MapSetsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var newMapSetName: String = ""
    @State private var showImportPicker = false
    @State private var shareSheetItems: [Any] = []
    @State private var alertTitle: String = ""
    @State private var alertMessage: String? = nil
    @State private var showImportActions = false
    @State private var showExportActions = false
    private var trimmedNewMapSetName: String {
        newMapSetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                
                Section("Create") {
                    HStack(spacing: 12) {
                        TextField("Map set name", text: $newMapSetName)

                        Button {
                            app.muster.createMapSet(named: trimmedNewMapSetName)
                            newMapSetName = ""
                        } label: {
                            Text("Create")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(trimmedNewMapSetName.isEmpty ? .gray : .accentColor)
                        .disabled(trimmedNewMapSetName.isEmpty)
                    }
                }
                Section("Map Sets") {
                    if app.muster.mapSets.isEmpty {
                        Text("No map sets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(app.muster.mapSets) { mapSet in
                            NavigationLink {
                                MapSetDetailView(mapSetID: mapSet.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(mapSet.displayTitle)
                                        if app.muster.selectedMapSetID == mapSet.id {
                                            Text("Current Map Set")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .foregroundStyle(.green)
                                                .background(.green.opacity(0.14), in: Capsule())
                                        }
                                        Spacer()
                                    }
                                    Text(summary(for: mapSet.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Created \(mapSet.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Set Current") {
                                    app.muster.selectMapSet(mapSet.id)
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                
                Section("Import") {
                    Button("Import Map Set") {
                        showImportPicker = true
                    }
                }

                Section("Export") {
                    if app.muster.mapSets.isEmpty {
                        Text("No map sets available for export.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Export Map Set") {
                            showExportActions = true
                        }
                    }
                
                }
            }
            .navigationTitle("Map Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importMapSet(result: result)
        }
        .sheet(
            isPresented: Binding(
                get: { !shareSheetItems.isEmpty },
                set: { if !$0 { shareSheetItems = [] } }
            )
        ) {
            MapSetActivityView(activityItems: shareSheetItems)
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Export Map Set",
            isPresented: $showExportActions,
            titleVisibility: .visible
        ) {
            ForEach(app.muster.mapSets) { mapSet in
                Button("\(mapSet.displayTitle) • \(mapSet.createdAt.formatted(date: .abbreviated, time: .omitted))") {
                    exportMapSet(mapSet)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func summary(for mapSetID: UUID) -> String {
        let boundaries = app.muster.importedBoundaries(in: mapSetID).count
        let markers = app.muster.importedMarkers(in: mapSetID).count
        let tracks = app.muster.importedTracks(in: mapSetID).count
        return "\(boundaries) boundaries • \(markers) markers • \(tracks) tracks"
    }

    private func exportMapSet(_ mapSet: MapSet) {
        struct MapSetBundle: Codable {
            var mapSet: MapSet
            var boundaries: [ImportedBoundary]
            var markers: [ImportedMarker]
            var tracks: [ImportedTrack]
        }

        do {
            let payload = MapSetBundle(
                mapSet: mapSet,
                boundaries: app.muster.importedBoundaries(in: mapSet.id).map(\.boundary),
                markers: app.muster.importedMarkers(in: mapSet.id).map(\.marker),
                tracks: app.muster.importedTracks(in: mapSet.id).map(\.track)
            )

            let data = try JSONEncoder().encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(mapSet.displayTitle.replacingOccurrences(of: " ", with: "_"))_map_set.json")
            try data.write(to: url, options: .atomic)
            shareSheetItems = [url]
        } catch {
            alertTitle = "Export Failed"
            alertMessage = error.localizedDescription
        }
    }

    private func importMapSet(result: Result<[URL], Error>) {
        struct MapSetBundle: Codable {
            var mapSet: MapSet
            var boundaries: [ImportedBoundary]
            var markers: [ImportedMarker]
            var tracks: [ImportedTrack]
        }

        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(MapSetBundle.self, from: data)
            let mapSetID = app.muster.createMapSet(named: payload.mapSet.displayTitle)

            var importedFile = ImportedMapFile(
                fileName: "Map Set - \(payload.mapSet.displayTitle)",
                format: .unknown,
                assignedCategory: .other,
                boundaries: payload.boundaries,
                markers: payload.markers,
                tracks: payload.tracks,
                isVisible: true
            )

            importedFile.boundaries = importedFile.boundaries.map {
                var item = $0
                item.id = UUID()
                item.mapSetID = mapSetID
                return item
            }

            importedFile.markers = importedFile.markers.map {
                var item = $0
                item.id = UUID()
                item.mapSetID = mapSetID
                return item
            }

            importedFile.tracks = importedFile.tracks.map {
                var item = $0
                item.id = UUID()
                item.mapSetID = mapSetID
                return item
            }

            app.muster.addImportedMapFile(importedFile)
        } catch {
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
        }
    }
}

private struct MapSetActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct MapSetDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let mapSetID: UUID
    @State private var duplicateAlertMessage: String? = nil
    @State private var shareSheetItems: [Any] = []
    @State private var alertTitle: String = ""
    @State private var alertMessage: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var isEditingName = false
    @State private var editingName = ""

    private var mapSet: MapSet? {
        app.muster.mapSets.first(where: { $0.id == mapSetID })
    }

    var body: some View {
        List {
            if let mapSet {
                Section("Name") {
                    HStack(spacing: 8) {
                        if isEditingName {
                            TextField("Map set name", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveNameEdits(for: mapSet)
                                }
                        } else {
                            Text(mapSet.displayTitle)
                        }
                        Button {
                            if isEditingName {
                                saveNameEdits(for: mapSet)
                            } else {
                                editingName = mapSet.displayTitle
                                isEditingName = true
                            }
                        } label: {
                            Image(systemName: isEditingName ? "checkmark" : "pencil")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }

                    Text("Created \(mapSet.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Actions") {
                    if app.muster.selectedMapSetID == mapSet.id {
                        HStack {
                            Text("Current Map Set")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.green.opacity(0.14), in: Capsule())
                            Spacer()
                        }
                    } else {
                        Button("Set as Current Map Set") {
                            app.muster.selectMapSet(mapSet.id)
                        }
                    }
                    Button("Duplicate") {
                        if let duplicatedMapSet = app.muster.duplicateMapSet(mapSetID: mapSet.id) {
                            duplicateAlertMessage = "\"\(duplicatedMapSet.displayTitle)\" was created."
                        }
                    }
                    Button("Export") {
                        exportMapSet(mapSet)
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
                Section("Tracks") {
                    let importedTracks = app.muster.importedTracks(in: mapSet.id)
                    let recordedSessions = app.muster.recordedSessions(in: mapSet.id)
                    if importedTracks.isEmpty && recordedSessions.isEmpty {
                        Text("No tracks")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recordedSessions, id: \.id) { session in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                Text("Muster • \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(importedTracks, id: \.track.id) { pair in
                            Text(pair.track.displayTitle)
                        }
                    }
                }

                Section("Boundaries") {
                    let boundaries = app.muster.importedBoundaries(in: mapSet.id)
                    if boundaries.isEmpty {
                        Text("No boundaries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(boundaries, id: \.boundary.id) { pair in
                            HStack {
                                Text(pair.boundary.displayTitle)
                                Spacer()
                                Button("Remove") {
                                    app.muster.assignImportedBoundary(fileID: pair.fileID, boundaryID: pair.boundary.id, to: nil)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                Section("Markers") {
                    let markers = app.muster.importedMarkers(in: mapSet.id)
                    if markers.isEmpty {
                        Text("No markers")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(markers, id: \.marker.id) { pair in
                            HStack {
                                Text(pair.marker.displayTitle)
                                Spacer()
                                Button("Remove") {
                                    app.muster.assignImportedMarker(fileID: pair.fileID, markerID: pair.marker.id, to: nil)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                Section("Move Existing Items Here") {
                    let availableBoundaries = app.muster.importedMapFiles
                        .flatMap { file in file.boundaries.map { (file.id, $0) } }
                        .filter { $0.1.mapSetID != mapSet.id }
                    let availableMarkers = app.muster.importedMapFiles
                        .flatMap { file in file.markers.map { (file.id, $0) } }
                        .filter { $0.1.mapSetID != mapSet.id }
                    let availableTracks = app.muster.importedMapFiles
                        .flatMap { file in file.tracks.map { (file.id, $0) } }
                        .filter { $0.1.mapSetID != mapSet.id }

                    if availableBoundaries.isEmpty && availableMarkers.isEmpty && availableTracks.isEmpty {
                        Text("No additional imported items available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableBoundaries.prefix(10), id: \.1.id) { pair in
                            Button("Add boundary: \(pair.1.displayTitle)") {
                                app.muster.assignImportedBoundary(fileID: pair.0, boundaryID: pair.1.id, to: mapSet.id)
                            }
                        }
                        ForEach(availableMarkers.prefix(10), id: \.1.id) { pair in
                            Button("Add marker: \(pair.1.displayTitle)") {
                                app.muster.assignImportedMarker(fileID: pair.0, markerID: pair.1.id, to: mapSet.id)
                            }
                        }
                        ForEach(availableTracks.prefix(10), id: \.1.id) { pair in
                            Button("Move track: \(pair.1.displayTitle)") {
                                app.muster.assignImportedTrack(fileID: pair.0, trackID: pair.1.id, to: mapSet.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(mapSet?.displayTitle ?? "Map Set")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: Binding(
                get: { !shareSheetItems.isEmpty },
                set: { if !$0 { shareSheetItems = [] } }
            )
        ) {
            MapSetActivityView(activityItems: shareSheetItems)
        }
        .onChange(of: mapSet?.id) { _, _ in
            isEditingName = false
            editingName = mapSet?.displayTitle ?? ""
        }
        .alert(
            "Map Set Duplicated",
            isPresented: Binding(
                get: { duplicateAlertMessage != nil },
                set: { if !$0 { duplicateAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                duplicateAlertMessage = nil
            }
        } message: {
            Text(duplicateAlertMessage ?? "")
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert(
            "Delete Map Set?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                guard let mapSet else { return }
                app.muster.deleteMapSet(mapSetID: mapSet.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the map set and reassign its items.")
        }
    }

    private func exportMapSet(_ mapSet: MapSet) {
        struct MapSetBundle: Codable {
            var mapSet: MapSet
            var boundaries: [ImportedBoundary]
            var markers: [ImportedMarker]
            var tracks: [ImportedTrack]
        }

        do {
            let payload = MapSetBundle(
                mapSet: mapSet,
                boundaries: app.muster.importedBoundaries(in: mapSet.id).map(\.boundary),
                markers: app.muster.importedMarkers(in: mapSet.id).map(\.marker),
                tracks: app.muster.importedTracks(in: mapSet.id).map(\.track)
            )

            let data = try JSONEncoder().encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(mapSet.displayTitle.replacingOccurrences(of: " ", with: "_"))_map_set.json")
            try data.write(to: url, options: .atomic)
            shareSheetItems = [url]
        } catch {
            alertTitle = "Export Failed"
            alertMessage = error.localizedDescription
        }
    }

    private func saveNameEdits(for mapSet: MapSet) {
        app.muster.renameMapSet(mapSetID: mapSet.id, newName: editingName)
        editingName = ""
        isEditingName = false
    }
}
