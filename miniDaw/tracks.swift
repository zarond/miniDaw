//
//  tracks.swift
//  miniDaw
//
//  Created by Artur Makoev on 29.06.2026.
//

import SwiftUI
import AVFoundation

@Observable
class Track: Identifiable {
    let id = UUID()
    
    enum TrackType {
        case backingTrack
        case recordingTrack
    }
    
    var name: String
    var type: TrackType
    
    var volume: Float = 1.0 {
        didSet {
            //engine.mainMixerNode.outputVolume = volume
        }
    }
    var mute: Bool = false
    var monitorOn: Bool = false
    
    var BTAudioFile : AVAudioFile?
    var BTAudioLengthSamples = AVAudioFramePosition()
    var BTAudioSampleRate : Double = 44100
    
    init(name: String, type: TrackType) {
        self.name = name
        self.type = type
    }
}
