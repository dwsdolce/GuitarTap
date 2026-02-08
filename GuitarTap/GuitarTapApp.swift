//
//  guitar_tap_App.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//
import SwiftUI

// MARK: - App Entry Point
@main
struct GuitarTapApp: App {
    var body: some Scene {
        #if os(macOS)
        // On macOS, use Window instead of WindowGroup to prevent multiple instances
        Window("Guitar Tap", id: "main") {
            TapToneAnalysisView()
        }
        .commandsRemoved() // Remove the "New Window" menu command
        #else
        // On iOS, WindowGroup is appropriate
        WindowGroup {
            TapToneAnalysisView()  
        }
        #endif
    }
}
