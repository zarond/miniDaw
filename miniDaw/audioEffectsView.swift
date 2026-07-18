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

struct LabeledSlider<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    var isLogarithmic: Bool = false
    var onChange: (() -> Void)? = nil

    // Create a localized formatter for the Float/Double value
    private var formatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.decimalSeparator = "."
        return f
    }
    
    // Helper bounds converted to Double for calculations
    private var minVal: Double { Double(range.lowerBound) }
    private var maxVal: Double { Double(range.upperBound) }
    
    var body: some View {
        HStack {
            if (!title.isEmpty) {
                Text(title)
                    .frame(width: 60, alignment: .trailing)
            }
            Slider(value: Binding(
                get: {
                    if isLogarithmic {
                        return V(linearValue(Double(value)))
                    } else {
                        return value
                    }
                },
                set: { sliderVal in
                    if isLogarithmic {
                        value = V(exponentialValue(Double(sliderVal)))
                    } else {
                        value = V(sliderVal)
                    }
                    onChange?()
                }
            ), in: isLogarithmic ? 0.0...1.0 : range)
            TextField("", value: Binding(
                get: { value },
                set: { newValue in
                    // Clamp the entered keyboard value to the allowed range
                    let clamped = max(range.lowerBound, min(newValue, range.upperBound))
                    value = clamped
                    onChange?()
                }
            ), formatter: formatter)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 65)
            .textFieldStyle(.roundedBorder)
        }
    }
    
    /// Maps a normalized [0, 1] slider position to the exponential target range
    private func exponentialValue(_ sliderValue: Double) -> Double {
        // Prevent log(0) issues by ensuring bounds are positive
        let floor = max(minVal, 0.0001)
        let ceil = max(maxVal, floor + 0.0001)
        
        return floor * pow(ceil / floor, sliderValue)
    }

    /// Maps an actual value back to a normalized [0, 1] slider position
    private func linearValue(_ actualValue: Double) -> Double {
        let floor = max(minVal, 0.0001)
        let ceil = max(maxVal, floor + 0.0001)
        let clampedActual = max(floor, min(actualValue, ceil))
        
        return log(clampedActual / floor) / log(ceil / floor)
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
                    get: { mix },
                    set: { mix = $0; reverb.wetDryMix = mix }
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
                    get: { feedback },
                    set: { feedback = $0; delay.feedback = feedback }
                ), range: -100...100)
                
                LabeledSlider(title: "LP Cutoff", value: Binding(
                    get: { cutoff },
                    set: { cutoff = $0; delay.lowPassCutoff = cutoff }
                ), range: 1000...20000, isLogarithmic: true)
                
                LabeledSlider(title: "Dry/Wet", value: Binding(
                    get: { mix },
                    set: { mix = $0; delay.wetDryMix = mix }
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
                    get: { preGain },
                    set: { preGain = $0; distortion.preGain = preGain }
                ), range: -80...20)
                
                LabeledSlider(title: "Dry/Wet", value: Binding(
                    get: { mix },
                    set: { mix = $0; distortion.wetDryMix = mix }
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
                LabeledSlider(title: "Gain", value: Binding(
                    get: { globalGain },
                    set: { globalGain = $0; eq.globalGain = globalGain }
                ), range: -96...24)
                ForEach(0..<eq.bands.count, id: \.self) { index in
                    EQSingleBandControl(band: eq.bands[index], index: index)
                }
            }
        }.onAppear {
            unitBypass = eq.bypass
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
                    get: { freq },
                    set: { freq = $0; band.frequency = freq }
                ), range: 20...20000, isLogarithmic: true)
                LabeledSlider(title: "Gain", value: Binding(
                    get: { gain },
                    set: { gain = $0; band.gain = gain }
                ), range: -96...24)
                LabeledSlider(title: "Q", value: Binding(
                    get: { q },
                    set: { q = $0; band.bandwidth = q }
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

struct CustomPluginControl: View {
    let effects_chain: AudioEffectsManager
    let unit: AVAudioUnit?
    
    @State private var bypass = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(unit?.name ?? "Custom Plugin", isOn: Binding(
                get: { !bypass },
                set: {
                    bypass = !$0;
                    unit?.auAudioUnit.shouldBypassEffect = bypass
                }
            )).bold()
            if (!bypass) {
                HStack() {
                    Button {
                        effects_chain.showAudioUnitInNewWindow()
                    } label: {
                        Text("Open Plugin Window")
                    }
                    Button {
                        effects_chain.removeCustomPlugin()
                    } label: {
                        Text("Remove Plugin")
                    }
                }
            }
        }.onAppear {
            bypass = unit?.auAudioUnit.shouldBypassEffect ?? true
        }
    }
}

struct PluginsLoadWindow: View {
    let effects_chain: AudioEffectsManager
    let manager = AudioEffectsManager.pluginsManager
    @State private var show_window = false
    @State private var selectedPlugin: UUID? = nil
    
    var body: some View {
        let plugins = manager.AllPluginsInfoList
        
        Button {
            show_window = true
        } label: {
            Text("Choose Plugin")
        }
        .sheet(isPresented: $show_window) {
            VStack() {
                Text("Sheet")
                
                List(plugins, selection: $selectedPlugin) { plugin in
                    Text(plugin.name + " - " + plugin.manufacturer).padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(height: 500)
                
                HStack {
                    Button("Cancel") {
                        show_window = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Choose") {
                        if let selectedPlugin {
                            effects_chain.loadCustomPlugin(id: selectedPlugin)
                        }
                        show_window = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedPlugin == nil)
                }
            }
            .padding()
        }
    }
}

#Preview {
    let model = AudioEngineModel()
    model.Tracks = [
        Track(name: "Track 1", type: .backingTrack),
    ]
    model.currentlySelectedTrack = model.Tracks[0]
    return InspectorPanelView().environment(model)
}
