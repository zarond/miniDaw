//
//  audioEffects.swift
//  miniDaw
//
//  Created by Artur Makoev on 11.07.2026.
//

import AVFoundation

@Observable
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

        // EQ band defaults for 4 bands: high pass, parametric, parametric, low pass
        if eq.bands.count >= 4 {
            // High-pass band
            let band0 = eq.bands[0]
            band0.filterType = .highPass
            band0.frequency = 80
            band0.bandwidth = 1.0
            band0.gain = 0.0
            band0.bypass = false

            // Low-mid parametric
            let band1 = eq.bands[1]
            band1.filterType = .parametric
            band1.frequency = 500
            band1.bandwidth = 1.0
            band1.gain = 0.0
            band1.bypass = false

            // High-mid parametric
            let band2 = eq.bands[2]
            band2.filterType = .parametric
            band2.frequency = 4000
            band2.bandwidth = 1.0
            band2.gain = 0.0
            band2.bypass = false

            // Low-pass band
            let band3 = eq.bands[3]
            band3.filterType = .lowPass
            band3.frequency = 12000
            band3.bandwidth = 1.0
            band3.gain = 0.0
            band3.bypass = false
        }

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

