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
    var monitorOn: Bool = false
    
    static weak var engine : AVAudioEngine?
    static weak var model : AudioEngineModel?
    
    let Player = AVAudioPlayerNode()
    
    var BTAudioFile : AVAudioFile?
    var BTAudioLengthSamples = AVAudioFramePosition()
    var TrackSampleRate : Double = 44100
    var AudioLengthSeconds : Double = 4.0
    var AudioStartSeconds : Double = 0.0
    
    var RecordBuffer : AVAudioPCMBuffer?
    
    var RegionStartTime = AVAudioFramePosition(0)    // relative time on timeline
    var RegionStopTime = AVAudioFramePosition(0)     // relative time on timeline
    
    init(name: String, type: TrackType, audioFile: AVAudioFile? = nil) {
        self.name = name
        self.type = type
        
        if let audioFile = audioFile {
            BTAudioFile = audioFile
            BTAudioLengthSamples = audioFile.length
            TrackSampleRate = audioFile.fileFormat.sampleRate
            RegionStartTime = 0                               // audio files are put at the beginning
            AudioLengthSeconds = Double(BTAudioLengthSamples) / TrackSampleRate
            RegionStopTime = AVAudioFramePosition(AudioLengthSeconds * (Track.model?.EngineSampleRate ?? 0))
        }
        
        guard let engine = Track.engine else { return }
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let hardwareInputFormat = engine.inputNode.inputFormat(forBus: 0)
        
        if (type == .recordingTrack) {
            AudioLengthSeconds = 0.0
            TrackSampleRate = hardwareInputFormat.sampleRate
        }
        
        engine.attach(Player)
        engine.connect(
            Player,
            to: engine.mainMixerNode,
            format: type == .backingTrack ? hardwareFormat : hardwareInputFormat)
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
            let number_frames = AVAudioFrameCount(AVAudioFramePosition(model.TimelineLengthSeconds * TrackSampleRate))
            Player.scheduleSegment(file, startingFrame: 0, frameCount: number_frames, at: when)
        } else if (model.currTime < RegionStopTime){
            let start_frame_engine = model.currTime - RegionStartTime
            let start_frame_seconds = Double(start_frame_engine) / model.EngineSampleRate
            let start_frame = AVAudioFramePosition(start_frame_seconds * TrackSampleRate)
            let number_frames = AVAudioFrameCount(
                max(AVAudioFramePosition(model.TimelineLengthSeconds * TrackSampleRate) - start_frame, 0)
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
            let segmentBuffer = cropped_buffer(from: RecordBuffer, start_frame: 0, number_frames: number_frames)
            Player.scheduleBuffer(segmentBuffer, at: when)
        } else if (model.currTime < RegionStopTime) {
            let start_frame = model.currTime - RegionStartTime
            let number_frames = AVAudioFrameCount(max(min(RegionStopTime, model.TimelineLength) - RegionStartTime - start_frame, 0))
            let segmentBuffer = cropped_buffer(from: RecordBuffer, start_frame: start_frame, number_frames: number_frames)
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

        // todo: need to join buffers instead of just replacing
        let start_frame = RecordStartTime
        let number_frames = AVAudioFrameCount(max(RecordStopTime - start_frame, 0))
        RecordBuffer = cropped_buffer(from: buffer, start_frame: start_frame, number_frames: number_frames, allow_skip_crop: false)
        
        self.RegionStartTime = RecordStartTime
        self.RegionStopTime = RecordStopTime
        
        AudioLengthSeconds = Double(self.RegionStopTime - self.RegionStartTime) / TrackSampleRate
        AudioStartSeconds = Double(self.RegionStartTime) / TrackSampleRate
    }
    
    private func cropped_buffer(from buffer: AVAudioPCMBuffer, start_frame: AVAudioFramePosition, number_frames: AVAudioFrameCount, allow_skip_crop: Bool = true) -> AVAudioPCMBuffer {
        guard let segmentBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: number_frames) else {
            return AVAudioPCMBuffer()
        }
        if (allow_skip_crop && start_frame == 0 && number_frames >= buffer.frameLength) {
            return buffer
        }
        segmentBuffer.frameLength = number_frames
        let channelCount = Int(buffer.format.channelCount)
        if let srcData = buffer.floatChannelData, let destData = segmentBuffer.floatChannelData {
            for channel in 0..<channelCount {
                let src = srcData[channel].advanced(by: Int(start_frame))
                let dst = destData[channel]
                let byteCount = Int(number_frames) * MemoryLayout<Float>.size
                memcpy(dst, src, byteCount)
            }
        } else if let srcData = buffer.int16ChannelData, let destData = segmentBuffer.int16ChannelData {
            for channel in 0..<channelCount {
                let src = srcData[channel].advanced(by: Int(start_frame))
                let dst = destData[channel]
                let byteCount = Int(number_frames) * MemoryLayout<Int16>.size
                memcpy(dst, src, byteCount)
            }
        }
        return segmentBuffer
    }
}
