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
    static let minBPM: Int = 1
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
    var looping: Bool = false
    
    private var nextLoopPlanned : Bool = false
    
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
    private let metronomePlayer = AVAudioPlayerNode()
    private let BTPlayer = AVAudioPlayerNode()
    var isPlayerReady: Bool = false
    
    var EngineSampleRate : Double = 44100.0
    
    var metronomeAudioBuffer = AVAudioPCMBuffer()
    var metronomeHighAudioBuffer = AVAudioPCMBuffer()
    
    var BTAudioFile : AVAudioFile?
    var BTAudioLengthSamples = AVAudioFramePosition()
    var BTAudioSampleRate : Double = 44100
    
    var displayLink = CADisplayLink()
    
    init() {
        setupAudio()
        recalculate_timeline_length()
        recalculate_samples_per_beat()
        reset_to_begining()
        setupAnimation()
    }
    
    private func setupAudio() {
        configureEngine()
        loadAudioFileToBuffer(file_name: "metronome_bip", file_extension: "wav", outputBufferRef: &metronomeAudioBuffer)
        loadAudioFileToBuffer(file_name: "metronome_bip_high", file_extension: "wav", outputBufferRef: &metronomeHighAudioBuffer)
    }
    
    private func configureEngine() {
        engine.attach(metronomePlayer)
        engine.attach(BTPlayer)
        
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)

        engine.connect(
            metronomePlayer,
            to: engine.mainMixerNode,
            format: hardwareFormat)
        
        engine.connect(
            BTPlayer,
            to: engine.mainMixerNode,
            format: hardwareFormat)

        engine.prepare()
        
        EngineSampleRate = hardwareFormat.sampleRate
        
        configureLowLatencyBuffer()

        do {
            try engine.start()
            isPlayerReady = true
        } catch {
            print("Error starting the player: \(error)")
        }
    }
    
    private func loadAudioFileToBuffer(file_name: String, file_extension: String, outputBufferRef: inout AVAudioPCMBuffer) {
        guard let url = Bundle.main.url(forResource: file_name, withExtension: file_extension) else {
            print("Audio file '\(file_name)' not found in bundle.")
            return
        }
        do {
            let file = try AVAudioFile(forReading: url)
            
            let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
            
            // Create a format converter to translate file format -> hardware format
            let converter = AVAudioConverter(from: file.processingFormat, to: hardwareFormat)
            
            let file_length_seconds = Double(file.length) / file.processingFormat.sampleRate
            
            // Allocate a buffer matching the hardware format
            let inputFileFrameCount = AVAudioFrameCount(file.length)
            let outputFileFrameCount = AVAudioFrameCount(file_length_seconds * hardwareFormat.sampleRate)
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inputFileFrameCount),
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: hardwareFormat, frameCapacity: outputFileFrameCount) else { return }
            
            try? file.read(into: inputBuffer)
            
            // Convert the audio data permanently into the hardware sample rate
            var error: NSError?
            converter?.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            outputBufferRef = outputBuffer
        } catch {
            print("Error reading audio file: \(error)")
        }
    }
    
    private func configureLowLatencyBuffer() {
        // 1. Get the hardware ID of the current output device
        let outputNode = engine.outputNode
        
        // 2. Define the target buffer frame size (64 or 128 is ideal for real-time tracking)
        var bufferFrameSize: UInt32 = 512
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        // 3. Set the property on the output AudioUnit
        let status = AudioUnitSetProperty(
            outputNode.audioUnit!,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0, // Element 0 is the output
            &bufferFrameSize,
            propertySize
        )
        
        if status == noErr {
            print("Successfully set hardware buffer size to \(bufferFrameSize) frames.")
        } else {
            print("Failed to set buffer size. Core Audio Error code: \(status)")
        }
    }
    
    func scheduleMetronomeTick(play_now: Bool = false) {
        update_current_time()
        
        let calcNextBeatNumber : Int = play_now ?
            Int(round(Double(currTime) / samplesPerBeat)) :
            Int(ceil(Double(currTime) / samplesPerBeat))
        
        if (calcNextBeatNumber == nextBeatNumber && !play_now) { return }
        
        nextBeatNumber = calcNextBeatNumber
        
        nextBeatTime = AVAudioFramePosition(Double(nextBeatNumber) * samplesPerBeat)
        print("time until beat: ", nextBeatNumber," - ", Double(nextBeatTime - currTime) / EngineSampleRate)
        
        var when: AVAudioTime? = nil
        if !play_now {
            let engineWhen = AVAudioTime(sampleTime: startTime + nextBeatTime, atRate: EngineSampleRate)
            when = metronomePlayer.playerTime(forNodeTime: engineWhen)
        }
        
        let strongBeat = nextBeatNumber.isMultiple(of: TimeSignatureHigh)
        print("tick 1")
        let audio_buffer = strongBeat ? metronomeHighAudioBuffer : metronomeAudioBuffer
        metronomePlayer.scheduleBuffer(audio_buffer, at: when, completionCallbackType : .dataPlayedBack)
        { callbacktype in
            print("tick 2")
            let debug_now = self.debugClock.now
            if let last_moment = self.debugPrevMoment {
                let elapsedTime = (debug_now - last_moment) * Double(self.bpm) / 60.0
                let secondsAsDouble = Double(elapsedTime.components.seconds) + (Double(elapsedTime.components.attoseconds) / 1e18)
                print("beetwen clicks: \(secondsAsDouble) in bpm measurement")
            }
            self.debugPrevMoment = debug_now
        }
    }
    
    func scheduleBT(force_full_loop : Bool = false) {
        guard let file = BTAudioFile else { return }
        let start_frame = force_full_loop ? 0 : AVAudioFramePosition(currTimeSeconds * BTAudioSampleRate)
        let number_frames = AVAudioFrameCount(
            max(min(AVAudioFramePosition(TimelineLengthSeconds * BTAudioSampleRate), BTAudioLengthSamples) - start_frame, 0)
        )
        BTPlayer.scheduleSegment(file, startingFrame: start_frame, frameCount: number_frames, at: nil) {}
    }
    
    func setupAnimation() {
        if let mainScreen = NSScreen.main {
            displayLink = mainScreen.displayLink(target: self, selector: #selector(updateAnimation))
            displayLink.add(to: .current, forMode: .default)
        }
    }
    
    @objc func updateAnimation(displaylink: CADisplayLink) { // updating needle position on timeline and scheduling upcoming events
        if (isPlaying) {
            update_current_time()
            if (metronomeOn) {
                if !metronomePlayer.isPlaying {
                    metronomePlayer.play()
                }
                scheduleMetronomeTick()
            } else if metronomePlayer.isPlaying {
                metronomePlayer.stop()
            }
            update_current_time_seconds()
            if (looping) {
                setupNextLoop() // try to set up next loop if near the end of the timeline
            } else if (currTime > TimelineLength) {
                stop()
            }
        }
    }
    
    func releaseResources() {
        metronomePlayer.stop()
        BTPlayer.stop()
        engine.stop()
    }
    
    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        
        if (currTime > TimelineLength) {
            reset_to_begining()
        } else {
            guard let now = engine.outputNode.lastRenderTime else { return }
            startTime = now.sampleTime - currTime
        }
        
        update_current_time_seconds()
        
        if (metronomeOn) {
            if !metronomePlayer.isPlaying {
                metronomePlayer.play()
            }
            if (isOnBeat()) {
                scheduleMetronomeTick(play_now: true)
            }
        }
        
        scheduleBT()
        BTPlayer.play()
    }
    
    func stop() {
        metronomePlayer.stop()
        BTPlayer.stop()
        nextBeatNumber = 0
        nextLoopPlanned = false
        
        update_current_time()
        update_current_time_seconds()
        
        isPlaying = false
        if (isRecording) {
            stop_recording()
        }
    }
    
    private func setupNextLoop() {
        if (nextLoopPlanned) {
            if (currTime < TimelineLength / 4) {
                nextLoopPlanned = false
            }
            return
        }
        if (currTime > TimelineLength * 3 / 4) {
            nextLoopPlanned = true
            
            scheduleBT( force_full_loop: true )
        }
    }
    
    func start_recording(){
        guard !isRecording else { return }
        isRecording = true
        start()
    }
    
    func stop_recording(){
        isRecording = false
    }
    
    func reset_to_begining(){
        guard let now = engine.outputNode.lastRenderTime else { return }
        startTime = now.sampleTime
        currTime = AVAudioFramePosition(0)
        currTimeSeconds = 0.0
        nextLoopPlanned = false
        
        if (metronomeOn) {
            metronomePlayer.stop()
            metronomePlayer.play()
            if (isPlaying && isOnBeat()) {
                scheduleMetronomeTick(play_now: true)
            }
        }
        if (isPlaying) {
            BTPlayer.stop()
            scheduleBT()
            BTPlayer.play()
        }
        
        nextBeatNumber = 0
    }
    
    private func recalculate_timeline_length() {
        TimelineLengthSeconds = Double(numBars * TimeSignatureHigh * 60)/Double(bpm)
        TimelineLength = AVAudioFramePosition(TimelineLengthSeconds * EngineSampleRate)
    }
    
    private func recalculate_samples_per_beat() {
        samplesPerBeat = EngineSampleRate * 60.0 / Double(bpm)
    }
    
    func update_current_time() {
        guard let now = engine.outputNode.lastRenderTime else { return }
        currTime = now.sampleTime - startTime
        if (looping && currTime > TimelineLength) {
            currTime -= TimelineLength
            startTime += TimelineLength
        }
    }
    
    func update_current_time_seconds() { // for visual feedback
        currTimeSeconds = Double(currTime) / EngineSampleRate
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
                let format = file.processingFormat
                
                BTAudioLengthSamples = file.length
                BTAudioSampleRate = format.sampleRate
                BTAudioFile = file
            } catch {
                print("Error reading audio file: \(error)")
            }
        }
    }
}
