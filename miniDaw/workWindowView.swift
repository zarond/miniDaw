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
            TimelineWindowView(
                model: model,
                isDragging: $isDraggingNeedle,
                dragProgress: $NeedleDragProgress,
                snapToBeat: snapToBeat
            )
            HStack() {
                Toggle(
                    "Snap to Beat",
                    systemImage: "inset.filled.leftthird.square",
                    isOn: $snapToBeat
                )
                .padding(.horizontal)
                Spacer()
            }
            Divider()
            TimelineBar(
                model: model,
                isDragging: $isDraggingNeedle,
                dragProgress: $NeedleDragProgress
            )
        }
        .frame(minWidth: 160)
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

#Preview {
    WorkWindowView()
        .environment(AudioEngineModel())
}
