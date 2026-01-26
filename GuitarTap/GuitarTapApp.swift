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
        WindowGroup {
//            ContentView()
//                .frame(minWidth: 600, minHeight: 700)
            TapToneAnalysisView()  
        }
    }
}
