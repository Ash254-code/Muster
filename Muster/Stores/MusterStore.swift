import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class MusterStore: ObservableObject, Codable {

    @Published var sessions: [MusterSession] = []
    @Published var markerTemplates: [MarkerTemplate] = []
    @Published var mapMarkers: [MapMarker] = []

    /// Imported read-only map content from GPX / KML / KMZ / GeoJSON
    @Published var importedMapFiles: [ImportedMapFile] = []
    @Published var mapSets: [MapSet] = []
    @Published var selectedMapSetID: UUID? = nil

    /// Per-category appearance for imported content
    @Published var importCategoryStyles: [ImportCategoryStyle] = .default

    /// Per-category map filter visibility
    @Published var importCategoryVisibility: ImportCategoryVisibility = .init()
    @Published var customImportCategories: [CustomImportCategory] = []

    @Published var activeSessionID: UUID? = nil
    @Published var activeSheepTargetMarkerID: UUID? = nil

    /// Master switch for rendering completed / previous tracks on the map.
    @Published var showPreviousTracksOnMap: Bool = true

    // Recording cleanup / smoothing thresholds
    private let recordingMaxHorizontalAccuracy: CLLocationAccuracy = 40
    private let recordingMinDeltaMeters: CLLocationDistance = 4.0
    private let recordingStationarySpeedThreshold: CLLocationSpeed = 0.7
    private let recordingLowSpeedThreshold: CLLocationSpeed = 1.5
    private let recordingRejectSmallMoveUnderLowSpeedMeters: CLLocationDistance = 5.0
    private let recordingFreshGapSeconds: TimeInterval = 20.0
    private let recordingMaxReasonableSpeedMetersPerSecond: CLLocationSpeed = 40.0

    // Save batching
    private let saveBatchInterval: TimeInterval = 30.0
    private var lastSaveAt: Date = .distantPast
    private var hasPendingChanges: Bool = false
    private var autosaveTask: Task<Void, Never>? = nil
    private var appLifecycleObservers: [NSObjectProtocol] = []

    enum CodingKeys: CodingKey {
        case sessions
        case markerTemplates
        case mapMarkers
        case importedMapFiles
        case mapSets
        case selectedMapSetID
        case importCategoryStyles
        case importCategoryVisibility
        case customImportCategories
        case activeSessionID
        case activeSheepTargetMarkerID
        case showPreviousTracksOnMap
    }

    init() {
        seedDefaultMarkerTemplatesIfNeeded()
        seedDefaultImportCategoryStylesIfNeeded()
        configureAutosaveObservers()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([MusterSession].self, forKey: .sessions) ?? []
        markerTemplates = try c.decodeIfPresent([MarkerTemplate].self, forKey: .markerTemplates) ?? []
        mapMarkers = try c.decodeIfPresent([MapMarker].self, forKey: .mapMarkers) ?? []
        importedMapFiles = try c.decodeIfPresent([ImportedMapFile].self, forKey: .importedMapFiles) ?? []
        mapSets = try c.decodeIfPresent([MapSet].self, forKey: .mapSets) ?? []
        selectedMapSetID = try c.decodeIfPresent(UUID.self, forKey: .selectedMapSetID)
        importCategoryStyles = try c.decodeIfPresent([ImportCategoryStyle].self, forKey: .importCategoryStyles) ?? .default
        importCategoryVisibility = try c.decodeIfPresent(ImportCategoryVisibility.self, forKey: .importCategoryVisibility) ?? .init()
        customImportCategories = try c.decodeIfPresent([CustomImportCategory].self, forKey: .customImportCategories) ?? []
        activeSessionID = try c.decodeIfPresent(UUID.self, forKey: .activeSessionID)
        activeSheepTargetMarkerID = try c.decodeIfPresent(UUID.self, forKey: .activeSheepTargetMarkerID)
        showPreviousTracksOnMap = try c.decodeIfPresent(Bool.self, forKey: .showPreviousTracksOnMap) ?? true

        seedDefaultMarkerTemplatesIfNeeded()
        seedDefaultImportCategoryStylesIfNeeded()
        normalizeImportedMapFilesIfNeeded()
        normalizeMapSetAssignmentsIfNeeded()
        normalizeSessionMapSetAssignmentsIfNeeded()
        normalizeMapMarkerSetAssignmentsIfNeeded()
        normalizeSelectedMapSetIfNeeded()
        configureAutosaveObservers()
    }

    deinit {
        autosaveTask?.cancel()

        let nc = NotificationCenter.default
        for observer in appLifecycleObservers {
            nc.removeObserver(observer)
        }
    }

    func deleteSessionMarker(markerID: UUID, in sessionID: UUID? = nil) {
        let targetSessionID = sessionID ?? activeSessionID
        guard let targetSessionID,
              let index = sessions.firstIndex(where: { $0.id == targetSessionID }) else { return }

        sessions[index].markers.removeAll { $0.id == markerID }

        if activeSheepTargetMarkerID == markerID {
            activeSheepTargetMarkerID = nil
        }

        save()
    }

    func renameSessionMarker(markerID: UUID, in sessionID: UUID? = nil, newName: String?) {
        let targetSessionID = sessionID ?? activeSessionID
        guard let targetSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == targetSessionID }),
              let markerIndex = sessions[sessionIndex].markers.firstIndex(where: { $0.id == markerID }) else { return }

        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sessions[sessionIndex].markers[markerIndex].note = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func moveSessionMarker(markerID: UUID, in sessionID: UUID? = nil, to coordinate: CLLocationCoordinate2D) {
        let targetSessionID = sessionID ?? activeSessionID
        guard let targetSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == targetSessionID }),
              let markerIndex = sessions[sessionIndex].markers.firstIndex(where: { $0.id == markerID }) else { return }

        sessions[sessionIndex].markers[markerIndex].lat = coordinate.latitude
        sessions[sessionIndex].markers[markerIndex].lon = coordinate.longitude
        save()
    }

    func deleteMapMarker(markerID: UUID) {
        mapMarkers.removeAll { $0.id == markerID }
        save()
    }

    func renameMapMarker(markerID: UUID, newName: String?) {
        guard let index = mapMarkers.firstIndex(where: { $0.id == markerID }) else { return }

        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mapMarkers[index].name = trimmed
        save()
    }

    func moveMapMarker(markerID: UUID, to coordinate: CLLocationCoordinate2D) {
        guard let index = mapMarkers.firstIndex(where: { $0.id == markerID }) else { return }

        mapMarkers[index].lat = coordinate.latitude
        mapMarkers[index].lon = coordinate.longitude
        save()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(markerTemplates, forKey: .markerTemplates)
        try c.encode(mapMarkers, forKey: .mapMarkers)
        try c.encode(importedMapFiles, forKey: .importedMapFiles)
        try c.encode(mapSets, forKey: .mapSets)
        try c.encode(selectedMapSetID, forKey: .selectedMapSetID)
        try c.encode(importCategoryStyles, forKey: .importCategoryStyles)
        try c.encode(importCategoryVisibility, forKey: .importCategoryVisibility)
        try c.encode(customImportCategories, forKey: .customImportCategories)
        try c.encode(activeSessionID, forKey: .activeSessionID)
        try c.encode(activeSheepTargetMarkerID, forKey: .activeSheepTargetMarkerID)
        try c.encode(showPreviousTracksOnMap, forKey: .showPreviousTracksOnMap)
    }

    // =========================================================
    // MARK: - Active / lookup helpers
    // =========================================================

    var activeSession: MusterSession? {
        get { sessions.first(where: { $0.id == activeSessionID }) }
        set {
            guard let newValue else { return }
            if let i = sessions.firstIndex(where: { $0.id == newValue.id }) {
                sessions[i] = newValue
            }
        }
    }

    var previousSessions: [MusterSession] {
        sessions
            .filter { $0.id != activeSessionID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var visiblePreviousSessions: [MusterSession] {
        guard showPreviousTracksOnMap else { return [] }
        return previousSessions
            .filter { session in
                session.isVisibleOnMap &&
                !session.points.isEmpty &&
                isVisibleInSelectedMapSet(session.mapSetID)
            }
    }

    var activeSheepTarget: MusterMarker? {
        guard let id = activeSheepTargetMarkerID else { return nil }
        return activeSession?.markers.first(where: { $0.id == id && $0.type == .sheepPin })
    }

    var kilometresForDay: Double {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return 0
        }

        return sessions.reduce(0) { total, session in
            total + recordedDistanceMetersForDay(
                in: session.points,
                from: startOfToday,
                to: startOfTomorrow
            )
        } / 1000.0
    }

    var kilometresForDayText: String {
        let km = kilometresForDay

        if km >= 10 {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.2f km", km)
        }
    }

    var visibleImportedMapFiles: [ImportedMapFile] {
        importedMapFiles.filter(\.isVisible)
    }

    var visibleMapMarkers: [MapMarker] {
        mapMarkers.filter { marker in
            isVisibleInSelectedMapSet(marker.mapSetID)
        }
    }

    var visibleImportedBoundaries: [ImportedBoundary] {
        visibleImportedMapFiles.flatMap { file in
            file.boundaries.filter { boundary in
                boundary.isVisible &&
                importCategoryVisibility.isVisible(boundary.category) &&
                isVisibleInSelectedMapSet(boundary.mapSetID)
            }
        }
    }

    var visibleImportedMarkers: [ImportedMarker] {
        visibleImportedMapFiles.flatMap { file in
            file.markers.filter { marker in
                marker.isVisible &&
                importCategoryVisibility.isVisible(marker.category) &&
                isVisibleInSelectedMapSet(marker.mapSetID)
            }
        }
    }

    var visibleImportedTracks: [ImportedTrack] {
        visibleImportedMapFiles.flatMap { file in
            file.tracks.filter { track in
                track.isVisible &&
                importCategoryVisibility.isVisible(track.category) &&
                isVisibleInSelectedMapSet(track.mapSetID)
            }
        }
    }

    func importedBoundaries(in mapSetID: UUID) -> [(fileID: UUID, boundary: ImportedBoundary)] {
        importedMapFiles.flatMap { file in
            file.boundaries.compactMap { boundary in
                guard boundary.mapSetID == mapSetID else { return nil }
                return (file.id, boundary)
            }
        }
    }

    func importedMarkers(in mapSetID: UUID) -> [(fileID: UUID, marker: ImportedMarker)] {
        importedMapFiles.flatMap { file in
            file.markers.compactMap { marker in
                guard marker.mapSetID == mapSetID else { return nil }
                return (file.id, marker)
            }
        }
    }

    func importedTracks(in mapSetID: UUID) -> [(fileID: UUID, track: ImportedTrack)] {
        importedMapFiles.flatMap { file in
            file.tracks.compactMap { track in
                guard track.mapSetID == mapSetID else { return nil }
                return (file.id, track)
            }
        }
    }

    func recordedSessions(in mapSetID: UUID) -> [MusterSession] {
        sessions
            .filter { $0.mapSetID == mapSetID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func totalTrackCount(in mapSetID: UUID) -> Int {
        let importedTrackCount = importedTracks(in: mapSetID).count
        let recordedTrackCount = recordedSessions(in: mapSetID).filter(\.hasTrack).count
        return importedTrackCount + recordedTrackCount
    }

    func markerTemplate(withID id: UUID?) -> MarkerTemplate? {
        guard let id else { return nil }

        if let template = markerTemplates.first(where: { $0.id == id }) {
            return template
        }

        if let category = customImportCategories.first(where: { $0.id == id }) {
            return MarkerTemplate(id: category.id, description: category.title, emoji: category.icon)
        }

        return nil
    }

    func importCategoryStyle(for category: ImportCategory) -> ImportCategoryStyle {
        importCategoryStyles.style(for: category)
    }

    func iconForImportCategory(_ category: ImportCategory) -> String {
        switch category {
        case .boundaries, .tracks:
            return ""
        case .waterPoints, .yards, .other:
            return importCategoryStyle(for: category).icon
        }
    }

    func strokeHexForImportCategory(_ category: ImportCategory) -> String? {
        importCategoryStyle(for: category).strokeHex
    }

    func fillHexForImportCategory(_ category: ImportCategory) -> String? {
        if category == .boundaries { return nil }
        return importCategoryStyle(for: category).fillHex
    }

    func save() {
        markDirtyAndScheduleSave()
    }

    func flushPendingSaves() {
        flushSave()
    }

    private func markDirtyAndScheduleSave(now: Date = Date()) {
        hasPendingChanges = true

        if now.timeIntervalSince(lastSaveAt) >= saveBatchInterval {
            flushSave(now: now)
        } else {
            scheduleAutosaveIfNeeded(now: now)
        }
    }

    private func scheduleAutosaveIfNeeded(now: Date = Date()) {
        guard autosaveTask == nil else { return }

        let remaining = max(0, saveBatchInterval - now.timeIntervalSince(lastSaveAt))
        let nanos = UInt64(remaining * 1_000_000_000)

        autosaveTask = Task { @MainActor [weak self] in
            guard nanos > 0 else {
                self?.completeAutosaveTask()
                return
            }

            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }

            self?.completeAutosaveTask()
        }
    }

    @MainActor
    private func completeAutosaveTask() {
        autosaveTask = nil
        flushSave()
    }

    private func flushSave(now: Date = Date()) {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasPendingChanges else {
            lastSaveAt = now
            return
        }

        hasPendingChanges = false
        lastSaveAt = now
        Persistence.save(self, to: "muster_store.json")
    }

    private func configureAutosaveObservers() {
        guard appLifecycleObservers.isEmpty else { return }

        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification
        ]

        appLifecycleObservers = names.map { name in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.flushSave()
                }
            }
        }
    }

    func load() {
        if let loaded: MusterStore = Persistence.load(MusterStore.self, from: "muster_store.json") {
            self.sessions = loaded.sessions
            self.markerTemplates = loaded.markerTemplates
            self.mapMarkers = loaded.mapMarkers
            self.importedMapFiles = loaded.importedMapFiles
            self.mapSets = loaded.mapSets
            self.selectedMapSetID = loaded.selectedMapSetID
            self.importCategoryStyles = loaded.importCategoryStyles
            self.importCategoryVisibility = loaded.importCategoryVisibility
            self.activeSessionID = loaded.activeSessionID
            self.activeSheepTargetMarkerID = loaded.activeSheepTargetMarkerID
            self.showPreviousTracksOnMap = loaded.showPreviousTracksOnMap

            seedDefaultMarkerTemplatesIfNeeded()
            seedDefaultImportCategoryStylesIfNeeded()
            seedDefaultCustomImportCategoriesIfNeeded()
            normalizeImportedMapFilesIfNeeded()
            normalizeMapSetAssignmentsIfNeeded()
            normalizeSessionMapSetAssignmentsIfNeeded()
            normalizeMapMarkerSetAssignmentsIfNeeded()
            normalizeSelectedMapSetIfNeeded()
            validateActiveSheepTarget()
        } else {
            seedDefaultMarkerTemplatesIfNeeded()
            seedDefaultImportCategoryStylesIfNeeded()
            seedDefaultCustomImportCategoriesIfNeeded()
        }

        hasPendingChanges = false
        lastSaveAt = Date()
    }

    // =========================================================
    // MARK: - Smart naming
    // =========================================================

    private static let smartSessionNameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "d MMMM yyyy - h:mma"
        return df
    }()

    func makeSmartSessionName(from date: Date = Date()) -> String {
        Self.smartSessionNameFormatter.string(from: date).lowercased()
    }

    @discardableResult
    func startSmartSession(at date: Date = Date()) -> Bool {
        startSession(name: makeSmartSessionName(from: date))
    }

    // =========================================================
    // MARK: - Map sets
    // =========================================================

    @discardableResult
    func createMapSet(named rawName: String? = nil) -> UUID {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalName = trimmed.isEmpty ? nextMapSetName() : trimmed

        let newSet = MapSet(createdAt: Date(), lastUsedAt: Date(), name: finalName)
        mapSets.insert(newSet, at: 0)
        selectedMapSetID = newSet.id
        save()
        return newSet.id
    }

    var selectedMapSet: MapSet? {
        guard let selectedMapSetID else { return nil }
        return mapSets.first(where: { $0.id == selectedMapSetID })
    }

    var canStartMusterOrTrack: Bool {
        selectedMapSet != nil
    }

    func selectMapSet(_ mapSetID: UUID) {
        guard let index = mapSets.firstIndex(where: { $0.id == mapSetID }) else { return }
        selectedMapSetID = mapSetID
        mapSets[index].lastUsedAt = Date()
        save()
    }

    func duplicateMapSet(mapSetID: UUID) -> MapSet? {
        guard let source = mapSets.first(where: { $0.id == mapSetID }) else { return nil }

        var duplicate = source
        duplicate.id = UUID()
        duplicate.createdAt = Date()
        duplicate.lastUsedAt = nil
        duplicate.name = "\(source.displayTitle) Copy"

        mapSets.insert(duplicate, at: 0)

        importedMapFiles = importedMapFiles.map { file in
            var updatedFile = file
            updatedFile.boundaries = file.boundaries.map { boundary in
                var updated = boundary
                if boundary.mapSetID == source.id {
                    updated.mapSetID = duplicate.id
                }
                return updated
            }
            updatedFile.markers = file.markers.map { marker in
                var updated = marker
                if marker.mapSetID == source.id {
                    updated.mapSetID = duplicate.id
                }
                return updated
            }
            updatedFile.tracks = file.tracks.map { track in
                var updated = track
                if track.mapSetID == source.id {
                    updated.mapSetID = duplicate.id
                }
                return updated
            }
            return updatedFile
        }

        sessions = sessions.map { session in
            var updated = session
            if session.mapSetID == source.id {
                updated.mapSetID = duplicate.id
            }
            return updated
        }

        mapMarkers += mapMarkers.compactMap { marker in
            guard marker.mapSetID == source.id else { return nil }
            var duplicateMarker = marker
            duplicateMarker.id = UUID()
            duplicateMarker.createdAt = Date()
            duplicateMarker.mapSetID = duplicate.id
            return duplicateMarker
        }

        save()
        return duplicate
    }

    func renameMapSet(mapSetID: UUID, newName: String) {
        guard let index = mapSets.firstIndex(where: { $0.id == mapSetID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mapSets[index].name = trimmed
        save()
    }

    func deleteMapSet(mapSetID: UUID) {
        guard mapSets.contains(where: { $0.id == mapSetID }) else { return }

        let replacementMapSetID = fallbackMapSetID(excluding: mapSetID)

        importedMapFiles = importedMapFiles.map { file in
            var updated = file
            updated.boundaries = file.boundaries.map { boundary in
                var value = boundary
                if value.mapSetID == mapSetID {
                    value.mapSetID = nil
                }
                return value
            }
            updated.markers = file.markers.map { marker in
                var value = marker
                if value.mapSetID == mapSetID {
                    value.mapSetID = nil
                }
                return value
            }
            updated.tracks = file.tracks.map { track in
                var value = track
                if value.mapSetID == mapSetID {
                    value.mapSetID = replacementMapSetID
                }
                return value
            }
            return updated
        }

        sessions = sessions.map { session in
            var updated = session
            if updated.mapSetID == mapSetID {
                updated.mapSetID = replacementMapSetID
            }
            return updated
        }

        mapMarkers = mapMarkers.map { marker in
            var updated = marker
            if updated.mapSetID == mapSetID {
                updated.mapSetID = replacementMapSetID
            }
            return updated
        }

        mapSets.removeAll { $0.id == mapSetID }
        if selectedMapSetID == mapSetID {
            selectedMapSetID = mapSets.first?.id
        }
        save()
    }

    func assignImportedBoundary(fileID: UUID, boundaryID: UUID, to mapSetID: UUID?) {
        guard mapSetID == nil || mapSets.contains(where: { $0.id == mapSetID }) else { return }
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let boundaryIndex = importedMapFiles[fileIndex].boundaries.firstIndex(where: { $0.id == boundaryID }) else { return }

        importedMapFiles[fileIndex].boundaries[boundaryIndex].mapSetID = mapSetID
        save()
    }

    func assignImportedMarker(fileID: UUID, markerID: UUID, to mapSetID: UUID?) {
        guard mapSetID == nil || mapSets.contains(where: { $0.id == mapSetID }) else { return }
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let markerIndex = importedMapFiles[fileIndex].markers.firstIndex(where: { $0.id == markerID }) else { return }

        importedMapFiles[fileIndex].markers[markerIndex].mapSetID = mapSetID
        save()
    }

    func assignImportedTrack(fileID: UUID, trackID: UUID, to mapSetID: UUID) {
        guard mapSets.contains(where: { $0.id == mapSetID }) else { return }
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let trackIndex = importedMapFiles[fileIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }

        importedMapFiles[fileIndex].tracks[trackIndex].mapSetID = mapSetID
        save()
    }

    func fileID(containingTrackID trackID: UUID) -> UUID? {
        importedMapFiles.first(where: { file in
            file.tracks.contains(where: { $0.id == trackID })
        })?.id
    }

    func renameImportedTrack(trackID: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for fileIndex in importedMapFiles.indices {
            if let trackIndex = importedMapFiles[fileIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                importedMapFiles[fileIndex].tracks[trackIndex].name = trimmed
                save()
                return
            }
        }
    }

    func renameSession(sessionID: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[sessionIndex].name = trimmed
        save()
    }

    func moveSession(sessionID: UUID, to mapSetID: UUID) {
        guard mapSets.contains(where: { $0.id == mapSetID }) else { return }
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[sessionIndex].mapSetID = mapSetID
        save()
    }

    func mapSetName(for id: UUID?) -> String {
        guard let id, let mapSet = mapSets.first(where: { $0.id == id }) else { return "None" }
        return mapSet.displayTitle
    }

    // =========================================================
    // MARK: - Imported map files
    // =========================================================

    func addImportedMapFile(_ file: ImportedMapFile) {
        guard file.hasContent else { return }
        let normalized = assigningRequiredTrackMapSet(to: file.applyingAssignedCategoryToChildren())
        importedMapFiles.insert(normalized, at: 0)
        save()
    }

    func addImportedMapFile(_ file: ImportedMapFile, assignedCategory: ImportCategory) {
        guard file.hasContent else { return }

        var updated = file
        updated.assignedCategory = assignedCategory
        if assignedCategory != .other {
            updated.assignedCustomCategoryID = nil
        }
        updated = updated.applyingAssignedCategoryToChildren()
        updated = assigningRequiredTrackMapSet(to: updated)

        importedMapFiles.insert(updated, at: 0)
        save()
    }

    func replaceImportedMapFile(_ file: ImportedMapFile) {
        guard let index = importedMapFiles.firstIndex(where: { $0.id == file.id }) else { return }
        importedMapFiles[index] = assigningRequiredTrackMapSet(to: file.applyingAssignedCategoryToChildren())
        save()
    }

    func replaceImportedMapFile(_ file: ImportedMapFile, assignedCategory: ImportCategory) {
        guard let index = importedMapFiles.firstIndex(where: { $0.id == file.id }) else { return }

        var updated = file
        updated.assignedCategory = assignedCategory
        if assignedCategory != .other {
            updated.assignedCustomCategoryID = nil
        }
        updated = updated.applyingAssignedCategoryToChildren()
        updated = assigningRequiredTrackMapSet(to: updated)

        importedMapFiles[index] = updated
        save()
    }

    func deleteImportedMapFile(fileID: UUID) {
        importedMapFiles.removeAll { $0.id == fileID }
        save()
    }

    func renameImportedMapFile(fileID: UUID, newName: String?) {
        guard let index = importedMapFiles.firstIndex(where: { $0.id == fileID }) else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        importedMapFiles[index].fileName = trimmed
        save()
    }

    func setImportedMapFileVisibility(fileID: UUID, isVisible: Bool) {
        guard let index = importedMapFiles.firstIndex(where: { $0.id == fileID }) else { return }
        importedMapFiles[index].isVisible = isVisible
        save()
    }

    func toggleImportedMapFileVisibility(fileID: UUID) {
        guard let index = importedMapFiles.firstIndex(where: { $0.id == fileID }) else { return }
        importedMapFiles[index].isVisible.toggle()
        save()
    }

    func showAllImportedMapFiles() {
        var changed = false
        for i in importedMapFiles.indices {
            if importedMapFiles[i].isVisible == false {
                importedMapFiles[i].isVisible = true
                changed = true
            }
        }
        if changed { save() }
    }

    func hideAllImportedMapFiles() {
        var changed = false
        for i in importedMapFiles.indices {
            if importedMapFiles[i].isVisible == true {
                importedMapFiles[i].isVisible = false
                changed = true
            }
        }
        if changed { save() }
    }

    func deleteAllImportedMapFiles() {
        guard !importedMapFiles.isEmpty else { return }
        importedMapFiles.removeAll()
        save()
    }

    func setImportedMapFileAssignedCategory(fileID: UUID, category: ImportCategory) {
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }) else { return }

        importedMapFiles[fileIndex].assignedCategory = category
        if category != .other {
            importedMapFiles[fileIndex].assignedCustomCategoryID = nil
        }
        importedMapFiles[fileIndex] = importedMapFiles[fileIndex].applyingAssignedCategoryToChildren()
        save()
    }

    func setImportedBoundaryVisibility(fileID: UUID, boundaryID: UUID, isVisible: Bool) {
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let boundaryIndex = importedMapFiles[fileIndex].boundaries.firstIndex(where: { $0.id == boundaryID }) else { return }

        importedMapFiles[fileIndex].boundaries[boundaryIndex].isVisible = isVisible
        save()
    }

    func setImportedMarkerVisibility(fileID: UUID, markerID: UUID, isVisible: Bool) {
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let markerIndex = importedMapFiles[fileIndex].markers.firstIndex(where: { $0.id == markerID }) else { return }

        importedMapFiles[fileIndex].markers[markerIndex].isVisible = isVisible
        save()
    }

    func setImportedTrackVisibility(fileID: UUID, trackID: UUID, isVisible: Bool) {
        guard let fileIndex = importedMapFiles.firstIndex(where: { $0.id == fileID }),
              let trackIndex = importedMapFiles[fileIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }

        importedMapFiles[fileIndex].tracks[trackIndex].isVisible = isVisible
        save()
    }

    func deleteImportedTrack(trackID: UUID) {
        var changed = false

        for fileIndex in importedMapFiles.indices {
            let originalCount = importedMapFiles[fileIndex].tracks.count
            importedMapFiles[fileIndex].tracks.removeAll { $0.id == trackID }

            if importedMapFiles[fileIndex].tracks.count != originalCount {
                changed = true
            }
        }

        if changed { save() }
    }

    // =========================================================
    // MARK: - Imported category filters / styling
    // =========================================================

    private func seedDefaultImportCategoryStylesIfNeeded() {
        var merged: [ImportCategoryStyle] = []

        for category in ImportCategory.allCases {
            if let existing = importCategoryStyles.first(where: { $0.category == category }) {
                var normalized = existing

                if category == .boundaries || category == .tracks {
                    normalized.icon = ""
                } else {
                    let trimmedIcon = normalized.icon.trimmingCharacters(in: .whitespacesAndNewlines)
                    normalized.icon = trimmedIcon.isEmpty ? category.defaultIcon : trimmedIcon
                }

                if category.supportsColor == false {
                    normalized.strokeHex = nil
                    normalized.fillHex = nil
                } else if category == .boundaries {
                    if (normalized.strokeHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        normalized.strokeHex = category.defaultStrokeHex
                    }
                    normalized.fillHex = nil
                } else {
                    if (normalized.strokeHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        normalized.strokeHex = category.defaultStrokeHex
                    }
                    if (normalized.fillHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        normalized.fillHex = category.defaultFillHex
                    }
                }

                merged.append(normalized)
            } else {
                merged.append(ImportCategoryStyle(category: category))
            }
        }

        importCategoryStyles = merged
    }

    private func normalizeImportedMapFilesIfNeeded() {
        importedMapFiles = importedMapFiles.map { file in
            var normalized = file

            if normalized.boundaries.isEmpty == false && normalized.assignedCategory == .other {
                normalized.assignedCategory = .boundaries
                normalized.assignedCustomCategoryID = nil
            } else if normalized.tracks.isEmpty == false && normalized.assignedCategory == .other {
                normalized.assignedCategory = .tracks
                normalized.assignedCustomCategoryID = nil
            } else if normalized.markers.isEmpty == false && normalized.assignedCategory == .other {
                let markerCategories = Set(normalized.markers.map(\.category))
                if markerCategories == [.waterPoints] {
                    normalized.assignedCategory = .waterPoints
                    normalized.assignedCustomCategoryID = nil
                } else if markerCategories == [.yards] {
                    normalized.assignedCategory = .yards
                    normalized.assignedCustomCategoryID = nil
                }
            }

            normalized = normalized.applyingAssignedCategoryToChildren()
            return normalized
        }
    }

    private func normalizeMapSetAssignmentsIfNeeded() {
        importedMapFiles = importedMapFiles.map { assigningRequiredTrackMapSet(to: $0) }
    }

    private func normalizeSessionMapSetAssignmentsIfNeeded() {
        guard sessions.isEmpty == false else { return }

        let fallbackID = fallbackMapSetID()
        sessions = sessions.map { session in
            var value = session
            if let id = value.mapSetID, mapSets.contains(where: { $0.id == id }) {
                return value
            }

            value.mapSetID = fallbackID
            return value
        }
    }

    private func normalizeMapMarkerSetAssignmentsIfNeeded() {
        guard mapMarkers.isEmpty == false else { return }

        let fallbackID = fallbackMapSetID()
        mapMarkers = mapMarkers.map { marker in
            var value = marker
            if let id = value.mapSetID, mapSets.contains(where: { $0.id == id }) {
                return value
            }

            value.mapSetID = fallbackID
            return value
        }
    }

    private func normalizeSelectedMapSetIfNeeded() {
        if let selectedMapSetID, mapSets.contains(where: { $0.id == selectedMapSetID }) {
            return
        }
        selectedMapSetID = nil
    }

    private func assigningRequiredTrackMapSet(to file: ImportedMapFile) -> ImportedMapFile {
        var updated = file
        guard updated.tracks.isEmpty == false else { return updated }

        let mapSetID = fallbackMapSetID()

        updated.tracks = updated.tracks.map { track in
            var value = track
            if value.mapSetID == nil || mapSets.contains(where: { $0.id == value.mapSetID }) == false {
                value.mapSetID = mapSetID
            }
            return value
        }

        updated.boundaries = updated.boundaries.map { boundary in
            var value = boundary
            if let id = value.mapSetID, mapSets.contains(where: { $0.id == id }) == false {
                value.mapSetID = nil
            }
            return value
        }

        updated.markers = updated.markers.map { marker in
            var value = marker
            if let id = value.mapSetID, mapSets.contains(where: { $0.id == id }) == false {
                value.mapSetID = nil
            }
            return value
        }

        return updated
    }

    private func fallbackMapSetID(excluding excludedID: UUID? = nil) -> UUID {
        if let existing = mapSets.first(where: { $0.id != excludedID }) {
            return existing.id
        }

        let newID = UUID()
        mapSets.insert(MapSet(id: newID, createdAt: Date(), lastUsedAt: nil, name: nextMapSetName()), at: 0)
        return newID
    }

    private func isVisibleInSelectedMapSet(_ mapSetID: UUID?) -> Bool {
        guard let selectedMapSetID else { return true }
        return mapSetID == selectedMapSetID
    }

    private func nextMapSetName() -> String {
        let names = Set(mapSets.map { $0.displayTitle.lowercased() })
        var index = 1
        while names.contains("map set \(index)") {
            index += 1
        }
        return "Map Set \(index)"
    }

    func isImportCategoryVisible(_ category: ImportCategory) -> Bool {
        importCategoryVisibility.isVisible(category)
    }

    func setImportCategoryVisibility(_ isVisible: Bool, for category: ImportCategory) {
        importCategoryVisibility.setVisible(isVisible, for: category)
        save()
    }

    func toggleImportCategoryVisibility(_ category: ImportCategory) {
        let current = importCategoryVisibility.isVisible(category)
        importCategoryVisibility.setVisible(!current, for: category)
        save()
    }

    func showAllImportCategories() {
        var updated = importCategoryVisibility
        var changed = false

        for category in ImportCategory.allCases {
            if updated.isVisible(category) == false {
                updated.setVisible(true, for: category)
                changed = true
            }
        }

        if changed {
            importCategoryVisibility = updated
            save()
        }
    }

    func hideAllImportCategories() {
        var updated = importCategoryVisibility
        var changed = false

        for category in ImportCategory.allCases {
            if updated.isVisible(category) == true {
                updated.setVisible(false, for: category)
                changed = true
            }
        }

        if changed {
            importCategoryVisibility = updated
            save()
        }
    }

    func addCustomImportCategory(title: String, icon: String, isVisibleByDefault: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalIcon = trimmedIcon.isEmpty ? "📍" : trimmedIcon

        customImportCategories.append(
            CustomImportCategory(
                title: trimmedTitle,
                icon: finalIcon,
                isVisibleByDefault: isVisibleByDefault
            )
        )
        save()
    }

    func updateCustomImportCategory(id: UUID, title: String, icon: String, isVisibleByDefault: Bool) {
        guard let index = customImportCategories.firstIndex(where: { $0.id == id }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        customImportCategories[index].title = trimmedTitle
        customImportCategories[index].icon = trimmedIcon.isEmpty ? "📍" : trimmedIcon
        customImportCategories[index].isVisibleByDefault = isVisibleByDefault
        save()
    }

    func deleteCustomImportCategory(id: UUID) {
        let originalCount = customImportCategories.count
        customImportCategories.removeAll { $0.id == id }

        if customImportCategories.count != originalCount {
            seedDefaultCustomImportCategoriesIfNeeded()
            save()
        }
    }
    private func applyCurrentCategoryStylesToExistingImports() {
        importedMapFiles = importedMapFiles.map { file in
            var updatedFile = file

            updatedFile.boundaries = updatedFile.boundaries.map { boundary in
                var updated = boundary
                let style = importCategoryStyle(for: updated.category)

                if updated.category.supportsColor {
                    updated.strokeHex = style.strokeHex

                    if updated.category == .boundaries {
                        updated.fillHex = nil
                    } else {
                        updated.fillHex = style.fillHex
                    }
                } else {
                    updated.strokeHex = nil
                    updated.fillHex = nil
                }

                return updated
            }

            updatedFile.markers = updatedFile.markers.map { marker in
                var updated = marker
                let style = importCategoryStyle(for: updated.category)

                if updated.category == .waterPoints || updated.category == .yards || updated.category == .other {
                    let trimmedEmoji = updated.emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if trimmedEmoji.isEmpty {
                        updated.emoji = style.icon
                    }
                }

                return updated
            }

            updatedFile.tracks = updatedFile.tracks.map { track in
                let updated = track
                return updated
            }

            return updatedFile
        }
    }

    func setImportCategoryIcon(_ icon: String, for category: ImportCategory) {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalIcon = trimmed.isEmpty ? category.defaultIcon : trimmed

        if let index = importCategoryStyles.firstIndex(where: { $0.category == category }) {
            importCategoryStyles[index].icon = finalIcon
        } else {
            importCategoryStyles.append(
                ImportCategoryStyle(category: category, icon: finalIcon)
            )
            seedDefaultImportCategoryStylesIfNeeded()
        }

        applyCurrentCategoryStylesToExistingImports()
        save()
    }

    func setImportCategoryStrokeHex(_ hex: String?, for category: ImportCategory) {
        guard category.supportsColor else { return }

        let cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalHex = (cleaned?.isEmpty ?? true) ? category.defaultStrokeHex : cleaned

        if let index = importCategoryStyles.firstIndex(where: { $0.category == category }) {
            importCategoryStyles[index].strokeHex = finalHex
        } else {
            importCategoryStyles.append(
                ImportCategoryStyle(category: category, strokeHex: finalHex)
            )
            seedDefaultImportCategoryStylesIfNeeded()
        }

        save()
    }

    func setImportCategoryFillHex(_ hex: String?, for category: ImportCategory) {
        guard category.supportsColor else { return }

        if category == .boundaries {
            if let index = importCategoryStyles.firstIndex(where: { $0.category == category }) {
                importCategoryStyles[index].fillHex = nil
            } else {
                importCategoryStyles.append(
                    ImportCategoryStyle(category: category, fillHex: nil)
                )
                seedDefaultImportCategoryStylesIfNeeded()
            }

            applyCurrentCategoryStylesToExistingImports()
            save()
            return
        }

        let cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalHex = (cleaned?.isEmpty ?? true) ? category.defaultFillHex : cleaned

        if let index = importCategoryStyles.firstIndex(where: { $0.category == category }) {
            importCategoryStyles[index].fillHex = finalHex
        } else {
            importCategoryStyles.append(
                ImportCategoryStyle(category: category, fillHex: finalHex)
            )
            seedDefaultImportCategoryStylesIfNeeded()
        }

        applyCurrentCategoryStylesToExistingImports()
        save()
    }

    private func seedDefaultCustomImportCategoriesIfNeeded() {
        guard customImportCategories.isEmpty else { return }

        customImportCategories = [
            CustomImportCategory(title: "POI", icon: "📍", isVisibleByDefault: true)
        ]
    }

    // =========================================================
    // MARK: - Default marker templates
    // =========================================================

    private func seedDefaultMarkerTemplatesIfNeeded() {
        guard markerTemplates.isEmpty else { return }

        markerTemplates = [
            MarkerTemplate(description: "Dam", emoji: "🔵"),
            MarkerTemplate(description: "Gate", emoji: "🚪"),
            MarkerTemplate(description: "Tank", emoji: "🔷"),
            MarkerTemplate(description: "Trough", emoji: "🚰"),
            MarkerTemplate(description: "Yards", emoji: "𝐘"),
            MarkerTemplate(description: "Shed", emoji: "🏠"),
            MarkerTemplate(description: "Hazard", emoji: "⚠️"),
            MarkerTemplate(description: "Tree", emoji: "🌳")
        ]
    }

    // =========================================================
    // MARK: - Marker templates
    // =========================================================

    func addMarkerTemplate(description: String, emoji: String) {
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDescription.isEmpty else { return }
        guard !cleanEmoji.isEmpty else { return }

        markerTemplates.append(
            MarkerTemplate(
                description: cleanDescription,
                emoji: cleanEmoji
            )
        )
        save()
    }

    func updateMarkerTemplate(id: UUID, description: String, emoji: String) {
        guard let i = markerTemplates.firstIndex(where: { $0.id == id }) else { return }

        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDescription.isEmpty else { return }
        guard !cleanEmoji.isEmpty else { return }

        markerTemplates[i].description = cleanDescription
        markerTemplates[i].emoji = cleanEmoji
        save()
    }

    func deleteMarkerTemplate(id: UUID) {
        markerTemplates.removeAll { $0.id == id }
        save()
    }

    func moveMarkerTemplates(fromOffsets: IndexSet, toOffset: Int) {
        let sortedOffsets = fromOffsets.sorted()
        let movingItems = sortedOffsets.map { markerTemplates[$0] }

        for index in sortedOffsets.reversed() {
            markerTemplates.remove(at: index)
        }

        var destination = toOffset
        for index in sortedOffsets where index < toOffset {
            destination -= 1
        }

        destination = max(0, min(destination, markerTemplates.count))
        markerTemplates.insert(contentsOf: movingItems, at: destination)

        save()
    }

    // =========================================================
    // MARK: - Global map markers
    // =========================================================

    func addMapMarker(
        coordinate: CLLocationCoordinate2D,
        templateID: UUID?,
        name: String
    ) {
        let template = markerTemplate(withID: templateID)
        let templateDescription = template?.displayTitle ?? "Marker"

        let trimmedEmoji = template?.emoji.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emoji = trimmedEmoji.isEmpty ? "📍" : trimmedEmoji

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let marker = MapMarker(
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            templateID: templateID,
            templateDescription: templateDescription,
            emoji: emoji,
            name: cleanName,
            mapSetID: selectedMapSetID ?? fallbackMapSetID()
        )

        mapMarkers.append(marker)
        save()
    }

    func updateMapMarker(
        markerID: UUID,
        templateID: UUID?,
        name: String
    ) {
        guard let i = mapMarkers.firstIndex(where: { $0.id == markerID }) else { return }

        let template = markerTemplate(withID: templateID)
        let templateDescription = template?.displayTitle ?? mapMarkers[i].templateDescription

        let trimmedEmoji = template?.emoji.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emoji = trimmedEmoji.isEmpty ? mapMarkers[i].emoji : trimmedEmoji

        mapMarkers[i].templateID = templateID
        mapMarkers[i].templateDescription = templateDescription
        mapMarkers[i].emoji = emoji
        mapMarkers[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // =========================================================
    // MARK: - Previous track visibility
    // =========================================================

    func setPreviousTracksVisible(_ isVisible: Bool) {
        showPreviousTracksOnMap = isVisible
        save()
    }

    func setSessionVisibilityOnMap(sessionID: UUID, isVisible: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        // Active session should remain controlled by live map logic,
        // but we still allow the value to be stored for when it becomes previous.
        sessions[index].isVisibleOnMap = isVisible
        save()
    }

    func toggleSessionVisibilityOnMap(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isVisibleOnMap.toggle()
        save()
    }

    func deleteSession(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[index].id != activeSessionID else { return }

        sessions.remove(at: index)
        save()
    }

    func showAllPreviousSessionsOnMap() {
        var changed = false

        for i in sessions.indices where sessions[i].id != activeSessionID {
            if sessions[i].isVisibleOnMap == false {
                sessions[i].isVisibleOnMap = true
                changed = true
            }
        }

        if showPreviousTracksOnMap == false {
            showPreviousTracksOnMap = true
            changed = true
        }

        if changed { save() }
    }

    func hideAllPreviousSessionsOnMap() {
        var changed = false

        for i in sessions.indices where sessions[i].id != activeSessionID {
            if sessions[i].isVisibleOnMap == true {
                sessions[i].isVisibleOnMap = false
                changed = true
            }
        }

        if changed { save() }
    }

    // =========================================================
    // MARK: - Sheep Pin Settings (UserDefaults)
    // =========================================================

    private enum SheepPinPrefs {
        static let enabledKey = "sheep_pin_enabled"
        static let expirySecondsKey = "sheep_pin_expiry_s"
        static let limitKey = "sheep_pin_limit"
        static let iconKey = "sheep_pin_icon"

        static var enabled: Bool {
            get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
        }

        static var expirySeconds: TimeInterval {
            get {
                let v = UserDefaults.standard.object(forKey: expirySecondsKey) as? Double
                return v ?? 3600
            }
            set { UserDefaults.standard.set(newValue, forKey: expirySecondsKey) }
        }

        static var limit: Int {
            get {
                let v = UserDefaults.standard.object(forKey: limitKey) as? Int
                return v ?? 3
            }
            set { UserDefaults.standard.set(max(1, newValue), forKey: limitKey) }
        }

        static var icon: String {
            get { UserDefaults.standard.string(forKey: iconKey) ?? "sheep" }
            set { UserDefaults.standard.set(newValue, forKey: iconKey) }
        }
    }

    var sheepPinsEnabled: Bool {
        get { SheepPinPrefs.enabled }
        set { SheepPinPrefs.enabled = newValue }
    }

    var sheepPinExpirySeconds: TimeInterval {
        get { SheepPinPrefs.expirySeconds }
        set { SheepPinPrefs.expirySeconds = newValue }
    }

    var sheepPinLimit: Int {
        get { SheepPinPrefs.limit }
        set { SheepPinPrefs.limit = newValue }
    }

    var sheepPinIcon: String {
        get { SheepPinPrefs.icon }
        set { SheepPinPrefs.icon = newValue }
    }

    // =========================================================
    // MARK: - Session lifecycle
    // =========================================================

    @discardableResult
    func startSession(name: String) -> Bool {
        guard canStartMusterOrTrack else { return false }
        if var current = activeSession, current.isActive {
            current.isActive = false
            current.endedAt = Date()
            activeSession = current
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? makeSmartSessionName() : cleanName

        let s = MusterSession(
            name: finalName,
            startedAt: Date(),
            endedAt: nil,
            mapSetID: selectedMapSetID,
            isActive: true,
            isVisibleOnMap: true
        )

        sessions.insert(s, at: 0)
        activeSessionID = s.id
        activeSheepTargetMarkerID = nil
        save()

        GoToLiveActivityManager.shared.startRecording()
        return true
    }

    func stopActiveSession() {
        guard var s = activeSession else { return }
        s.isActive = false
        s.endedAt = Date()
        activeSession = s
        activeSessionID = nil
        activeSheepTargetMarkerID = nil
        save()
        flushPendingSaves()

        Task {
            await GoToLiveActivityManager.shared.stop()
        }
    }

    // =========================================================
    // MARK: - Active sheep target
    // =========================================================

    func setActiveSheepTarget(markerID: UUID) {
        guard let marker = activeSession?.markers.first(where: { $0.id == markerID }) else { return }
        guard marker.type == .sheepPin else { return }
        activeSheepTargetMarkerID = markerID
        save()
    }

    func clearActiveSheepTarget() {
        activeSheepTargetMarkerID = nil
        save()
    }

    private func validateActiveSheepTarget() {
        guard let id = activeSheepTargetMarkerID else { return }
        let stillExists = activeSession?.markers.contains(where: { $0.id == id && $0.type == .sheepPin }) ?? false
        if !stillExists {
            activeSheepTargetMarkerID = nil
        }
    }

    // =========================================================
    // MARK: - Recording logic
    // =========================================================

    private func shouldAcceptRecordedPoint(
        _ loc: CLLocation,
        after lastPoint: TrackPoint?
    ) -> Bool {
        if loc.horizontalAccuracy < 0 { return false }
        if loc.horizontalAccuracy > recordingMaxHorizontalAccuracy { return false }

        guard let lastPoint else { return true }

        let lastLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lastPoint.lat, longitude: lastPoint.lon),
            altitude: lastPoint.elevationM ?? 0,
            horizontalAccuracy: lastPoint.acc,
            verticalAccuracy: -1,
            timestamp: lastPoint.t
        )

        let dist = lastLoc.distance(from: loc)
        let dt = loc.timestamp.timeIntervalSince(lastPoint.t)
        let reportedSpeed = max(loc.speed, 0)

        // Fresh continuation after a long pause / background gap.
        if dt > recordingFreshGapSeconds {
            return true
        }

        // Ignore duplicate or out-of-order timestamps.
        if dt <= 0 {
            return false
        }

        // Ignore tiny GPS jitter.
        if dist < recordingMinDeltaMeters {
            return false
        }

        // Ignore obviously impossible jumps.
        let inferredSpeed = dist / dt
        if inferredSpeed > recordingMaxReasonableSpeedMetersPerSecond {
            return false
        }

        // Ignore little shuffles while basically stationary.
        if reportedSpeed >= 0, reportedSpeed < recordingStationarySpeedThreshold, dist < 6 {
            return false
        }

        // Ignore tiny low-speed drift.
        if reportedSpeed >= 0,
           reportedSpeed < recordingLowSpeedThreshold,
           dist < recordingRejectSmallMoveUnderLowSpeedMeters {
            return false
        }

        return true
    }

    func considerRecording(location loc: CLLocation) {
        guard var s = activeSession, s.isActive else { return }
        guard shouldAcceptRecordedPoint(loc, after: s.points.last) else { return }

        let coord = loc.coordinate
        let altitude: Double? = {
            guard loc.verticalAccuracy >= 0 else { return nil }
            return loc.altitude
        }()

        s.points.append(
            TrackPoint(
                t: loc.timestamp,
                lat: coord.latitude,
                lon: coord.longitude,
                acc: loc.horizontalAccuracy,
                elevationM: altitude
            )
        )
        activeSession = s

        let totalDistanceMeters = totalRecordedDistanceMeters(for: s.points)

        Task {
            await GoToLiveActivityManager.shared.updateRecording(distanceMeters: totalDistanceMeters)
        }

        save()
    }

    private func totalRecordedDistanceMeters(for points: [TrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }

        var total: Double = 0
        var previous = CLLocation(latitude: points[0].lat, longitude: points[0].lon)

        for point in points.dropFirst() {
            let current = CLLocation(latitude: point.lat, longitude: point.lon)
            total += previous.distance(from: current)
            previous = current
        }

        return total
    }

    private func recordedDistanceMetersForDay(
        in points: [TrackPoint],
        from start: Date,
        to end: Date
    ) -> Double {
        guard points.count > 1 else { return 0 }

        var total: Double = 0

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let currentPoint = points[index]

            guard previousPoint.t >= start, previousPoint.t < end,
                  currentPoint.t >= start, currentPoint.t < end else {
                continue
            }

            let previousLocation = CLLocation(latitude: previousPoint.lat, longitude: previousPoint.lon)
            let currentLocation = CLLocation(latitude: currentPoint.lat, longitude: currentPoint.lon)
            total += previousLocation.distance(from: currentLocation)
        }

        return total
    }

    // =========================================================
    // MARK: - General markers
    // =========================================================

    func dropMarker(at coordinate: CLLocationCoordinate2D, type: MarkerType, note: String?) {
        guard var s = activeSession else { return }

        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = (trimmed?.isEmpty ?? true) ? nil : trimmed

        s.markers.append(
            MusterMarker(
                t: Date(),
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                type: type,
                note: cleanNote
            )
        )
        activeSession = s
        save()
    }

    // =========================================================
    // MARK: - Sheep temporary pins
    // =========================================================

    @discardableResult
    func dropSheepPin(at location: CLLocation, sheepCountEstimate: Int? = nil) -> UUID? {
        guard SheepPinPrefs.enabled else { return nil }

        if activeSession == nil {
            startSmartSession()
        }

        guard var s = activeSession else { return nil }

        let newMarker = MusterMarker(
            t: Date(),
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            type: .sheepPin,
            note: nil,
            sheepCountEstimate: sheepCountEstimate
        )

        s.markers.append(newMarker)
        s.markers = applySheepPinRules(to: s.markers, now: Date())

        activeSession = s

        // Do NOT automatically start Go To or set this new sheep pin as active target.
        // A user tap on an existing sheep pin should do that instead.
        validateActiveSheepTarget()
        save()

        let stillExists = s.markers.contains(where: { $0.id == newMarker.id })
        return stillExists ? newMarker.id : nil
    }

    func updateSheepCountEstimate(
        markerID: UUID,
        in sessionID: UUID? = nil,
        sheepCountEstimate: Int?
    ) {
        let targetSessionID = sessionID ?? activeSessionID
        guard let targetSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == targetSessionID }),
              let markerIndex = sessions[sessionIndex].markers.firstIndex(where: { $0.id == markerID }) else { return }

        guard sessions[sessionIndex].markers[markerIndex].type == .sheepPin else { return }

        sessions[sessionIndex].markers[markerIndex].sheepCountEstimate = sheepCountEstimate
        save()
    }

    func tickSheepPinMaintenance() {
        guard SheepPinPrefs.enabled else { return }
        guard var s = activeSession else { return }

        let updated = applySheepPinRules(to: s.markers, now: Date())
        if updated != s.markers {
            s.markers = updated
            activeSession = s
            validateActiveSheepTarget()
            save()
        } else {
            validateActiveSheepTarget()
        }
    }

    private func applySheepPinRules(to markers: [MusterMarker], now: Date) -> [MusterMarker] {
        let expiry = SheepPinPrefs.expirySeconds
        let limit = SheepPinPrefs.limit

        let filtered = markers.filter { m in
            guard m.type == .sheepPin else { return true }
            return now.timeIntervalSince(m.t) <= expiry
        }

        var sheepPins: [MusterMarker] = []
        var others: [MusterMarker] = []

        sheepPins.reserveCapacity(filtered.count)
        others.reserveCapacity(filtered.count)

        for m in filtered {
            if m.type == .sheepPin {
                sheepPins.append(m)
            } else {
                others.append(m)
            }
        }

        if sheepPins.count <= limit {
            return others + sheepPins
        }

        sheepPins.sort { $0.t < $1.t }
        let keep = Array(sheepPins.suffix(limit))
        return others + keep
    }
}
