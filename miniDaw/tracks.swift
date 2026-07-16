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
            Player.volume = mute ? 0.0 : volume
        }
    }
    var mute: Bool = false {
        didSet {
            Player.volume = mute ? 0.0 : volume
        }
    }
    var pan: Float = 0.0 {
        didSet {
            Player.pan = pan
        }
    }
    private(set) var monitorOn: Bool = false
    
    static weak var engine : AVAudioEngine?
    static weak var model : AudioEngineModel?
    
    let Player = AVAudioPlayerNode()
    let preFXMixer = AVAudioMixerNode()
    
    var TrackFormat = AVAudioFormat()
    var AudioLengthSeconds : Double = 4.0
    var AudioStartSeconds : Double = 0.0
    
    var AudioBuffer : AVAudioPCMBuffer?
    var RecordBufferCounter = 0
    
    var RegionStartTime = AVAudioFramePosition(0)    // relative time on timeline
    var RegionStopTime = AVAudioFramePosition(0)     // relative time on timeline
    
    var effectsManager: AudioEffectsManager?
    
    init(name: String, type: TrackType, audioFile: AVAudioFile? = nil) {
        self.name = name
        self.type = type
        
        guard let engine = Track.engine else { return }
        guard let model = Track.model else { return }
        
        effectsManager = AudioEffectsManager(model: model, engine: engine)
        
        let outputFormat = Track.model!.outputFormat
        TrackFormat = outputFormat
        
        if let audioFile = audioFile {
            AudioBuffer = loadAudioFileToBuffer(file: audioFile, outputFormat: TrackFormat)
            
            RegionStartTime = 0                                         // audio files are put at the beginning
            AudioLengthSeconds = Double(AudioBuffer?.frameLength ?? 0) / TrackFormat.sampleRate
            RegionStopTime = Int64(AudioBuffer?.frameLength ?? 0)
        }
        
        engine.attach(Player)
        engine.attach(preFXMixer)
        
        if (type == .recordingTrack) {
            AudioLengthSeconds = 0.0
        }
        engine.connect(
            Player,
            to: preFXMixer,
            format: outputFormat)
        
        engine.connect(
            preFXMixer,
            to: effectsManager!.eq,
            //to: engine.mainMixerNode,
            format: outputFormat)
    }
    
    deinit {
        releaseResources()
    }
    
    func play() {
        Player.play()
    }
    
    func stop() {
        Player.stop()
    }
    
    func schedule(prepare_next_loop : Bool = false) {
        guard let model = Track.model else { return }
        schedule_audio_track(model: model, prepare_next_loop : prepare_next_loop)
    }
    
    private func schedule_audio_track(model: AudioEngineModel,  prepare_next_loop : Bool = false) {
        guard let AudioBuffer else { return }
        if (prepare_next_loop || model.currTime < RegionStartTime) {
            let sampleTime = model.startTime + RegionStartTime + (prepare_next_loop ? model.TimelineLength : 0)
            let engineWhen = AVAudioTime(sampleTime: sampleTime, atRate: model.EngineSampleRate)
            let when = Player.playerTime(forNodeTime: engineWhen)
            let number_frames = AVAudioFrameCount(max(min(RegionStopTime, model.TimelineLength) - RegionStartTime, 0))
            let segmentBuffer = cropped_buffer(from: AudioBuffer, format: TrackFormat, start_frame: 0, number_frames: number_frames) ?? AVAudioPCMBuffer()
            Player.scheduleBuffer(segmentBuffer, at: when)
        } else if (model.currTime < RegionStopTime) {
            let start_frame = model.currTime - RegionStartTime
            let number_frames = AVAudioFrameCount(max(min(RegionStopTime, model.TimelineLength) - RegionStartTime - start_frame, 0))
            let segmentBuffer = cropped_buffer(from: AudioBuffer, format: TrackFormat, start_frame: start_frame, number_frames: number_frames) ?? AVAudioPCMBuffer()
            Player.scheduleBuffer(segmentBuffer)
        }
    }
    
    func replace_recording_buffer(
        with buffer: AVAudioPCMBuffer,
        RecordStartTime : AVAudioFramePosition,
        RecordStopTime : AVAudioFramePosition,
    ) {
        if (type == .backingTrack) { return }
        if (RecordStartTime >= RecordStopTime) { return }
        
        if (AudioBuffer == nil) {
            let number_frames = AVAudioFrameCount(max(RecordStopTime - RecordStartTime, 0))
            AudioBuffer = cropped_buffer(from: buffer, format: TrackFormat, start_frame: RecordStartTime, number_frames: number_frames, allow_skip_crop: false)
            
            RegionStartTime = RecordStartTime
            RegionStopTime = RecordStopTime
        } else {
            let newRegionStartTime = min(RecordStartTime, RegionStartTime)
            let newRegionStopTime = max(RecordStopTime, RegionStopTime)
            
            if (RegionStartTime <= RecordStartTime && RecordStopTime <= RegionStopTime) {
                let number_frames = RecordStopTime - RecordStartTime
                let offset = RecordStartTime - RegionStartTime
                copyBuffer(from: buffer, to: AudioBuffer!, atOffset: offset, startFrameSrc: RecordStartTime,
                           frameNumberSrc: AVAudioFrameCount(number_frames))
            } else {
                let number_frames_total = newRegionStopTime - newRegionStartTime
                let newRecordBuffer = createZeroedBuffer(format: TrackFormat, capacity: AVAudioFrameCount(number_frames_total)) ?? AVAudioPCMBuffer()
                let number_frames_A = RegionStopTime - RegionStartTime
                let number_frames_B = RecordStopTime - RecordStartTime
                let offset_A = RegionStartTime - newRegionStartTime
                let offset_B = RecordStartTime - newRegionStartTime
                copyBuffer(from: AudioBuffer!, to: newRecordBuffer, atOffset : offset_A, startFrameSrc: 0,
                           frameNumberSrc: AVAudioFrameCount(number_frames_A))
                copyBuffer(from: buffer, to: newRecordBuffer, atOffset : offset_B, startFrameSrc: RecordStartTime,
                           frameNumberSrc: AVAudioFrameCount(number_frames_B))
                AudioBuffer = newRecordBuffer
            }
            RegionStartTime = newRegionStartTime
            RegionStopTime = newRegionStopTime
        }
        RecordBufferCounter += 1
        AudioLengthSeconds = Double(self.RegionStopTime - self.RegionStartTime) / TrackFormat.sampleRate
        AudioStartSeconds = Double(self.RegionStartTime) / TrackFormat.sampleRate
    }
    
    func enableMonitoring(){
        guard type == .recordingTrack else { return }
        guard !monitorOn else { return }
        guard let engine = Track.engine else { return }
        guard let model = Track.model else { return }

        // Connect input to main mixer
        let inputFormat = model.inputFormat
        engine.connect(model.inputNode!, to: preFXMixer, format: inputFormat)

        monitorOn = true
    }
    
    func disableMonitoring(){
        guard type == .recordingTrack else { return }
        guard monitorOn else { return }
        guard let engine = Track.engine else { return }
        guard let model = Track.model else { return }

        engine.disconnectNodeOutput(model.inputNode!)

        monitorOn = false
    }
    
    private func releaseResources(){
        disableMonitoring()
        Player.stop()
        Track.engine?.disconnectNodeOutput(Player)
        Track.engine?.detach(Player)
        Player.reset()
    }
}
