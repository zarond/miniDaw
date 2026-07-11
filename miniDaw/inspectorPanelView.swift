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
        VStack(alignment: .leading, spacing: 4) {
            Text("Track name:")
            
            EditableNameTextField(name: $bindableTrack.name)
            
            Text("Volume:")
            
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
            
            Knob(
                value: $bindableTrack.pan,
                title: "",
                minValue: -1.0, maxValue: 1.0,
            ).offset(x: 16, y: -16)
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 160)
    }
}

#Preview {
    var model = AudioEngineModel()
    model.Tracks = [
        Track(name: "Track 1", type: .backingTrack),
        Track(name: "Track 2", type: .backingTrack),
        Track(name: "Track 3", type: .recordingTrack)
    ]
    model.currentlySelectedTrack = model.Tracks[0]
    return InspectorPanelView().environment(model)
}
