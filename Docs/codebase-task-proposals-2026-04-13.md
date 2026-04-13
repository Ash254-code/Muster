# Codebase Task Proposals (April 13, 2026)

## 1) Typo fix (1 task)

### Task T1 — Rename misspelled settings source file
**Issue:** The settings screen source file is spelled `AdimMapTuningView.swift` while all contained symbols use `Admin...` naming.

**Why this matters:** The filename typo hurts discoverability and slows code search/navigation.

**Proposed fix:**
- Rename `Muster/Settings/AdimMapTuningView.swift` → `Muster/Settings/AdminMapTuningView.swift`.
- Ensure Xcode project references are updated.

**Definition of done:**
- Project builds successfully after rename.
- No stale file references in `project.pbxproj`.

---

## 2) Bug fixes (2 tasks)

### Task B1 — Persist share-session changes after stop/revoke operations
**Issue:** `stopShareSession(_:)` and `revokeInvite(_:)` mutate `activeSessions` / `members` / `pendingInvites` but never call `save()` in success paths.

**Why this is a bug:** Session or invite state may revert after app restart because modified state is not persisted.

**Proposed fix:**
- Call `save()` at the end of successful `stopShareSession(_:)` and `revokeInvite(_:)` mutations.
- Add tests that load persisted state and verify the mutation survives restart.

**Definition of done:**
- Stopping a session remains stopped after relaunch.
- Revoked invites remain removed after relaunch.

### Task B2 — Use timestamp from the active transport when mapping contacts
**Issue:** `mappedContactsWithRadioFallback(_:)` computes a `status` (`CELL`, `XRS`, `STALE`) from `effectiveTransport`, but `updatedAt` always prefers `cellularTimestamp` first via `cellularTimestamp ?? xrsTimestamp`.

**Why this is a bug:** The displayed/forwarded freshness timestamp can be wrong when effective transport is XRS but stale cellular timestamp exists.

**Proposed fix:**
- Choose `updatedAt` by transport:
  - `.cellular` → `cellularTimestamp`
  - `.xrs` / `.stale` → `xrsTimestamp` if available, otherwise fallback logic
- Add unit tests covering mixed timestamp cases.

**Definition of done:**
- Mapped contacts show timestamp aligned with transport source in all tested permutations.

---

## 3) Code comment / documentation discrepancy fixes (2 tasks)

### Task D1 — Reconcile autosteer architecture doc with shipped implementation status
**Issue:** `Docs/AutosteerRealtimeViewPlan.md` presents guidance as a strict plan with “non-negotiable” telemetry requirements and rollout stages, but the app already contains a production guidance-only rendering path.

**Why this matters:** The document reads as pre-implementation planning, which can mislead maintainers about what is already live.

**Proposed fix:**
- Split the doc into:
  - **Implemented now** (current architecture and limits)
  - **Remaining work** (telemetry gaps, future rollout)
- Add references to concrete code locations for the guidance-only viewport path.

**Definition of done:**
- Doc clearly distinguishes completed vs pending items.
- New contributors can map architecture statements to actual code.

### Task D2 — Replace template comments in tests with project-specific intent
**Issue:** Test files still contain generated placeholder comments (“Write your test here…”, “Put setup code here…”), but no commentary on actual app behaviors under test.

**Why this matters:** Placeholder comments create noise and can imply expected coverage exists when it does not.

**Proposed fix:**
- Remove template comments.
- Add concise comments that describe real test purpose and expected behavior.

**Definition of done:**
- No template scaffolding comments remain in test targets.
- Each test file has clear purpose-oriented header comments.

---

## 4) Test improvements (2 tasks)

### Task Q1 — Add unit tests for `SmartETAEstimator` state transitions
**Current gap:** No assertions currently validate ETA transition behavior.

**Proposed tests:**
- `distance == nil` sets `displayText = "Recalc"` and `isRecalculating = true`.
- Under minimum elapsed time, stays in calculating mode.
- Arrival threshold sets `etaSeconds = 0` and `displayText = "Arriving"`.
- Minute-level throttling of display updates behaves as expected.

**Definition of done:**
- Deterministic unit tests with fixed timestamps.
- Edge cases around zero/negative progress covered.

### Task Q2 — Replace smoke UI test with actionable launch and navigation assertions
**Current gap:** UI tests only launch app / capture screenshot without validating key UI states.

**Proposed tests:**
- Assert root tab view appears on launch.
- Assert at least one critical control is hittable (e.g., map/muster entry point).
- Add a simple quick-action handling test path using launch arguments/environment where possible.

**Definition of done:**
- UI test suite fails when core launch/navigation regresses.
- Tests avoid flaky timing by using accessibility identifiers + expectations.
