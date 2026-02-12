//
//  AVAudioDevice.swift
//  GuitarTap
//
//  Created by David Smith on 2/12/26.
//

import Foundation
import AVFoundation

#if os(macOS)
import CoreAudio
#endif

/// A simple wrapper for audio devices across platforms
struct AVAudioDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let uid: String
    let sampleRate: Double
    
    #if os(macOS)
    let deviceID: AudioDeviceID
    
    init(name: String, uid: String, sampleRate: Double, deviceID: AudioDeviceID) {
        self.name = name
        self.uid = uid
        self.sampleRate = sampleRate
        self.deviceID = deviceID
    }
    #else
    let port: AVAudioSessionPortDescription?
    
    init(name: String, uid: String, sampleRate: Double, port: AVAudioSessionPortDescription?) {
        self.name = name
        self.uid = uid
        self.sampleRate = sampleRate
        self.port = port
    }
    #endif
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
    
    static func == (lhs: AVAudioDevice, rhs: AVAudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }
}
