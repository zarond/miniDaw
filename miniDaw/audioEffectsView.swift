//
//  audioEffectsView.swift
//  miniDaw
//
//  Created by Artur Makoev on 14.07.2026.
//

import SwiftUI
import AVFoundation

extension AVAudioUnitReverbPreset: CaseIterable, CustomStringConvertible {
    public static var allCases: [AVAudioUnitReverbPreset] {
        return [
            .smallRoom, .mediumRoom, .largeRoom, .mediumHall, .largeHall,
            .plate, .mediumChamber, .largeChamber, .cathedral, .largeRoom2,
            .mediumHall2, .mediumHall3, .largeHall2
        ]
    }
    
    public var description : String {
        switch self {
        case .smallRoom : return "Small Room"
        case .mediumRoom : return "Medium Room"
        case .largeRoom : return "Large Room"
        case .mediumHall : return "Medium Hall"
        case .largeHall : return "Large Hall"
        case .plate : return "Plate"
        case .mediumChamber : return "Medium Chamber"
        case .largeChamber : return "Large Chamber"
        case .cathedral : return "Cathedral"
        case .largeRoom2 : return "Large Room 2"
        case .mediumHall2 : return "Medium Hall 2"
        case .mediumHall3 : return "Medium Hall 3"
        case .largeHall2 : return "Large Hall 2"
        @unknown default:
            return "Unknown Reverb"
        }
    }
}

extension AVAudioUnitDistortionPreset: CaseIterable, CustomStringConvertible {
    public static var allCases: [AVAudioUnitDistortionPreset] {
        return [
            .drumsBitBrush,
            .drumsBufferBeats,
            .drumsLoFi,
            .multiBrokenSpeaker,
            .multiCellphoneConcert,
            .multiDecimated1,
            .multiDecimated2,
            .multiDecimated3,
            .multiDecimated4,
            .multiDistortedFunk,
            .multiDistortedCubed,
            .multiDistortedSquared,
            .multiEcho1,
            .multiEcho2,
            .multiEchoTight1,
            .multiEchoTight2,
            .multiEverythingIsBroken,
            .speechAlienChatter,
            .speechCosmicInterference,
            .speechGoldenPi,
            .speechRadioTower,
            .speechWaves,
        ]
    }
    
    public var description : String {
        switch self {
        case .drumsBitBrush:             return "Drums Bit Brush"
        case .drumsBufferBeats:          return "Drums Buffer Beats"
        case .drumsLoFi:                 return "Drums Lo-Fi"
        case .multiBrokenSpeaker:        return "Broken Speaker"
        case .multiCellphoneConcert:     return "Cellphone Concert"
        case .multiDecimated1:           return "Decimated 1"
        case .multiDecimated2:           return "Decimated 2"
        case .multiDecimated3:           return "Decimated 2"
        case .multiDecimated4:           return "Decimated 2"
        case .multiDistortedFunk:        return "Distorted Funk"
        case .multiDistortedCubed:       return "Distorted Cubed"
        case .multiDistortedSquared:     return "Multi Distorted Squared"
        case .multiEcho1:                return "Multi Echo 1"
        case .multiEcho2:                return "Multi Echo 2"
        case .multiEchoTight1:           return "Multi Echo Tight 1"
        case .multiEchoTight2:           return "Multi Echo Tight 2"
        case .multiEverythingIsBroken:   return "Multi Everything Is Broken"
        case .speechAlienChatter:        return "Speech Alien Chatter"
        case .speechCosmicInterference:  return "Speech Cosmic Interference"
        case .speechGoldenPi:            return "Speech Golden Pi"
        case .speechRadioTower:          return "Speech Radio Tower"
        case .speechWaves:               return "Speech Waves"
        
        @unknown default:                return "Unknown Distortion"
        }
    }
}

extension AVAudioUnitEQFilterType: CaseIterable, CustomStringConvertible {
    public static var allCases: [AVAudioUnitEQFilterType] {
        return [.parametric, .lowPass, .highPass, .resonantLowPass, .resonantHighPass, .bandPass, .bandStop, .lowShelf, .highShelf, .resonantLowShelf, .resonantHighShelf]
    }
    
    public var description : String {
        switch self {
        case .parametric: return "Parametric"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        case .resonantLowPass: return "Resonant Low Pass"
        case .resonantHighPass: return "Resonant High Pass"
        case .bandPass: return "Band Pass"
        case .bandStop: return "Band Stop"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .resonantLowShelf: return "Resonant Low Shelf"
        case .resonantHighShelf: return "Resonant High Shelf"
        @unknown default: return "Unknown"
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
            Slider(value: Binding(
                get: { value },
                set: { value = $0; onChange?() }
            ), in: range)
            Text(String(format: "%.2f", value))
                .monospacedDigit()
                .frame(width: 65, alignment: .trailing)
        }
    }
}

struct ReverbControls: View {
    let reverb: AVAudioUnitReverb
    @State private var mix: Float = 30
    @State private var preset: AVAudioUnitReverbPreset = .mediumHall
    @State private var bypass = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Reverb", isOn: Binding(
                get: { !bypass },
                set: { bypass = !$0; reverb.bypass = bypass }
            )).bold()
            if (!bypass) {
                Picker("Preset", selection: $preset) {
                    ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) { preset in
                        Text(preset.description)
                            .tag(preset)
                    }
                }
                .onChange(of: preset) { reverb.loadFactoryPreset(preset) }
                LabeledSlider(title: "Dry/Wet", value: Binding(
                    get: { Double(mix) },
                    set: { mix = Float($0); reverb.wetDryMix = mix }
                ), range: 0...100)
            }
        }
        .onAppear {
            // Initialize state from the unit
            bypass = reverb.bypass
            mix = reverb.wetDryMix
            // AVAudioUnitReverb does not expose current preset, keep using local state
            reverb.loadFactoryPreset(preset)
            // Apply current state back to the unit to ensure sync
            reverb.bypass = bypass
            reverb.wetDryMix = mix
        }
    }
}

struct DelayControls: View {
    let delay: AVAudioUnitDelay
    @State private var time: Double = 0.25
    @State private var feedback: Float = 25
    @State private var cutoff: Float = 15000
    @State private var mix: Float = 20
    @State private var bypass = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Delay", isOn: Binding(
                get: { !bypass },
                set: { bypass = !$0; delay.bypass = bypass }
            )).bold()
            if (!bypass) {
                LabeledSlider(title: "Time", value: $time, range: 0...2) {
                    delay.delayTime = time
                }
                LabeledSlider(title: "Feedback", value: Binding(
                    get: { Double(feedback) },
                    set: { feedback = Float($0); delay.feedback = feedback }
                ), range: -100...100)
                
                LabeledSlider(title: "LP Cutoff", value: Binding(
                    get: { Double(cutoff) },
                    set: { cutoff = Float($0); delay.lowPassCutoff = cutoff }
                ), range: 1000...20000)
                
                LabeledSlider(title: "Dry/Wet", value: Binding(
                    get: { Double(mix) },
                    set: { mix = Float($0); delay.wetDryMix = mix }
                ), range: 0...100)
            }
        }
        .onAppear {
            // Initialize state from unit
            bypass = delay.bypass
            time = delay.delayTime
            feedback = delay.feedback
            cutoff = delay.lowPassCutoff
            mix = delay.wetDryMix
        }
    }
}

struct PitchControls: View {
    let timePitch: AVAudioUnitTimePitch
    @State private var cents: Float = 0
    @State private var overlap: Float = 8
    @State private var bypass = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Time/Pitch", isOn: Binding(
                get: { !bypass },
                set: { bypass = !$0; timePitch.bypass = bypass }
            )).bold()
            if (!bypass) {
                HStack {
                    Text("Pitch (cents)")
                    Slider(value: Binding(
                        get: { Double(cents) },
                        set: { cents = Float($0); timePitch.pitch = cents }
                    ), in: -2400...2400)
                    Text("\(Int(cents))")
                }
                
                HStack {
                    Text("Overlap")
                    Slider(value: Binding(
                        get: { Double(overlap) },
                        set: { overlap = Float($0); timePitch.overlap = overlap }
                    ), in: 3...32)
                    Text(String(format: "%.1f", overlap))
                }
            }
        }
        .onAppear {
            // Initialize state from unit
            bypass = timePitch.bypass
            cents = timePitch.pitch
            overlap = timePitch.overlap
        }
    }
}

struct DistortionControls: View {
    let distortion: AVAudioUnitDistortion
    @State private var mix: Float = 25
    @State private var preGain: Float = -6
    @State private var preset: AVAudioUnitDistortionPreset = .multiDistortedCubed
    @State private var bypass = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Distortion", isOn: Binding(
                get: { !bypass },
                set: { bypass = !$0; distortion.bypass = bypass }
            )).bold()
            if (!bypass) {
                Picker("Preset", selection: $preset) {
                    ForEach(AVAudioUnitDistortionPreset.allCases, id: \.self) { preset in
                        Text(preset.description)
                            .tag(preset)
                    }
                }
                .onChange(of: preset) { distortion.loadFactoryPreset(preset) }
                
                LabeledSlider(title: "Pre-gain", value: Binding(
                    get: { Double(preGain) },
                    set: { preGain = Float($0); distortion.preGain = preGain }
                ), range: -80...20)
                
                LabeledSlider(title: "Dry/Wet", value: Binding(
                    get: { Double(mix) },
                    set: { mix = Float($0); distortion.wetDryMix = mix }
                ), range: 0...100)
            }
        }
        .onAppear {
            // Initialize state from unit
            bypass = distortion.bypass
            mix = distortion.wetDryMix
            // AVAudioUnitDistortion does not expose current preset; keep local preset state
            distortion.loadFactoryPreset(preset)
            // Apply back to ensure sync
            distortion.bypass = bypass
            distortion.wetDryMix = mix
        }
    }
}

struct EQBandControl: View {
    let eq: AVAudioUnitEQ
    @State private var globalGain: Float = 0
    @State private var unitBypass = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("EQ", isOn: Binding(
                get: { !unitBypass },
                set: { unitBypass = !$0; eq.bypass = unitBypass }
            )).bold()
            if (!unitBypass) {
                LabeledSlider(title: "Global Gain", value: Binding(
                    get: { Double(globalGain) },
                    set: { globalGain = Float($0); eq.globalGain = globalGain }
                ), range: -96...24)
                ForEach(0..<eq.bands.count, id: \.self) { index in
                    EQSingleBandControl(band: eq.bands[index], index: index)
                }
            }
        }
    }
}

struct EQSingleBandControl: View {
    let band: AVAudioUnitEQFilterParameters
    let index: Int
    @State private var freq: Float = 1000
    @State private var gain: Float = 0
    @State private var q: Float = 1.0
    @State private var bypass = false
    @State private var filterType: AVAudioUnitEQFilterType = .parametric
    
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("EQ Band \(index)", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Bypass Band \(index)", isOn: Binding(
                    get: { bypass },
                    set: { bypass = $0; band.bypass = bypass }
                ))
                Picker("Filter type", selection: $filterType) {
                    ForEach(AVAudioUnitEQFilterType.allCases, id: \.self) { preset in
                        Text(preset.description)
                            .tag(preset)
                    }
                }
                .onChange(of: filterType) { band.filterType = filterType }
                LabeledSlider(title: "Freq", value: Binding(
                    get: { Double(freq) },
                    set: { freq = Float($0); band.frequency = freq }
                ), range: 20...20000)
                LabeledSlider(title: "Gain", value: Binding(
                    get: { Double(gain) },
                    set: { gain = Float($0); band.gain = gain }
                ), range: -96...24)
                LabeledSlider(title: "Q", value: Binding(
                    get: { Double(q) },
                    set: { q = Float($0); band.bandwidth = q }
                ), range: 0.05...5.0)
            }
        }
         .onAppear {
             // Initialize state from the unit
             freq = band.frequency
             gain = band.gain
             q = band.bandwidth
             bypass = band.bypass
             filterType = band.filterType
         }
    }
}

#Preview {
    var model = AudioEngineModel()
    model.Tracks = [
        Track(name: "Track 1", type: .backingTrack),
    ]
    model.currentlySelectedTrack = model.Tracks[0]
    return InspectorPanelView().environment(model)
}
