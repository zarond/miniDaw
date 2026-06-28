//
//  workWindowView.swift
//  miniDaw
//
//  Created by Artur Makoev on 28.06.2026.
//

import SwiftUI

struct WorkWindowView: View {
    @Environment(AudioEngineModel.self) private var model
    
    var body: some View {
        @Bindable var bindableModel = model
        
        VStack() {
            TimelineWindowView(model: model)
            Spacer()
            Divider()
            TimelineBar(model: model)
        }
        .frame(minWidth: 160)
    }
}

struct TimelineBar: View {
    var model: AudioEngineModel
    
    @State private var isHovering: Bool = false
    @State private var isDragging = false
    @State private var dragProgress = 0.0
    
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
                                        isDragging = false
                                        let relativeX = min(max(0, value.location.x), geo.size.width)
                                        let newProgress = Double(relativeX / geo.size.width)
                                        self.model.set_to_relative_position(newProgress)
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
    
    var body: some View {
        @Bindable var bindableModel = model
        VStack() {
            // toDo
            Rectangle()
        }
    }
}

#Preview {
    WorkWindowView()
        .environment(AudioEngineModel())
}
