//
//  MusterLiveActivityLiveActivity.swift
//  MusterLiveActivity
//

import ActivityKit
import WidgetKit
import SwiftUI

struct MusterLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoToMarkerAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(1.0))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    leadingExpandedView(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    trailingExpandedView(context: context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    bottomExpandedView(context: context)
                }
            } compactLeading: {
                compactLeadingView(context: context)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                minimalView(context: context)
            }
            .keylineTint(.white)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 52, height: 52)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Track Active")
                        .font(.headline)
                        .lineLimit(1)

                    Text(distanceText(context.state.recordingDistanceMeters ?? 0))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 52, height: 52)

                    if isShowingRadioOverride(context) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: context.state.arrived ? "checkmark.circle.fill" : "location.north.fill")
                            .font(.system(size: 24, weight: .bold))
                            .rotationEffect(.degrees(context.state.arrived ? 0 : context.state.relativeBearingDegrees))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let radioUser = context.state.radioUser,
                       let radioDistanceMeters = context.state.radioDistanceMeters {
                        Text("Radio Update")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(radioUser)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let radioBearing = context.state.radioRelativeBearingDegrees {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .rotationEffect(.degrees(radioBearing))
                            }

                            Text(distanceText(radioDistanceMeters))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                        }
                    } else {
                        Text("Go To Marker")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(context.attributes.markerName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(context.state.arrived ? "Arrived" : distanceText(context.state.distanceMeters))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func leadingExpandedView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            Circle()
                .fill(Color.red)
                .frame(width: 18, height: 18)
        } else if isShowingRadioOverride(context) {
            if let radioBearing = context.state.radioRelativeBearingDegrees {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 22, weight: .bold))
                    .rotationEffect(.degrees(radioBearing))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .bold))
            }
        } else {
            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .bold))
                .rotationEffect(.degrees(context.state.relativeBearingDegrees))
        }
    }

    @ViewBuilder
    private func trailingExpandedView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Distance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(distanceText(context.state.recordingDistanceMeters ?? 0))
                    .font(.headline)
                    .bold()
                    .monospacedDigit()
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                if let radioDistanceMeters = context.state.radioDistanceMeters,
                   isShowingRadioOverride(context) {
                    Text("Radio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(distanceText(radioDistanceMeters))
                        .font(.headline)
                        .bold()
                        .monospacedDigit()
                } else {
                    Text(context.state.arrived ? "Arrived" : "Distance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(distanceText(context.state.distanceMeters))
                        .font(.headline)
                        .bold()
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func bottomExpandedView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Track is running")
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

                    Text(shortDistanceText(context.state.recordingDistanceMeters ?? 0))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let radioUser = context.state.radioUser,
                       isShowingRadioOverride(context) {
                        Text("Radio Update")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(radioUser)
                            .font(.headline)
                            .lineLimit(1)
                    } else {
                        Text("Go To")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(context.attributes.markerName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let radioBearing = context.state.radioRelativeBearingDegrees,
                   isShowingRadioOverride(context) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                            .rotationEffect(.degrees(radioBearing))
                        Text("Mate")
                            .font(.subheadline.weight(.semibold))
                    }
                } else if context.state.arrived {
                    Label("Arrived", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func compactLeadingView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
        } else if let radioBearing = context.state.radioRelativeBearingDegrees,
                  isShowingRadioOverride(context) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 15, weight: .bold))
                .rotationEffect(.degrees(radioBearing))
        } else if isShowingRadioOverride(context) {
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .bold))
        } else {
            Image(systemName: "location.north.fill")
                .font(.system(size: 15, weight: .bold))
                .rotationEffect(.degrees(context.state.relativeBearingDegrees))
        }
    }

    @ViewBuilder
    private func compactTrailingView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            Text(shortDistanceText(context.state.recordingDistanceMeters ?? 0))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else if let radioDistanceMeters = context.state.radioDistanceMeters,
                  isShowingRadioOverride(context) {
            Text(shortDistanceText(radioDistanceMeters))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        } else {
            Text(shortDistanceText(context.state.distanceMeters))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<GoToMarkerAttributes>) -> some View {
        if context.state.presentationMode == .recording {
            Circle()
                .fill(Color.red)
        } else if isShowingRadioOverride(context) {
            Image(systemName: "person.fill")
        } else {
            Image(systemName: context.state.arrived ? "checkmark.circle.fill" : "location.north.fill")
        }
    }

    private func isShowingRadioOverride(_ context: ActivityViewContext<GoToMarkerAttributes>) -> Bool {
        context.state.presentationMode != .recording &&
        context.state.radioUser != nil &&
        context.state.radioDistanceMeters != nil
    }

    private func distanceText(_ meters: Double) -> String {
        if meters < 30 { return "0.0 km" }
        if meters < 1000 { return String(format: "%.2f km", meters / 1000.0) }
        return String(format: "%.1f km", meters / 1000.0)
    }

    private func shortDistanceText(_ meters: Double) -> String {
        if meters < 30 { return "0.0k" }
        if meters < 1000 { return String(format: "%.2fk", meters / 1000.0) }
        return String(format: "%.1fk", meters / 1000.0)
    }
}

#Preview("Notification", as: .content, using: GoToMarkerAttributes(
    markerName: "North Gate",
    lat: -34.0,
    lon: 138.0
)) {
    MusterLiveActivityLiveActivity()
} contentStates: {
    GoToMarkerAttributes.ContentState(
        distanceMeters: 420,
        relativeBearingDegrees: 35,
        arrived: false,
        radioUser: nil,
        radioDistanceMeters: nil,
        radioRelativeBearingDegrees: nil,
        presentationMode: .goTo,
        recordingActive: false,
        recordingDistanceMeters: nil
    )

    GoToMarkerAttributes.ContentState(
        distanceMeters: 12,
        relativeBearingDegrees: 0,
        arrived: true,
        radioUser: nil,
        radioDistanceMeters: nil,
        radioRelativeBearingDegrees: nil,
        presentationMode: .goTo,
        recordingActive: false,
        recordingDistanceMeters: nil
    )

    GoToMarkerAttributes.ContentState(
        distanceMeters: 420,
        relativeBearingDegrees: 35,
        arrived: false,
        radioUser: "Tom",
        radioDistanceMeters: 350,
        radioRelativeBearingDegrees: 18,
        presentationMode: .goTo,
        recordingActive: false,
        recordingDistanceMeters: nil
    )

    GoToMarkerAttributes.ContentState(
        distanceMeters: 0,
        relativeBearingDegrees: 0,
        arrived: false,
        radioUser: nil,
        radioDistanceMeters: nil,
        radioRelativeBearingDegrees: nil,
        presentationMode: .recording,
        recordingActive: true,
        recordingDistanceMeters: 12430
    )
}
