//
//  miniDawApp.swift
//  miniDaw
//
//  Created by Artur Makoev on 23.06.2026.
//

import SwiftUI
import AVFoundation

@main
struct miniDawApp: App {
    @State private var audioModel = AudioEngineModel()
    
    var body: some Scene {
        Window("miniDaw", id: "main") {
            ContentView()
                .environment(audioModel) // Pass object directly into environment
        }
    }
}

@Observable
class AudioEngineModel {
    static let minBPM: Int = 10
    static let maxBPM: Int = 320
    
    var bpm: Int = 120 {
        didSet {
            print("Internal BPM updated to: \(bpm)")
            recalculate_timeline_length()
            recalculate_samples_per_beat()
        }
    }
    
    private var samplesPerBeat: Double = 1.0
    
    var isPlaying: Bool = false {
        didSet {
            print(isPlaying ? "Audio Started" : "Audio Stopped")
        }
    }
    
    var isRecording: Bool = false {
        didSet {
            print(isRecording ? "Recording Started" : "Recording Stopped")
        }
    }
    
    var startTime = AVAudioFramePosition()      // absolute time
    var currTime = AVAudioFramePosition()       // relative time on timeline
    var TimelineLength = AVAudioFramePosition()
    var nextBeatTime = AVAudioFramePosition()   // relative time on timeline
    var nextBeatNumber : Int = 0
    
    private var debugClock = ContinuousClock()
    private var debugPrevMoment : ContinuousClock.Instant?
    
    var currTimeSeconds: TimeInterval = 0.0
    var TimelineLengthSeconds: TimeInterval = 1.0
    
    var volume: Float = 1.0 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
        }
    }
    var numBars: Int = 8 {
        didSet {
            recalculate_timeline_length()
        }
    }
    var metronomeOn: Bool = true
    var preCount: Bool = false
    private var preCountBeats: Int = 0
    var looping: Bool = false {
        didSet {
            if !looping {
                update_current_time_with_reset_to_timeline_range()
            }
        }
    }
    
    var TimeSignatureHigh: Int = 4 {
        didSet {
            recalculate_timeline_length()
        }
    }
    var TimeSignatureLow: Int = 4 {
        didSet {
            recalculate_timeline_length()
        }
    }
    
    private var engine = AVAudioEngine()
    private var metronomeSourceNode: AVAudioSourceNode? = nil
    
    var isPlayerReady: Bool = false
    
    var EngineSampleRate : Double = 44100.0
    private(set) var IOBufferSize : UInt32 = 512
    
    var metronomeAudioBuffer = AVAudioPCMBuffer()
    var metronomeHighAudioBuffer = AVAudioPCMBuffer()
    
    var displayLink = CADisplayLink()
    
    var Tracks : [Track] = []
    weak var currentlySelectedTrack: Track? = nil
    weak var currentlyRecordingTrack: Track? = nil
    
    var inputNode: AVAudioInputNode?
    var inputFormat = AVAudioFormat()
    var outputFormat = AVAudioFormat()
    private(set) var inputIsMono = false
    private var stereoInputIsAvailable = false
    
    var inputRecordBuffer = AVAudioPCMBuffer()
    var RecordTime = AVAudioFramePosition()         // relative time on timeline
    var RecordStartTime = AVAudioFramePosition()    // relative time on timeline
    var RecordStopTime = AVAudioFramePosition()     // relative time on timeline
    
    init() {
        try? checkRecordingPermission()
        setupAudio()
        recalculate_timeline_length()
        recalculate_samples_per_beat()
        reset_to_begining()
        setupAnimation()
    }
    
    deinit {
        releaseResources()
    }
    
    private func setupAudio() {
        configureEngine()
        metronomeAudioBuffer = loadAudioFileToBufferByName(file_name: "metronome_bip", file_extension: "wav") ?? AVAudioPCMBuffer()
        metronomeHighAudioBuffer = loadAudioFileToBufferByName(file_name: "metronome_bip_high", file_extension: "wav") ?? AVAudioPCMBuffer()
        Track.engine = self.engine
        Track.model = self
        create_recording_track()
        select_track(id: Tracks.first?.id)
    }
    
    enum InputError: Error {
        case permissionDenied
        case unknownPermission
        case builtinMicNotFound
        case inputNotEnabled
        
        var message: String {
            switch self  {
            case .permissionDenied:
                "Recording Permission Denied."
            case .unknownPermission:
                "Unknown Recording Permission."
            case .builtinMicNotFound:
                "Built in Mic is not found."
            case .inputNotEnabled:
                "Input node is not available to use"
            }
        }
    }
    
    private func checkRecordingPermission() throws {
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
            
        case .undetermined:
            AVAudioApplication.requestRecordPermission() { granted in
                if granted {
                    print("Microphone access allowed!")
                } else {
                    print("Microphone access denied.")
                }
            }
            return
            
        case .denied:
            throw InputError.permissionDenied
            
        case .granted:
            return
            
        @unknown default:
            throw InputError.unknownPermission
        }
    }
    
    private func configureEngine() {
        inputNode = engine.inputNode
        if let inputNode {
            stereoInputIsAvailable = (inputNode.inputFormat(forBus: 0).channelCount >= 2)
            inputFormat = configureFormat(inputNode.inputFormat(forBus: 0), numChannels: 2)
            inputIsMono = (inputFormat.channelCount == 1)
            printInputNodeInfo()
            installInputTap(bufferSize: IOBufferSize)
        }
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        print("Output Hardware format is:", hardwareFormat)
        
        outputFormat = configureFormat(hardwareFormat)
        print("Output DAW format is:", outputFormat)
        
        if (outputFormat.sampleRate != inputFormat.sampleRate) {
            print("Error: output sample rate does not match input sample rate.")
        }

        EngineSampleRate = outputFormat.sampleRate
        
        installMetronomeSource()
        
        if let metronomeSourceNode {
            engine.attach(metronomeSourceNode)
            
            engine.connect(
                metronomeSourceNode,
                to: engine.mainMixerNode,
                format: outputFormat
            )
        }
        
        engine.prepare()
        
        configureLowLatencyBuffer(bufferSize: IOBufferSize)

        do {
            try engine.start()
            isPlayerReady = true
        } catch {
            print("Error starting the player: \(error)")
        }
    }
    
    // clip number of channels to max 2
    private func configureFormat(_ sourceFormat: AVAudioFormat, numChannels: UInt32 = 2) -> AVAudioFormat {
        var settings = sourceFormat.settings
        settings[AVNumberOfChannelsKey] = min(sourceFormat.channelCount, numChannels)
        settings[AVChannelLayoutKey] = nil
        return AVAudioFormat(settings: settings) ?? sourceFormat
    }
    
    private func loadAudioFileToBufferByName(file_name: String, file_extension: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: file_name, withExtension: file_extension) else {
            print("Audio file '\(file_name)' not found in bundle.")
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            return loadAudioFileToBuffer(file: file, outputFormat: outputFormat)
        } catch {
            print("Error reading audio file: \(error)")
        }
        return nil
    }
    
    private func configureLowLatencyBuffer(bufferSize: UInt32 = 512) {
        // 1. Get the hardware ID of the current output device
        let outputNode = engine.outputNode
        
        // 2. Define the target buffer frame size (64 or 128 is ideal for real-time tracking)
        var bufferSize = bufferSize
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        // 3. Set the property on the output AudioUnit
        let status = AudioUnitSetProperty(
            outputNode.audioUnit!,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0, // Element 0 is the output
            &bufferSize,
            propertySize
        )
        
        if status == noErr {
            print("Successfully set hardware buffer size to \(bufferSize) frames.")
        } else {
            print("Failed to set buffer size. Core Audio Error code: \(status)")
        }
    }
    
    // TODO: Find bug thats breaking time calculations after proper restart!
    @discardableResult
    func changeBufferFrameSize(to newSize: UInt32) -> Bool {
        if isPlaying {
            stop()
        }
        displayLink.invalidate()
        
        inputNode?.removeTap(onBus: 0)
        //engine.stop() // TODO: properly stop engine
        
        configureLowLatencyBuffer(bufferSize: newSize)
        
        /* TODO: properly restart engine
        engine.reset()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Failed to restart engine after buffer size change: \(error)")
            return false
        }*/
        
        inputNode = engine.inputNode
        if let inputNode {
            stereoInputIsAvailable = (inputNode.inputFormat(forBus: 0).channelCount >= 2)
            inputFormat = configureFormat(inputNode.inputFormat(forBus: 0), numChannels: inputIsMono ? 1 : 2)
            inputIsMono = (inputFormat.channelCount == 1)
            printInputNodeInfo()
        }
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        print("Output Hardware format is:", hardwareFormat)
        
        outputFormat = configureFormat(hardwareFormat)
        print("Output DAW format is:", outputFormat)
        
        if (outputFormat.sampleRate != inputFormat.sampleRate) {
            print("Error: output sample rate does not match input sample rate.")
        }
        EngineSampleRate = outputFormat.sampleRate
        
        installInputTap(bufferSize: newSize)
        
        setupAnimation()
        
        recalculate_timeline_length()
        recalculate_samples_per_beat()
        
        IOBufferSize = newSize
        return true
    }

    private func installInputTap(bufferSize: UInt32) {
        inputRecordBuffer = createZeroedBuffer(format: inputFormat, capacity: AVAudioFrameCount(TimelineLength)) ?? AVAudioPCMBuffer()
        
        inputNode!.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            if (!self.isRecording) { return }
            let master = self.inputRecordBuffer
            self.RecordTime %= TimelineLength
            if (self.RecordTime < 0) {
                self.RecordTime += self.TimelineLength
            }
            copyBuffer(from: buffer, to: master, atOffset: self.RecordTime, startFrameSrc: 0,
                       frameNumberSrc: buffer.frameLength, loop: true)
            self.RecordTime += AVAudioFramePosition(buffer.frameLength)
        }
    }
    
    func scheduleMetronomeTick(play_now: Bool = false) -> Bool {
        _ = update_current_time()
        
        let calcNextBeatNumber : Int = play_now ?
            Int(round(Double(currTime) / samplesPerBeat)) :
            Int(ceil(Double(currTime) / samplesPerBeat))
        
        if (calcNextBeatNumber == nextBeatNumber && !play_now) { return false }
        
        nextBeatNumber = calcNextBeatNumber
        nextBeatTime = AVAudioFramePosition(Double(nextBeatNumber) * samplesPerBeat)
        return true
    }
    
    func setupAnimation() {
        if let mainScreen = NSScreen.main {
            displayLink = mainScreen.displayLink(target: self, selector: #selector(updateAnimation))
            displayLink.add(to: .main, forMode: .common)
        }
    }
    
    @objc func updateAnimation(displaylink: CADisplayLink) { // updating needle position on timeline and scheduling upcoming events
        if (isPlaying) {
            let outside = update_current_time()
            if isRecording && looping && outside {
                stop_recording(at_loop_end: true)
            }
            update_current_time_seconds()
            if !looping && outside {
                stop()
            }
        }
    }
    
    func releaseResources() {
        inputNode?.removeTap(onBus: 0)
        engine.stop()
        displayLink.invalidate()
    }
    
    func start(start_recording : Bool = false) {
        guard !isPlaying else { return }
        isPlaying = true
        
        preCountBeats = 0
        
        if (currTime >= TimelineLength) {
            reset_to_begining()
        } else {
            guard let now = engine.outputNode.lastRenderTime else { return }
            if (start_recording && preCount) {
                currTime -= AVAudioFramePosition(samplesPerBeat * Double(TimeSignatureHigh))
            }
            startTime = now.sampleTime - currTime
        }
        
        update_current_time_seconds()
        
        if metronomeOn || (preCount && start_recording) {
            let click_scheduled = scheduleMetronomeTick(play_now: isOnBeat())
            if (click_scheduled) {
                preCountBeats += 1
            }
        }
    }
    
    func stop() {
        nextBeatNumber = 0
            
        if (isRecording) {
            stop_recording()
        }
        
        update_current_time_with_reset_to_timeline_range()
        update_current_time_seconds()
        
        isPlaying = false
    }
    
    func start_recording(){
        guard !isRecording else { return }
        currentlyRecordingTrack = currentlySelectedTrack
        if (isPlaying) {
            update_current_time_with_reset_to_timeline_range()
        }
        let already_playing = isPlaying
        if (!already_playing) {
            start(start_recording: true)
        }
        RecordStartTime = currTime + (!already_playing && preCount ? AVAudioFramePosition(samplesPerBeat * Double(TimeSignatureHigh)) : 0)
        RecordTime = currTime
        isRecording = true
    }
    
    func stop_recording(at_loop_end: Bool = false){
        guard isRecording else { return }
        _ = update_current_time()
        RecordStopTime = at_loop_end ? TimelineLength : currTime
        
        currentlyRecordingTrack?.replace_recording_buffer(
            with: inputRecordBuffer,
            RecordStartTime: RecordStartTime,
            RecordStopTime: RecordStopTime)
        currentlyRecordingTrack = nil
        isRecording = false
    }
    
    func reset_to_begining(){
        guard let now = engine.outputNode.lastRenderTime else { return }
        
        if (isRecording) {
            stop_recording()
        }
        
        startTime = now.sampleTime
        currTime = AVAudioFramePosition(0)
        currTimeSeconds = 0.0
        
        if (metronomeOn && isPlaying) {
            _ = scheduleMetronomeTick(play_now: true)
        }
        
        nextBeatNumber = 0
    }
    
    func set_to_relative_position(_ position: Double, snapToBeat: Bool = false) {
        let wasPlaying = isPlaying
        if (wasPlaying) {
            stop()
        }
        if (snapToBeat) {
            let beatNumber = Int(round(Double(position * Double(TimelineLength)) / samplesPerBeat))
            currTime = AVAudioFramePosition(Double(beatNumber) * samplesPerBeat)
        } else {
            currTime = AVAudioFramePosition(position * Double(TimelineLength))
        }
        if (wasPlaying) {
            start()
        } else {
            update_current_time_seconds()
        }
    }
    
    private func recalculate_timeline_length() {
        TimelineLengthSeconds = Double(numBars * TimeSignatureHigh * 60)/Double(bpm)
        TimelineLength = AVAudioFramePosition(TimelineLengthSeconds * EngineSampleRate)
        
        inputRecordBuffer = createZeroedBuffer(format: inputFormat, capacity: AVAudioFrameCount(TimelineLength)) ?? AVAudioPCMBuffer()
    }
    
    private func recalculate_samples_per_beat() {
        samplesPerBeat = EngineSampleRate * 60.0 / Double(bpm)
    }
    
    func update_current_time() -> Bool {
        guard let now = engine.outputNode.lastRenderTime else { return false }
        currTime = now.sampleTime - startTime
        let outside_limit = (currTime >= TimelineLength)
        return outside_limit
    }
    
    func update_current_time_with_reset_to_timeline_range() {
        guard let now = engine.outputNode.lastRenderTime else { return }
        currTime = now.sampleTime - startTime
        if currTime >= TimelineLength {
            currTime %= TimelineLength
            startTime = now.sampleTime - currTime
            _ = scheduleMetronomeTick(play_now: true)
        }
    }
    
    func update_current_time_seconds() { // for visual feedback
        let time = Double(currTime) / EngineSampleRate
        currTimeSeconds = isPlaying && looping ? time.truncatingRemainder(dividingBy: TimelineLengthSeconds) : time
    }
    
    private func isOnBeat() -> Bool {
        let BeatNumber : Int = Int(round(Double(currTime) / samplesPerBeat))
        let BeatTime = AVAudioFramePosition(Double(BeatNumber) * samplesPerBeat)
        let onBeat = abs(currTime - BeatTime) < 128 // 3 ms leeway
        return onBeat
    }
    
    func load_backing_track(file_url: URL){
        if file_url.startAccessingSecurityScopedResource() {
            defer { file_url.stopAccessingSecurityScopedResource() }
            
            print("Loading file: ", file_url.path())
            do {
                let file = try AVAudioFile(forReading: file_url)
                let new_track = Track(name: file_url.deletingPathExtension().lastPathComponent, type: .backingTrack, audioFile: file)
                
                Tracks.append(new_track)
            } catch {
                print("Error reading audio file: \(error)")
            }
        }
    }
    
    func create_recording_track(){
        Tracks.append(Track(name: "Recording Track", type: .recordingTrack))
    }
    
    func delete_track(id: UUID?){
        let element_index = Tracks.firstIndex(where: {$0.id == id})
        guard let element_index else { return }
        let track = Tracks[element_index]
        if currentlySelectedTrack === track {
            currentlySelectedTrack = nil
        }
        track.disableMonitoring()
        Tracks.remove(at: element_index)
    }
    
    enum MoveDirection {
        case up, down
    }
    
    func move_track(id: UUID?, direction: MoveDirection){
        let element_index = Tracks.firstIndex(where: {$0.id == id})
        guard let element_index else { return }
        switch direction {
        case .up:
            if element_index > 0 {
                Tracks.swapAt(element_index, element_index - 1)
            }
        case .down:
            if element_index < Tracks.count - 1 {
                Tracks.swapAt(element_index, element_index + 1)
            }
        }
    }
    
    func select_track(id: UUID?){
        currentlySelectedTrack = Tracks.first(where: {$0.id == id})
    }
    
    func set_monitoring(for id: UUID, enabled: Bool) {
        guard let SelectedTrack = Tracks.first(where: {$0.id == id}) else { return }
        Tracks.filter { $0 !== SelectedTrack && $0.monitorOn }.forEach { $0.disableMonitoring() }
        if enabled {
            SelectedTrack.enableMonitoring()
        } else {
            SelectedTrack.disableMonitoring()
        }
    }
    
    private func printInputNodeInfo() {
        guard let inputNode else { return }
        
        // Print input device name and format info
        if let audioUnit = inputNode.audioUnit {
            var deviceID = AudioDeviceID(0)
            var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioUnitGetProperty(audioUnit,
                                              kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global,
                                              0,
                                              &deviceID,
                                              &propSize)
            if status == noErr, deviceID != 0 {
                var deviceName = CFStringCreateMutable(nil, 0)
                var nameSize = UInt32(MemoryLayout<CFString?>.size)
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                let nameStatus = withUnsafeMutablePointer(to: &deviceName) { ptr in
                    ptr.withMemoryRebound(to: UInt8.self, capacity: Int(nameSize)) { rawPtr in
                        AudioObjectGetPropertyData(
                            deviceID,
                            &address,
                            0,
                            nil,
                            &nameSize,
                            rawPtr
                        )
                    }
                }
                if nameStatus == noErr && deviceName != nil {
                    print("Input Audio Device Name: \(deviceName!)")
                }
            }
        }
        print("Input Format: \(inputFormat)")
        print("Number of Channels: \(inputFormat.channelCount)")
    }
    
    func configureInputMixer(mono: Bool) {
        if inputNode == nil { return }
        guard inputIsMono != mono else { return }
        if (!stereoInputIsAvailable) { return }
        if mono {
            switchToLeftChannelOnly()
        } else {
            switchToFullStereo()
        }
        inputIsMono = mono
    }
    
    private func switchToLeftChannelOnly() {
        guard let inputNode else { return }
        inputFormat = configureFormat(inputNode.inputFormat(forBus: 0), numChannels: 1)
        Tracks.filter { $0.monitorOn }.forEach { $0.disableMonitoring() }
        
        inputNode.removeTap(onBus: 0)
        installInputTap(bufferSize: IOBufferSize)
    }

    private func switchToFullStereo() {
        guard let inputNode else { return }
        inputFormat = configureFormat(inputNode.inputFormat(forBus: 0), numChannels: 2)
        Tracks.filter { $0.monitorOn }.forEach { $0.disableMonitoring() }
        
        inputNode.removeTap(onBus: 0)
        installInputTap(bufferSize: IOBufferSize)
    }
    
    private func installMetronomeSource() {
        metronomeSourceNode = AVAudioSourceNode { [weak self] isSilence, timestamp, frameCount, outputData -> OSStatus in
            guard let self = self else { isSilence.pointee = true; return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            
            // If metronome is off or not playing, do nothing further
            if !self.isPlaying || !self.metronomeOn && !(self.preCount && self.isRecording && self.preCountBeats <= self.TimeSignatureHigh) {
                isSilence.pointee = true
                return noErr
            }
            
            let ts = timestamp.pointee
            guard ts.mFlags.contains(.sampleTimeValid) else {
                isSilence.pointee = true
                return noErr
            }
            
            // Determine which metronome buffer to use: strong beat or regular
            let strongBeat = self.nextBeatNumber.isMultiple(of: self.TimeSignatureHigh)
            let audio_buffer = strongBeat ? self.metronomeHighAudioBuffer : self.metronomeAudioBuffer
            
            let currentBlockStartSample = AVAudioFramePosition(ts.mSampleTime) - self.startTime
            
            // Calculate the frame index within this block where the metronome click should start
            let startFrameInBlock = Int(self.nextBeatTime - currentBlockStartSample)
            
            // Compute copy parameters allowing partial overlap if startFrameInBlock < 0
            
            let clickStartInBuffer = max(startFrameInBlock, 0)
            let clickStartInAudio = max(-startFrameInBlock, 0)
            let audioBufferFrameLength = Int(audio_buffer.frameLength)
            
            let outputChannelCount = ablPointer.count
            let audioBufferChannelCount = Int(audio_buffer.format.channelCount)
            
            let framesLeftInBlock = Int(frameCount) - clickStartInBuffer
            let framesLeftInAudio = audioBufferFrameLength - clickStartInAudio
            let framesToCopy = min(framesLeftInBlock, framesLeftInAudio)
            
            if (framesLeftInAudio <= 0) {
                // Advance nextBeatTime and nextBeatNumber to schedule next beat
                self.nextBeatTime += AVAudioFramePosition(self.samplesPerBeat)
                self.nextBeatNumber += 1
                self.preCountBeats += 1
            }
            
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
            
            // Copy metronome samples into output for each channel starting at clickStartInBuffer in output
            // and clickStartInAudio in audio buffer
            
            guard let audioBufferChannels = audio_buffer.floatChannelData else { return noErr }
            
            for channelIndex in 0..<outputChannelCount {
                let outputBuffer = ablPointer[channelIndex]
                guard let outputData = outputBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                
                // Use modulo to repeat first channel if output has more channels than audio buffer
                let sourceChannelIndex = channelIndex < audioBufferChannelCount ? channelIndex : 0
                let sourceData = audioBufferChannels[sourceChannelIndex]
                
                // Copy samples from audio_buffer to output buffer
                for frame in 0..<framesToCopy {
                    let outputFrameIndex = clickStartInBuffer + frame
                    let sourceFrameIndex = clickStartInAudio + frame
                    outputData[outputFrameIndex] = sourceData[sourceFrameIndex]
                }
            }
            
            return noErr
        }
    }
}

extension AVAudioInputNode {
    var isEnabled: Bool {
        let inputFormat = self.inputFormat(forBus: 0)
        if inputFormat.sampleRate.isZero || inputFormat.sampleRate.isNaN {
            return false
        }
        if inputFormat.channelCount == 0 {
            return false
        }
        return true
    }
}

