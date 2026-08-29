# Left/Right Modifier Heatmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distinguish left and right `Shift`, `Option`, and `Cmd` keys in the keyboard heatmap and count them independently for newly collected data.

**Architecture:** Keep the change narrow by introducing explicit left/right modifier key names at the input-capture layer, extending keyboard heatmap normalization to understand those names, and splitting the heatmap layout so each side has a unique key id. Legacy unified modifier keys remain readable for old data but are not migrated or redistributed.

**Tech Stack:** Swift 5, AppKit, XCTest

---

### Task 1: Heatmap normalization tests

**Files:**
- Modify: `KeyStatsTests/AppStatsTests.swift`

- [ ] **Step 1: Write the failing test**

Add coverage for a day containing `LeftShift`, `RightShift`, `LeftOption`, `RightOption`, `LeftCmd`, `RightCmd`, and a legacy unified `Shift` key to verify that the heatmap preserves left/right counts for new keys and still recognizes old unified keys without splitting them.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: FAIL because heatmap normalization does not yet expose separate left/right modifier keys.

- [ ] **Step 3: Write minimal implementation**

Update keyboard heatmap normalization to return explicit left/right modifier key ids and keep legacy unified ids recognized for older persisted data.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: PASS

### Task 2: Input capture for left/right modifiers

**Files:**
- Modify: `KeyStats/InputMonitor.swift`

- [ ] **Step 1: Write the failing test**

Extend the same focused test coverage by incrementing key counts from explicit left/right modifier event names that the monitor should now emit.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: FAIL because `InputMonitor` still emits unified modifier names.

- [ ] **Step 3: Write minimal implementation**

Map left/right modifier key codes to `LeftShift`, `RightShift`, `LeftOption`, `RightOption`, `LeftCmd`, and `RightCmd` before building combo names, without changing unrelated key naming.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: PASS

### Task 3: Heatmap layout split

**Files:**
- Modify: `KeyStats/KeyboardHeatmapViewController.swift`
- Modify: `KeyStats/StatsPopoverViewController.swift`

- [ ] **Step 1: Write the failing test**

Use the existing heatmap data test to assert the distinct layout ids are addressable by the aggregated counts.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: FAIL because the layout still reuses `Shift`, `Option`, and `Cmd` ids on both sides.

- [ ] **Step 3: Write minimal implementation**

Give left/right modifier keys distinct heatmap ids and update any shared symbol-name mapping so labels/icons still render correctly in list views.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: PASS

### Task 4: Verification

**Files:**
- Verify: `KeyStats/InputMonitor.swift`
- Verify: `KeyStats/StatsManager.swift`
- Verify: `KeyStats/KeyboardHeatmapViewController.swift`
- Verify: `KeyStats/StatsPopoverViewController.swift`
- Verify: `KeyStatsTests/AppStatsTests.swift`

- [ ] **Step 1: Run focused tests**

Run: `xcodebuild test -project KeyStats.xcodeproj -scheme KeyStats -only-testing:KeyStatsTests/AppStatsTests`
Expected: PASS

- [ ] **Step 2: Run build verification**

Run: `xcodebuild -project KeyStats.xcodeproj -scheme KeyStats -configuration Debug build`
Expected: BUILD SUCCEEDED
