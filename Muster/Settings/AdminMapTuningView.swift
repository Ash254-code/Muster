import SwiftUI

// Admin / tuning keys
let kAdminRingRebuildDistanceKey = "admin_ring_rebuild_distance_m"     // Double
let kAdminHeadingDeadbandKey = "admin_heading_deadband_deg"            // Double
let kAdminMinSpeedForCourseKey = "admin_min_speed_for_course_mps"      // Double
let kAdminBottomSheetSnapThresholdKey = "admin_bottom_sheet_snap_pts"  // Double
let kAdminBottomSheetSpringResponseKey = "admin_bottom_sheet_spring_r" // Double
let kAdminBottomSheetSpringDampingKey = "admin_bottom_sheet_spring_d"  // Double
let kAdminRightControlsBottomGapKey = "admin_right_controls_bottom_gap"// Double

struct AdminMapTuningDefaults {
    static let ringRebuildDistance: Double = 10
    static let headingDeadband: Double = 2
    static let minSpeedForCourse: Double = 1.0
    static let bottomSheetSnapThreshold: Double = 50
    static let bottomSheetSpringResponse: Double = 0.5
    static let bottomSheetSpringDamping: Double = 0.70
    static let rightControlsBottomGap: Double = 130
    
}

struct AdminMapTuningView: View {

    @AppStorage(kAdminRingRebuildDistanceKey)
    private var ringRebuildDistance: Double = AdminMapTuningDefaults.ringRebuildDistance

    @AppStorage(kAdminHeadingDeadbandKey)
    private var headingDeadband: Double = AdminMapTuningDefaults.headingDeadband

    @AppStorage(kAdminMinSpeedForCourseKey)
    private var minSpeedForCourse: Double = AdminMapTuningDefaults.minSpeedForCourse

    @AppStorage(kAdminBottomSheetSnapThresholdKey)
    private var bottomSheetSnapThreshold: Double = AdminMapTuningDefaults.bottomSheetSnapThreshold

    @AppStorage(kAdminBottomSheetSpringResponseKey)
    private var bottomSheetSpringResponse: Double = AdminMapTuningDefaults.bottomSheetSpringResponse

    @AppStorage(kAdminBottomSheetSpringDampingKey)
    private var bottomSheetSpringDamping: Double = AdminMapTuningDefaults.bottomSheetSpringDamping

    @AppStorage(kAdminRightControlsBottomGapKey)
    private var rightControlsBottomGap: Double = AdminMapTuningDefaults.rightControlsBottomGap

    var body: some View {
        Form {
            Section("Map Motion") {
                AdminSliderRow(
                    title: "Ring rebuild distance",
                    subtitle: "Higher = smoother rings, lower = more reactive.",
                    value: $ringRebuildDistance,
                    range: 5...30,
                    step: 1,
                    format: { "\(Int($0)) m" },
                    defaultValue: AdminMapTuningDefaults.ringRebuildDistance
                )

                AdminSliderRow(
                    title: "Heading deadband",
                    subtitle: "Ignores tiny heading changes to reduce arrow wobble.",
                    value: $headingDeadband,
                    range: 0...20,
                    step: 1,
                    format: { "\(Int($0))°" },
                    defaultValue: AdminMapTuningDefaults.headingDeadband
                )

                AdminSliderRow(
                    title: "Min speed for course heading",
                    subtitle: "Below this speed, course-based heading is ignored.",
                    value: $minSpeedForCourse,
                    range: 0...5,
                    step: 0.1,
                    format: { String(format: "%.1f m/s", $0) },
                    defaultValue: AdminMapTuningDefaults.minSpeedForCourse
                )
            }

            Section("Bottom Sheet") {
                AdminSliderRow(
                    title: "Snap threshold",
                    subtitle: "How far you drag before the sheet snaps to the next detent.",
                    value: $bottomSheetSnapThreshold,
                    range: 30...160,
                    step: 1,
                    format: { "\(Int($0)) pt" },
                    defaultValue: AdminMapTuningDefaults.bottomSheetSnapThreshold
                )

                AdminSliderRow(
                    title: "Spring response",
                    subtitle: "Lower = snappier. Higher = softer.",
                    value: $bottomSheetSpringResponse,
                    range: 0.15...0.8,
                    step: 0.01,
                    format: { String(format: "%.2f", $0) },
                    defaultValue: AdminMapTuningDefaults.bottomSheetSpringResponse
                )

                AdminSliderRow(
                    title: "Spring damping",
                    subtitle: "Higher = less bounce. Lower = more bounce.",
                    value: $bottomSheetSpringDamping,
                    range: 0.5...1.2,
                    step: 0.01,
                    format: { String(format: "%.2f", $0) },
                    defaultValue: AdminMapTuningDefaults.bottomSheetSpringDamping
                )
            }

            Section("Overlay Positioning") {
                AdminSliderRow(
                    title: "Right control bottom gap",
                    subtitle: "Distance between the right control pill and the bottom area.",
                    value: $rightControlsBottomGap,
                    range: 40...180,
                    step: 1,
                    format: { "\(Int($0)) pt" },
                    defaultValue: AdminMapTuningDefaults.rightControlsBottomGap
                )
            }

            Section("Reset") {
                Button("Reset all tuning to defaults") {
                    resetAll()
                }
                .foregroundStyle(.red)

                Text("These controls are for field tuning. Defaults are marked under each slider so you can always get back to a known-good setup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Map Tuning")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resetAll() {
        ringRebuildDistance = AdminMapTuningDefaults.ringRebuildDistance
        headingDeadband = AdminMapTuningDefaults.headingDeadband
        minSpeedForCourse = AdminMapTuningDefaults.minSpeedForCourse
        bottomSheetSnapThreshold = AdminMapTuningDefaults.bottomSheetSnapThreshold
        bottomSheetSpringResponse = AdminMapTuningDefaults.bottomSheetSpringResponse
        bottomSheetSpringDamping = AdminMapTuningDefaults.bottomSheetSpringDamping
        rightControlsBottomGap = AdminMapTuningDefaults.rightControlsBottomGap
    }
}

struct AdminSliderRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let defaultValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)

            HStack {
                Text(format(range.lowerBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Default \(format(defaultValue))")
                    .font(.caption)
                    .foregroundStyle(isNearDefault ? .green : .secondary)

                Spacer()

                Text(format(range.upperBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reset to Default") {
                    value = defaultValue
                }
                .font(.footnote.weight(.semibold))
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var isNearDefault: Bool {
        abs(value - defaultValue) < max(step, 0.011)
    }
}
