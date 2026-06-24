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
            if isPlaying {
                stop()
                start()
            }
        }
    }
    
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
    
    var currTime: TimeInterval = 0.0
    var volume: Float = 1.0
    var numBars: Int = 8
    var metronomeOn: Bool = true
    var preCount: Bool = false
    var looping: Bool = false
    
    var TimeSignatureHigh: Int = 4
    var TimeSignatureLow: Int = 4
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: DispatchSourceTimer?
    
    init() {
        setupAudio()
    }
    
    private func setupAudio() {
        // Load your click sound from the app bundle
        guard let url = Bundle.main.url(forResource: "metronome_bip", withExtension: "wav") else {
            print("Audio file 'metronome_bip.wav' not found in bundle.")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to initialize audio player: \(error)")
        }
    }
    
    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        
        // Create a precise background timer using Grand Central Dispatch (GCD)
        let queue = DispatchQueue(label: "com.metronome.timer", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        
        // Configure to fire immediately, repeating as bpm.
        // leeway: .nanoseconds(0) ensures maximum strict precision.
        timer?.schedule(deadline: .now(), repeating: 60.0/Double(bpm), leeway: .nanoseconds(0))
        
        timer?.setEventHandler { [weak self] in
            // Play sound immediately on the background thread for minimal latency
            self?.audioPlayer?.play()
        }
        
        timer?.resume()
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        isPlaying = false
        if (isRecording) {
            stop_recording()
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
        currTime = 0.0
    }
    
    func load_backing_track(file: URL){
        if file.startAccessingSecurityScopedResource() {
            defer { file.stopAccessingSecurityScopedResource() }
            
            print("Loading file: ", file.path())
            // Todo: load
        }
    }
}
