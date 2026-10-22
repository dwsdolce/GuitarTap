// @parity util/date-display
//
//  DateDisplay.swift
//  GuitarTap
//
//  Single source of truth for user-facing date/time display. Locale-aware, in the user's
//  local time: medium date + short time, e.g. en-US "Jun 25, 2026, 2:34 PM"; de-DE
//  "25.06.2026, 14:34". Mirrors the web's Intl medium/short and Python's Babel medium/short.
//
//  DISPLAY only — the .guitartap `timestamp` stays ISO-8601 UTC and export filenames keep
//  their `<slug>-<unix>` form; neither goes through here.
//

import Foundation

enum DateDisplay {
    /// Medium date + short time, locale-aware (local timezone). For lists, detail, PDF, etc.
    ///
    /// Formats date and time in SEPARATE calls joined with ", " — modern ICU applies the CLDR
    /// `atTime` glue ("… at …") whenever ONE formatter combines a date and a time (both the
    /// `date:time:` style AND field-based combos), so the only way to guarantee the comma form is to
    /// never combine them in one call. Result: en-US "Jul 16, 2026, 3:56 PM", matching Python (Babel's
    /// standard combine) and the web.
    static func string(_ date: Date) -> String {
        let d = date.formatted(.dateTime.year().month(.abbreviated).day())
        let t = date.formatted(.dateTime.hour().minute())
        return "\(d), \(t)"
    }

    /// Compact variant (no year) for tight spots like chart titles / comparison legends:
    /// e.g. "Jun 25, 2:34 PM".
    ///
    /// Same rule as `string(_:)` above: format date and time in SEPARATE calls joined with ", "
    /// so modern ICU never applies the `atTime` glue ("… at …") that a single combined formatter
    /// would. Result matches Python's compact combine.
    static func compact(_ date: Date) -> String {
        let d = date.formatted(.dateTime.month(.abbreviated).day())
        let t = date.formatted(.dateTime.hour().minute())
        return "\(d), \(t)"
    }
}