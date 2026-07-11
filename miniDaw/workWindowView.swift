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
                let beatSpacing = CGFloat(max(rulerWidth / Double(totalBeats), 8))
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
    
    @FocusState private var focusedID: UUID?
    @State private var selectedID: UUID?
    
    var body: some View {
        ZStack() {
            Rectangle()
                .fill(Color(white: 0.15))
            
            VStack(alignment: .leading, spacing: 1){
                Rectangle()
                    .fill(Color(white: 0.2))
                    .frame(height: 20)
                
                ForEach(model.Tracks) { track in
                    TrackView(track: track, isFocused: selectedID == track.id)
                        .focusable()
                        .focused($focusedID, equals: track.id)
                        .focusEffectDisabled()
                        .onDeleteCommand {
                            model.delete_track(id: selectedID)
                        }
                }
                
                Spacer()
                
                BottomButtons(model: model, selectedID: selectedID)
            }
            .onChange(of: focusedID) { oldValue, newValue in
                if newValue == nil { return }
                selectedID = newValue
            }
            .onChange(of: selectedID) { oldValue, newValue in
                model.select_track(id: newValue)
            }
        }
        .frame(maxWidth: 230, maxHeight: .infinity)
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
            
            HStack() {
                EditableNameTextField(name: $bindableTrack.name)
                    .frame(maxWidth: 80)
                
                VolumeSlider(volume: $bindableTrack.volume)
                    .frame(width: 60)
                
                Knob(
                    value: $bindableTrack.pan,
                    title: "PAN",
                    minValue: -1.0, maxValue: 1.0,
                    hideText: true
                )
                    .scaleEffect(0.2)
                    .frame(width: 16, height: 8)
                
                Toggle(isOn: $bindableTrack.mute) {
                    Image(systemName: "speaker.slash")
                    .font(.system(size: 10, weight: .medium))
                }
                .frame(width: 16, height: 8)
                .toggleStyle(.button)
                
                if (track.type == .recordingTrack) {
                    let monitorBinding = Binding<Bool>(
                        get: { bindableTrack.monitorOn },
                        set: { newValue in
                            Track.model?.set_monitoring(for: track.id, enabled: newValue)
                        }
                    )
                    Toggle(isOn: monitorBinding) {
                        Image(systemName: "microphone")
                        .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 16, height: 8)
                    .toggleStyle(.button)
                }
            }
        }
        .frame(width: 230, height: 40)
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
        let audio_length = max(track.AudioLengthSeconds * oneSecondLength, 1e-5)
        let length: CGFloat = min(audio_length, maxLength)
        let startOffset: CGFloat = track.AudioStartSeconds * oneSecondLength
        let visibleRatio = (audio_length < maxLength) ? 1.0 : maxLength / audio_length
        
        ZStack() {
            RoundedRectangle(cornerRadius: 5)
                .fill(track.type == .backingTrack ? Color.green :  Color.red)
                .frame(width: length, height: 40)
                .shadow(radius: 3)
            
            AudioWaveformView(
                audio_file: track.BTAudioFile,
                audio_buffer: track.RecordBuffer,
                audio_buffer_counter: track.RecordBufferCounter,
                visibleRatio: visibleRatio.isNaN ? 1.0 : visibleRatio
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

struct Knob: View {
    @Binding var value: Float // Expected range: 0.0 to 1.0
    
    var title: String = "Volume"
    var minValue: Float = 0.0
    var maxValue: Float = 1.0
    var centerValue: Float = 0.0
    var minAngle: Float = -140.0
    var maxAngle: Float = 140.0
    var hideText: Bool = false
    
    @State private var dragStartValue: Float? = nil
    @State private var isDragging: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            if !hideText {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            ZStack {
                // Background Track
                Circle()
                    .trim(from: 0.0, to: 0.78) // Leaves a gap at the bottom
                    .stroke(Color(white: 0.4), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(130))
                    .frame(width: 95, height: 95)
                
                // Active Value Fill Track
                let colorBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
                let valueRange = maxValue - minValue
                let relativeValue = (value - minValue) / valueRange
                let relativeCenter = (centerValue - minValue) / valueRange
                let from = 0.78 * CGFloat(relativeCenter)
                let to = 0.78 * CGFloat(relativeValue)
                Circle()
                    .trim(from: min(from, to), to: max(from, to))
                    .stroke(colorBlue, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(130))
                    .frame(width: 95, height: 95)
                    .animation(.linear(duration: 0.1), value: value)
                
                // The Center Dial Knob
                Circle()
                    .fill(Color(white: 0.2))
                    .shadow(radius: 4)
                    .frame(width: 80, height: 80)
                    .overlay(
                        // Indicator dot/line
                        Circle()
                            .fill(colorBlue)
                            .frame(width: 16, height: 16)
                            .offset(y: -30) // Push it to the outer rim
                    )
                    .rotationEffect(.degrees(Double(currentAngle)))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                isDragging = true
                                handleDrag(gesture: gesture)
                            }
                            .onEnded { _ in
                                dragStartValue = nil
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDragging = false
                                }
                            }
                    )
                    .simultaneousGesture(
                        TapGesture()
                            .modifiers(.control)
                            .onEnded {
                                value = centerValue
                            }
                    )
            }
            
            if (!hideText){
                Text("\(Int(value * 100))%")
                    .font(.body)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
        }
    }
    
    // Dynamic angle mapping based on value
    private var currentAngle: Float {
        let totalRange = maxAngle - minAngle
        let valueRange = maxValue - minValue
        let value_relative = (value - minValue) / valueRange
        return minAngle + (value_relative * totalRange)
    }
    
    private func handleDrag(gesture: DragGesture.Value) {
        let scalingFactor: Float = 150.0 // Adjust for sensitivity!
        if dragStartValue == nil {
            dragStartValue = value
        }
        let newValue = (dragStartValue ?? value) + Float(gesture.translation.width) / scalingFactor
        value = max(minValue, min(maxValue, newValue))
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

#Preview {
    @Previewable @State var volume : Float = 0
    @Previewable @State var pan : Float = 0
    HStack() {
        Knob(value: $volume, title: "Volume")
            .padding()
        Knob(value: $pan, title: "Pan", minValue: -1.0, maxValue: 1.0)
            .padding()
    }
}
