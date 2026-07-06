//
//  workWindowView.swift
//  miniDaw
//
//  Created by Artur Makoev on 28.06.2026.
//

import SwiftUI

struct WorkWindowView: View {
    @Environment(AudioEngineModel.self) private var model
    
    @State private var isDraggingNeedle = false
    @State private var NeedleDragProgress = 0.0
    @State private var snapToBeat = true
    
    var body: some View {
        @Bindable var bindableModel = model
        
        VStack() {
            HStack(spacing: 0) {
                TracksView(model: model)
                
                TimelineWindowView(
                    model: model,
                    isDragging: $isDraggingNeedle,
                    dragProgress: $NeedleDragProgress,
                    snapToBeat: snapToBeat
                )
            }
            HStack() {
                Toggle(
                    "Snap to Beat",
                    systemImage: "inset.filled.leftthird.square",
                    isOn: $snapToBeat
                )
                .padding(.horizontal)
                Spacer()
                
                RewindButton(onPress: bindableModel.reset_to_begining)
                PlayButton(
                    isPlaying: $bindableModel.isPlaying,
                    onStart: {bindableModel.start()},
                    onStop: bindableModel.stop
                )
                RecordButton(
                    isRecording: $bindableModel.isRecording,
                    onStart: bindableModel.start_recording,
                    onStop: {bindableModel.stop_recording()}
                )

                Spacer()
            }
            Divider()
            TimelineBar(
                model: model,
                isDragging: $isDraggingNeedle,
                dragProgress: $NeedleDragProgress
            )
        }
        .frame(minWidth: 500)
    }
}

struct TimelineBar: View {
    var model: AudioEngineModel
    
    @State private var isHovering: Bool = false
    @Binding var isDragging: Bool
    @Binding var dragProgress: Double
    
    var body: some View {
        TimelineView(.animation) { timelineContext in
            let progress = model.currTimeSeconds / model.TimelineLengthSeconds
            let clampedProgress = max(0.0, min(isDragging ? dragProgress : progress, 1.0))
            
            VStack {
                Text(timeString(model.currTimeSeconds))
                // Custom Progress Bar container
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                        
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: geo.size.width * CGFloat(clampedProgress))
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black)
                            .frame(width: 6)
                            .contentShape(Rectangle().inset(by: -10)) // Expand tap area
                            .padding(.vertical, -8)
                            .offset(x: geo.size.width * CGFloat(clampedProgress))
                            .opacity(isHovering ? 1.0 : 0.1)
                            .onHover { hovering in
                                isHovering = hovering
                            }
                            .animation(.easeInOut(duration: 0.1), value: isHovering)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let relativeX = min(max(0, value.location.x), geo.size.width)
                                        let newProgress = Double(relativeX / geo.size.width)
                                        dragProgress = newProgress
                                    }
                                    .onEnded { value in
                                        let relativeX = min(max(0, value.location.x), geo.size.width)
                                        let newProgress = Double(relativeX / geo.size.width)
                                        self.model.set_to_relative_position(newProgress)
                                        isDragging = false
                                    }
                            )
                    }
                }
                .frame(height: 12)
                .padding(.bottom)
                .padding(.horizontal)
            }
        }
    }
    
    private func timeString(_ totalSeconds : Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional // Uses numbers separated by colons
        formatter.zeroFormattingBehavior = .pad // Adds the leading zeros (01:05)
        
        return formatter.string(from: totalSeconds) ?? "00:00"
    }
}

struct TimelineWindowView: View {
    var model: AudioEngineModel
    
    @Binding var isDragging: Bool
    @Binding var dragProgress: Double
    let snapToBeat : Bool
    
    var body: some View {
        @Bindable var bindableModel = model
        GeometryReader { geo in
            // --- MEASURE RULER ---
            ScrollView(.horizontal, showsIndicators: true) {
                let barCount = max(model.numBars, 1)
                let beatsPerBar = max(model.TimeSignatureHigh, 1)
                let totalBeats = barCount * beatsPerBar
                let rulerHeight: CGFloat = 20
                let rulerWidth = geo.size.width
                let beatSpacing = max(rulerWidth / CGFloat(totalBeats), 8)
                let timeline_width = beatSpacing * CGFloat(totalBeats)
                let oneSecondLength = (Double(model.bpm) / 60.0) * beatSpacing
                
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(white: 0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Rectangle()
                        .fill(Color(white: 0.2))
                        .frame(maxWidth: .infinity, maxHeight: rulerHeight)

                    // Beat lines
                    ForEach(0..<totalBeats, id: \.self) { beat in
                        let isStrongBeat = (beat % beatsPerBar == 0)
                        Rectangle()
                            .fill(Color.white.opacity(isStrongBeat ? 0.9 : 0.3))
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: CGFloat(beat) * beatSpacing)
                    }

                    // Bar numbers
                    ForEach(0..<barCount, id: \.self) { bar in
                        let x = CGFloat(bar * beatsPerBar) * beatSpacing
                        Text("\(bar + 1)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .offset(x: x + 4, y: 2)
                    }
                    
                    // Regions
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.Tracks) { track in
                            RegionView(
                                track: track,
                                oneSecondLength: oneSecondLength,
                                maxLength: timeline_width)
                        }
                    }.offset(y: rulerHeight + 1)
                    
                    // Needle
                    NeedleView(
                        model : model,
                        timeline_width: timeline_width,
                        isDragging: $isDragging,
                        dragProgress: $dragProgress,
                        snapToBeat: snapToBeat
                    )
                }
                .frame(width: timeline_width)
            }
        }
    }
}

struct NeedleView: View {
    var model: AudioEngineModel
    var timeline_width: CGFloat
    
    @Binding var isDragging: Bool
    @Binding var dragProgress: Double
    
    let snapToBeat : Bool
    
    var body: some View {
        let progress = isDragging ? dragProgress : (model.currTimeSeconds / model.TimelineLengthSeconds)
        let offset : CGFloat = progress * timeline_width
        
        Rectangle()
            .fill(Color.white)
            .frame(width: 2)
            .contentShape(Rectangle().inset(by: -10)) // Expand tap area
            .offset(x: offset)
            .shadow(radius: 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let relativeX = min(max(0, value.location.x), timeline_width)
                        let newProgress = Double(relativeX / timeline_width)
                        dragProgress = newProgress
                    }
                    .onEnded { value in
                        let relativeX = min(max(0, value.location.x), timeline_width)
                        let newProgress = Double(relativeX / timeline_width)
                        self.model.set_to_relative_position(newProgress, snapToBeat: snapToBeat)
                        isDragging = false
                    }
            )
        
        Triangle()
            .fill(Color.red)
            .frame(width: 12, height: 10)
            .offset(x:offset - 5, y: 16)
            .shadow(radius: 1)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        
        return path
    }
}

struct TracksView: View {
    var model: AudioEngineModel
    
    @FocusState private var selectedID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1){
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(width: 205, height: 20)
            
            ForEach(model.Tracks) { track in
                TrackView(track: track, isFocused: selectedID == track.id)
                    .focusable()
                    .focused($selectedID, equals: track.id)
                    .focusEffectDisabled()
                    .onDeleteCommand {
                        model.delete_track(id: selectedID)
                    }
            }
            
            Spacer()
            
            BottomButtons(model: model, selectedID: selectedID)
                .frame(width: 205)
        }
        .background(Color(white: 0.15))
        .onChange(of: selectedID) { oldValue, newValue in
            model.select_track(id: newValue)
        }
    }
}

struct TrackView: View {
    let track: Track
    let isFocused: Bool
    
    var body: some View {
        @Bindable var bindableTrack = track
        
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isFocused ? Color.teal : Color.gray)
                .frame(width: 205, height: 40)
            
            HStack() {
                EditableNameTextField(name: $bindableTrack.name)
                    .frame(maxWidth: 80)
                
                VolumeSlider(volume: $bindableTrack.volume)
                    .frame(width: 60)
                
                Toggle(isOn: $bindableTrack.mute) {
                    Image(systemName: "speaker.slash")
                    .font(.system(size: 10, weight: .medium))
                }
                .frame(width: 16, height: 8)
                .toggleStyle(.button)
                
                if (track.type == .recordingTrack) {
                    Toggle(isOn: $bindableTrack.monitorOn) {
                        Image(systemName: "microphone")
                        .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 16, height: 8)
                    .toggleStyle(.button)
                }
            }
        }
    }
}

struct EditableNameTextField: View {
    @State private var isEditing: Bool = false
    @State private var text: String = ""
    @FocusState private var isTextFieldFocused: Bool // Auto-focuses the keyboard/cursor
    @Binding var name: String
    
    private func ApplyName() {
        isEditing = false
        let trimmed_text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (!trimmed_text.isEmpty) {
            name = trimmed_text
        } else {
            name = "Untitled"
        }
        text = name
    }
    var body: some View {
        if (isEditing) {
            TextField(name, text: $text)
                .focused($isTextFieldFocused)
                .onSubmit {
                    ApplyName()
                }
                .onChange(of: isTextFieldFocused) { _, newValue in
                    if !newValue {
                        ApplyName()
                    }
                }
        } else {
            Text(name)
                .onTapGesture(count: 2) {
                    text = name
                    isEditing = true
                    isTextFieldFocused = true
                }
        }
    }
}

struct RegionView: View {
    let track: Track
    let oneSecondLength: CGFloat
    let maxLength: CGFloat
    
    var body: some View {
        let audio_length = track.AudioLengthSeconds * oneSecondLength
        let length: CGFloat = min(audio_length, maxLength)
        let startOffset: CGFloat = track.AudioStartSeconds * oneSecondLength
        
        ZStack() {
            RoundedRectangle(cornerRadius: 5)
                .fill(track.type == .backingTrack ? Color.green :  Color.red)
                .frame(width: length, height: 40)
                .shadow(radius: 3)
            
            AudioWaveformView(
                audio_file: track.BTAudioFile,
                audio_buffer: track.RecordBuffer,
                audio_buffer_counter: track.RecordBufferCounter,
                visibleRatio: (audio_length == 0.0) ? 0.0 : length / (audio_length)
            ).frame(width: length, height: 40)
        }
        .offset(x: startOffset)
    }
}

struct BottomButtons: View {
    var model: AudioEngineModel
    
    let selectedID: UUID?
    
    var body: some View {
        HStack() {
            Button {
                model.create_recording_track()
            } label: {
                Image(systemName: "plus" )
                    .frame(width: 0, height: 8)
            }
            
            Button {
                model.delete_track(id: selectedID)
            } label: {
                Image(systemName: "minus" )
                    .frame(width: 0, height: 8)
            }
            
            Spacer()
            
            Button {
                model.move_track(id: selectedID, direction: .up)
            } label: {
                Image(systemName: "arrowshape.up" )
                    .frame(width: 0, height: 8)
            }
            Button {
                model.move_track(id: selectedID, direction: .down)
            } label: {
                Image(systemName: "arrowshape.down" )
                    .frame(width: 0, height: 8)
            }
        }
        .padding(2)
        .background(Color(white: 0.9))
    }
}

#Preview {
    var model = AudioEngineModel()
    model.Tracks = [
        Track(name: "Track 1", type: .backingTrack),
        Track(name: "Track 2", type: .backingTrack),
        Track(name: "Track 3", type: .recordingTrack)
    ]
    return WorkWindowView().environment(model)
}
