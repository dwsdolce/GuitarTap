//
//  TapToneAnalyzer+AnnotationManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI

extension TapToneAnalyzer {

    // MARK: - Annotation Management
    
    /// Update the offset for a peak annotation
    /// - Parameters:
    ///   - peakID: The unique identifier for the peak
    ///   - offset: The new offset position
    /// - Note: Always called on main thread to ensure UI consistency
    func updateAnnotationOffset(for peakID: UUID, offset: CGPoint) {
        // If already on main thread, update directly to avoid deadlock
        if Thread.isMainThread {
            peakAnnotationOffsets[peakID] = offset
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets[peakID] = offset
            }
        }
    }
    
    /// Get the offset for a peak annotation
    /// - Parameter peakID: The unique identifier for the peak
    /// - Returns: The current offset, or .zero if not customized
    func getAnnotationOffset(for peakID: UUID) -> CGPoint {
        peakAnnotationOffsets[peakID] ?? .zero
    }
    
    /// Reset annotation offset for a specific peak
    /// - Parameter peakID: The unique identifier for the peak
    func resetAnnotationOffset(for peakID: UUID) {
        if Thread.isMainThread {
            peakAnnotationOffsets.removeValue(forKey: peakID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets.removeValue(forKey: peakID)
            }
        }
    }
    
    /// Reset all annotation offsets to default positions
    func resetAllAnnotationOffsets() {
        if Thread.isMainThread {
            peakAnnotationOffsets = [:]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = [:]
            }
        }
    }
    
    /// Apply annotation offsets from a measurement (used when loading saved measurements)
    /// - Parameter offsets: Dictionary of peak IDs to offset positions
    func applyAnnotationOffsets(_ offsets: [UUID: CGPoint]) {
        if Thread.isMainThread {
            peakAnnotationOffsets = offsets
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = offsets
            }
        }
    }
}
