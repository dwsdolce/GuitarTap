//
//  ExportFilename.swift
//  GuitarTap
//
//  Single source of truth for exported-artifact filenames.
//  See FILE-PATHS-AND-NAMES-SPEC.md §2b.
//
// @parity model/export-filename tests=test/export-filenames

import Foundation

/// The filename stem shared by every exported artifact — `.guitartap`, PDF, and spectrum PNG.
///
/// Rule (FILE-PATHS-AND-NAMES-SPEC §2b):
///
///     stem = <measurement name, slugged  OR  the artifact's own default word> - <unix seconds>
///
/// - The name is slugged: spaces and `/` become `-`, then lowercased.
/// - The timestamp is a **discriminator**, not part of the name — two measurements may share a
///   name — and is always integer seconds (never fractional).
/// - `unnamed` is the per-artifact default word used only when there is no name:
///   `"measurement"` for `.guitartap`, `"report"` for PDF, `"spectrum"` for PNG. It is a default
///   **name**, never an infix: a named measurement's PDF is `martin-000-28-<ts>.pdf`, with no
///   `report` in it.
///
/// This one function replaces four hand-rolled copies of the same slug logic, which had drifted
/// (wrong default words, some sites not slugging `/`, one emitting a fractional timestamp).
enum ExportFilename {
    static func stem(name: String?, timestamp: Date, unnamed: String) -> String {
        let slug = name?
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let namePart = (slug?.isEmpty == false) ? slug! : unnamed
        return "\(namePart)-\(Int(timestamp.timeIntervalSince1970))"
    }
}