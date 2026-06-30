//
//  ContentView.swift
//  miniDaw
//
//  Created by Artur Makoev on 23.06.2026.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        HStack() {
            MainOptionsView()
            Divider()
            WorkWindowView()
        }
    }
}

struct MainOptionsView: View {
    @Environment(AudioEngineModel.self) private var model
    
    var body: some View {
        // Create a bindable reference locally to allow the use of '$'
        @Bindable var bindableModel = model
        
        VStack(alignment: .leading) {
            HStack() {
                Image(systemName: "music.pages")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, DAW!")
            }
            
            NumericalFieldWithStepper(
                mainValue: $bindableModel.bpm,
                minValue: AudioEngineModel.minBPM,
                maxValue: AudioEngineModel.maxBPM,
                TextMsg: "BPM:"
            )
            
            NumericalFieldWithStepper(
                mainValue: $bindableModel.numBars,
                minValue: 1,
                maxValue: 1024,
                TextMsg: "Bars:"
            )
            
            TimeSignatureUI(
                high: $bindableModel.TimeSignatureHigh,
                low: $bindableModel.TimeSignatureLow
            )
            
            Toggle(
                "Metronome",
                systemImage: "metronome",
                isOn: $bindableModel.metronomeOn
            )
            
            Toggle(
                "Count-in",
                systemImage: "numbers.rectangle",
                isOn: $bindableModel.preCount
            )
            
            Toggle(
                "Loop",
                systemImage: "repeat",
                isOn: $bindableModel.looping
            )
            
            LoadBTButton(onPress: bindableModel.load_backing_track)
            
            Text("Output Sound Volume:")
                .padding(.top, 10)
            VolumeSlider(volume: $bindableModel.volume)
                .frame(width: 135)
        }
        .padding(.leading)
        .frame(minWidth: 160)
    }
}

struct NumericalFieldWithStepper: View {
    @State private var valueString: String = "120"
    @FocusState private var FieldIsFocused: Bool
    
    @Binding var mainValue: Int
    
    var minValue: Int = 0
    var maxValue: Int = 10
    
    var TextMsg: String
    
    var body: some View {
        HStack {
            Text(TextMsg)
            
            TextField("", text: $valueString)
                .frame(width: 60)
                .focused($FieldIsFocused)
                .onChange(of: valueString) { oldValue, newValue in
                    // Validate and clamp the input
                    let value_optional = Int(newValue)
                    if newValue.isEmpty {}
                    else if let value = value_optional, value == 0 {}
                    else if let value = value_optional, value >= minValue, value <= maxValue {
                        if (mainValue == value) { return }
                        mainValue = value
                    } else {
                        valueString = String(mainValue)
                    }
                }
                .onChange(of: FieldIsFocused) { oldValue, newValue in
                    valueString = String(mainValue)
                }
                .onSubmit {
                    FieldIsFocused = false
                }
            
            Stepper("", value: $mainValue, in: minValue...maxValue)
                .onChange(of: mainValue) { oldValue, newValue in
                    valueString = String(newValue)
                }
        }
        .onAppear {
            valueString = String(mainValue)
        }
    }
}

struct PlayButton: View {
    @Binding var isPlaying: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button {
            if isPlaying {
                onStop()
            } else {
                onStart()
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .frame(width: 16, height: 16)
        }
        .keyboardShortcut(.space, modifiers: [])
    }
}

struct RecordButton: View {
    @Binding var isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button {
            if isRecording {
                onStop()
            } else {
                onStart()
            }
        } label: {
            Image(systemName: isRecording ? "stop.fill" : "record.circle")
                .foregroundStyle(.tint)
                .tint(.red)
                .frame(width: 16, height: 16)
        }
        .tint(isRecording ? .red : nil)
        .keyboardShortcut("r", modifiers: [])
    }
}

struct RewindButton: View {
    let onPress: () -> Void

    var body: some View {
        Button(action: {
            onPress()
        }) {
            Image(systemName: "backward.end")
                .frame(width: 16, height: 16)
        }
        .keyboardShortcut("b", modifiers: [])
    }
}

struct TimeSignatureUI: View {
    @Binding var high: Int
    @Binding var low: Int
    
    var body: some View {
        Text("Time Signature:")
        HStack {
            Picker("", selection: $high) {
                ForEach(1...32, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 50)
            Text("/")
            Picker("", selection: $low) {
                ForEach([1, 2, 4, 8, 16], id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 50)
        }
    }
}

struct LoadBTButton: View {
    @State private var isPresentingFilePicker = false
    
    let onPress: (URL) -> Void
    var body: some View {
        Button(
            action: {
                isPresentingFilePicker = true
            },
            label: {
                Text("Load backing track")
            }
        )
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [.mp3, .aiff, .wav]
        ) { result in
            switch result {
            case .success(let url):
                onPress(url)
            case .failure:
                print("Failed to load backing track file")
            }
        }
    }
}

struct VolumeSlider: View {
    @Binding var volume: Float
    var body: some View {
        Slider(value: $volume, in: 0...1)
    }
}

#Preview {
    var model = AudioEngineModel()
    model.Tracks = [
        Track(name: "Track 1", type: .backingTrack),
        Track(name: "Track 2", type: .backingTrack)
    ]
    return ContentView().environment(model)
}

