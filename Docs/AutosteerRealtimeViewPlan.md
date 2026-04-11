# Autosteer Real-Time Accuracy + Smoothness Plan

## Decision: use a dedicated Autosteer Guidance view

Yes — for steering, use a dedicated view that is separate from the full map browsing view.

A full map background should be optional, not mandatory, while steering is active.

Why:
- Steering needs deterministic frame timing, while map rendering is bursty and can stutter under load.
- You can decouple high-rate guidance updates from lower-rate map/UI updates.
- It reduces visual clutter so operators can react faster.

Recommended modes:
1. **Guidance mode (default while steering):** no map tiles; guidance line, cross-track error, heading, speed, GNSS quality.
2. **Map assist mode (optional):** lightweight map at lower update cadence.

## Target performance budgets

For sub-2 cm while moving, the control pipeline needs strict latency and jitter budgets.

- GNSS/INS ingest: 20–50 Hz input, <10 ms parse + validation.
- Guidance solver: 50–100 Hz deterministic loop (fixed timestep).
- Steering command output: 20–50 Hz with timestamped commands.
- UI rendering: 60 FPS target, but never block guidance/control thread.
- End-to-end sensor-to-command latency target: ideally <80 ms, consistently.

## Core architecture changes

1. **Split loops by responsibility**
   - **Control loop (real-time priority):** sensor fusion, line selection, cross-track error, steering output.
   - **UI loop (main thread):** display-only, reads latest snapshot from control state.
   - **Persistence/logging loop:** async buffered writes.

2. **State handoff strategy**
   - Maintain a single latest immutable `GuidanceSnapshot` (timestamped).
   - UI polls/subscribes to snapshots; no expensive transforms on main thread.
   - Never do geodesy computations in SwiftUI view body.

3. **Map decoupling**
   - In Guidance mode, avoid map tile rendering entirely.
   - If map is enabled, cap map camera updates (e.g., 10–15 Hz) while control still runs at high rate.

4. **Numerical stability + filtering**
   - Use local tangent plane math (ENU/NED) for short-range guidance.
   - Keep heading/course smoothing separate from cross-track filtering.
   - Filter with bounded-latency methods (e.g., tuned alpha-beta/Kalman) and log innovation spikes.

5. **Quality gates before steering engage**
   - Require RTK fixed and acceptable age of corrections.
   - Require speed floor and heading validity checks.
   - Fail-safe to manual if quality or timing drops below threshold.

## UI/UX recommendations for steering screen

Minimal, high-contrast, low-latency elements only:
- Cross-track error in cm (large numeric).
- Lightbar/needle deviation.
- Current line index + side (left/right).
- Speed, heading, and GNSS status (RTK fixed/float, HDOP, correction age).
- Engage/disengage + hard fault banner.

Avoid heavy transitions, blur, and animated map camera while engaged.

## Instrumentation required (non-negotiable)

Add telemetry for:
- Sensor timestamp vs receive time.
- Guidance loop duration + jitter histogram.
- Command output latency.
- UI frame time and dropped frame count.
- GNSS mode transitions and correction age.

Without this, tuning for sub-2 cm will be guesswork.

## Suggested rollout

1. Build Guidance-only screen behind a feature flag.
2. Keep existing map screen for setup/planning.
3. Add profiler overlay with loop rate and latency.
4. Run field tests and tune filters/loop rates.
5. Only then enable map assist option during steering.

## Practical takeaway

If your primary goal is **sub-2 cm while moving**, treat steering as a real-time control product first and a map app second.

A separate, map-optional guidance view is the right architecture.
