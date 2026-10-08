//
//  Palette.swift
//  GuitarTap
//
// @parity view/palette tests=test/theme,test/analysis-quality,test/mode-colors,test/quality-colors
//
// Every colour the app draws itself, as a functional role: what the colour is for (secondary text, the fL curve,
// the Peak Min line), with one light value and one dark value, chosen by the colour scheme it is drawn in. Two roles
// may share a value without being linked. The values are pinned rather than taken from the system's semantic
// colours, which change between OS releases, so every edition shows the same colours on every OS. The colour only
// tells values apart; the exact shade does not matter, but it must be the same everywhere. Exports are drawn in the
// light scheme, so they use the light values.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Palette {
    /// A colour's purpose. The raw value is the role's name in the theme table.
    enum Role: String, CaseIterable {
        case backgroundWindow = "background.window"
        case backgroundPanel = "background.panel"
        case backgroundControl = "background.control"
        case backgroundSubtle = "background.subtle"
        case backgroundPicker = "background.picker"
        case separator = "separator"
        case dividerSection = "divider.section"
        case dividerHeaderFooter = "divider.headerFooter"
        case textPrimary = "text.primary"
        case textSecondary = "text.secondary"
        case textOnColor = "text.onColor"
        case accent = "accent"
        case accentText = "accent.text"
        case toolbarInactive = "toolbar.inactive"
        case scrim = "scrim"
        case overlayCard = "overlay.card"
        case chartBackground = "chart.background"
        case chartGrid = "chart.grid"
        case chartBorder = "chart.border"
        case chartAxis = "chart.axis"
        case chartTitle = "chart.title"
        case chartSpectrum = "chart.spectrum"
        case chartCrosshairLine = "chart.crosshair.line"
        case chartCrosshairFrequency = "chart.crosshair.frequency"
        case chartReadoutBackground = "chart.readout.background"
        case chartPeakMin = "chart.peakMin"
        case chartHighlightedPeak = "chart.highlightedPeak"
        case modeAir = "mode.air"
        case modeTop = "mode.top"
        case modeBack = "mode.back"
        case modeDipole = "mode.dipole"
        case modeRing = "mode.ring"
        case modeUpper = "mode.upper"
        case modeUnknown = "mode.unknown"
        case modeUserDefined = "mode.userDefined"
        case materialLongitudinal = "material.longitudinal"
        case materialCross = "material.cross"
        case materialFlc = "material.flc"
        case materialUnselected = "material.unselected"
        case materialPhaseInactive = "material.phaseInactive"
        case materialGoreBox = "material.goreBox"
        case phaseNotStarted = "phase.notStarted"
        case phaseComplete = "phase.complete"
        case peakMagnitudeStrong = "peak.magnitude.strong"
        case peakMagnitudeModerate = "peak.magnitude.moderate"
        case peakMagnitudeWeak = "peak.magnitude.weak"
        case peakMagnitudeFaint = "peak.magnitude.faint"
        case peakPitch = "peak.pitch"
        case peakSelectedStar = "peak.selectedStar"
        case peakUnselectedStar = "peak.unselectedStar"
        case peakInRange = "peak.inRange"
        case peakOutOfRange = "peak.outOfRange"
        case qualityGray = "quality.gray"
        case qualityOrange = "quality.orange"
        case qualityYellow = "quality.yellow"
        case qualityGreen = "quality.green"
        case qualityBlue = "quality.blue"
        case qualityRed = "quality.red"
        case woodExcellent = "wood.excellent"
        case woodVeryGood = "wood.veryGood"
        case woodGood = "wood.good"
        case woodFair = "wood.fair"
        case woodPoor = "wood.poor"
        case badgeGuitar = "badge.guitar"
        case badgeMaterial = "badge.material"
        case badgeComparison = "badge.comparison"
        case resultsTapsActive = "results.tapsActive"
        case series1 = "series.1"
        case series2 = "series.2"
        case series3 = "series.3"
        case series4 = "series.4"
        case series5 = "series.5"
        case series6 = "series.6"
        case series7 = "series.7"
        case series8 = "series.8"
        case series9 = "series.9"
        case series10 = "series.10"
        case seriesAverage = "series.average"
        case statusRunning = "status.running"
        case statusTapDetected = "status.tapDetected"
        case statusComplete = "status.complete"
        case statusStopped = "status.stopped"
        case statusIdle = "status.idle"
        case statusPaused = "status.paused"
        case statusFrozen = "status.frozen"
        case statusWarning = "status.warning"
        case statusPlayingFile = "status.playingFile"
        case statusInfo = "status.info"
        case statusSaved = "status.saved"
        case statusProgress = "status.progress"
        case statusTapCount = "status.tapCount"
        case statusPeakReadout = "status.peakReadout"
        case statusError = "status.error"
        case statusInactiveDot = "status.inactiveDot"
        case meterGroove = "meter.groove"
        case meterGrooveBorder = "meter.grooveBorder"
        case meterLevelTop = "meter.levelTop"
        case meterLevelMiddle = "meter.levelMiddle"
        case meterLevelBottom = "meter.levelBottom"
        case meterClip = "meter.clip"
        case meterTicks = "meter.ticks"
        case meterPeakHold = "meter.peakHold"
        case meterPeakHoldBorder = "meter.peakHoldBorder"
        case meterThresholdHandle = "meter.thresholdHandle"
        case meterThresholdHandleBorder = "meter.thresholdHandleBorder"
        case metricGood = "metric.good"
        case metricFair = "metric.fair"
        case metricHigh = "metric.high"
        case metricOverload = "metric.overload"
        case pdfAccent = "pdf.accent"
        case pdfText = "pdf.text"
        case pdfSecondary = "pdf.secondary"
        case pdfDivider = "pdf.divider"
        case pdfBox = "pdf.box"
        case pdfPill = "pdf.pill"
        case pdfGoreBox = "pdf.goreBox"
        case pdfChartMatte = "pdf.chartMatte"
    }

    /// An opacity applied to another role's colour (the peak-row tint over its mode colour).
    enum Opacity: String, CaseIterable {
        case peakRowTint = "peak.rowTint"
        case statusMessageBackground = "status.messageBackground"
    }

    /// A colour's two values, as "#RRGGBB", or "#RRGGBBAA" when the role has an opacity.
    struct Pair: Equatable {
        let light: String
        let dark: String
    }

    static let pairs: [Role: Pair] = [
        .backgroundWindow: Pair(light: "#F2F2F7", dark: "#0B0E13"),
        .backgroundPanel: Pair(light: "#FFFFFF", dark: "#141A22"),
        .backgroundControl: Pair(light: "#FFFFFF", dark: "#11161D"),
        .backgroundSubtle: Pair(light: "#8E8E9314", dark: "#8E8E931A"),
        .backgroundPicker: Pair(light: "#00000014", dark: "#FFFFFF14"),
        .separator: Pair(light: "#D8DEE6", dark: "#222A33"),
        .dividerSection: Pair(light: "#1A233059", dark: "#FFFFFF59"),
        .dividerHeaderFooter: Pair(light: "#1A2330", dark: "#E7EBF0"),
        .textPrimary: Pair(light: "#1A2330", dark: "#E7EBF0"),
        .textSecondary: Pair(light: "#6B7785", dark: "#8A96A5"),
        .textOnColor: Pair(light: "#FFFFFF", dark: "#FFFFFF"),
        .accent: Pair(light: "#007AFF", dark: "#0A84FF"),
        .accentText: Pair(light: "#007AFF", dark: "#409CFF"),
        .toolbarInactive: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .scrim: Pair(light: "#0000004D", dark: "#00000080"),
        .overlayCard: Pair(light: "#3A3A3CCC", dark: "#3A3A3CCC"),
        .chartBackground: Pair(light: "#FFFFFF", dark: "#0E1116"),
        .chartGrid: Pair(light: "#E3E8EE", dark: "#1C242E"),
        .chartBorder: Pair(light: "#C2CAD4", dark: "#2A3543"),
        .chartAxis: Pair(light: "#6B7785", dark: "#8A97A6"),
        .chartTitle: Pair(light: "#1A2330", dark: "#DFE4EA"),
        .chartSpectrum: Pair(light: "#FF3B30", dark: "#FF453A"),
        .chartCrosshairLine: Pair(light: "#5A646E80", dark: "#96A0AA8C"),
        .chartCrosshairFrequency: Pair(light: "#FF3B30", dark: "#FF453A"),
        .chartReadoutBackground: Pair(light: "#FFFFFFF5", dark: "#141921EB"),
        .chartPeakMin: Pair(light: "#34C759", dark: "#30D158"),
        .chartHighlightedPeak: Pair(light: "#FF3B30", dark: "#FF453A"),
        .modeAir: Pair(light: "#00B0DC", dark: "#64D2FF"),
        .modeTop: Pair(light: "#269342", dark: "#30D158"),
        .modeBack: Pair(light: "#BB6D00", dark: "#FF9F0A"),
        .modeDipole: Pair(light: "#FF3B30", dark: "#FF453A"),
        .modeRing: Pair(light: "#AF52DE", dark: "#BF5AF2"),
        .modeUpper: Pair(light: "#A2845E", dark: "#AC8E68"),
        .modeUnknown: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .modeUserDefined: Pair(light: "#5856D6", dark: "#7D7AFF"),
        .materialLongitudinal: Pair(light: "#007AFF", dark: "#0A84FF"),
        .materialCross: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .materialFlc: Pair(light: "#AF52DE", dark: "#BF5AF2"),
        .materialUnselected: Pair(light: "#6B7785", dark: "#8A96A5"),
        .materialPhaseInactive: Pair(light: "#8E8E9333", dark: "#8E8E9333"),
        .materialGoreBox: Pair(light: "#007AFF14", dark: "#0A84FF14"),
        .phaseNotStarted: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .phaseComplete: Pair(light: "#34C759", dark: "#30D158"),
        .peakMagnitudeStrong: Pair(light: "#34C759", dark: "#30D158"),
        .peakMagnitudeModerate: Pair(light: "#007AFF", dark: "#0A84FF"),
        .peakMagnitudeWeak: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .peakMagnitudeFaint: Pair(light: "#FF3B30", dark: "#FF453A"),
        .peakPitch: Pair(light: "#AF52DE", dark: "#BF5AF2"),
        .peakSelectedStar: Pair(light: "#007AFF", dark: "#0A84FF"),
        .peakUnselectedStar: Pair(light: "#6B7785", dark: "#8A96A5"),
        .peakInRange: Pair(light: "#34C759", dark: "#30D158"),
        .peakOutOfRange: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .qualityGray: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .qualityOrange: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .qualityYellow: Pair(light: "#FFCC00", dark: "#FFD60A"),
        .qualityGreen: Pair(light: "#34C759", dark: "#30D158"),
        .qualityBlue: Pair(light: "#007AFF", dark: "#0A84FF"),
        .qualityRed: Pair(light: "#FF3B30", dark: "#FF453A"),
        .woodExcellent: Pair(light: "#34C759", dark: "#30D158"),
        .woodVeryGood: Pair(light: "#00C7BE", dark: "#63E6E2"),
        .woodGood: Pair(light: "#007AFF", dark: "#0A84FF"),
        .woodFair: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .woodPoor: Pair(light: "#FF3B30", dark: "#FF453A"),
        .badgeGuitar: Pair(light: "#007AFF33", dark: "#0A84FF33"),
        .badgeMaterial: Pair(light: "#FF950033", dark: "#FF9F0A33"),
        .badgeComparison: Pair(light: "#AF52DE33", dark: "#BF5AF233"),
        .resultsTapsActive: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .series1: Pair(light: "#007AFF", dark: "#0A84FF"),
        .series2: Pair(light: "#E07800", dark: "#FF9F0A"),
        .series3: Pair(light: "#269342", dark: "#30D158"),
        .series4: Pair(light: "#AF52DE", dark: "#BF5AF2"),
        .series5: Pair(light: "#0090B0", dark: "#64D2FF"),
        .series6: Pair(light: "#E0302A", dark: "#FF453A"),
        .series7: Pair(light: "#D6177A", dark: "#FF6FB5"),
        .series8: Pair(light: "#8B6A42", dark: "#C29A6B"),
        .series9: Pair(light: "#7A8A00", dark: "#B8D430"),
        .series10: Pair(light: "#5E6B7A", dark: "#A8B4C2"),
        .seriesAverage: Pair(light: "#EBC300", dark: "#FFD900"),
        .statusRunning: Pair(light: "#34C759", dark: "#30D158"),
        .statusTapDetected: Pair(light: "#34C759", dark: "#30D158"),
        .statusComplete: Pair(light: "#34C759", dark: "#30D158"),
        .statusStopped: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .statusIdle: Pair(light: "#8E8E93", dark: "#8E8E93"),
        .statusPaused: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .statusFrozen: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .statusWarning: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .statusPlayingFile: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .statusInfo: Pair(light: "#007AFF", dark: "#0A84FF"),
        .statusSaved: Pair(light: "#007AFF", dark: "#0A84FF"),
        .statusProgress: Pair(light: "#007AFF", dark: "#0A84FF"),
        .statusTapCount: Pair(light: "#007AFF", dark: "#0A84FF"),
        .statusPeakReadout: Pair(light: "#007AFF", dark: "#0A84FF"),
        .statusError: Pair(light: "#FF3B30", dark: "#FF453A"),
        .statusInactiveDot: Pair(light: "#8E8E934D", dark: "#8E8E934D"),
        .meterGroove: Pair(light: "#EBEBEB", dark: "#0A0D12"),
        .meterGrooveBorder: Pair(light: "#8E8E9399", dark: "#8E8E9373"),
        .meterLevelTop: Pair(light: "#66CCFF", dark: "#66CCFF"),
        .meterLevelMiddle: Pair(light: "#0066CC", dark: "#0066CC"),
        .meterLevelBottom: Pair(light: "#001E50", dark: "#001E50"),
        .meterClip: Pair(light: "#FF3B30D9", dark: "#FF453AD9"),
        .meterTicks: Pair(light: "#3D8C3DB3", dark: "#3D8C3DB3"),
        .meterPeakHold: Pair(light: "#FFC700", dark: "#FFC700"),
        .meterPeakHoldBorder: Pair(light: "#FFFFFFD9", dark: "#FFFFFFD9"),
        .meterThresholdHandle: Pair(light: "#FF3B30", dark: "#FF453A"),
        .meterThresholdHandleBorder: Pair(light: "#800000", dark: "#800000"),
        .metricGood: Pair(light: "#34C759", dark: "#30D158"),
        .metricFair: Pair(light: "#FFCC00", dark: "#FFD60A"),
        .metricHigh: Pair(light: "#FF9500", dark: "#FF9F0A"),
        .metricOverload: Pair(light: "#FF3B30", dark: "#FF453A"),
        .pdfAccent: Pair(light: "#2659BF", dark: "#2659BF"),
        .pdfText: Pair(light: "#1C1C1E", dark: "#1C1C1E"),
        .pdfSecondary: Pair(light: "#787880", dark: "#787880"),
        .pdfDivider: Pair(light: "#D2D2D4", dark: "#D2D2D4"),
        .pdfBox: Pair(light: "#F2F2F4", dark: "#F2F2F4"),
        .pdfPill: Pair(light: "#ECECEE", dark: "#ECECEE"),
        .pdfGoreBox: Pair(light: "#F7F9FD", dark: "#F7F9FD"),
        .pdfChartMatte: Pair(light: "#0D0D0D", dark: "#0D0D0D")
    ]

    static let opacities: [Opacity: (light: Double, dark: Double)] = [
        .peakRowTint: (light: 0.10, dark: 0.20),
        .statusMessageBackground: (light: 0.12, dark: 0.12),
    ]

    static func pair(_ role: Role) -> Pair { pairs[role]! }

    /// The colour for `role`, light or dark by the colour scheme it is drawn in.
    static func color(_ role: Role) -> Color {
        dynamicColor { dark in rgba(dark ? pair(role).dark : pair(role).light) }
    }

    /// The colour for `role` at the scheme's value of `opacity` (a mode colour as a peak row's tint).
    static func color(_ role: Role, opacity: Opacity) -> Color {
        dynamicColor { dark in
            var c = rgba(dark ? pair(role).dark : pair(role).light)
            c.a *= dark ? opacities[opacity]!.dark : opacities[opacity]!.light
            return c
        }
    }

    /// Draws the app — its windows, controls and the palette's colours — in the scheme `appearance` resolves to:
    /// the operating system's own for System.
    @MainActor static func apply(_ appearance: Appearance) {
        #if os(macOS)
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #else
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
        #endif
    }

    /// The role of a guitar mode's colour.
    static func role(_ mode: GuitarMode) -> Role {
        switch mode {
        case .air: return .modeAir
        case .top: return .modeTop
        case .back: return .modeBack
        case .dipole: return .modeDipole
        case .ringMode: return .modeRing
        case .upperModes: return .modeUpper
        case .unknown: return .modeUnknown
        }
    }

    /// The role of a wood-quality grade's colour.
    static func role(_ quality: WoodQuality) -> Role {
        switch quality {
        case .excellent: return .woodExcellent
        case .veryGood: return .woodVeryGood
        case .good: return .woodGood
        case .fair: return .woodFair
        case .poor: return .woodPoor
        }
    }

    /// The role of a peak's magnitude (dB) in a peak list: strong from −40 dB, moderate from −60, weak from −80,
    /// faint below.
    static func role(magnitude: Float) -> Role {
        if magnitude >= -40 { return .peakMagnitudeStrong }
        if magnitude >= -60 { return .peakMagnitudeModerate }
        if magnitude >= -80 { return .peakMagnitudeWeak }
        return .peakMagnitudeFaint
    }

    /// A guitar mode's colour.
    static func color(_ mode: GuitarMode) -> Color { color(role(mode)) }

    /// A wood-quality grade's colour.
    static func color(_ quality: WoodQuality) -> Color { color(role(quality)) }

    /// The colour of a freeform (user-defined) mode label.
    static let userDefined = color(.modeUserDefined)

    /// The multi-tap and comparison series, by slot; a slot past the last starts again at the first.
    static let seriesRoles: [Role] = [
        .series1, .series2, .series3, .series4, .series5, .series6, .series7, .series8, .series9, .series10,
    ]

    /// The colour of series slot `index` (0-based).
    static func series(_ index: Int) -> Color { color(seriesRoles[index % seriesRoles.count]) }

    /// The colour of the averaged spectrum among the series.
    static let seriesAverage = color(.seriesAverage)

    /// A comparison entry's colour, drawn in the current scheme by its slot (its stored colour is the light value,
    /// kept for files only): the multi-tap report's "Averaged" entry takes the average's colour, every other entry
    /// its series slot.
    static func comparisonColor(index: Int, label: String) -> Color {
        label == "Averaged" ? seriesAverage : series(index)
    }

    /// The light scheme's environment: a colour that is stored (a saved comparison's) is its light value.
    static var lightEnvironment: EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        return environment
    }

    static let gray = color(.qualityGray)
    static let orange = color(.qualityOrange)
    static let yellow = color(.qualityYellow)
    static let green = color(.qualityGreen)
    static let blue = color(.qualityBlue)
    static let red = color(.qualityRed)

    private struct RGBA { var r: Double, g: Double, b: Double, a: Double }

    /// "#RRGGBB" or "#RRGGBBAA" as components in 0…1.
    private static func rgba(_ hex: String) -> RGBA {
        let v = UInt64(hex.dropFirst(), radix: 16)!
        let withAlpha = hex.count == 9 ? v : v << 8 | 0xFF
        func byte(_ shift: UInt64) -> Double { Double((withAlpha >> shift) & 0xFF) / 255 }
        return RGBA(r: byte(24), g: byte(16), b: byte(8), a: byte(0))
    }

    private static func dynamicColor(_ value: @escaping (_ dark: Bool) -> RGBA) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = value(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = value(traits.userInterfaceStyle == .dark)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
        #endif
    }
}
