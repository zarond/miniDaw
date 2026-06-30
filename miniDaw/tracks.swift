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
            BTPlayer.volume = mute ? 0.0 : volume
        }
    }
    var mute: Bool = false {
        didSet {
            BTPlayer.volume = mute ? 0.0 : volume
        }
    }
    var monitorOn: Bool = false
    
    static weak var engine : AVAudioEngine?
    static weak var model : AudioEngineModel?
    
    let BTPlayer = AVAudioPlayerNode()
    
    var BTAudioFile : AVAudioFile?
    var BTAudioLengthSamples = AVAudioFramePosition()
    var BTAudioSampleRate : Double = 44100
    var AudioLengthSeconds : Double = 4.0
    
    init(name: String, type: TrackType, audioFile: AVAudioFile? = nil) {
        self.name = name
        self.type = type
        
        if let audioFile = audioFile {
            BTAudioFile = audioFile
            BTAudioLengthSamples = audioFile.length
            BTAudioSampleRate = audioFile.fileFormat.sampleRate
            AudioLengthSeconds = Double(BTAudioLengthSamples) / BTAudioSampleRate
        }
        
        if (type == .recordingTrack) {
            AudioLengthSeconds = 0.0
        }
        
        guard let engine = Track.engine else { return }
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.attach(BTPlayer)
        engine.connect(
            BTPlayer,
            to: engine.mainMixerNode,
            format: hardwareFormat)
    }
    
    func play() {
        BTPlayer.play()
    }
    
    func stop() {
        BTPlayer.stop()
    }
    
    func schedule(prepare_next_loop : Bool = false) {
        guard let file = BTAudioFile else { return }
        guard let model = Track.model else { return }
        
        if (!prepare_next_loop && model.currTimeSeconds >= 0) {
            let start_frame = AVAudioFramePosition(model.currTimeSeconds * BTAudioSampleRate)
            let number_frames = AVAudioFrameCount(
                max(AVAudioFramePosition(model.TimelineLengthSeconds * BTAudioSampleRate) - start_frame, 0)
            )
            BTPlayer.scheduleSegment(file, startingFrame: start_frame, frameCount: number_frames, at: nil) {}
        } else {
            let sampleTime = model.startTime + (prepare_next_loop ? model.TimelineLength : 0)
            let engineWhen = AVAudioTime(sampleTime: sampleTime, atRate: model.EngineSampleRate)
            let when = BTPlayer.playerTime(forNodeTime: engineWhen)
            let number_frames = AVAudioFrameCount(AVAudioFramePosition(model.TimelineLengthSeconds * BTAudioSampleRate))
            BTPlayer.scheduleSegment(file, startingFrame: 0, frameCount: number_frames, at: when) {}
        }
    }
}
