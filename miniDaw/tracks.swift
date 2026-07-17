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
            PlayerSourceNode?.volume = mute ? 0.0 : volume
            if monitorOn {
                Track.model?.inputNode?.volume = mute ? 0.0 : volume
            }
        }
    }
    var mute: Bool = false {
        didSet {
            PlayerSourceNode?.volume = mute ? 0.0 : volume
            if monitorOn {
                Track.model?.inputNode?.volume = mute ? 0.0 : volume
            }
        }
    }
    var pan: Float = 0.0 {
        didSet {
            PlayerSourceNode?.pan = pan
            if monitorOn {
                Track.model?.inputNode?.pan = pan
            }
        }
    }
    private(set) var monitorOn: Bool = false
    
    static weak var engine : AVAudioEngine?
    static weak var model : AudioEngineModel?
    
    private var PlayerSourceNode: AVAudioSourceNode? = nil
    let preFXMixer = AVAudioMixerNode()
    
    var TrackFormat = AVAudioFormat()
    var AudioLengthSeconds : Double = 0.0
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
        
        installPlayerSource()
        
        if let PlayerSourceNode {
            engine.attach(PlayerSourceNode)
        }
        
        engine.attach(preFXMixer)
        
        if let PlayerSourceNode {
            engine.connect(
                PlayerSourceNode,
                to: preFXMixer,
                format: outputFormat)
        }
        
        engine.connect(
            preFXMixer,
            to: effectsManager!.eq,
            //to: engine.mainMixerNode,
            format: outputFormat)
    }
    
    deinit {
        releaseResources()
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

        model.inputNode?.volume = mute ? 0.0 : volume
        model.inputNode?.pan = pan
        
        monitorOn = true
    }
    
    func disableMonitoring(){
        guard type == .recordingTrack else { return }
        guard monitorOn else { return }
        guard let engine = Track.engine else { return }
        guard let model = Track.model else { return }

        engine.disconnectNodeOutput(model.inputNode!)
        
        model.inputNode?.volume = 1.0
        model.inputNode?.pan = 0.0

        monitorOn = false
    }
    
    func delete_region() {
        RegionStartTime = 0
        RegionStopTime = 0
        AudioLengthSeconds = 0.0
        AudioStartSeconds = 0.0
        AudioBuffer = nil
    }
    
    private func releaseResources(){
        disableMonitoring()
        if let PlayerSourceNode, let engine = Track.engine {
            engine.disconnectNodeOutput(PlayerSourceNode)
            engine.detach(PlayerSourceNode)
            PlayerSourceNode.reset()
        }
    }
    
    private func installPlayerSource() {
        PlayerSourceNode = AVAudioSourceNode { [weak self] isSilence, timestamp, frameCount, outputData -> OSStatus in
            guard let self = self, let model = Track.model, let audio_buffer = self.AudioBuffer
                else { isSilence.pointee = true; return noErr }
            let isCurrentlyRecordingTrack : Bool = (self === model.currentlyRecordingTrack)
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            
            if !model.isPlaying || isCurrentlyRecordingTrack {
                isSilence.pointee = true
                return noErr
            }
            
            let ts = timestamp.pointee
            var ts_SampleTime: AVAudioFramePosition = model.startTime
            if ts.mFlags.contains(.sampleTimeValid) {
                ts_SampleTime = AVAudioFramePosition(ts.mSampleTime)
            }
            
            var currentBlockStartSample = ts_SampleTime - model.startTime
            // todo: this is not a perfect looping, there is a cutoff (inaudible)
            if (model.looping) {
                currentBlockStartSample %= model.TimelineLength
            }
            
            // Calculate the frame index within this block where the audio region should start
            let startFrameInBlock = Int(self.RegionStartTime - currentBlockStartSample)
            
            // Compute copy parameters allowing partial overlap if startFrameInBlock < 0
            
            let regionStartInBuffer = max(startFrameInBlock, 0)
            let regionStartInAudio = max(-startFrameInBlock, 0)
            let audioBufferFrameLength = Int(audio_buffer.frameLength)
            
            let outputChannelCount = ablPointer.count
            let audioBufferChannelCount = Int(audio_buffer.format.channelCount)
            
            let framesLeftInBlock = Int(frameCount) - regionStartInBuffer
            let framesLeftInAudio = audioBufferFrameLength - regionStartInAudio
            let framesToCopy = min(framesLeftInBlock, framesLeftInAudio)
            
            // If no frames to copy, return early
            if framesToCopy <= 0 {
                isSilence.pointee = true
                return noErr
            }
            isSilence.pointee = false
            
            // Clear the output buffer initially
            for buffer in ablPointer {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            
            // Copy audio region samples into output for each channel starting at regionStartInBuffer in output
            // and regionStartInAudio in audio buffer
            
            guard let audioBufferChannels = audio_buffer.floatChannelData else { return noErr }
            
            for channelIndex in 0..<outputChannelCount {
                let outputBuffer = ablPointer[channelIndex]
                guard let outputData = outputBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                
                // Use modulo to repeat first channel if output has more channels than audio buffer
                let sourceChannelIndex = channelIndex < audioBufferChannelCount ? channelIndex : 0
                let sourceData = audioBufferChannels[sourceChannelIndex]
                
                // Copy samples from audio_buffer to output buffer
                for frame in 0..<framesToCopy {
                    let outputFrameIndex = regionStartInBuffer + frame
                    let sourceFrameIndex = regionStartInAudio + frame
                    outputData[outputFrameIndex] = sourceData[sourceFrameIndex]
                }
            }
            
            return noErr
        }
    }
}
