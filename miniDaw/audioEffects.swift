//
//  audioEffects.swift
//  miniDaw
//
//  Created by Artur Makoev on 11.07.2026.
//

import AVFoundation

final class AudioEffectsManager {
    // Core engine and nodes
    let model : AudioEngineModel
    let engine : AVAudioEngine

    // Effects
    //let timePitch = AVAudioUnitTimePitch() // doesn't work well with monitoring
    let eq: AVAudioUnitEQ
    let distortion = AVAudioUnitDistortion()
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()

    init(model: AudioEngineModel, engine: AVAudioEngine, eqBands: Int = 4) {
        self.eq = AVAudioUnitEQ(numberOfBands: max(1, eqBands))
        self.model = model
        self.engine = engine
        
        // Attach nodes
        //engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(distortion)
        engine.attach(delay)
        engine.attach(reverb)

        configureDefaults()
        connectChain()
    }

    private func configureDefaults() {
        // TimePitch: 0 cents, default overlap for quality
        //timePitch.pitch = 0
        //timePitch.overlap = 8.0

        eq.globalGain = 0

        // Distortion
        distortion.loadFactoryPreset(.multiDistortedCubed)
        distortion.wetDryMix = 25

        // Delay
        delay.delayTime = 0.25
        delay.feedback = 25
        delay.lowPassCutoff = 15000
        delay.wetDryMix = 20

        // Reverb
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 30
        
        // Bypass all
        eq.bypass = true
        distortion.bypass = true
        delay.bypass = true
        reverb.bypass = true
    }

    private func connectChain() {
        let mainMixer = engine.mainMixerNode
        let outputFormat = model.outputFormat

        // EQ → Distortion → Delay → Reverb
        //engine.connect(timePitch, to: eq, format: outputFormat)
        engine.connect(eq, to: distortion, format: outputFormat)
        engine.connect(distortion, to: delay, format: outputFormat)
        engine.connect(delay, to: reverb, format: outputFormat)
        engine.connect(reverb, to: mainMixer, format: outputFormat)
    }
    
    //func firstEffect() -> AVAudio​Node? {
    //    return nil
    //}
}

