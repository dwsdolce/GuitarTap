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
    static func string(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Compact variant (no year) for tight spots like chart titles / comparison legends:
    /// e.g. "Jun 25, 2:34 PM".
    static func compact(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}