import SwiftUI
import UIKit
import Combine

#if canImport(UIKit)
import UIKit
#endif

// Shared keys (must match MapMainView / MapViewRepresentable usage)
private let kRingCountKey = "rings_count"              // Int
private let kRingSpacingKey = "rings_spacing_m"        // Double
private let kRingColorKey = "rings_color"              // String
private let kRingThicknessScaleKey = "rings_thickness_scale" // Double (0.5...2.0)
private let kRingDistanceLabelsEnabledKey = "rings_distance_labels_enabled" // Bool
private let kMapOrientationKey = "map_orientation"     // String: "headsUp" | "northUp"
private let kHeadsUpPitchDegreesKey = "heads_up_pitch_degrees" // Double
private let kHeadsUpUserVerticalOffsetKey = "heads_up_user_vertical_offset" // Double: 0...10
private let kAppearanceModeKey = "appearance_mode"     // String: "system" | "light" | "dark"

// Quick zoom preset keys
private let kQuickZoom1MetersKey = "quick_zoom_1_m"    // Double
private let kQuickZoom2MetersKey = "quick_zoom_2_m"    // Double
private let kQuickZoom3MetersKey = "quick_zoom_3_m"    // Double

// Top pill keys (must match MapMainView)
private let kTopLeftPillMetricKey = "top_left_pill_metric"
private let kTopRightPillMetricKey = "top_right_pill_metric"

// Sheep pin keys (must match MusterStore prefs)
private let kSheepPinEnabledKey = "sheep_pin_enabled"        // Bool
private let kSheepPinExpirySecondsKey = "sheep_pin_expiry_s" // Double (seconds)
private let kSheepPinLimitKey = "sheep_pin_limit"            // Int
private let kSheepPinIconKey = "sheep_pin_icon"              // String

// XRS radio keys
private let kXRSRadioMarkerLimitKey = "xrs_radio_marker_limit"      // Int
private let kXRSRadioExpiryMinutesKey = "xrs_radio_expiry_minutes"  // Int
private let kXRSRadioTrailsEnabledKey = "xrs_radio_trails_enabled"  // Bool
private let kXRSRadioTrailColorKey = "xrs_radio_trail_color"        // String

// Admin battery / thermal keys
private let kAdminBatteryDiagnosticsEnabledKey = "admin_battery_diagnostics_enabled"
private let kAdminBatteryImpactSensitivityKey = "admin_battery_impact_sensitivity"
private let kAdminBatteryImpactIncludeHeadingKey = "admin_battery_impact_include_heading"
private let kAdminBatteryImpactIncludeBackgroundKey = "admin_battery_impact_include_background"
private let kAdminMap3DCostEnabledKey = "admin_battery_map3d_cost_enabled"
private let kAdminKeepScreenAwakeCostEnabledKey = "admin_battery_keep_screen_awake_cost_enabled"

// Admin battery model assumption keys
private let kAdminAssumeFollowUserKey = "admin_assume_follow_user"
private let kAdminAssumeBackgroundGPSKey = "admin_assume_background_gps"
private let kAdminAssumeHeadingActiveKey = "admin_assume_heading_active"
private let kAdminAssume3DMapActiveKey = "admin_assume_3d_map_active"
private let kAdminAssumeKeepScreenAwakeKey = "admin_assume_keep_screen_awake"
private let kAdminAssumeHighAccuracyGPSKey = "admin_assume_high_accuracy_gps"
private let kAdminAssumeFastRedrawKey = "admin_assume_fast_redraw"
private let kAdminEstimatedDistanceFilterKey = "admin_estimated_distance_filter_m"

private let kMediaButtonEnabledKey = "media_button_enabled" // Bool

private let kTPMSEnabledKey = "tpms_enabled"               // Bool
private let kTPMSLowPressureKey = "tpms_low_pressure"     // Double
private let kTPMSHighPressureKey = "tpms_high_pressure"   // Double
private let kTPMSAlertsEnabledKey = "tpms_alerts_enabled" // Bool

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @AppStorage(kAppearanceModeKey) private var appearanceMode: String = "system"

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    NavigationLink {
                        BluetoothSettingsView()
                    } label: {
                        Label("XRS Radio", systemImage: "dot.radiowaves.left.and.right")
                    }

                    NavigationLink {
                        TPMSDashboardHostView()
                    } label: {
                        Label("TPMS", systemImage: "tirepressure")
                    }

                    NavigationLink {
                        GroupTrackingSettingsView()
                    } label: {
                        Label("Group Tracking", systemImage: "person.2")
                    }
                }
                Section("Map") {
                    NavigationLink {
                        MapSettingsView()
                    } label: {
                        Label("Map View", systemImage: "map")
                    }

                    NavigationLink {
                        RingsSettingsView()
                    } label: {
                        Label("Rings", systemImage: "scope")
                    }

                    NavigationLink {
                        TopPillsSettingsView()
                    } label: {
                        Label("Top Pills", systemImage: "capsule")
                    }

                    NavigationLink {
                        MarkerTemplatesSettingsView()
                            .environmentObject(app)
                    } label: {
                        Label("Marker Templates", systemImage: "mappin.and.ellipse")
                    }

                    NavigationLink {
                        SheepPinSettingsView()
                    } label: {
                        Label("Quick Drop Pin", systemImage: "mappin")
                    }

                    NavigationLink {
                        AdvancedMapSettingsView()
                    } label: {
                        Label("Advanced Map", systemImage: "map.fill")
                    }
                }

                Section("Data") {
                    NavigationLink {
                        ImportExportView(mode: .import)
                            .environmentObject(app)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                    NavigationLink {
                        ImportExportView(mode: .export)
                            .environmentObject(app)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    NavigationLink {
                        ImportCategoriesSettingsView()
                            .environmentObject(app)
                    } label: {
                        Label("Import Categories", systemImage: "folder.badge.plus")
                    }
                }

                Section("Admin") {
                    NavigationLink {
                        AdminMapTuningView()
                    } label: {
                        Label("Map Tuning", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        BLERadioDebugView()
                    } label: {
                        Label("XRS Radio Debug", systemImage: "waveform.path.ecg")
                    }

                    NavigationLink {
                        BatteryThermalSettingsView()
                    } label: {
                        Label("Battery & Thermal", systemImage: "battery.75")
                    }
                }
            }
            .navigationTitle("Settings")
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
    }
}

// =========================================================
// MARK: - Group Tracking
// =========================================================

private struct GroupTrackingSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink("Radio") {
                    RadioSettingsView()
                }
            } footer: {
                Text("Settings for tracking other users via radio position updates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Group Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =========================================================
// MARK: - Settings
// =========================================================

private struct AppSettingsView: View {
    var body: some View {
        Form {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }

            NavigationLink {
                UnitsSettingsView()
            } label: {
                Label("Units", systemImage: "ruler")
            }

            NavigationLink {
                MediaSettingsView()
            } label: {
                Label("Media", systemImage: "speaker.wave.2")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(kAppearanceModeKey) private var appearanceMode: String = "system"

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone or iPad setting. Light and Dark force the app to stay in that mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UnitsSettingsView: View {
    var body: some View {
        PlaceholderSettingsDetail(title: "Units")
    }
}
struct TPMSDashboardHostView: View {
    @StateObject private var tpmsStore = TPMSStore()
    @StateObject private var tpmsBluetoothHolder = TPMSBluetoothManagerHolder()

    var body: some View {
        TPMSDashboardView()
            .environmentObject(tpmsStore)
            .environmentObject(resolvedBluetoothManager)
            .onAppear {
                if tpmsBluetoothHolder.manager == nil {
                    tpmsBluetoothHolder.manager = TPMSBluetoothManager(tpmsStore: tpmsStore)
                }
            }
    }

    private var resolvedBluetoothManager: TPMSBluetoothManager {
        if let manager = tpmsBluetoothHolder.manager {
            return manager
        }

        let manager = TPMSBluetoothManager(tpmsStore: tpmsStore)
        tpmsBluetoothHolder.manager = manager
        return manager
    }
}

@MainActor
private final class TPMSBluetoothManagerHolder: ObservableObject {
    @Published var manager: TPMSBluetoothManager?
}

// =========================================================
// MARK: - Top Pills
// =========================================================

private struct TopPillsSettingsView: View {

    private enum TopSidePillMetric: String, CaseIterable, Identifiable {
        case weather
        case wind
        case altitude
        case distanceToTarget
        case etaAtTarget
        case headingBearing
        case tripDistance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weather: return "Weather"
            case .wind: return "Wind"
            case .altitude: return "Altitude"
            case .distanceToTarget: return "Distance to Target"
            case .etaAtTarget: return "ETA at Target"
            case .headingBearing: return "Heading / Bearing"
            case .tripDistance: return "Total kms on track / trip"
            }
        }

        var shortDescription: String {
            switch self {
            case .weather:
                return "Shows the current weather symbol and temperature."
            case .wind:
                return "Shows wind speed and direction."
            case .altitude:
                return "Shows current altitude."
            case .distanceToTarget:
                return "Shows distance to the active Go To target."
            case .etaAtTarget:
                return "Shows estimated time to the active Go To target using current speed."
            case .headingBearing:
                return "Shows heading when no target is active, or bearing to target when one is selected."
            case .tripDistance:
                return "Shows total distance recorded on the active track."
            }
        }
    }

    @AppStorage(kTopLeftPillMetricKey) private var topLeftPillMetricRaw: String = TopSidePillMetric.weather.rawValue
    @AppStorage(kTopRightPillMetricKey) private var topRightPillMetricRaw: String = TopSidePillMetric.wind.rawValue

    private var leftMetric: TopSidePillMetric {
        TopSidePillMetric(rawValue: topLeftPillMetricRaw) ?? .weather
    }

    private var rightMetric: TopSidePillMetric {
        TopSidePillMetric(rawValue: topRightPillMetricRaw) ?? .wind
    }

    var body: some View {
        Form {
            Section {
                Picker("Left pill", selection: $topLeftPillMetricRaw) {
                    ForEach(TopSidePillMetric.allCases) { metric in
                        Text(metric.title).tag(metric.rawValue)
                    }
                }

                Picker("Right pill", selection: $topRightPillMetricRaw) {
                    ForEach(TopSidePillMetric.allCases) { metric in
                        Text(metric.title).tag(metric.rawValue)
                    }
                }
            } header: {
                Text("Default Pill Content")
            } footer: {
                Text("These are the two smaller pills at the top of the map. You can also long-press either pill on the map itself to change it quickly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Left", value: leftMetric.title)
                LabeledContent("Right", value: rightMetric.title)
            } header: {
                Text("Current Selection")
            }

            Section("Available options") {
                ForEach(TopSidePillMetric.allCases) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.body.weight(.semibold))

                        Text(metric.shortDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Top Pills")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        if TopSidePillMetric(rawValue: topLeftPillMetricRaw) == nil {
            topLeftPillMetricRaw = TopSidePillMetric.weather.rawValue
        }

        if TopSidePillMetric(rawValue: topRightPillMetricRaw) == nil {
            topRightPillMetricRaw = TopSidePillMetric.wind.rawValue
        }
    }
}

// =========================================================
// MARK: - Marker Templates
// =========================================================

private struct MarkerTemplatesSettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showAddSheet = false
    @State private var editingTemplate: MarkerTemplate? = nil

    var body: some View {
        List {
            Section {
                if app.muster.markerTemplates.isEmpty {
                    Text("No marker templates yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.muster.markerTemplates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            HStack(spacing: 12) {
                                Text(template.emoji)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.displayTitle)
                                        .foregroundStyle(.primary)

                                    Text("Tap to edit")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { app.muster.markerTemplates[$0].id }
                        for id in ids {
                            app.muster.deleteMarkerTemplate(id: id)
                        }
                    }
                    .onMove { from, to in
                        app.muster.moveMarkerTemplates(fromOffsets: from, toOffset: to)
                    }
                }
            } header: {
                Text("Templates")
            } footer: {
                Text("These are the marker types you’ll choose from when long-pressing the map.")
            }

            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Marker Template", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Marker Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MarkerTemplateEditorSheet(mode: .add)
                .environmentObject(app)
        }
        .sheet(item: $editingTemplate) { template in
            MarkerTemplateEditorSheet(mode: .edit(template))
                .environmentObject(app)
        }
    }
}

private struct MarkerTemplateEditorSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(MarkerTemplate)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let template):
                return template.id.uuidString
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let mode: Mode

    @State private var descriptionText: String = ""
    @State private var emojiText: String = ""

    private var title: String {
        switch mode {
        case .add: return "Add Template"
        case .edit: return "Edit Template"
        }
    }

    private var saveTitle: String {
        switch mode {
        case .add: return "Add"
        case .edit: return "Save"
        }
    }

    private var canSave: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !emojiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Marker Details") {
                    TextField("Description", text: $descriptionText)
                        .textInputAutocapitalization(.words)

                    TextField("Emoji", text: $emojiText)
                        .autocorrectionDisabled()

                    if !emojiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Text("Preview")
                            Spacer()
                            Text(emojiText.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.title2)
                        }
                    }
                }

                Section("Examples") {
                    Text("Dam + 💧")
                    Text("Gate + 🚪")
                    Text("Tank + 🛢️")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(saveTitle) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                configureInitialValues()
            }
        }
    }

    private func configureInitialValues() {
        switch mode {
        case .add:
            if descriptionText.isEmpty && emojiText.isEmpty {
                descriptionText = ""
                emojiText = ""
            }

        case .edit(let template):
            if descriptionText.isEmpty && emojiText.isEmpty {
                descriptionText = template.description
                emojiText = template.emoji
            }
        }
    }

    private func save() {
        let cleanDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmoji = emojiText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDescription.isEmpty, !cleanEmoji.isEmpty else { return }

        switch mode {
        case .add:
            app.muster.addMarkerTemplate(description: cleanDescription, emoji: cleanEmoji)

        case .edit(let template):
            app.muster.updateMarkerTemplate(
                id: template.id,
                description: cleanDescription,
                emoji: cleanEmoji
            )
        }

        dismiss()
    }
}

// =========================================================
// MARK: - Import Categories
// =========================================================

private struct ImportCategoriesSettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var isPresentingAddCustomCategory = false

    var body: some View {
        List {
            Section("Built-in Categories") {
                ForEach(ImportCategory.allCases) { category in
                    NavigationLink {
                        ImportCategoryEditorView(category: category)
                            .environmentObject(app)
                    } label: {
                        HStack(spacing: 12) {
                            if !category.supportsColor {
                                Text(app.muster.iconForImportCategory(category))
                                    .font(.title3)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)

                                if category.supportsColor {
                                    Text(categorySummary(for: category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Tap to edit icon / emoji")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: app.muster.isImportCategoryVisible(category) ? "eye.fill" : "eye.slash.fill")
                                .foregroundStyle(app.muster.isImportCategoryVisible(category) ? .primary : .secondary)
                        }
                    }
                }
            } footer: {
                Text("Choose the icon or emoji used for each imported category. Boundaries and Tracks can also have their own colours. Visibility here sets the default filter state used on the map.")
            }

            if !app.muster.customImportCategories.isEmpty {
                Section("Custom Categories") {
                    ForEach(app.muster.customImportCategories) { category in
                        NavigationLink {
                            CustomImportCategoryEditorView(categoryID: category.id)
                                .environmentObject(app)
                        } label: {
                            HStack(spacing: 12) {
                                Text(category.icon)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title)
                                    Text("Tap to edit icon / emoji")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: category.isVisibleByDefault ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(category.isVisibleByDefault ? .primary : .secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Custom categories are used for organizing imported marker-like points.")
                }
            }

            Section("Quick visibility") {
                ForEach(ImportCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { app.muster.isImportCategoryVisible(category) },
                        set: { app.muster.setImportCategoryVisibility($0, for: category) }
                    )) {
                        HStack(spacing: 10) {
                            Text(app.muster.iconForImportCategory(category))
                            Text(category.title)
                        }
                    }
                }
            }

            Section {
                Button("Show All Categories") {
                    app.muster.showAllImportCategories()
                }

                Button("Hide All Categories") {
                    app.muster.hideAllImportCategories()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Import Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddCustomCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $isPresentingAddCustomCategory) {
            NavigationStack {
                NewCustomImportCategoryView()
                    .environmentObject(app)
            }
        }
    }

    private func categorySummary(for category: ImportCategory) -> String {
        if let preset = selectedPreset(for: category) {
            return "Colour: \(preset.title)"
        }

        let stroke = app.muster.strokeHexForImportCategory(category) ?? "-"
        return "Stroke: \(stroke)"
    }

    private func selectedPreset(for category: ImportCategory) -> ImportColorPreset? {
        guard category.supportsColor else { return nil }
        let currentStroke = app.muster.strokeHexForImportCategory(category) ?? category.defaultStrokeHex ?? ""
        return ImportColorPreset.allCases.first {
            $0.strokeHex.caseInsensitiveCompare(currentStroke) == .orderedSame
        }
    }
}

private struct NewCustomImportCategoryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var icon: String = ""
    @State private var isVisibleByDefault: Bool = true

    var body: some View {
        Form {
            Section("Category") {
                TextField("Name", text: $title)
                TextField("Icon or emoji", text: $icon)
                    .autocorrectionDisabled()
            }

            Section("Visibility") {
                Toggle("Visible in map filter by default", isOn: $isVisibleByDefault)
            }
        }
        .navigationTitle("New Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        app.muster.addCustomImportCategory(
            title: title,
            icon: icon,
            isVisibleByDefault: isVisibleByDefault
        )
        dismiss()
    }
}

private struct ImportCategoryEditorView: View {
    @EnvironmentObject private var app: AppState

    let category: ImportCategory

    @State private var iconText: String = ""
    @State private var selectedPreset: ImportColorPreset? = nil

    private let colorColumns = [
        GridItem(.adaptive(minimum: 52, maximum: 60), spacing: 12)
    ]

    var body: some View {
        Form {
            if !category.supportsColor {
                Section("Icon / Emoji") {
                    TextField("Icon or emoji", text: $iconText)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Preview")
                        Spacer()
                        Text(previewIcon)
                            .font(.title2)
                    }
                }
            }

            Section {
                Toggle(
                    "Visible in map filter by default",
                    isOn: Binding(
                        get: { app.muster.isImportCategoryVisible(category) },
                        set: { app.muster.setImportCategoryVisibility($0, for: category) }
                    )
                )
            } header: {
                Text("Visibility")
            }

            if category.supportsColor {
                Section {
                    LazyVGrid(columns: colorColumns, spacing: 14) {
                        ForEach(category.availableColorPresets) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.clear)
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        colorFromHex(preset.strokeHex) ?? .clear,
                                                        lineWidth: 4
                                                    )
                                            )

                                        if selectedPreset == preset {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(checkmarkColor(for: preset))
                                        }
                                    }
                                    .frame(width: 46, height: 46)
                                    .background(
                                        Circle()
                                            .strokeBorder(
                                                selectedPreset == preset ? Color.accentColor : .clear,
                                                lineWidth: 2
                                            )
                                    )

                                    Text(preset.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Stroke preview")
                        Spacer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentStrokeColor)
                            .frame(width: 44, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }

                    Button("Reset to Default Colour") {
                        resetToDefaultPreset()
                    }
                    .foregroundStyle(.red)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Choose from preset colours for the line colour.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                switch category {
                case .boundaries:
                    Text("Fence line")
                    Text("Paddock")
                case .tracks:
                    Text("Vehicle track")
                    Text("Imported run")
                case .waterPoints:
                    Text("💧  Trough")
                    Text("🚰  Tank")
                case .yards:
                    Text("🔸  Yards")
                    Text("📦  Holding yard")
                case .other:
                    Text("📍  Landmark")
                    Text("⭐️  Misc point")
                }
            } header: {
                Text("Examples")
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadValues()
        }
        .onChange(of: iconText) { _, newValue in
            if !category.supportsColor {
                app.muster.setImportCategoryIcon(newValue, for: category)
            }
        }
    }

    private var previewIcon: String {
        let trimmed = iconText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.defaultIcon : trimmed
    }

    private var currentStrokeColor: Color {
        let hex = selectedPreset?.strokeHex ?? category.defaultStrokeHex
        return colorFromHex(hex) ?? .clear
    }

    private func loadValues() {
        iconText = app.muster.iconForImportCategory(category)
        selectedPreset = currentPresetForCategory()
    }

    private func currentPresetForCategory() -> ImportColorPreset? {
        guard category.supportsColor else { return nil }

        let currentStroke = app.muster.strokeHexForImportCategory(category) ?? category.defaultStrokeHex ?? ""

        if let match = ImportColorPreset.allCases.first(where: {
            $0.strokeHex.caseInsensitiveCompare(currentStroke) == .orderedSame
        }) {
            return match
        }

        return category.defaultPreset
    }

    private func applyPreset(_ preset: ImportColorPreset) {
        guard category.supportsColor else { return }

        selectedPreset = preset
        app.muster.setImportCategoryStrokeHex(preset.strokeHex, for: category)
        app.muster.setImportCategoryFillHex(nil, for: category)
    }

    private func resetToDefaultPreset() {
        guard category.supportsColor else { return }

        let fallback = category.defaultPreset ?? .blue
        applyPreset(fallback)
    }

    private func checkmarkColor(for preset: ImportColorPreset) -> Color {
        switch preset {
        case .yellow, .amber, .mint, .sky:
            return .black
        default:
            return .white
        }
    }

    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }

        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let r, g, b, a: Double

        if cleaned.count == 8 {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
            a = Double(value & 0x000000FF) / 255.0
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
            a = 1.0
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

private struct CustomImportCategoryEditorView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let categoryID: UUID

    @State private var title: String = ""
    @State private var icon: String = ""
    @State private var isVisibleByDefault: Bool = true

    var body: some View {
        Form {
            Section("Category") {
                TextField("Name", text: $title)
                TextField("Icon or emoji", text: $icon)
                    .autocorrectionDisabled()

                HStack {
                    Text("Preview")
                    Spacer()
                    Text(previewIcon)
                        .font(.title2)
                }
            }

            Section("Visibility") {
                Toggle("Visible in map filter by default", isOn: $isVisibleByDefault)
            }

            Section {
                Button("Delete Category", role: .destructive) {
                    app.muster.deleteCustomImportCategory(id: categoryID)
                    dismiss()
                }
            }
        }
        .navigationTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Category" : title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
        .onChange(of: title) { _, _ in saveIfValid() }
        .onChange(of: icon) { _, _ in saveIfValid() }
        .onChange(of: isVisibleByDefault) { _, _ in saveIfValid() }
    }

    private var previewIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "📍" : trimmed
    }

    private func load() {
        guard let category = app.muster.customImportCategories.first(where: { $0.id == categoryID }) else { return }
        title = category.title
        icon = category.icon
        isVisibleByDefault = category.isVisibleByDefault
    }

    private func saveIfValid() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        app.muster.updateCustomImportCategory(
            id: categoryID,
            title: title,
            icon: icon,
            isVisibleByDefault: isVisibleByDefault
        )
    }
}

// =========================================================
// MARK: - Sheep Pin Settings
// =========================================================

private struct SheepPinSettingsView: View {

    private enum SheepPinIconOption: String, CaseIterable, Identifiable {
        case sheep
        case cattle
        case flag
        case target
        case bell
        case pin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sheep: return "Sheep"
            case .cattle: return "Cattle"
            case .flag: return "Flag"
            case .target: return "Target"
            case .bell: return "Bell"
            case .pin: return "Pin"
            }
        }

        var icon: String {
            switch self {
            case .sheep: return "🐑"
            case .cattle: return "🐄"
            case .flag: return "🚩"
            case .target: return "🎯"
            case .bell: return "🔔"
            case .pin: return "📍"
            }
        }
    }

    @AppStorage(kSheepPinEnabledKey) private var enabled: Bool = true
    @AppStorage(kSheepPinExpirySecondsKey) private var expirySeconds: Double = 3600
    @AppStorage(kSheepPinLimitKey) private var limit: Int = 3
    @AppStorage(kSheepPinIconKey) private var sheepPinIconRaw: String = SheepPinIconOption.sheep.rawValue

    private struct ExpiryOption: Identifiable {
        let id = UUID()
        let label: String
        let seconds: Double
    }

    private let expiryOptions: [ExpiryOption] = [
        .init(label: "15 minutes", seconds: 15 * 60),
        .init(label: "30 minutes", seconds: 30 * 60),
        .init(label: "1 hour", seconds: 60 * 60),
        .init(label: "2 hours", seconds: 2 * 60 * 60),
        .init(label: "4 hours", seconds: 4 * 60 * 60),
        .init(label: "8 hours", seconds: 8 * 60 * 60),
        .init(label: "24 hours", seconds: 24 * 60 * 60)
    ]

    private let limitOptions = Array(1...10)

    private var expiryLabel: String {
        if expirySeconds < 3600 {
            return "\(Int(expirySeconds / 60)) min"
        } else if expirySeconds.truncatingRemainder(dividingBy: 3600) == 0 {
            return "\(Int(expirySeconds / 3600)) h"
        } else {
            return String(format: "%.1f h", expirySeconds / 3600)
        }
    }

    private var selectedIcon: SheepPinIconOption {
        SheepPinIconOption(rawValue: sheepPinIconRaw) ?? .sheep
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Quick Drop button", isOn: $enabled)

                Text("When enabled, the Quick Drop button appears on the map panel so you can quickly drop a temporary pin at your current location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Quick Drop Pin")
            }

            Section {
                Picker("Button icon", selection: $sheepPinIconRaw) {
                    ForEach(SheepPinIconOption.allCases) { option in
                        HStack {
                            Text(option.icon)
                            Text(option.title)
                        }
                        .tag(option.rawValue)
                    }
                }

                HStack {
                    Text("Current icon")
                    Spacer()
                    Text(selectedIcon.icon)
                        .font(.title3)
                }

                Text("Choose the icon shown on the quick drop pin button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Icon")
            }

            Section {
                Picker("Pin expires after", selection: $expirySeconds) {
                    ForEach(expiryOptions) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }

                Text("Current expiry: \(expiryLabel). Older pins auto-remove to keep the map clean while mustering.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Expiry")
            }

            Section {
                Picker("Maximum visible Quick Drop pins", selection: $limit) {
                    ForEach(limitOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }

                Text("If you drop more than \(limit) pins, the oldest one is removed automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Limit")
            }
        }
        .navigationTitle("Quick Drop Pin")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =========================================================
// MARK: - Radio Settings
// =========================================================

private struct RadioSettingsView: View {

    private enum RadioTrailColorOption: String, CaseIterable, Identifiable {
        case blue
        case red
        case green
        case orange
        case yellow
        case white

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blue: return "Blue"
            case .red: return "Red"
            case .green: return "Green"
            case .orange: return "Orange"
            case .yellow: return "Yellow"
            case .white: return "White"
            }
        }

        var swatch: Color {
            switch self {
            case .blue: return .blue
            case .red: return .red
            case .green: return .green
            case .orange: return .orange
            case .yellow: return .yellow
            case .white: return .white
            }
        }
    }

    @AppStorage(kXRSRadioMarkerLimitKey) private var markerLimit: Int = 1
    @AppStorage(kXRSRadioExpiryMinutesKey) private var expiryMinutes: Int = 120
    @AppStorage(kXRSRadioTrailsEnabledKey) private var trailsEnabled: Bool = true
    @AppStorage(kXRSRadioTrailColorKey) private var trailColorRaw: String = RadioTrailColorOption.blue.rawValue

    private let markerLimitOptions = Array(1...10)
    private let expiryOptions = Array(stride(from: 15, through: 600, by: 15))

    private var selectedTrailColor: RadioTrailColorOption {
        RadioTrailColorOption(rawValue: trailColorRaw) ?? .blue
    }

    var body: some View {
        Form {
            Section {
                Picker("Markers per radio user", selection: $markerLimit) {
                    ForEach(markerLimitOptions, id: \.self) { n in
                        if n == 1 {
                            Text("1 marker").tag(n)
                        } else {
                            Text("\(n) markers").tag(n)
                        }
                    }
                }

                Text("Controls how many recent radio positions are kept for each user. Set to 1 to show only the latest position.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("History")
            }

            Section {
                Picker("Time radio pins stay visible", selection: $expiryMinutes) {
                    ForEach(expiryOptions, id: \.self) { minutes in
                        if minutes < 60 {
                            Text("\(minutes) minutes").tag(minutes)
                        } else if minutes % 60 == 0 {
                            Text("\(minutes / 60) hour" + (minutes == 60 ? "" : "s")).tag(minutes)
                        } else {
                            let hours = Double(minutes) / 60.0
                            Text(String(format: "%.1f hours", hours)).tag(minutes)
                        }
                    }
                }

                Text("Radio markers older than \(expiryLabel) will be removed automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Expiry")
            }

            Section {
                Toggle("Show Radio Trails", isOn: $trailsEnabled)

                Text("Shows a joined trail of recent radio locations on the map. Radio trails will only be shown in the current muster track context.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Trails")
            }

            Section {
                Picker("Trail Colour", selection: $trailColorRaw) {
                    ForEach(RadioTrailColorOption.allCases) { option in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(option.swatch)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.secondary.opacity(option == .white ? 0.45 : 0.15), lineWidth: 1)
                                )

                            Text(option.title)
                        }
                        .tag(option.rawValue)
                    }
                }

                HStack {
                    Text("Current trail colour")
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(selectedTrailColor.swatch)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(.secondary.opacity(selectedTrailColor == .white ? 0.45 : 0.15), lineWidth: 1)
                            )

                        Text(selectedTrailColor.title)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Trail Appearance")
            }

            Section("Current selection") {
                LabeledContent("Markers per user", value: "\(markerLimit)")
                LabeledContent("Visibility time", value: expiryLabel)
                LabeledContent("Trails", value: trailsEnabled ? "On" : "Off")
                LabeledContent("Trail colour", value: selectedTrailColor.title)
            }
        }
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeValues()
        }
        .onChange(of: markerLimit) { _, newValue in
            markerLimit = normalizedMarkerLimit(newValue)
        }
        .onChange(of: expiryMinutes) { _, newValue in
            expiryMinutes = normalizedExpiryMinutes(newValue)
        }
        .onChange(of: trailColorRaw) { _, newValue in
            if RadioTrailColorOption(rawValue: newValue) == nil {
                trailColorRaw = RadioTrailColorOption.blue.rawValue
            }
        }
    }

    private var expiryLabel: String {
        if expiryMinutes < 60 {
            return "\(expiryMinutes) min"
        } else if expiryMinutes % 60 == 0 {
            let hours = expiryMinutes / 60
            return "\(hours) h"
        } else {
            return String(format: "%.1f h", Double(expiryMinutes) / 60.0)
        }
    }

    private func normalizedMarkerLimit(_ value: Int) -> Int {
        min(max(value, 1), 10)
    }

    private func normalizedExpiryMinutes(_ value: Int) -> Int {
        let clamped = min(max(value, 15), 600)
        return ((clamped + 7) / 15) * 15
    }

    private func normalizeValues() {
        markerLimit = normalizedMarkerLimit(markerLimit)
        expiryMinutes = normalizedExpiryMinutes(expiryMinutes)

        if RadioTrailColorOption(rawValue: trailColorRaw) == nil {
            trailColorRaw = RadioTrailColorOption.blue.rawValue
        }
    }
}
// =========================================================
// MARK: - Map Settings
// =========================================================

private struct MapSettingsView: View {
    @AppStorage(kMapOrientationKey) private var orientationRaw: String = "headsUp"
    @AppStorage(kHeadsUpPitchDegreesKey) private var headsUpPitchDegrees: Double = 45
    @AppStorage(kHeadsUpUserVerticalOffsetKey) private var headsUpUserVerticalOffset: Double = 10

    private var isHeadsUp: Bool { orientationRaw == "headsUp" }

    private let headsUpPitchOptions: [Double] = [0, 45, 80]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { isHeadsUp },
                    set: { orientationRaw = $0 ? "headsUp" : "northUp" }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Heads Up")
                        Text("When off, the map stays North Up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Orientation")
            }

            Section {
                Picker("Heads-Up View Angle", selection: $headsUpPitchDegrees) {
                    ForEach(headsUpPitchOptions, id: \.self) { value in
                        if value == 0 {
                            Text("0° • Straight Down").tag(value)
                        } else if value == 45 {
                            Text("45° • Angled").tag(value)
                        } else {
                            Text("80° • Steep").tag(value)
                        }
                    }
                }

                Text(angleDescription(for: headsUpPitchDegrees))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Heads-Up Camera")
            } footer: {
                Text("This only affects Heads Up mode. North Up always uses a flat 0° camera.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("User screen position")
                        Spacer()
                        Text("\(Int(headsUpUserVerticalOffset))")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $headsUpUserVerticalOffset,
                        in: 0...10,
                        step: 1
                    )

                    HStack {
                        Text("0 • Centre")
                        Spacer()
                        Text("10 • Bottom")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Moves your on-screen position in Heads Up mode. Higher values place you closer to the bottom of the map so you can see more country ahead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Heads-Up User Position")
            } footer: {
                Text("Only affects Heads Up mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeHeadsUpPitch()
            normalizeHeadsUpUserVerticalOffset()
        }
        .onChange(of: headsUpPitchDegrees) { _, newValue in
            headsUpPitchDegrees = normalizedHeadsUpPitch(newValue)
        }
        .onChange(of: headsUpUserVerticalOffset) { _, newValue in
            headsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffset(newValue)
        }
    }

    private func normalizedHeadsUpPitch(_ value: Double) -> Double {
        let allowed = headsUpPitchOptions
        if allowed.contains(value) { return value }

        return allowed.min(by: { abs($0 - value) < abs($1 - value) }) ?? 45
    }

    private func normalizeHeadsUpPitch() {
        headsUpPitchDegrees = normalizedHeadsUpPitch(headsUpPitchDegrees)
    }

    private func normalizedHeadsUpUserVerticalOffset(_ value: Double) -> Double {
        min(max(value.rounded(), 0), 10)
    }

    private func normalizeHeadsUpUserVerticalOffset() {
        headsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffset(headsUpUserVerticalOffset)
    }

    private func angleDescription(for value: Double) -> String {
        switch Int(normalizedHeadsUpPitch(value)) {
        case 0:
            return "Straight-down view. Best for accurate map reading and least visual distortion."
        case 45:
            return "Balanced angled view. Good mix of forward visibility and map clarity."
        case 80:
            return "Steeper forward-looking view. Best when you want more of a navigation feel."
        default:
            return "Choose how tilted the map looks while in Heads Up mode."
        }
    }
}

// =========================================================
// MARK: - Rings Settings
// =========================================================

struct RingsSettingsView: View {
    private enum RingColorOption: String, CaseIterable, Identifiable {
        case blue
        case yellow
        case orange
        case red
        case green
        case purple
        case black
        case white

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }
    }

    @AppStorage(kRingCountKey) private var ringCount: Int = 4
    @AppStorage(kRingSpacingKey) private var ringSpacingM: Double = 100
    @AppStorage(kRingColorKey) private var ringColorRaw: String = RingColorOption.blue.rawValue
    @AppStorage(kRingThicknessScaleKey) private var ringThicknessScale: Double = 1.0
    @AppStorage(kRingDistanceLabelsEnabledKey) private var ringDistanceLabelsEnabled: Bool = true

    private let countOptions = Array(1...10)
    private let spacingOptions: [Double] = Array(stride(from: 250, through: 2500, by: 250))

    var body: some View {
        Form {
            Section {
                Picker("Number of rings", selection: $ringCount) {
                    ForEach(countOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }

                Picker("Ring spacing", selection: $ringSpacingM) {
                    ForEach(spacingOptions, id: \.self) { v in
                        Text("\(Int(v)) m").tag(v)
                    }
                }

                Picker("Ring color", selection: $ringColorRaw) {
                    ForEach(RingColorOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Ring thickness")
                        Spacer()
                        Text("\(ringThicknessScale, specifier: "%.2f")x")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $ringThicknessScale, in: 0.5...2.0, step: 0.05)
                }

                Toggle("Distance labels", isOn: $ringDistanceLabelsEnabled)

                let ringsSummary =
                    "Showing \(ringCount) rings at \(Int(ringSpacingM)) metre intervals in \(ringColorRaw.capitalized) " +
                    "at \(String(format: "%.2f", ringThicknessScale))x thickness" +
                    (ringDistanceLabelsEnabled ? " with" : " without") +
                    " distance labels."

                Text(ringsSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Distance Rings")
            }
        }
        .navigationTitle("Rings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if RingColorOption(rawValue: ringColorRaw) == nil {
                ringColorRaw = RingColorOption.blue.rawValue
            }
        }
    }
}

// =========================================================
// MARK: - Advanced Map
// =========================================================

private struct AdvancedMapSettingsView: View {

    @AppStorage(kRingCountKey) private var ringCount: Int = 4
    @AppStorage(kRingSpacingKey) private var ringSpacingM: Double = 100
    @AppStorage(kMapOrientationKey) private var orientationRaw: String = "headsUp"
    @AppStorage(kHeadsUpPitchDegreesKey) private var headsUpPitchDegrees: Double = 45
    @AppStorage(kHeadsUpUserVerticalOffsetKey) private var headsUpUserVerticalOffset: Double = 10
    @AppStorage(kSheepPinEnabledKey) private var sheepPinEnabled: Bool = true
    @AppStorage(kTopLeftPillMetricKey) private var topLeftPillMetricRaw: String = "weather"
    @AppStorage(kTopRightPillMetricKey) private var topRightPillMetricRaw: String = "wind"
    @AppStorage(kXRSRadioMarkerLimitKey) private var radioMarkerLimit: Int = 1
    @AppStorage(kXRSRadioExpiryMinutesKey) private var radioExpiryMinutes: Int = 120

    @AppStorage(kQuickZoom1MetersKey) private var quickZoom1M: Double = 1000
    @AppStorage(kQuickZoom2MetersKey) private var quickZoom2M: Double = 5000
    @AppStorage(kQuickZoom3MetersKey) private var quickZoom3M: Double = 12000

    private var orientationLabel: String {
        orientationRaw == "headsUp" ? "Heads Up" : "North Up"
    }

    private var headsUpPitchLabel: String {
        guard orientationRaw == "headsUp" else { return "0° (North Up)" }

        switch Int(headsUpPitchDegrees.rounded()) {
        case 0: return "0°"
        case 45: return "45°"
        case 80: return "80°"
        default: return "\(Int(headsUpPitchDegrees.rounded()))°"
        }
    }

    private var headsUpUserPositionLabel: String {
        orientationRaw == "headsUp"
            ? "\(Int(headsUpUserVerticalOffset.rounded()))"
            : "Not used"
    }

    private var topLeftPillLabel: String {
        labelForTopPill(topLeftPillMetricRaw)
    }

    private var topRightPillLabel: String {
        labelForTopPill(topRightPillMetricRaw)
    }

    private var radioExpiryLabel: String {
        if radioExpiryMinutes < 60 {
            return "\(radioExpiryMinutes) min"
        } else if radioExpiryMinutes % 60 == 0 {
            return "\((radioExpiryMinutes / 60)) h"
        } else {
            return String(format: "%.1f h", Double(radioExpiryMinutes) / 60.0)
        }
    }

    private func zoomLabel(_ meters: Double) -> String {
        "\(Int(meters.rounded())) m"
    }

    var body: some View {
        Form {
            Section("Current map setup") {
                LabeledContent("Orientation", value: orientationLabel)
                LabeledContent("Heads-up angle", value: headsUpPitchLabel)
                LabeledContent("Heads-up user position", value: headsUpUserPositionLabel)
                LabeledContent("Ring count", value: "\(ringCount)")
                LabeledContent("Ring spacing", value: "\(Int(ringSpacingM)) m")
                LabeledContent("Top left pill", value: topLeftPillLabel)
                LabeledContent("Top right pill", value: topRightPillLabel)
                LabeledContent("Quick zoom 1", value: zoomLabel(quickZoom1M))
                LabeledContent("Quick zoom 2", value: zoomLabel(quickZoom2M))
                LabeledContent("Quick zoom 3", value: zoomLabel(quickZoom3M))
                LabeledContent("Sheep pin", value: sheepPinEnabled ? "On" : "Off")
                LabeledContent("Radio markers per user", value: "\(radioMarkerLimit)")
                LabeledContent("Radio pin visibility", value: radioExpiryLabel)
            }

            Section("Note") {
                Text("Quick zoom controls are adjusted directly from the map screen by long-pressing any quick zoom button. Heads-up angle only applies in Heads Up mode. North Up always stays flat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Advanced Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labelForTopPill(_ rawValue: String) -> String {
        switch rawValue {
        case "weather": return "Weather"
        case "wind": return "Wind"
        case "altitude": return "Altitude"
        case "distanceToTarget": return "Distance to Target"
        case "etaAtTarget": return "ETA at Target"
        case "headingBearing": return "Heading / Bearing"
        case "tripDistance": return "Total kms on track / trip"
        default: return "Unknown"
        }
    }
}

// =========================================================
// MARK: - Battery + Thermal
// =========================================================

private struct BatteryThermalSettingsView: View {
    @StateObject private var diagnostics = AdminBatteryDiagnosticsStore()

    @AppStorage(kAdminBatteryDiagnosticsEnabledKey) private var diagnosticsEnabled: Bool = true
    @AppStorage(kAdminBatteryImpactSensitivityKey) private var impactSensitivity: Double = 1.0
    @AppStorage(kAdminBatteryImpactIncludeHeadingKey) private var includeHeadingCost: Bool = true
    @AppStorage(kAdminBatteryImpactIncludeBackgroundKey) private var includeBackgroundCost: Bool = true
    @AppStorage(kAdminMap3DCostEnabledKey) private var include3DCost: Bool = true
    @AppStorage(kAdminKeepScreenAwakeCostEnabledKey) private var includeScreenAwakeCost: Bool = true

    @AppStorage(kAdminAssumeFollowUserKey) private var assumeFollowUser: Bool = true
    @AppStorage(kAdminAssumeBackgroundGPSKey) private var assumeBackgroundGPS: Bool = true
    @AppStorage(kAdminAssumeHeadingActiveKey) private var assumeHeadingActive: Bool = true
    @AppStorage(kAdminAssume3DMapActiveKey) private var assume3DMapActive: Bool = false
    @AppStorage(kAdminAssumeKeepScreenAwakeKey) private var assumeKeepScreenAwake: Bool = true
    @AppStorage(kAdminAssumeHighAccuracyGPSKey) private var assumeHighAccuracyGPS: Bool = true
    @AppStorage(kAdminAssumeFastRedrawKey) private var assumeFastRedraw: Bool = false
    @AppStorage(kAdminEstimatedDistanceFilterKey) private var estimatedDistanceFilterM: Double = 2

    private var impactLevel: AdminBatteryDiagnosticsStore.ImpactLevel {
        diagnostics.estimatedImpact(
            includeHeading: includeHeadingCost && assumeHeadingActive,
            includeBackground: includeBackgroundCost && assumeBackgroundGPS,
            include3DMap: include3DCost && assume3DMapActive,
            includeScreenAwake: includeScreenAwakeCost && assumeKeepScreenAwake,
            followUser: assumeFollowUser,
            highAccuracyGPS: assumeHighAccuracyGPS,
            fastRedraw: assumeFastRedraw,
            distanceFilterMeters: estimatedDistanceFilterM,
            sensitivity: impactSensitivity
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Battery Diagnostics", isOn: $diagnosticsEnabled)
            } footer: {
                Text("Shows live battery status, charging state, Low Power Mode, thermal state, and an estimated battery impact model for your current field-use assumptions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if diagnosticsEnabled {
                Section {
                    LabeledContent("Battery") {
                        Text(diagnostics.batteryLevelPercent.map { "\($0)%" } ?? "Unavailable")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Battery State") {
                        Text(diagnostics.batteryStateText)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Low Power Mode") {
                        Text(diagnostics.isLowPowerModeEnabled ? "On" : "Off")
                            .foregroundStyle(diagnostics.isLowPowerModeEnabled ? .orange : .secondary)
                    }

                    LabeledContent("Thermal State") {
                        Text(diagnostics.thermalStateText)
                            .foregroundStyle(thermalColor(diagnostics.thermalState))
                    }
                } header: {
                    Text("Live Device Status")
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Current Estimate")
                            Text("This is a relative estimate, not a true battery current reading.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(impactLevel.rawValue)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(impactColor(impactLevel))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Impact Sensitivity")
                            Spacer()
                            Text(String(format: "%.1fx", impactSensitivity))
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $impactSensitivity, in: 0.5...2.0, step: 0.1)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Estimated Battery Impact")
                }

                Section {
                    Toggle("Assume Follow User Active", isOn: $assumeFollowUser)
                    Toggle("Assume Background GPS Active", isOn: $assumeBackgroundGPS)
                    Toggle("Assume Heading Active", isOn: $assumeHeadingActive)
                    Toggle("Assume 3D Map Active", isOn: $assume3DMapActive)
                    Toggle("Assume Keep Screen Awake", isOn: $assumeKeepScreenAwake)
                    Toggle("Assume High Accuracy GPS", isOn: $assumeHighAccuracyGPS)
                    Toggle("Assume Fast Map Redraw", isOn: $assumeFastRedraw)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Estimated Distance Filter")
                            Spacer()
                            Text(distanceFilterLabel(estimatedDistanceFilterM))
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { estimatedDistanceFilterM },
                                set: { estimatedDistanceFilterM = snappedDistanceFilter($0) }
                            ),
                            in: 1...50,
                            step: 1
                        )
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Model Inputs")
                } footer: {
                    Text("These toggles let you quickly model how aggressive settings might affect battery use while mustering.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Include Heading Cost", isOn: $includeHeadingCost)
                    Toggle("Include Background GPS Cost", isOn: $includeBackgroundCost)
                    Toggle("Include 3D Map Cost", isOn: $include3DCost)
                    Toggle("Include Screen Awake Cost", isOn: $includeScreenAwakeCost)
                } header: {
                    Text("Impact Weighting")
                } footer: {
                    Text("Turn weighting items on or off if you want the estimate to be more conservative or more forgiving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if diagnostics.thermalState == .serious || diagnostics.thermalState == .critical {
                    Section {
                        Text("The device is thermally constrained. Consider using a larger distance filter, disabling heading where possible, avoiding 3D map mode, or allowing the screen to sleep sooner.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Thermal Warning")
                    }
                }

                Section {
                    Text("Battery temperature in °C and actual live battery draw are not available through normal public iPhone/iPad app APIs, so this screen shows live battery state plus a practical estimated impact model instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Notes")
                }
            }
        }
        .navigationTitle("Battery & Thermal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            estimatedDistanceFilterM = snappedDistanceFilter(estimatedDistanceFilterM)
        }
    }

    private func snappedDistanceFilter(_ value: Double) -> Double {
        min(max(value.rounded(), 1), 50)
    }

    private func distanceFilterLabel(_ meters: Double) -> String {
        "\(Int(snappedDistanceFilter(meters))) m"
    }

    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .secondary
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    private func impactColor(_ level: AdminBatteryDiagnosticsStore.ImpactLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

@MainActor
private final class AdminBatteryDiagnosticsStore: ObservableObject {

    enum ImpactLevel: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    @Published private(set) var batteryLevelPercent: Int?
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private var cancellables = Set<AnyCancellable>()

    init() {
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        refresh()

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .sink { [weak self] _ in
                self?.refreshBattery()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.refreshPower()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.refreshThermal()
            }
            .store(in: &cancellables)
    }

    deinit {
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    func refresh() {
        refreshBattery()
        refreshPower()
        refreshThermal()
    }

    private func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        batteryLevelPercent = level < 0 ? nil : Int((level * 100).rounded())
        batteryState = UIDevice.current.batteryState
    }

    private func refreshPower() {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func refreshThermal() {
        thermalState = ProcessInfo.processInfo.thermalState
    }

    var batteryStateText: String {
        switch batteryState {
        case .unknown: return "Unknown"
        case .unplugged: return "On Battery"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    var thermalStateText: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    func estimatedImpact(
        includeHeading: Bool,
        includeBackground: Bool,
        include3DMap: Bool,
        includeScreenAwake: Bool,
        followUser: Bool,
        highAccuracyGPS: Bool,
        fastRedraw: Bool,
        distanceFilterMeters: Double,
        sensitivity: Double
    ) -> ImpactLevel {
        var score = 0.0

        if highAccuracyGPS {
            score += 2.2
        } else {
            score += 0.9
        }

        if distanceFilterMeters <= 2 {
            score += 2.0
        } else if distanceFilterMeters <= 5 {
            score += 1.3
        } else if distanceFilterMeters <= 10 {
            score += 0.8
        } else if distanceFilterMeters <= 20 {
            score += 0.4
        } else {
            score += 0.2
        }

        if includeHeading { score += 1.0 }
        if includeBackground { score += 1.4 }
        if include3DMap { score += 1.0 }
        if includeScreenAwake { score += 1.2 }
        if followUser { score += 0.7 }
        if fastRedraw { score += 0.9 }
        if isLowPowerModeEnabled { score += 0.3 }

        switch thermalState {
        case .fair:
            score += 0.5
        case .serious:
            score += 1.2
        case .critical:
            score += 2.0
        case .nominal:
            break
        @unknown default:
            break
        }

        score *= max(0.5, min(2.0, sensitivity))

        if score < 4.0 { return .low }
        if score < 7.5 { return .medium }
        return .high
    }
}

// =========================================================
// MARK: - TPMS
// =========================================================

struct TPMSSettingsView: View {
    @EnvironmentObject private var tpmsStore: TPMSStore
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    @AppStorage(kTPMSEnabledKey) private var tpmsEnabled: Bool = false
    @AppStorage(kTPMSAlertsEnabledKey) private var alertsEnabled: Bool = true
    @AppStorage(kTPMSLowPressureKey) private var lowPressure: Double = 26
    @AppStorage(kTPMSHighPressureKey) private var highPressure: Double = 44

    var body: some View {
        Form {
            Section {
                Toggle("Enable TPMS", isOn: $tpmsEnabled)
                Toggle("Enable pressure alerts", isOn: $alertsEnabled)
            } footer: {
                Text("Turn tyre pressure monitoring and alert popups on or off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Paired sensors", value: "\(tpmsStore.pairedSensorCount) / \(tpmsStore.maxSensors)")

                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(tpmsBluetooth.isBluetoothPoweredOn ? "On" : "Off")
                        .foregroundStyle(tpmsBluetooth.isBluetoothPoweredOn ? .green : .secondary)
                }

                NavigationLink("Manage Sensors") {
                    TPMSSensorListView(
                        lowPressure: lowPressure,
                        highPressure: highPressure,
                        alertsEnabled: alertsEnabled
                    )
                    .environmentObject(tpmsStore)
                    .environmentObject(tpmsBluetooth)
                }
                .disabled(!tpmsEnabled)

                NavigationLink("Pair New Sensor") {
                    TPMSPairingView()
                        .environmentObject(tpmsStore)
                        .environmentObject(tpmsBluetooth)
                }
                .disabled(!tpmsEnabled || tpmsStore.pairedSensorCount >= tpmsStore.maxSensors)
            } header: {
                Text("Sensors")
            } footer: {
                Text("Pair up to 6 sensors, assign them to wheel positions, and rotate them by changing positions later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("Live Sensor Log") {
                    TPMSLogView()
                        .environmentObject(tpmsBluetooth)
                }
            } header: {
                Text("Debug")
            }
            Section {
                HStack {
                    Text("Low pressure alarm")
                    Spacer()
                    Text("\(Int(lowPressure)) psi")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $lowPressure, in: 10...60, step: 1)

                HStack {
                    Text("High pressure alarm")
                    Spacer()
                    Text("\(Int(highPressure)) psi")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $highPressure, in: 20...90, step: 1)
            } header: {
                Text("Alert Thresholds")
            } footer: {
                Text("These are global pressure alarm points for all paired sensors.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let activeAlert = tpmsStore.activeAlert {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activeAlert.message)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)

                        Text("Pressure: \(String(format: "%.1f", activeAlert.pressurePSI)) psi")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear Active Alert") {
                        tpmsStore.clearActiveAlert()
                    }
                } else {
                    Text("No active TPMS alerts.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Live Alert State")
            }

            Section {
                Button("Trigger Test Low Alert") {
                    triggerTestAlert(low: true)
                }
                .disabled(tpmsStore.sensors.isEmpty || !tpmsEnabled)

                Button("Trigger Test High Alert") {
                    triggerTestAlert(low: false)
                }
                .disabled(tpmsStore.sensors.isEmpty || !tpmsEnabled)

                Button("Normalize First Sensor") {
                    normalizeFirstSensor()
                }
                .disabled(tpmsStore.sensors.isEmpty || !tpmsEnabled)
            } header: {
                Text("Testing")
            } footer: {
                Text("These buttons simulate live readings so the alert flow can be tested before real Bluetooth decoding is wired up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("TPMS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeThresholds()
        }
        .onChange(of: lowPressure) { _, _ in
            normalizeThresholds()
        }
        .onChange(of: highPressure) { _, _ in
            normalizeThresholds()
        }
        .alert(
            tpmsStore.activeAlert?.message ?? "TPMS Alert",
            isPresented: Binding(
                get: { tpmsStore.activeAlert != nil && alertsEnabled && tpmsEnabled },
                set: { newValue in
                    if !newValue {
                        tpmsStore.clearActiveAlert()
                    }
                }
            )
        ) {
            Button("OK") {
                tpmsStore.clearActiveAlert()
            }
        } message: {
            if let activeAlert = tpmsStore.activeAlert {
                Text("Current pressure: \(String(format: "%.1f", activeAlert.pressurePSI)) psi")
            }
        }
    }

    private func normalizeThresholds() {
        lowPressure = min(max(lowPressure.rounded(), 10), 60)
        highPressure = min(max(highPressure.rounded(), 20), 90)

        if highPressure <= lowPressure {
            highPressure = min(lowPressure + 1, 90)
        }
    }

    private func triggerTestAlert(low: Bool) {
        guard let firstSensor = tpmsStore.sensors.first else { return }

        let pressure = low ? max(lowPressure - 4, 1) : min(highPressure + 4, 120)

        tpmsStore.ingestMockReading(
            sensorID: firstSensor.sensorID,
            pressurePSI: pressure,
            lowThresholdPSI: lowPressure,
            highThresholdPSI: highPressure,
            alertsEnabled: alertsEnabled && tpmsEnabled
        )
    }

    private func normalizeFirstSensor() {
        guard let firstSensor = tpmsStore.sensors.first else { return }

        let safeMidpoint = ((lowPressure + highPressure) / 2.0).rounded()

        tpmsStore.ingestMockReading(
            sensorID: firstSensor.sensorID,
            pressurePSI: safeMidpoint,
            lowThresholdPSI: lowPressure,
            highThresholdPSI: highPressure,
            alertsEnabled: alertsEnabled && tpmsEnabled
        )
    }
}

private struct TPMSSensorListView: View {
    @EnvironmentObject private var tpmsStore: TPMSStore
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    let lowPressure: Double
    let highPressure: Double
    let alertsEnabled: Bool

    var body: some View {
        List {
            if tpmsStore.sensors.isEmpty {
                Section {
                    Text("No TPMS sensors paired yet.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Go back and use Pair New Sensor to add your first tyre pressure sensor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Sensors") {
                    ForEach(tpmsStore.sensors) { sensor in
                        NavigationLink {
                            TPMSSensorDetailView(
                                sensorID: sensor.id,
                                lowPressure: lowPressure,
                                highPressure: highPressure,
                                alertsEnabled: alertsEnabled
                            )
                            .environmentObject(tpmsStore)
                            .environmentObject(tpmsBluetooth)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(sensor.displayName)
                                        .font(.body.weight(.semibold))

                                    Spacer()

                                    Text(sensor.assignedPosition.shortTitle)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.thinMaterial, in: Capsule())
                                }

                                HStack(spacing: 12) {
                                    Text(sensor.sensorID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let pressure = sensor.pressurePSI {
                                        Text("\(String(format: "%.1f", pressure)) psi")
                                            .font(.caption)
                                            .foregroundStyle(pressureColor(pressure))
                                    } else {
                                        Text("No pressure yet")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: deleteSensors)
                }

                Section {
                    Button("Clear All TPMS Sensors", role: .destructive) {
                        tpmsStore.clearAllSensors()
                    }
                }
            }
        }
        .navigationTitle("Manage Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !tpmsStore.sensors.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func deleteSensors(at offsets: IndexSet) {
        let sensorsToDelete = offsets.map { tpmsStore.sensors[$0] }
        for sensor in sensorsToDelete {
            tpmsStore.removeSensor(id: sensor.id)
        }
    }

    private func pressureColor(_ pressure: Double) -> Color {
        if pressure < lowPressure { return .red }
        if pressure > highPressure { return .orange }
        return .secondary
    }
}

private struct TPMSSensorDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tpmsStore: TPMSStore
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    let sensorID: UUID
    let lowPressure: Double
    let highPressure: Double
    let alertsEnabled: Bool

    @State private var selectedPosition: TPMSWheelPosition = .frontLeft

    private var sensor: TPMSSensor? {
        tpmsStore.sensors.first(where: { $0.id == sensorID })
    }

    var body: some View {
        Form {
            if let sensor {
                Section("Sensor") {
                    LabeledContent("Name", value: sensor.displayName)
                    LabeledContent("Sensor ID", value: sensor.sensorID)
                    LabeledContent("Assigned", value: sensor.assignedPosition.title)

                    if let pressure = sensor.pressurePSI {
                        LabeledContent("Pressure", value: "\(String(format: "%.1f", pressure)) psi")
                    }

                    if let battery = sensor.batteryPercent {
                        LabeledContent("Battery", value: "\(battery)%")
                    }

                    if let lastSeen = sensor.lastSeenAt {
                        LabeledContent("Last seen", value: relativeDate(lastSeen))
                    }
                }

                Section {
                    NavigationLink("Live Sensor Log") {
                        TPMSSensorLogView(
                            sensorID: sensor.sensorID,
                            sensorName: sensor.displayName
                        )
                        .environmentObject(tpmsBluetooth)
                    }
                } header: {
                    Text("Debug")
                }

                Section {
                    Picker("Wheel position", selection: $selectedPosition) {
                        ForEach(TPMSWheelPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }

                    Button("Save Position Change") {
                        tpmsStore.reassignSensor(id: sensor.id, to: selectedPosition)
                    }
                } header: {
                    Text("Reassign")
                } footer: {
                    Text("Use this after tyre rotations to move the paired sensor to a new wheel position.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Test readings") {
                    Button("Set Low Pressure") {
                        tpmsStore.ingestMockReading(
                            sensorID: sensor.sensorID,
                            pressurePSI: max(lowPressure - 4, 1),
                            lowThresholdPSI: lowPressure,
                            highThresholdPSI: highPressure,
                            alertsEnabled: alertsEnabled
                        )
                    }

                    Button("Set Normal Pressure") {
                        tpmsStore.ingestMockReading(
                            sensorID: sensor.sensorID,
                            pressurePSI: ((lowPressure + highPressure) / 2.0).rounded(),
                            lowThresholdPSI: lowPressure,
                            highThresholdPSI: highPressure,
                            alertsEnabled: alertsEnabled
                        )
                    }

                    Button("Set High Pressure") {
                        tpmsStore.ingestMockReading(
                            sensorID: sensor.sensorID,
                            pressurePSI: min(highPressure + 4, 120),
                            lowThresholdPSI: lowPressure,
                            highThresholdPSI: highPressure,
                            alertsEnabled: alertsEnabled
                        )
                    }
                }

                Section {
                    Button("Remove Sensor", role: .destructive) {
                        tpmsStore.removeSensor(id: sensor.id)
                        dismiss()
                    }
                }
            } else {
                Section {
                    Text("Sensor not found.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let sensor {
                selectedPosition = sensor.assignedPosition
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct TPMSPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tpmsStore: TPMSStore
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    @State private var manualSensorName: String = ""
    @State private var manualSensorID: String = ""
    @State private var selectedPosition: TPMSWheelPosition = .frontLeft
    @State private var replaceExistingAtPosition: Bool = true
    @State private var selectedDiscoveredDeviceID: UUID?

    private var normalizedManualSensorID: String {
        manualSensorID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var selectedDiscoveredDevice: TPMSDiscoveredDevice? {
        guard let selectedDiscoveredDeviceID else { return nil }
        return tpmsBluetooth.discoveredDevices.first(where: { $0.id == selectedDiscoveredDeviceID })
    }

    private var existingSensorAtPosition: TPMSSensor? {
        tpmsStore.sensor(for: selectedPosition)
    }

    private var canSaveDiscovered: Bool {
        selectedDiscoveredDevice != nil && (replaceExistingAtPosition || existingSensorAtPosition == nil)
    }

    private var canSaveManual: Bool {
        !normalizedManualSensorID.isEmpty && (replaceExistingAtPosition || existingSensorAtPosition == nil)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(tpmsBluetooth.isBluetoothPoweredOn ? "On" : "Off")
                        .foregroundStyle(tpmsBluetooth.isBluetoothPoweredOn ? .green : .secondary)
                }

                HStack {
                    Text("Scan")
                    Spacer()
                    Text(tpmsBluetooth.isScanning ? "Running" : "Stopped")
                        .foregroundStyle(tpmsBluetooth.isScanning ? .green : .secondary)
                }

                Button(tpmsBluetooth.isScanning ? "Stop Scan" : "Start Scan") {
                    tpmsBluetooth.isScanning ? tpmsBluetooth.stopScan() : tpmsBluetooth.startScan()
                }
                .disabled(!tpmsBluetooth.isBluetoothPoweredOn)

                Button("Clear Discovered Devices") {
                    tpmsBluetooth.clearDiscoveredDevices()
                    selectedDiscoveredDeviceID = nil
                }
                .disabled(tpmsBluetooth.discoveredDevices.isEmpty)
            } header: {
                Text("Bluetooth Discovery")
            } footer: {
                Text("Scan for nearby BLE devices. Any discovered candidates with advertisement data will show here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if tpmsBluetooth.discoveredDevices.isEmpty {
                    Text("No BLE sensors discovered yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(tpmsBluetooth.discoveredDevices), id: \.id) { device in
                        Button {
                            selectedDiscoveredDeviceID = device.id
                            if manualSensorName.isEmpty {
                                manualSensorName = device.displayName
                            }
                        } label: {
                            tpmsDiscoveredDeviceRow(
                                device: device,
                                isSelected: selectedDiscoveredDeviceID == device.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Discovered Sensors")
            }

            Section {
                Picker("Wheel position", selection: $selectedPosition) {
                    ForEach(TPMSWheelPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }

                if let existingSensorAtPosition {
                    Toggle("Replace existing sensor in this position", isOn: $replaceExistingAtPosition)

                    Text("Currently assigned here: \(existingSensorAtPosition.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Assign Position")
            }

            Section {
                TextField("Saved sensor name (optional)", text: $manualSensorName)
                    .textInputAutocapitalization(.words)

                Button("Save Selected BLE Sensor") {
                    saveSelectedBLEDevice()
                }
                .disabled(!canSaveDiscovered)
            } header: {
                Text("Save Discovered Sensor")
            } footer: {
                Text("Tap a discovered BLE candidate above, choose a wheel position, then save it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Sensor name (optional)", text: $manualSensorName)
                    .textInputAutocapitalization(.words)

                TextField("Sensor ID", text: $manualSensorID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("Save Manual Sensor") {
                    saveManualSensor()
                }
                .disabled(!canSaveManual)
            } header: {
                Text("Manual Fallback")
            } footer: {
                Text("Use manual entry if the BLE device is not being decoded properly yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pair New Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let firstFreePosition = TPMSWheelPosition.allCases.first(where: { !tpmsStore.isPositionAssigned($0) }) {
                selectedPosition = firstFreePosition
            }
        }
    }
    @ViewBuilder
    private func tpmsDiscoveredDeviceRow(
        device: TPMSDiscoveredDevice,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .foregroundStyle(.primary)

                Text(device.sensorIDGuess)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text("RSSI \(device.rssi)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if device.hasPayload {
                        Text("Payload")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
    private func saveSelectedBLEDevice() {
        guard let selectedDiscoveredDevice else { return }
        guard replaceExistingAtPosition || existingSensorAtPosition == nil else { return }

        tpmsBluetooth.saveDiscoveredDeviceToStore(
            selectedDiscoveredDevice,
            name: manualSensorName,
            position: selectedPosition
        )

        dismiss()
    }

    private func saveManualSensor() {
        guard canSaveManual else { return }
        guard replaceExistingAtPosition || existingSensorAtPosition == nil else { return }

        tpmsStore.addOrReplaceSensor(
            sensorID: normalizedManualSensorID,
            name: manualSensorName,
            position: selectedPosition
        )

        dismiss()
    }
}
private struct MediaSettingsView: View {
    @AppStorage(kMediaButtonEnabledKey) private var mediaButtonEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Show Media Buttons on Map", isOn: $mediaButtonEnabled)
            } footer: {
                Text("Shows the play/pause and skip controls on the lower left of the map screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
    }
}
// =========================================================
// MARK: - Placeholder
// =========================================================

private struct PlaceholderSettingsDetail: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text("Coming soon")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
