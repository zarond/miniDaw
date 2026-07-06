//
//  AudioBufferHelpers.swift
//  miniDaw
//
//  Created by Artur Makoev on 06.07.2026.
//

import AVFoundation

// Helper function to safely copy PCM data between buffers
func copyBuffer(from source: AVAudioPCMBuffer,
                to destination: AVAudioPCMBuffer,
                atOffset offsetDst: AVAudioFramePosition,
                startFrameSrc: AVAudioFramePosition,
                frameNumberSrc: AVAudioFrameCount,
                loop : Bool = false) {
    guard let srcData = source.floatChannelData, let destData = destination.floatChannelData else { return }
    
    let channelCount = Int(source.format.channelCount)
    let bytesPerSample : Int = formatNumBytes(source.format)
    
    for channel in 0..<channelCount {
        let srcChannelPointer = srcData[channel].advanced(by: Int(startFrameSrc))
        let destChannelPointer = destData[channel].advanced(by: Int(offsetDst))
    
        let framesTillEnd = Int(destination.frameLength) - Int(offsetDst)
        
        let framesInSrc = min(Int(source.frameLength) - Int(startFrameSrc), Int(frameNumberSrc))
        var framesToCopy = min(framesInSrc, framesTillEnd)
        memcpy(destChannelPointer, srcChannelPointer, framesToCopy * bytesPerSample)
        framesToCopy -= framesInSrc
        if loop, framesToCopy < 0 {
            framesToCopy = -framesToCopy
            
            let srcChannelPointer = srcData[channel].advanced(by: Int(startFrameSrc) + framesTillEnd)
            let destChannelPointer = destData[channel]
            memcpy(destChannelPointer, srcChannelPointer, framesToCopy * bytesPerSample)
        }
    }
}

func createZeroedBuffer(format: AVAudioFormat, capacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        return nil
    }
    
    buffer.frameLength = capacity
    
    let channelCount = Int(format.channelCount)
    let bytesToClear = Int(capacity) * formatNumBytes(format)
    
    if let channelData = buffer.floatChannelData {
        for channel in 0..<channelCount {
            memset(channelData[channel], 0, bytesToClear)
        }
    }
    
    return buffer
}

func cropped_buffer(from buffer: AVAudioPCMBuffer, start_frame: AVAudioFramePosition, number_frames: AVAudioFrameCount, allow_skip_crop: Bool = true) -> AVAudioPCMBuffer? {
    if (allow_skip_crop && start_frame == 0 && number_frames >= buffer.frameLength) {
        return buffer
    }
    guard let segmentBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: number_frames) else {
        return nil
    }
    segmentBuffer.frameLength = number_frames
    let channelCount = Int(buffer.format.channelCount)
    if let srcData = buffer.floatChannelData, let destData = segmentBuffer.floatChannelData {
        for channel in 0..<channelCount {
            let src = srcData[channel].advanced(by: Int(start_frame))
            let dst = destData[channel]
            let byteCount = Int(number_frames) * MemoryLayout<Float>.size
            memcpy(dst, src, byteCount)
        }
    } else if let srcData = buffer.int16ChannelData, let destData = segmentBuffer.int16ChannelData {
        for channel in 0..<channelCount {
            let src = srcData[channel].advanced(by: Int(start_frame))
            let dst = destData[channel]
            let byteCount = Int(number_frames) * MemoryLayout<Int16>.size
            memcpy(dst, src, byteCount)
        }
    }
    return segmentBuffer
}

fileprivate func formatNumBytes(_ format: AVAudioFormat) -> Int {
    switch format.commonFormat {
    case .pcmFormatFloat32:
        return MemoryLayout<Float>.size
    case .pcmFormatInt16:
        return MemoryLayout<Int16>.size
    case .pcmFormatInt32:
        return MemoryLayout<Int32>.size
    case .pcmFormatFloat64:
        return MemoryLayout<Double>.size
    case .otherFormat:
        return 4
    @unknown default:
        return  4
    }
}
