//
//  CombinedPeakModeRowView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

struct CombinedPeakModeRowView: View {
    let peak: ResonantPeak
    let mode: GuitarMode
    /// Effective label to display (auto-detected or user override)
    var effectiveModeLabel: String
    /// Whether the label has been manually overridden by the user
    var isManualOverride: Bool = false
    var isSelected: Bool = true
    var onToggleSelection: (() -> Void)? = nil
    /// Called when the user picks a mode label (from quick-list or custom text)
    var onSetModeOverride: ((String) -> Void)? = nil
    /// Called when the user resets back to auto-detection
    var onResetModeOverride: (() -> Void)? = nil

    @State private var showCustomLabelPopover = false
    @State private var customLabelDraft = ""
    @State private var showModePickerSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection toggle button
            if let toggleAction = onToggleSelection {
                Button {
                    toggleAction()
                } label: {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.body)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect peak" : "Select peak")
            }

            // Mode icon and color
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .foregroundColor(mode.color)
                    .font(.title3)
                    .frame(width: 30, height: 30)

                // Mode range indicator
                if mode != .unknown && mode != .upperModes {
                    let inRange = mode.idealRange.contains(peak.frequency)
                    Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(inRange ? .green : .orange)
                        .font(.caption2)
                }
            }

            // Peak and mode information
            VStack(alignment: .leading, spacing: 6) {
                // Mode name and frequency
                HStack {
                    modeLabelView

                    Spacer()

                    Text("\(peak.frequency, specifier: "%.2f") Hz")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                // Pitch information (prominent)
                if peak.pitchNote != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundColor(.purple)

                        Text(peak.formattedPitch)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                }

                // Peak details
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Q:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.quality, specifier: "%.1f")")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 4) {
                        Text("BW:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.bandwidth, specifier: "%.1f") Hz")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    // Magnitude with color coding
                    Text("\(peak.magnitude, specifier: "%.1f") dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(magnitudeColor(peak.magnitude))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(mode.color.opacity(0.05))
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
                        autoLabel: mode.displayName,
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
                .foregroundColor(mode.color)
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
                    Label("Reset to Auto-Detected (\(mode.displayName))", systemImage: "arrow.counterclockwise")
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
        HStack(spacing: 4) {
            Text(effectiveModeLabel)
                .font(isManualOverride ? .headline.italic() : .headline)
                .foregroundColor(mode.color)
            if isManualOverride {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundColor(mode.color.opacity(0.8))
            }
        }
    }

    // MARK: - Helpers

    private func magnitudeColor(_ mag: Float) -> Color {
        if mag >= -40.0 {
            return .green
        } else if mag >= -60.0 {
            return .blue
        } else if mag >= -80.0 {
            return .orange
        } else {
            return .red
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
                                    .foregroundColor(.primary)
                                Spacer()
                                if label == currentLabel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
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
                                    .foregroundColor(.primary)
                                Spacer()
                                if label == currentLabel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
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
