//
//  AudioWaveformView.swift
//  miniDaw
//
//  Created by Artur Makoev on 30.06.2026.
//

import SwiftUI
import Charts
import AVFoundation
import Accelerate

struct AudioWaveformView: View {
    let audio : AVAudioFile?
    let visibleRatio: Double
    
    @State private var data: [AudioPeak] = []
    
    var body: some View {
        Chart(data.enumerated(), id: \.offset) { index, peak in
            AreaMark(
                x: .value("Position", index),
                yStart: .value("Min Amplitude", peak.min),
                yEnd: .value("Max Amplitude", peak.max)
            )
            .foregroundStyle(Color.black.opacity(0.5))
        }
        .task(id: audio) {
            self.data = convertAudioToArray(audio)
        }
        .chartXScale(domain: 0...max(Int(visibleRatio * Double(data.count)) - 1, 0))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: -1.0...1.0)
    }
}

fileprivate struct AudioPeak {
    let min: Float
    let max: Float
}

fileprivate func convertAudioToArray(_ audioFile: AVAudioFile?) -> [AudioPeak] {
    guard let audioFile else { return [] }
    
    let lengthSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
    let data_points_per_second: Int = 30
    
    let totalFrames = AVAudioFrameCount(audioFile.length)
    
    guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: totalFrames) else {
        return []
    }
    
    do {
        audioFile.framePosition = 0
        try audioFile.read(into: buffer)
    } catch { return [] }
    
    guard let channelData = buffer.floatChannelData else { return [] }
    let allSamples = channelData[0]
    
    let pointsNumber = max(Int(lengthSeconds * Double(data_points_per_second)), 3)
    let samplesPerPeriod = Int(totalFrames / UInt32(pointsNumber))
    
    var values = [AudioPeak](repeating: AudioPeak(min: 0.0, max: 0.0), count: pointsNumber)
    
    DispatchQueue.concurrentPerform(iterations: pointsNumber) { i in
        let startOffset = i * samplesPerPeriod
        
        // Pointer to the start of this specific period
        let periodSamplesPointer = allSamples.advanced(by: startOffset)
        
        var minVal: Float = 0.0
        var maxVal: Float = 0.0
        
        // Vectorized min/max calculation
        vDSP_minv(periodSamplesPointer, 1, &minVal, vDSP_Length(samplesPerPeriod))
        vDSP_maxv(periodSamplesPointer, 1, &maxVal, vDSP_Length(samplesPerPeriod))
        
        values[i] = AudioPeak(min: minVal, max: maxVal)
    }
    
    return values
}

#Preview("Sample Audio") {
    let url = Bundle.main.url(forResource: "metronome_bip", withExtension: "wav")
    let audioFile = try? url.flatMap { try AVAudioFile(forReading: $0) }
    return AudioWaveformView(audio: audioFile, visibleRatio: 1.0)
}
