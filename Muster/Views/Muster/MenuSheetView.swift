import SwiftUI
import MapKit
import UniformTypeIdentifiers
import UIKit

struct MenuSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var showMissingMapSetPrompt = false
    @State private var showMapSetsSheet = false
    @State private var startMapSetCreationFlowOnOpen = false
    @State private var pendingTrackName = ""
    @State private var showNewTrackNamePrompt = false
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
                        pendingTrackName = app.muster.makeSmartSessionName()
                        showNewTrackNamePrompt = true
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
                startMapSetCreationFlowOnOpen = true
                showMapSetsSheet = true
            }
            Button("Select Map Set From List") {
                startMapSetCreationFlowOnOpen = false
                showMapSetsSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New track can’t be started without a Map Set selected.")
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
            MapSetsSheetView(startInCreateFlow: startMapSetCreationFlowOnOpen)
                .environmentObject(app)
        }
        .alert("New Track", isPresented: $showNewTrackNamePrompt) {
            TextField("Track name", text: $pendingTrackName)
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                if app.muster.startSession(name: pendingTrackName) {
                    dismiss()
                } else {
                    showMissingMapSetPrompt = true
                }
            }
        } message: {
            Text("Choose a track name.")
        }
        .onChange(of: showMapSetsSheet) { _, isPresented in
            if isPresented == false {
                startMapSetCreationFlowOnOpen = false
            }
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
    let startInCreateFlow: Bool

    @State private var pendingMapSetName: String = ""
    @State private var stagedMapSetName: String = ""
    @State private var selectedBoundaryKeys: Set<MapItemSelectionKey> = []
    @State private var selectedMarkerKeys: Set<MapItemSelectionKey> = []
    @State private var selectedTrackKeys: Set<MapItemSelectionKey> = []
    @State private var showCreateNamePrompt = false
    @State private var showBoundarySelection = false
    @State private var showMarkerSelection = false
    @State private var showImportPicker = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String? = nil
    @State private var didAutoStartCreateFlow = false

    init(startInCreateFlow: Bool = false) {
        self.startInCreateFlow = startInCreateFlow
    }
    private var trimmedPendingMapSetName: String {
        pendingMapSetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableBoundaryChoices: [MapItemChoice] {
        app.muster.importedMapFiles.flatMap { file in
            file.boundaries.map { boundary in
                MapItemChoice(
                    key: MapItemSelectionKey(fileID: file.id, itemID: boundary.id),
                    title: boundary.displayTitle
                )
            }
        }
    }

    private var availableMarkerChoices: [MapItemChoice] {
        app.muster.importedMapFiles.flatMap { file in
            file.markers.map { marker in
                MapItemChoice(
                    key: MapItemSelectionKey(fileID: file.id, itemID: marker.id),
                    title: marker.displayTitle
                )
            }
        }
    }

    private var availableTrackChoices: [MapItemChoice] {
        app.muster.importedMapFiles.flatMap { file in
            file.tracks.map { track in
                MapItemChoice(
                    key: MapItemSelectionKey(fileID: file.id, itemID: track.id),
                    title: track.displayTitle
                )
            }
        }
    }

    private var orderedMapSets: [MapSet] {
        app.muster.mapSets.sorted { lhs, rhs in
            if lhs.id == app.muster.selectedMapSetID { return true }
            if rhs.id == app.muster.selectedMapSetID { return false }

            let lhsLastUsed = lhs.lastUsedAt ?? lhs.createdAt
            let rhsLastUsed = rhs.lastUsedAt ?? rhs.createdAt
            if lhsLastUsed != rhsLastUsed {
                return lhsLastUsed > rhsLastUsed
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                
                Section("Map Sets") {
                    if app.muster.mapSets.isEmpty {
                        Text("No map sets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(orderedMapSets) { mapSet in
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pendingMapSetName = ""
                        stagedMapSetName = ""
                        selectedBoundaryKeys = []
                        selectedMarkerKeys = []
                        selectedTrackKeys = []
                        showCreateNamePrompt = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.green, in: Circle())
                    }
                    .accessibilityLabel("Create map set")
                }
            }
        }
        .alert("New Map Set", isPresented: $showCreateNamePrompt) {
            TextField("Map set name", text: $pendingMapSetName)
            Button("Cancel", role: .cancel) {
                pendingMapSetName = ""
            }
            Button("Next") {
                stagedMapSetName = trimmedPendingMapSetName
                showBoundarySelection = true
            }
            .disabled(trimmedPendingMapSetName.isEmpty)
        } message: {
            Text("Enter a name for the new map set.")
        }
        .sheet(isPresented: $showBoundarySelection) {
            NavigationStack {
                List {
                    Section("Boundaries") {
                        if availableBoundaryChoices.isEmpty {
                            Text("No boundaries available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableBoundaryChoices) { choice in
                                selectionRow(
                                    title: choice.title,
                                    isSelected: selectedBoundaryKeys.contains(choice.key)
                                ) {
                                    toggleSelection(choice.key, in: &selectedBoundaryKeys)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Include Boundaries")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showBoundarySelection = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") {
                            showBoundarySelection = false
                            showMarkerSelection = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showMarkerSelection) {
            NavigationStack {
                List {
                    Section("Markers") {
                        if availableMarkerChoices.isEmpty {
                            Text("No markers available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableMarkerChoices) { choice in
                                selectionRow(
                                    title: choice.title,
                                    isSelected: selectedMarkerKeys.contains(choice.key)
                                ) {
                                    toggleSelection(choice.key, in: &selectedMarkerKeys)
                                }
                            }
                        }
                    }

                    Section("Waypoints") {
                        if availableTrackChoices.isEmpty {
                            Text("No waypoints available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableTrackChoices) { choice in
                                selectionRow(
                                    title: choice.title,
                                    isSelected: selectedTrackKeys.contains(choice.key)
                                ) {
                                    toggleSelection(choice.key, in: &selectedTrackKeys)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Include Markers")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            showMarkerSelection = false
                            showBoundarySelection = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Create") {
                            finishMapSetCreation()
                            showMarkerSelection = false
                        }
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
        .onAppear {
            guard startInCreateFlow, didAutoStartCreateFlow == false else { return }
            didAutoStartCreateFlow = true
            pendingMapSetName = ""
            stagedMapSetName = ""
            selectedBoundaryKeys = []
            selectedMarkerKeys = []
            selectedTrackKeys = []
            showCreateNamePrompt = true
        }
    }

    @ViewBuilder
    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ key: MapItemSelectionKey, in set: inout Set<MapItemSelectionKey>) {
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
    }

    private func finishMapSetCreation() {
        let mapSetID = app.muster.createMapSet(named: stagedMapSetName)

        for choice in selectedBoundaryKeys {
            app.muster.assignImportedBoundary(fileID: choice.fileID, boundaryID: choice.itemID, to: mapSetID)
        }

        for choice in selectedMarkerKeys {
            app.muster.assignImportedMarker(fileID: choice.fileID, markerID: choice.itemID, to: mapSetID)
        }

        for choice in selectedTrackKeys {
            app.muster.assignImportedTrack(fileID: choice.fileID, trackID: choice.itemID, to: mapSetID)
        }

        pendingMapSetName = ""
        stagedMapSetName = ""
        selectedBoundaryKeys = []
        selectedMarkerKeys = []
        selectedTrackKeys = []
    }

    private func summary(for mapSetID: UUID) -> String {
        let boundaries = app.muster.importedBoundaries(in: mapSetID).count
        let markers = app.muster.importedMarkers(in: mapSetID).count
        let tracks = app.muster.totalTrackCount(in: mapSetID)
        return "\(boundaries) boundaries • \(markers) markers • \(tracks) tracks"
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

private struct MapItemSelectionKey: Hashable {
    let fileID: UUID
    let itemID: UUID
}

private struct MapItemChoice: Identifiable {
    let key: MapItemSelectionKey
    let title: String

    var id: MapItemSelectionKey { key }
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
    @State private var selectedTrackPreview: TrackPreviewTarget? = nil
    @State private var pendingTrackDeletion: TrackPreviewTarget? = nil
    @State private var selectedTrackActions: TrackPreviewTarget? = nil
    @State private var pendingTrackMove: TrackPreviewTarget? = nil
    @State private var editingTrackTarget: TrackPreviewTarget? = nil
    @State private var editingTrackName = ""

    private var mapSet: MapSet? {
        app.muster.mapSets.first(where: { $0.id == mapSetID })
    }

    var body: some View {
        List {
            if let mapSet {
                Section("Name") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if isEditingName {
                            TextField("Map set name", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveNameEdits(for: mapSet)
                                }
                            Button {
                                saveNameEdits(for: mapSet)
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text(mapSet.displayTitle)
                            Text(mapSet.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

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
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name)
                                    Text("Muster • \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedTrackActions = .recorded(session)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.body.weight(.semibold))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit actions for \(session.name)")
                            }
                        }
                        ForEach(importedTracks, id: \.track.id) { pair in
                            HStack(spacing: 10) {
                                Text(pair.track.displayTitle)
                                Spacer()
                                Button {
                                    selectedTrackActions = .imported(track: pair.track)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.body.weight(.semibold))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit actions for \(pair.track.displayTitle)")
                            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let mapSet {
                    Menu {
                        Button("Display", systemImage: "eye") {
                            app.muster.selectMapSet(mapSet.id)
                        }
                        Button("Edit", systemImage: "pencil") {
                            editingName = mapSet.displayTitle
                            isEditingName = true
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            if let duplicatedMapSet = app.muster.duplicateMapSet(mapSetID: mapSet.id) {
                                duplicateAlertMessage = "\"\(duplicatedMapSet.displayTitle)\" was created."
                            }
                        }
                        Button("Export", systemImage: "square.and.arrow.up") {
                            exportMapSet(mapSet)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Map set actions")
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { !shareSheetItems.isEmpty },
                set: { if !$0 { shareSheetItems = [] } }
            )
        ) {
            MapSetActivityView(activityItems: shareSheetItems)
        }
        .sheet(item: $selectedTrackPreview) { track in
            TrackPreviewSheet(
                title: track.title,
                coordinates: track.coordinates,
                onExport: {
                    exportTrack(track)
                },
                onDelete: {
                    pendingTrackDeletion = track
                }
            )
        }
        .confirmationDialog(
            selectedTrackActions?.title ?? "Track Actions",
            isPresented: Binding(
                get: { selectedTrackActions != nil },
                set: { if !$0 { selectedTrackActions = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let track = selectedTrackActions {
                Button("Display", systemImage: "eye") {
                    selectedTrackPreview = track
                }
                Button("Edit", systemImage: "pencil") {
                    editingTrackTarget = track
                    editingTrackName = track.title
                }
                Button("Move", systemImage: "arrow.left.arrow.right") {
                    pendingTrackMove = track
                }
                Button("Export", systemImage: "square.and.arrow.up") {
                    exportTrack(track)
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingTrackDeletion = track
                }
            }
        }
        .sheet(item: $pendingTrackMove) { track in
            NavigationStack {
                List {
                    Section("Move to Map Set") {
                        ForEach(app.muster.mapSets, id: \.id) { targetMapSet in
                            Button(targetMapSet.displayTitle) {
                                moveTrack(track, to: targetMapSet.id)
                                pendingTrackMove = nil
                            }
                        }
                    }
                }
                .navigationTitle("Move Track")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            pendingTrackMove = nil
                        }
                    }
                }
            }
        }
        .onChange(of: mapSet?.id) { _, _ in
            isEditingName = false
            editingName = mapSet?.displayTitle ?? ""
        }
        .alert(
            "Edit Track Name",
            isPresented: Binding(
                get: { editingTrackTarget != nil },
                set: { if !$0 { editingTrackTarget = nil } }
            )
        ) {
            TextField("Track name", text: $editingTrackName)
            Button("Save") {
                guard let target = editingTrackTarget else { return }
                renameTrack(target, to: editingTrackName)
                editingTrackTarget = nil
                editingTrackName = ""
            }
            Button("Cancel", role: .cancel) {
                editingTrackTarget = nil
                editingTrackName = ""
            }
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
        .alert(
            "Delete Track?",
            isPresented: Binding(
                get: { pendingTrackDeletion != nil },
                set: { if !$0 { pendingTrackDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let target = pendingTrackDeletion else { return }
                deleteTrack(target)
                pendingTrackDeletion = nil
                selectedTrackPreview = nil
            }
            Button("Cancel", role: .cancel) {
                pendingTrackDeletion = nil
            }
        } message: {
            Text("This cannot be undone.")
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

    private func deleteTrack(_ track: TrackPreviewTarget) {
        switch track {
        case .recorded(let session):
            app.muster.deleteSession(sessionID: session.id)
        case .imported(let importedTrack):
            app.muster.deleteImportedTrack(trackID: importedTrack.id)
        }
    }

    private func exportTrack(_ track: TrackPreviewTarget) {
        do {
            let fileURL = try writeGPXTrackFile(for: track)
            shareSheetItems = [fileURL]
        } catch {
            alertTitle = "Export Failed"
            alertMessage = "Could not export GPX track: \(error.localizedDescription)"
        }
    }

    private func renameTrack(_ track: TrackPreviewTarget, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch track {
        case .recorded(let session):
            app.muster.renameSession(sessionID: session.id, newName: trimmed)
        case .imported(let importedTrack):
            app.muster.renameImportedTrack(trackID: importedTrack.id, newName: trimmed)
        }
    }

    private func moveTrack(_ track: TrackPreviewTarget, to mapSetID: UUID) {
        switch track {
        case .recorded(let session):
            app.muster.moveSession(sessionID: session.id, to: mapSetID)
        case .imported(let importedTrack):
            guard let fileID = app.muster.fileID(containingTrackID: importedTrack.id) else { return }
            app.muster.assignImportedTrack(fileID: fileID, trackID: importedTrack.id, to: mapSetID)
        }
    }

    private func writeGPXTrackFile(for track: TrackPreviewTarget) throws -> URL {
        var xml: [String] = []
        xml.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        xml.append(#"<gpx version="1.1" creator="Muster" xmlns="http://www.topografix.com/GPX/1/1">"#)
        xml.append("<trk>")
        xml.append("<name>\(xmlEscaped(track.title))</name>")
        xml.append("<trkseg>")

        for coordinate in track.coordinates {
            xml.append(#"<trkpt lat="\#(coordinate.latitude)" lon="\#(coordinate.longitude)"></trkpt>"#)
        }

        xml.append("</trkseg>")
        xml.append("</trk>")
        xml.append("</gpx>")

        let text = xml.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        let fileName = sanitizedFileBaseName(track.title.isEmpty ? "Muster Track" : track.title)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("gpx")

        try data.write(to: url, options: .atomic)
        return url
    }

    private func sanitizedFileBaseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Muster Track" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = base.components(separatedBy: invalid).joined(separator: "-")
        return cleaned
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func xmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private enum ExportError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode export file."
            }
        }
    }
}

private enum TrackPreviewTarget: Identifiable {
    case recorded(MusterSession)
    case imported(track: ImportedTrack)

    var id: UUID {
        switch self {
        case .recorded(let session):
            return session.id
        case .imported(let track):
            return track.id
        }
    }

    var title: String {
        switch self {
        case .recorded(let session):
            return session.name
        case .imported(let track):
            return track.displayTitle
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        switch self {
        case .recorded(let session):
            return session.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        case .imported(let track):
            return track.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        }
    }
}

private struct TrackPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let coordinates: [CLLocationCoordinate2D]
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TrackOverviewMap(coordinates: coordinates)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TrackOverviewMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.mapType = .hybrid
        map.isUserInteractionEnabled = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard coordinates.count > 1 else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue
            renderer.lineWidth = 4
            renderer.lineCap = .round
            return renderer
        }
    }
}
