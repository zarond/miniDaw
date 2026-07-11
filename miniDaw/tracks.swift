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
    
    var BTAudioFile : AVAudioFile?
    var BTAudioLengthSamples = AVAudioFramePosition()
    var TrackFormat = AVAudioFormat()
    var AudioLengthSeconds : Double = 4.0
    var AudioStartSeconds : Double = 0.0
    
    var RecordBuffer : AVAudioPCMBuffer?
    var RecordBufferCounter = 0
    
    var RegionStartTime = AVAudioFramePosition(0)    // relative time on timeline
    var RegionStopTime = AVAudioFramePosition(0)     // relative time on timeline
    
    init(name: String, type: TrackType, audioFile: AVAudioFile? = nil) {
        self.name = name
        self.type = type
        
        if let audioFile = audioFile {
            BTAudioFile = audioFile
            BTAudioLengthSamples = audioFile.length
            TrackFormat = audioFile.fileFormat
            RegionStartTime = 0                               // audio files are put at the beginning
            AudioLengthSeconds = Double(BTAudioLengthSamples) / TrackFormat.sampleRate
            RegionStopTime = AVAudioFramePosition(AudioLengthSeconds * (Track.model?.EngineSampleRate ?? 0))
        }
        
        guard let engine = Track.engine else { return }
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let hardwareInputFormat = engine.inputNode.inputFormat(forBus: 0)
        
        if (type == .recordingTrack) {
            AudioLengthSeconds = 0.0
            TrackFormat = hardwareInputFormat
        }
        
        engine.attach(Player)
        engine.connect(
            Player,
            to: engine.mainMixerNode,
            format: type == .backingTrack ? hardwareFormat : hardwareInputFormat)
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
        
        switch type {
        case .backingTrack:
            guard let file = BTAudioFile else { return }
            schedule_backing_track(file: file, model: model, prepare_next_loop : prepare_next_loop)
        case .recordingTrack:
            schedule_recording_track(model: model, prepare_next_loop : prepare_next_loop)
        }
    }
    
    private func schedule_backing_track(file: AVAudioFile, model: AudioEngineModel,  prepare_next_loop : Bool = false) {
        if (prepare_next_loop || model.currTime < RegionStartTime) {
            let sampleTime = model.startTime + RegionStartTime + (prepare_next_loop ? model.TimelineLength : 0)
            let engineWhen = AVAudioTime(sampleTime: sampleTime, atRate: model.EngineSampleRate)
            let when = Player.playerTime(forNodeTime: engineWhen)
            let number_frames = AVAudioFrameCount(AVAudioFramePosition(model.TimelineLengthSeconds * TrackFormat.sampleRate))
            Player.scheduleSegment(file, startingFrame: 0, frameCount: number_frames, at: when)
        } else if (model.currTime < RegionStopTime){
            let start_frame_engine = model.currTime - RegionStartTime
            let start_frame_seconds = Double(start_frame_engine) / model.EngineSampleRate
            let start_frame = AVAudioFramePosition(start_frame_seconds * TrackFormat.sampleRate)
            let number_frames = AVAudioFrameCount(
                max(AVAudioFramePosition(model.TimelineLengthSeconds * TrackFormat.sampleRate) - start_frame, 0)
            )
            Player.scheduleSegment(file, startingFrame: start_frame, frameCount: number_frames, at: nil)
        }
    }
    
    private func schedule_recording_track(model: AudioEngineModel,  prepare_next_loop : Bool = false) {
        guard let RecordBuffer else { return }
        if (prepare_next_loop || model.currTime < RegionStartTime) {
            let sampleTime = model.startTime + RegionStartTime + (prepare_next_loop ? model.TimelineLength : 0)
            let engineWhen = AVAudioTime(sampleTime: sampleTime, atRate: model.EngineSampleRate)
            let when = Player.playerTime(forNodeTime: engineWhen)
            let number_frames = AVAudioFrameCount(max(min(RegionStopTime, model.TimelineLength) - RegionStartTime, 0))
            let segmentBuffer = cropped_buffer(from: RecordBuffer, start_frame: 0, number_frames: number_frames) ?? AVAudioPCMBuffer()
            Player.scheduleBuffer(segmentBuffer, at: when)
        } else if (model.currTime < RegionStopTime) {
            let start_frame = model.currTime - RegionStartTime
            let number_frames = AVAudioFrameCount(max(min(RegionStopTime, model.TimelineLength) - RegionStartTime - start_frame, 0))
            let segmentBuffer = cropped_buffer(from: RecordBuffer, start_frame: start_frame, number_frames: number_frames) ?? AVAudioPCMBuffer()
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
        
        if (RecordBuffer == nil) {
            let number_frames = AVAudioFrameCount(max(RecordStopTime - RecordStartTime, 0))
            RecordBuffer = cropped_buffer(from: buffer, start_frame: RecordStartTime, number_frames: number_frames, allow_skip_crop: false)
            
            RegionStartTime = RecordStartTime
            RegionStopTime = RecordStopTime
        } else {
            let newRegionStartTime = min(RecordStartTime, RegionStartTime)
            let newRegionStopTime = max(RecordStopTime, RegionStopTime)
            
            if (RegionStartTime <= RecordStartTime && RecordStopTime <= RegionStopTime) {
                let number_frames = RecordStopTime - RecordStartTime
                let offset = RecordStartTime - RegionStartTime
                copyBuffer(from: buffer, to: RecordBuffer!, atOffset: offset, startFrameSrc: RecordStartTime,
                           frameNumberSrc: AVAudioFrameCount(number_frames))
            } else {
                let number_frames_total = newRegionStopTime - newRegionStartTime
                let newRecordBuffer = createZeroedBuffer(format: TrackFormat, capacity: AVAudioFrameCount(number_frames_total)) ?? AVAudioPCMBuffer()
                let number_frames_A = RegionStopTime - RegionStartTime
                let number_frames_B = RecordStopTime - RecordStartTime
                let offset_A = RegionStartTime - newRegionStartTime
                let offset_B = RecordStartTime - newRegionStartTime
                copyBuffer(from: RecordBuffer!, to: newRecordBuffer, atOffset : offset_A, startFrameSrc: 0,
                           frameNumberSrc: AVAudioFrameCount(number_frames_A))
                copyBuffer(from: buffer, to: newRecordBuffer, atOffset : offset_B, startFrameSrc: RecordStartTime,
                           frameNumberSrc: AVAudioFrameCount(number_frames_B))
                RecordBuffer = newRecordBuffer
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

        // Connect input to main mixer
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: inputFormat)
        // todo: connect to this tracks chain of effects, not globally

        monitorOn = true
    }
    
    func disableMonitoring(){
        guard type == .recordingTrack else { return }
        guard monitorOn else { return }
        guard let engine = Track.engine else { return }

        engine.disconnectNodeOutput(engine.inputNode)

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
