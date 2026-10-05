//
//  CombinedPeakModeRowView.swift
//  GuitarTap
//
// @parity view/peak-card

/// # CombinedPeakModeRowView
///
/// A list row showing a single `ResonantPeak` with its guitar mode
/// classification, allowing the user to select/deselect the peak and
/// assign a custom mode label override.
///
/// ## Layout
///
/// ```
/// [star toggle]  [mode icon + range indicator]  [peak info + mode label]  [picker]
/// ```
///
/// - The **star toggle** calls `onToggleSelection` when tapped; it is hidden
///   when `onToggleSelection` is `nil`.
/// - The **mode icon** uses `GuitarMode.icon` and `GuitarMode.color`; a
///   checkmark or warning badge indicates whether the peak frequency falls
///   within the mode's ideal range.
/// - The **peak info** column shows frequency (Hz), magnitude (dBFS), and
///   optionally Q-factor and pitch (note + cents deviation).
/// - The **mode label** picker presents a quick-pick list of common names
///   plus a "Custom…" text entry. Selecting a name calls
///   `onSetModeOverride`; "Reset to Auto" calls `onResetModeOverride`.
///
/// ## Mode Override Presentation
///
/// - macOS: the picker appears as a `Popover`.
/// - iOS compact: the picker appears as a sheet (`showModePickerSheet`).
///
/// - SeeAlso: `TapAnalysisResultsView`, `UserAssignedMode`

import SwiftUI

struct CombinedPeakModeRowView: View {
    /// The resonant peak this row displays.
    let peak: ResonantPeak
    /// Auto-classified guitar mode for the peak (drives the in-range badge).
    let mode: GuitarMode
    /// The mode a "Reset to Auto-Detected" would restore this peak to — the auto-classification with
    /// no override applied. Names the reset menu item's target, NOT the peak's current label (which,
    /// after an override, would be the name the user just assigned). Defaults to ``mode`` for the
    /// read-only call sites that never show the reset item.
    var autoDetectedMode: GuitarMode? = nil
    /// Effective label to display (auto-detected or user override)
    var effectiveModeLabel: String
    /// Whether the label has been manually overridden by the user
    var isManualOverride: Bool = false
    /// Whether this peak is currently selected (filled star).
    var isSelected: Bool = true
    /// Called when the star is tapped to toggle selection; the star is hidden when nil.
    var onToggleSelection: (() -> Void)? = nil
    /// Called when the user picks a mode label (from quick-list or custom text)
    var onSetModeOverride: ((String) -> Void)? = nil
    /// Called when the user resets back to auto-detection
    var onResetModeOverride: (() -> Void)? = nil

    @State private var showCustomLabelPopover = false
    @State private var customLabelDraft = ""
    @State private var showModePickerSheet = false

    /// Whether the override label is freeform text (not a predefined GuitarMode).
    private var isFreeformOverride: Bool {
        isManualOverride && GuitarMode.fromDisplayName(effectiveModeLabel) == nil
    }

    /// Effective display color: user-defined teal for freeform overrides,
    /// otherwise the mode's standard color.
    private var displayColor: Color { Palette.color(displayRole) }

    /// The role of the effective display colour.
    private var displayRole: Palette.Role {
        isFreeformOverride ? .modeUserDefined : Palette.role(mode)
    }

    /// Effective display icon: tag for freeform overrides,
    /// otherwise the mode's standard icon.
    private var displayIcon: String {
        isFreeformOverride ? GuitarMode.userDefinedIcon : mode.icon
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection toggle button
            if let toggleAction = onToggleSelection {
                Button {
                    toggleAction()
                } label: {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .foregroundColor(Palette.color(isSelected ? .peakSelectedStar : .peakUnselectedStar))
                        .font(.body)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect peak" : "Select peak")
            }

            // Mode icon and color
            VStack(spacing: 4) {
                Image(systemName: displayIcon)
                    .foregroundColor(displayColor)
                    .font(.title3)
                    .frame(width: 30, height: 30)

                // Mode range indicator
                if mode != .unknown && mode != .upperModes {
                    let inRange = mode.modeRange.contains(peak.frequency)
                    Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.color(inRange ? .peakInRange : .peakOutOfRange))
                        .font(.caption2)
                }
            }

            // Peak and mode information
            VStack(alignment: .leading, spacing: 6) {
                // Mode name and frequency
                HStack {
                    modeLabelView

                    Spacer()

                    Text("\(FieldPrecision.string(peak.frequency, FieldPrecision.peakFrequencyHz)) Hz")
                        .font(.headline)
                        .foregroundColor(Palette.color(.textPrimary))
                }

                // Pitch information (prominent)
                if peak.pitchNote != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundColor(Palette.color(.peakPitch))

                        Text(peak.formattedPitch)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Palette.color(.peakPitch))
                    }
                }

                // Peak details
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Q:")
                            .font(.caption)
                            .foregroundColor(Palette.color(.textSecondary))
                        Text(FieldPrecision.string(peak.quality, FieldPrecision.qFactor))
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 4) {
                        Text("BW:")
                            .font(.caption)
                            .foregroundColor(Palette.color(.textSecondary))
                        Text("\(FieldPrecision.string(peak.bandwidth, FieldPrecision.bandwidthHz)) Hz")
                            .font(.caption)
                            .fontWeight(.medium)
                            .fixedSize()
                    }

                    Spacer()

                    // Magnitude with color coding
                    Text("\(FieldPrecision.string(peak.magnitude, FieldPrecision.peakMagnitudeDB)) dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Palette.color(Palette.role(magnitude: peak.magnitude)))
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Palette.color(displayRole, opacity: .peakRowTint))
        .cornerRadius(8)
    }

    // MARK: - Mode Label (Menu or plain Text)

    @ViewBuilder
    private var modeLabelView: some View {
        if onSetModeOverride != nil {
            modeLabelButton
                .popover(isPresented: $showCustomLabelPopover, arrowEdge: .bottom) {
                    CustomModeLabelPopover(draft: $customLabelDraft) { label in
                        onSetModeOverride?(label)
                    }
                }
                #if os(iOS)
                .sheet(isPresented: $showModePickerSheet) {
                    ModePickerSheet(
                        currentLabel: effectiveModeLabel,
                        isManualOverride: isManualOverride,
                        autoLabel: (autoDetectedMode ?? mode).displayName,
                        onSelect: { label in onSetModeOverride?(label) },
                        onReset: onResetModeOverride,
                        onCustom: {
                            customLabelDraft = isManualOverride ? effectiveModeLabel : ""
                            showModePickerSheet = false
                            // Small delay so the sheet dismisses before the popover opens
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showCustomLabelPopover = true
                            }
                        }
                    )
                }
                #endif
        } else {
            // Read-only fallback (no callbacks provided)
            Text(effectiveModeLabel)
                .font(.headline)
                .foregroundColor(displayColor)
                .lineLimit(1)
                .truncationMode(.tail)
                #if os(macOS)
                .help(effectiveModeLabel)
                #endif
        }
    }

    @ViewBuilder
    private var modeLabelButton: some View {
        #if os(iOS)
        // On iOS, Menu is an action sheet with a fixed max height — use a scrollable sheet instead
        Button {
            showModePickerSheet = true
        } label: {
            modeLabelContent
        }
        .buttonStyle(.plain)
        #else
        Menu {
            // Reset option shown only when there is an active override
            if isManualOverride {
                Button {
                    onResetModeOverride?()
                } label: {
                    Label("Reset to Auto-Detected (\((autoDetectedMode ?? mode).displayName))", systemImage: "arrow.counterclockwise")
                }
                Divider()
            }

            // Quick-pick: standard guitar tap-tone modes
            ForEach(UserAssignedMode.guitarTapModes, id: \.self) { label in
                Button(label) { onSetModeOverride?(label) }
            }

            Divider()

            // Quick-pick: extended modes
            ForEach(UserAssignedMode.additionalModes, id: \.self) { label in
                Button(label) { onSetModeOverride?(label) }
            }

            Divider()

            // Free-text entry
            Button {
                customLabelDraft = isManualOverride ? effectiveModeLabel : ""
                showCustomLabelPopover = true
            } label: {
                Label("Custom…", systemImage: "pencil")
            }
        } label: {
            modeLabelContent
        }
        .buttonStyle(.plain)
        .help(isManualOverride
              ? "Manually assigned — tap to change or reset"
              : "Tap to assign a mode label")
        #endif
    }

    private var modeLabelContent: some View {
        // A manually overridden mode is shown italic with a trailing " *" — the ONE convention used
        // everywhere (peak list, annotation, PDF, multi-tap/comparison tables). No glyph: at label
        // size a small icon was unreadable. The separate in-range check/triangle badge is unrelated.
        HStack(spacing: 4) {
            #if os(macOS)
            // Fixed-width label column: capped at the width of the longest predefined
            // mode name. The hidden Text sets the frame via layout; the overlay renders
            // the actual label on top without affecting the measured size, so custom
            // labels longer than the cap are clipped/truncated rather than expanding.
            Text(UserAssignedMode.longestPredefinedLabel)
                .font(.headline)
                .hidden()
                .help(effectiveModeLabel)
                .overlay(alignment: .leading) {
                    Text(effectiveModeLabel + (isManualOverride ? " *" : ""))
                        .font(isManualOverride ? .headline.italic() : .headline)
                        .foregroundColor(displayColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            #else
            Text(effectiveModeLabel + (isManualOverride ? " *" : ""))
                .font(isManualOverride ? .headline.italic() : .headline)
                .foregroundColor(displayColor)
                .lineLimit(1)
                .truncationMode(.tail)
            #endif
        }
    }
}

// MARK: - Mode Picker Sheet (iOS only)

#if os(iOS)
/// A scrollable sheet showing all mode suggestions, used on iOS where Menu is height-limited.
private struct ModePickerSheet: View {
    let currentLabel: String
    let isManualOverride: Bool
    let autoLabel: String
    let onSelect: (String) -> Void
    let onReset: (() -> Void)?
    let onCustom: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isManualOverride {
                    Section {
                        Button {
                            onReset?()
                            dismiss()
                        } label: {
                            Label("Reset to Auto-Detected (\(autoLabel))", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                Section("Standard Modes") {
                    ForEach(UserAssignedMode.guitarTapModes, id: \.self) { label in
                        Button {
                            onSelect(label)
                            dismiss()
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundColor(Palette.color(.textPrimary))
                                Spacer()
                                if label == currentLabel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Palette.color(.accentText))
                                }
                            }
                        }
                    }
                }

                Section("Extended Modes") {
                    ForEach(UserAssignedMode.additionalModes, id: \.self) { label in
                        Button {
                            onSelect(label)
                            dismiss()
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundColor(Palette.color(.textPrimary))
                                Spacer()
                                if label == currentLabel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Palette.color(.accentText))
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        onCustom()
                        dismiss()
                    } label: {
                        Label("Custom…", systemImage: "pencil")
                    }
                }
            }
            .navigationTitle("Assign Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif

// MARK: - Custom Mode Label Popover

/// A small popover that lets the user type an arbitrary mode label.
private struct CustomModeLabelPopover: View {
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    let onAssign: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Mode Label")
                .font(.headline)

            TextField("e.g. Cross Dipole, T(1,0)…", text: $draft)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Assign") {
                    let trimmed = draft.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onAssign(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 260)
        #else
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(160)])
        .presentationDragIndicator(.visible)
        #endif
    }
}
