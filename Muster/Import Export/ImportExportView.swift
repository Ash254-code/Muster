import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportExportView: View {
    @EnvironmentObject private var app: AppState

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case geoJSON
        case gpx

        var id: String { rawValue }

        var title: String {
            switch self {
            case .geoJSON: return "GeoJSON"
            case .gpx: return "GPX"
            }
        }

        var fileExtension: String {
            switch self {
            case .geoJSON: return "geojson"
            case .gpx: return "gpx"
            }
        }
    }

    private struct PendingImportedFile: Identifiable {
        let id = UUID()
        let sourceURL: URL
        let file: ImportedMapFile
        let allowedCategories: [ImportCategory]
    }

    @State private var showImporter = false
    @State private var showImportCategoryPicker = false
    @State private var applyCategoryToAllPendingImports = false

    @State private var alertTitle: String = ""
    @State private var alertMessage: String? = nil

    @State private var shareURL: URL? = nil
    @State private var shareSheetItems: [Any] = []
    @State private var showExportFormatPicker = false
    @State private var showTrackExportSheet = false
    @State private var selectedExportFormat: ExportFormat? = nil
    @State private var selectedExportSessionID: UUID? = nil

    @State private var pendingImports: [PendingImportedFile] = []
    @State private var currentPendingImport: PendingImportedFile? = nil

    @State private var importResultImportedCount: Int = 0
    @State private var importResultFailedFiles: [String] = []
    @State private var importResultImportedBoundaries: Int = 0
    @State private var importResultImportedMarkers: Int = 0
    @State private var importResultImportedTracks: Int = 0
    @State private var importResultSelectedCount: Int = 0
    @State private var importResultSupportedCount: Int = 0

    private var importedFileCount: Int {
        app.muster.importedMapFiles.count
    }

    private var visibleImportedFileCount: Int {
        app.muster.visibleImportedMapFiles.count
    }

    private var boundaryCount: Int {
        app.muster.importedMapFiles.reduce(0) { $0 + $1.boundaries.count }
    }

    private var markerCount: Int {
        app.muster.importedMapFiles.reduce(0) { $0 + $1.markers.count }
    }

    private var trackCount: Int {
        app.muster.importedMapFiles.reduce(0) { $0 + $1.tracks.count }
    }

    private var exportableSessions: [MusterSession] {
        app.muster.sessions
            .filter { !$0.points.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Files or Folder", systemImage: "square.and.arrow.down")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Supported import formats")
                        .font(.subheadline.weight(.semibold))

                    Text("GeoJSON, GPX, KML and KMZ")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                }
                .padding(.vertical, 2)
            } header: {
                Text("Import")
            } footer: {
                Text("Use this to bring in paddock boundaries, markers and tracks from existing files.")
            }

            Section {
                Button {
                    showExportFormatPicker = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(exportableSessions.isEmpty)

                .padding(.vertical, 2)
            } header: {
                Text("Export")
            } footer: {
                Text("Choose a format first, then pick a previous or active track to export.")
            }

            Section {
                LabeledContent("Imported files", value: "\(importedFileCount)")
                LabeledContent("Visible on map", value: "\(visibleImportedFileCount)")
                LabeledContent("Boundaries", value: "\(boundaryCount)")
                LabeledContent("Markers", value: "\(markerCount)")
                LabeledContent("Tracks", value: "\(trackCount)")
            } header: {
                Text("Imported Data")
            }

            Section {
                Button {
                    app.muster.showAllImportedMapFiles()
                } label: {
                    Text("Show All Imported Files")
                }
                .disabled(importedFileCount == 0)

                Button {
                    app.muster.hideAllImportedMapFiles()
                } label: {
                    Text("Hide All Imported Files")
                }
                .disabled(importedFileCount == 0)
            } header: {
                Text("Manage Visibility")
            }

            Section {
                if app.muster.importedMapFiles.isEmpty {
                    Text("No imported files yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.muster.importedMapFiles) { file in
                        NavigationLink {
                            ImportedMapFileDetailView(fileID: file.id)
                                .environmentObject(app)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(file.displayTitle)
                                            .foregroundStyle(.primary)

                                        Text(file.format.title)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.thinMaterial, in: Capsule())
                                    }

                                    HStack(spacing: 8) {
                                        if file.assignedCategory == .waterPoints ||
                                            file.assignedCategory == .yards ||
                                            file.assignedCategory == .other {
                                            Text(categoryIcon(for: file.assignedCategory))
                                        }

                                        Text(file.assignedCategory.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("\(file.boundaries.count) boundaries • \(file.markers.count) markers • \(file.tracks.count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { file.isVisible },
                                        set: { app.muster.setImportedMapFileVisibility(fileID: file.id, isVisible: $0) }
                                    )
                                )
                                .labelsHidden()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { app.muster.importedMapFiles[$0].id }
                        for id in ids {
                            app.muster.deleteImportedMapFile(fileID: id)
                        }
                    }
                }
            } header: {
                Text("Imported Files")
            } footer: {
                Text("Imported files are stored in the app and can be shown or hidden on the map.")
            }
        }
        .navigationTitle("Imported Maps & Tracks")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                .json,
                .xml,
                .data,
                .item,
                .folder
            ],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result: result)
        }
        .sheet(isPresented: $showImportCategoryPicker) {
            importCategoryPickerSheet
        }
        .confirmationDialog(
            "Export Format",
            isPresented: $showExportFormatPicker,
            titleVisibility: .visible
        ) {
            ForEach(ExportFormat.allCases) { format in
                Button(format.title) {
                    selectedExportFormat = format
                    selectedExportSessionID = nil
                    showTrackExportSheet = true
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the file format for export.")
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { !shareSheetItems.isEmpty },
                set: { presented in
                    if !presented {
                        shareSheetItems = []
                        shareURL = nil
                    }
                }
            )
        ) {
            ActivityView(activityItems: shareSheetItems)
        }
        .sheet(isPresented: $showTrackExportSheet) {
            NavigationStack {
                ExportTrackPickerView(
                    sessions: exportableSessions,
                    selectedSessionID: $selectedExportSessionID
                ) {
                    exportSelectedTrack()
                }
            }
        }
    }


    @ViewBuilder
    private var importCategoryPickerSheet: some View {
        NavigationStack {
            List {
                if let pending = currentPendingImport {
                    Section {
                        ForEach(pending.allowedCategories, id: \.self) { category in
                            Button {
                                applyImportCategory(category)
                            } label: {
                                HStack {
                                    Text("\(categoryIcon(for: category)) \(category.title)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text(importCategoryDialogTitle)
                    } footer: {
                        Text(importCategoryDialogMessage)
                    }

                    Section {
                        Toggle("Apply to all remaining imports", isOn: $applyCategoryToAllPendingImports)
                    }
                }
            }
            .navigationTitle("Choose Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel Import") {
                        cancelCurrentImportSelection()
                    }
                }
            }
        }
    }

    // MARK: - Import

    private var importCategoryDialogTitle: String {
        "Choose Category"
    }

    private var importCategoryDialogMessage: String {
        guard let pending = currentPendingImport else { return "" }
        return "Assign “\(pending.file.displayTitle)” to a category before importing."
    }

    private func handleImport(result: Result<[URL], Error>) {
        do {
            let selectedURLs = try result.get()
            guard !selectedURLs.isEmpty else { return }

            importResultImportedCount = 0
            importResultFailedFiles = []
            importResultImportedBoundaries = 0
            importResultImportedMarkers = 0
            importResultImportedTracks = 0
            importResultSelectedCount = selectedURLs.count
            importResultSupportedCount = 0
            pendingImports = []
            currentPendingImport = nil
            showImportCategoryPicker = false
            applyCategoryToAllPendingImports = false

            var scopedURLs: [URL] = []
            for url in selectedURLs {
                if url.startAccessingSecurityScopedResource() {
                    scopedURLs.append(url)
                }
            }

            defer {
                for url in scopedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let importableURLs = collectImportableFiles(from: selectedURLs)
            importResultSupportedCount = importableURLs.count

            if importableURLs.isEmpty {
                alertTitle = "Nothing to Import"
                alertMessage = "No supported import files were found. Supported formats are GeoJSON, GPX, KML and KMZ."
                return
            }

            for url in importableURLs {
                do {
                    let data = try Data(contentsOf: url)
                    let importedFile = try MapImportService.importFile(from: url, data: data)
                    let allowedCategories = MapImportService.suggestedCategories(for: importedFile)

                    pendingImports.append(
                        PendingImportedFile(
                            sourceURL: url,
                            file: importedFile,
                            allowedCategories: allowedCategories
                        )
                    )
                } catch {
                    importResultFailedFiles.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if pendingImports.isEmpty {
                finishImportFlow()
            } else {
                presentNextPendingImport()
            }
        } catch {
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
        }
    }

    private func presentNextPendingImport() {
        guard !pendingImports.isEmpty else {
            currentPendingImport = nil
            showImportCategoryPicker = false
            applyCategoryToAllPendingImports = false
            finishImportFlow()
            return
        }

        currentPendingImport = pendingImports.removeFirst()
        showImportCategoryPicker = true
    }

    private func applyImportCategory(_ category: ImportCategory) {
        guard let pending = currentPendingImport else { return }

        importPendingFile(pending, as: category)

        if applyCategoryToAllPendingImports {
            let applicable = pendingImports.filter { $0.allowedCategories.contains(category) }
            for item in applicable {
                importPendingFile(item, as: category)
            }
            pendingImports.removeAll { $0.allowedCategories.contains(category) }
        }

        currentPendingImport = nil
        showImportCategoryPicker = false
        applyCategoryToAllPendingImports = false

        DispatchQueue.main.async {
            presentNextPendingImport()
        }
    }

    private func importPendingFile(_ pending: PendingImportedFile, as category: ImportCategory) {
        let adjustedFile = remapImportedFile(pending.file, to: category)

        app.muster.addImportedMapFile(
            adjustedFile,
            assignedCategory: category
        )

        importResultImportedCount += 1
        importResultImportedBoundaries += adjustedFile.boundaries.count
        importResultImportedMarkers += adjustedFile.markers.count
        importResultImportedTracks += adjustedFile.tracks.count
    }

    private func remapImportedFile(_ file: ImportedMapFile, to category: ImportCategory) -> ImportedMapFile {
        switch category {
        case .boundaries:
            var boundaries = file.boundaries

            let convertedTracks: [ImportedBoundary] = file.tracks.compactMap { track in
                let ring = closedRing(from: track.points)
                guard ring.count >= 4 else { return nil }

                return ImportedBoundary(
                    name: track.displayTitle,
                    category: .boundaries,
                    geometryKind: .polygon,
                    rings: [ring],
                    strokeHex: app.muster.strokeHexForImportCategory(.boundaries),
                    fillHex: nil,
                    isVisible: true
                )
            }

            boundaries = boundaries.map { boundary in
                var updated = boundary
                updated.category = .boundaries
                if updated.strokeHex == nil {
                    updated.strokeHex = app.muster.strokeHexForImportCategory(.boundaries)
                }
                updated.fillHex = nil
                return updated
            }
            boundaries.append(contentsOf: convertedTracks)

            let remainingTracks = file.tracks.filter { track in
                closedRing(from: track.points).count < 4
            }

            let updatedMarkers = file.markers.map { marker in
                var updated = marker
                updated.category = .boundaries
                return updated
            }

            return ImportedMapFile(
                id: file.id,
                importedAt: file.importedAt,
                fileName: file.fileName,
                format: file.format,
                assignedCategory: .boundaries,
                boundaries: boundaries,
                markers: updatedMarkers,
                tracks: remainingTracks,
                isVisible: file.isVisible
            )

        case .tracks:
            let updatedTracks = file.tracks.map { track in
                var updated = track
                updated.category = .tracks
                return updated
            }

            let updatedBoundaries = file.boundaries.map { boundary in
                var updated = boundary
                updated.category = .tracks
                updated.fillHex = nil
                return updated
            }

            let updatedMarkers = file.markers.map { marker in
                var updated = marker
                updated.category = .tracks
                return updated
            }

            return ImportedMapFile(
                id: file.id,
                importedAt: file.importedAt,
                fileName: file.fileName,
                format: file.format,
                assignedCategory: .tracks,
                boundaries: updatedBoundaries,
                markers: updatedMarkers,
                tracks: updatedTracks,
                isVisible: file.isVisible
            )

        case .waterPoints, .yards, .other:
            let updatedMarkers = file.markers.map { marker in
                var updated = marker
                updated.category = category
                return updated
            }

            let updatedBoundaries = file.boundaries.map { boundary in
                var updated = boundary
                updated.category = category
                return updated
            }

            let updatedTracks = file.tracks.map { track in
                var updated = track
                updated.category = category
                return updated
            }

            return ImportedMapFile(
                id: file.id,
                importedAt: file.importedAt,
                fileName: file.fileName,
                format: file.format,
                assignedCategory: category,
                boundaries: updatedBoundaries,
                markers: updatedMarkers,
                tracks: updatedTracks,
                isVisible: file.isVisible
            )
        }
    }

    private func closedRing(from points: [CodableCoordinate]) -> [CodableCoordinate] {
        guard points.count >= 3 else { return [] }

        var ring = points

        if let first = ring.first, let last = ring.last {
            let closesAlready =
                abs(first.lat - last.lat) < 0.0000001 &&
                abs(first.lon - last.lon) < 0.0000001

            if !closesAlready {
                ring.append(first)
            }
        }

        return ring.count >= 4 ? ring : []
    }

    private func cancelCurrentImportSelection() {
        if let pending = currentPendingImport {
            importResultFailedFiles.append("\(pending.sourceURL.lastPathComponent): Import cancelled before category selection.")
        }

        currentPendingImport = nil
        showImportCategoryPicker = false
        applyCategoryToAllPendingImports = false

        DispatchQueue.main.async {
            presentNextPendingImport()
        }
    }

    private func finishImportFlow() {
        let importedCount = importResultImportedCount
        let failedFiles = importResultFailedFiles
        let totalHandled = importResultSupportedCount
        let skippedCount = max(0, totalHandled - importedCount - failedFiles.count)

        alertTitle = importedCount > 0 ? "Import Complete" : "Import Failed"

        var lines: [String] = []
        lines.append("Selected \(importResultSelectedCount) item\(importResultSelectedCount == 1 ? "" : "s").")
        lines.append("Found \(importResultSupportedCount) supported file\(importResultSupportedCount == 1 ? "" : "s").")
        lines.append("")
        lines.append("Imported \(importedCount) file\(importedCount == 1 ? "" : "s").")
        lines.append("Boundaries: \(importResultImportedBoundaries)")
        lines.append("Markers: \(importResultImportedMarkers)")
        lines.append("Tracks: \(importResultImportedTracks)")

        if skippedCount > 0 {
            lines.append("")
            lines.append("Skipped \(skippedCount) file\(skippedCount == 1 ? "" : "s").")
        }

        if !failedFiles.isEmpty {
            lines.append("")
            lines.append("Failed \(failedFiles.count) file\(failedFiles.count == 1 ? "" : "s"):")
            lines.append(contentsOf: failedFiles.prefix(8))
            if failedFiles.count > 8 {
                lines.append("…and \(failedFiles.count - 8) more.")
            }
        }

        alertMessage = lines.joined(separator: "\n")
    }

    private func collectImportableFiles(from urls: [URL]) -> [URL] {
        var collected: [URL] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            guard exists else { continue }

            if isDirectory.boolValue {
                collected.append(contentsOf: importableFiles(inFolder: url))
            } else if isSupportedImportFile(url) {
                collected.append(url)
            }
        }

        var seen: Set<String> = []
        var deduped: [URL] = []

        for url in collected {
            let key = url.standardizedFileURL.path
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(url)
            }
        }

        return deduped.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func importableFiles(inFolder folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []

        for case let fileURL as URL in enumerator {
            if isSupportedImportFile(fileURL) {
                results.append(fileURL)
            }
        }

        return results
    }

    private func isSupportedImportFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedImportExtensions.contains(ext)
    }

    private var supportedImportExtensions: Set<String> {
        ["geojson", "json", "gpx", "kml", "kmz"]
    }

    private func categoryIcon(for category: ImportCategory) -> String {
        app.muster.iconForImportCategory(category)
    }
    // MARK: - Export

    private func exportSelectedTrack() {
        guard
            let format = selectedExportFormat,
            let selectedSessionID = selectedExportSessionID,
            let session = app.muster.sessions.first(where: { $0.id == selectedSessionID }),
            !session.points.isEmpty
        else { return }

        do {
            let fileURL: URL
            switch format {
            case .geoJSON:
                fileURL = try writeGeoJSONTrackFile(for: session)
            case .gpx:
                fileURL = try writeGPXTrackFile(for: session)
            }

            showTrackExportSheet = false
            shareURL = fileURL
            shareSheetItems = [fileURL]
        } catch {
            alertTitle = "Export Failed"
            alertMessage = "Could not export \(format.title) track: \(error.localizedDescription)"
        }
    }

    private func writeGeoJSONTrackFile(for session: MusterSession) throws -> URL {
        let coordinates = session.points.map { [$0.lon, $0.lat] }

        let properties: [String: Any] = {
            var dict: [String: Any] = [
                "name": session.name,
                "sessionID": session.id.uuidString,
                "startedAt": iso8601String(session.startedAt)
            ]
            if let endedAt = session.endedAt {
                dict["endedAt"] = iso8601String(endedAt)
            }
            return dict
        }()

        let feature: [String: Any] = [
            "type": "Feature",
            "properties": properties,
            "geometry": [
                "type": "LineString",
                "coordinates": coordinates
            ]
        ]

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": [feature]
        ]

        let data = try JSONSerialization.data(
            withJSONObject: collection,
            options: [.prettyPrinted, .sortedKeys]
        )

        let fileName = sanitizedFileBaseName(session.name.isEmpty ? "Muster Track" : session.name)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension(ExportFormat.geoJSON.fileExtension)

        try data.write(to: url, options: .atomic)
        return url
    }

    private func writeGPXTrackFile(for session: MusterSession) throws -> URL {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]

        var xml: [String] = []
        xml.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        xml.append(#"<gpx version="1.1" creator="Muster" xmlns="http://www.topografix.com/GPX/1/1">"#)
        xml.append("<metadata>")
        xml.append("<name>\(xmlEscaped(session.name.isEmpty ? "Muster Track" : session.name))</name>")
        xml.append("<time>\(df.string(from: session.startedAt))</time>")
        xml.append("</metadata>")
        xml.append("<trk>")
        xml.append("<name>\(xmlEscaped(session.name.isEmpty ? "Muster Track" : session.name))</name>")
        xml.append("<trkseg>")

        for point in session.points {
            xml.append(#"<trkpt lat="\#(point.lat)" lon="\#(point.lon)">"#)
            if let elevation = point.elevationM {
                xml.append("<ele>\(elevation)</ele>")
            }
            xml.append("<time>\(df.string(from: point.t))</time>")
            xml.append("</trkpt>")
        }

        xml.append("</trkseg>")
        xml.append("</trk>")
        xml.append("</gpx>")

        let text = xml.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        let fileName = sanitizedFileBaseName(session.name.isEmpty ? "Muster Track" : session.name)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension(ExportFormat.gpx.fileExtension)

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

    private func iso8601String(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df.string(from: date)
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

private struct ExportTrackPickerView: View {
    let sessions: [MusterSession]
    @Binding var selectedSessionID: UUID?
    let onExport: () -> Void

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Tracks Available", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Record a track first to export.")
                }
            } else {
                Section("Tracks") {
                    ForEach(sessions) { session in
                        Button {
                            selectedSessionID = session.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name.isEmpty ? "Muster Track" : session.name)
                                        .foregroundStyle(.primary)

                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: selectedSessionID == session.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedSessionID == session.id ? .tint : .tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Select one track, then tap Export.")
                }
            }
        }
        .navigationTitle("Choose Track")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Export") {
                onExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSessionID == nil)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom)
            .background(.thinMaterial)
        }
    }
}

// MARK: - Imported File Detail

private struct ImportedMapFileDetailView: View {
    @EnvironmentObject private var app: AppState

    let fileID: UUID

    private var file: ImportedMapFile? {
        app.muster.importedMapFiles.first(where: { $0.id == fileID })
    }

    var body: some View {
        List {
            if let file {
                Section {
                    LabeledContent("Name", value: file.displayTitle)
                    LabeledContent("Format", value: file.format.title)
                    LabeledContent("Category", value: file.assignedCategory.title)
                    LabeledContent("Imported", value: file.importedAt.formatted(date: .abbreviated, time: .shortened))
                } header: {
                    Text("File")
                }

                Section {
                    LabeledContent("Boundaries", value: "\(file.boundaries.count)")
                    LabeledContent("Markers", value: "\(file.markers.count)")
                    LabeledContent("Tracks", value: "\(file.tracks.count)")
                } header: {
                    Text("Contents")
                }

                if !file.boundaries.isEmpty {
                    Section {
                        ForEach(file.boundaries) { boundary in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(boundary.displayTitle)

                                        if isMergedPropertyBoundary(boundary) {
                                            Text("MERGED")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.blue, in: Capsule())
                                        }
                                    }

                                    Text(boundary.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text("\(boundary.rings.count) ring\(boundary.rings.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { boundary.isVisible },
                                        set: {
                                            app.muster.setImportedBoundaryVisibility(
                                                fileID: fileID,
                                                boundaryID: boundary.id,
                                                isVisible: $0
                                            )
                                        }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                    } header: {
                        Text("Boundaries")
                    }
                }

                if !file.markers.isEmpty {
                    Section {
                        ForEach(file.markers) { marker in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(marker.displayTitle)

                                    HStack(spacing: 6) {
                                        Text(app.muster.iconForImportCategory(marker.category))
                                        Text(marker.category.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("\(marker.lat), \(marker.lon)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { marker.isVisible },
                                        set: {
                                            app.muster.setImportedMarkerVisibility(
                                                fileID: fileID,
                                                markerID: marker.id,
                                                isVisible: $0
                                            )
                                        }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                    } header: {
                        Text("Markers")
                    }
                }

                if !file.tracks.isEmpty {
                    Section {
                        ForEach(file.tracks) { track in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.displayTitle)

                                    Text(track.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text("\(track.points.count) points")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { track.isVisible },
                                        set: {
                                            app.muster.setImportedTrackVisibility(
                                                fileID: fileID,
                                                trackID: track.id,
                                                isVisible: $0
                                            )
                                        }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                    } header: {
                        Text("Tracks")
                    }
                }
            } else {
                Section {
                    Text("File not found.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Imported File")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isMergedPropertyBoundary(_ boundary: ImportedBoundary) -> Bool {
        let name = boundary.displayTitle.lowercased()
        return name.contains("– property") || name.contains("property – merged")
    }
}

// MARK: - Share Sheet

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
