import SwiftUI
import UIKit
import Combine

#if canImport(UIKit)
import UIKit
#endif

// Shared keys (must match MapMainView / MapViewRepresentable usage)
private let kRingCountKey = "rings_count"              // Int
private let kRingSpacingKey = "rings_spacing_m"        // Double
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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @AppStorage(kAppearanceModeKey) private var appearanceMode: String = "system"

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink("Units") {
                        PlaceholderSettingsDetail(title: "Units")
                    }

                    NavigationLink("Appearance") {
                        AppearanceSettingsView()
                    }

                    NavigationLink("Bluetooth") {
                        BluetoothSettingsView()
                    }

                    NavigationLink("Media") {
                        MediaSettingsView()
                    }

                    NavigationLink("Group Tracking") {
                        GroupTrackingSettingsView()
                    }
                }

                Section("Map") {
                    NavigationLink("Map & Rings") {
                        RingsSettingsView()
                    }

                    NavigationLink("Top Pills") {
                        TopPillsSettingsView()
                    }

                    NavigationLink("Marker Templates") {
                        MarkerTemplatesSettingsView()
                            .environmentObject(app)
                    }

                    NavigationLink("Quick Drop Pin") {
                        SheepPinSettingsView()
                    }

                    NavigationLink("Advanced Map") {
                        AdvancedMapSettingsView()
                    }
                }

                Section("Imports") {
                    NavigationLink("Imported Files") {
                        ImportExportView()
                            .environmentObject(app)
                    }

                    NavigationLink("Import Categories") {
                        ImportCategoriesSettingsView()
                            .environmentObject(app)
                    }
                }

                Section("Admin") {
                    NavigationLink("Map Tuning") {
                        AdminMapTuningView()
                    }

                    NavigationLink("XRS Radio Debug") {
                        BLERadioDebugView()
                    }

                    NavigationLink("Battery & Thermal") {
                        BatteryThermalSettingsView()
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
// MARK: - Appearance
// =========================================================

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

    var body: some View {
        List {
            Section {
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
            } header: {
                Text("Categories")
            } footer: {
                Text("Choose the icon or emoji used for each imported category. Boundaries and Tracks can also have their own colours. Visibility here sets the default filter state used on the map.")
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

    @AppStorage(kXRSRadioMarkerLimitKey) private var markerLimit: Int = 1
    @AppStorage(kXRSRadioExpiryMinutesKey) private var expiryMinutes: Int = 120

    private let markerLimitOptions = Array(1...10)
    private let expiryOptions = Array(stride(from: 15, through: 600, by: 15))

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

                Text("Radio markers older than \(expiryLabel) will be removed automatically once XRSRadioStore is wired to these settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Expiry")
            }

            Section("Current selection") {
                LabeledContent("Markers per user", value: "\(markerLimit)")
                LabeledContent("Visibility time", value: expiryLabel)
            }

            Section("Later additions") {
                Text("Show radio trails")
                Text("Radio label size")
                Text("Radio freshness fade timing")
            }
            .foregroundStyle(.secondary)
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
    }
}

private struct MediaSettingsView: View {
    @AppStorage(kMediaButtonEnabledKey) private var mediaButtonEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Show media button on map", isOn: $mediaButtonEnabled)
            } footer: {
                Text("Shows a media control pill on the left side of the map. The top half skips forward and the bottom half plays or pauses audio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =========================================================
// MARK: - Rings + Map Settings
// =========================================================

private struct RingsSettingsView: View {

    @AppStorage(kRingCountKey) private var ringCount: Int = 4
    @AppStorage(kRingSpacingKey) private var ringSpacingM: Double = 100
    @AppStorage(kMapOrientationKey) private var orientationRaw: String = "headsUp"
    @AppStorage(kHeadsUpPitchDegreesKey) private var headsUpPitchDegrees: Double = 45
    @AppStorage(kHeadsUpUserVerticalOffsetKey) private var headsUpUserVerticalOffset: Double = 10

    private var isHeadsUp: Bool { orientationRaw == "headsUp" }

    private let countOptions = Array(1...10)
    private let spacingOptions: [Double] = Array(stride(from: 250, through: 2500, by: 250))
    private let headsUpPitchOptions: [Double] = [0, 45, 80]

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

                Text("Showing \(ringCount) rings at \(Int(ringSpacingM)) metre intervals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Distance Rings")
            }

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
        .navigationTitle("Map & Rings")
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
