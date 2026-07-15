//
//  inspectorPanelView.swift
//  miniDaw
//
//  Created by Artur Makoev on 10.07.2026.
//

import SwiftUI

struct InspectorPanelView: View {
    @Environment(AudioEngineModel.self) private var model
    
    var body: some View {
        weak let selectedTrack = model.currentlySelectedTrack
        if let selectedTrack {
            TrackOptionsView(track: selectedTrack)
        } else {
            Text("Inspector")
        }
    }
}

struct TrackOptionsView: View {
    let track : Track
    var body: some View {
        @Bindable var bindableTrack = track
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Track name:")
                    .bold()
                
                EditableNameTextField(name: $bindableTrack.name)
                
                Text("Volume:")
                    .bold()
                
                HStack() {
                    VolumeSlider(volume: $bindableTrack.volume)
                    Toggle(isOn: $bindableTrack.mute) {
                        Image(systemName: "speaker.slash")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 16, height: 8)
                    .toggleStyle(.button)
                }
                
                Text("Pan:")
                    .bold()
                
                LabeledSlider(title: "", value: $bindableTrack.pan, range: -1.0...1.0)
                
                Divider()
                if track.effectsManager != nil {
                    EffectsOptions(manager: track.effectsManager!)
                }
            }
            .padding(16)
            .frame(maxWidth: 300)
            .id(track.id)
        }
    }
}

struct EffectsOptions: View {
    let manager: AudioEffectsManager
    var body: some View {
        Text("Effects:")
            .bold()
        //Divider()
        //PitchControls(timePitch: manager.timePitch)
        Divider()
        EQBandControl(eq: manager.eq)
        Divider()
        DistortionControls(distortion: manager.distortion)
        Divider()
        DelayControls(delay: manager.delay)
        Divider()
        ReverbControls(reverb: manager.reverb)
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
