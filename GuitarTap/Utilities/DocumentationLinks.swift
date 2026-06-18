//
//  DocumentationLinks.swift
//  GuitarTap
//
//  Shared URLs for the published documentation hosted on dolcesfogato.com.
//

import Foundation

enum DocumentationLinks {
    /// URL for the published User Manual, with the filename matched to the
    /// app's current marketing version so the link stays accurate across
    /// version bumps without code changes.
    static var userManual: URL? {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return URL(string: "https://www.dolcesfogato.com/guitar_tap/manual/GuitarTap-User-Manual-\(version).html")
    }
}
