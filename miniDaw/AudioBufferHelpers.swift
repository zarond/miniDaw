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
                loop : Bool = false)
{
    // Ensure formats and channel counts match for raw memcpy
    guard source.format.commonFormat == destination.format.commonFormat else {
        assertionFailure("Mismatched buffer formats.")
        return
    }

    let channelCount = Int(destination.format.channelCount)
    let SRC_channelCount = Int(source.format.channelCount)
    let totalRequested = Int(frameNumberSrc)
    let framesTillEnd = max(0, Int(destination.frameLength) - Int(offsetDst))
    let framesInSrc = max(0, min(Int(source.frameLength) - Int(startFrameSrc), totalRequested))

    switch source.format.commonFormat {
    case .pcmFormatFloat32:
        guard let srcData = source.floatChannelData,
              let dstData = destination.floatChannelData else { return }
        for ch in 0..<channelCount {
            let src = srcData[ch % SRC_channelCount].advanced(by: Int(startFrameSrc))
            let dst = dstData[ch].advanced(by: Int(offsetDst))

            let firstCopyFrames = min(framesInSrc, framesTillEnd)
            if firstCopyFrames > 0 {
                memcpy(dst, src, firstCopyFrames * MemoryLayout<Float>.size)
            }

            let remaining = totalRequested - firstCopyFrames
            if loop, remaining > 0 {
                let src2 = src.advanced(by: firstCopyFrames)
                let dst2 = dstData[ch]
                memcpy(dst2, src2, remaining * MemoryLayout<Float>.size)
            }
        }

    case .pcmFormatInt16:
        guard let srcData = source.int16ChannelData,
              let dstData = destination.int16ChannelData else { return }
        for ch in 0..<channelCount {
            let src = srcData[ch % SRC_channelCount].advanced(by: Int(startFrameSrc))
            let dst = dstData[ch].advanced(by: Int(offsetDst))

            let firstCopyFrames = min(framesInSrc, framesTillEnd)
            if firstCopyFrames > 0 {
                memcpy(dst, src, firstCopyFrames * MemoryLayout<Int16>.size)
            }

            let remaining = totalRequested - firstCopyFrames
            if loop, remaining > 0 {
                let src2 = src.advanced(by: firstCopyFrames)
                let dst2 = dstData[ch]
                memcpy(dst2, src2, remaining * MemoryLayout<Int16>.size)
            }
        }

    case .pcmFormatInt32:
        guard let srcData = source.int32ChannelData,
              let dstData = destination.int32ChannelData else { return }
        for ch in 0..<channelCount {
            let src = srcData[ch % SRC_channelCount].advanced(by: Int(startFrameSrc))
            let dst = dstData[ch].advanced(by: Int(offsetDst))

            let firstCopyFrames = min(framesInSrc, framesTillEnd)
            if firstCopyFrames > 0 {
                memcpy(dst, src, firstCopyFrames * MemoryLayout<Int32>.size)
            }

            let remaining = totalRequested - firstCopyFrames
            if loop, remaining > 0 {
                let src2 = src.advanced(by: firstCopyFrames)
                let dst2 = dstData[ch]
                memcpy(dst2, src2, remaining * MemoryLayout<Int32>.size)
            }
        }

    case .pcmFormatFloat64, .otherFormat:
        assertionFailure("Unsupported PCM format in copyBuffer")
        return
    @unknown default:
        return
    }
}

func createZeroedBuffer(format: AVAudioFormat, capacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        return nil
    }
    buffer.frameLength = capacity
    let channelCount = Int(format.channelCount)

    switch format.commonFormat {
    case .pcmFormatFloat32:
        if let channelData = buffer.floatChannelData {
            let bytesToClear = Int(capacity) * MemoryLayout<Float>.size
            for ch in 0..<channelCount {
                memset(channelData[ch], 0, bytesToClear)
            }
        }
    case .pcmFormatInt16:
        if let channelData = buffer.int16ChannelData {
            let bytesToClear = Int(capacity) * MemoryLayout<Int16>.size
            for ch in 0..<channelCount {
                memset(channelData[ch], 0, bytesToClear)
            }
        }
    case .pcmFormatInt32:
        if let channelData = buffer.int32ChannelData {
            let bytesToClear = Int(capacity) * MemoryLayout<Int32>.size
            for ch in 0..<channelCount {
                memset(channelData[ch], 0, bytesToClear)
            }
        }
    case .pcmFormatFloat64, .otherFormat:
        assertionFailure("Unsupported PCM format in createZeroedBuffer")
    @unknown default:
        break
    }

    return buffer
}

func cropped_buffer(from buffer: AVAudioPCMBuffer, format: AVAudioFormat, start_frame: AVAudioFramePosition, number_frames: AVAudioFrameCount, allow_skip_crop: Bool = true) -> AVAudioPCMBuffer? {
    if (allow_skip_crop && start_frame == 0 && number_frames >= buffer.frameLength && format == buffer.format) {
        return buffer
    }
    guard let segmentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: number_frames) else {
        return nil
    }
    guard format.commonFormat == buffer.format.commonFormat else {
        assertionFailure("Mismatched buffer formats.")
        return nil
    }
    segmentBuffer.frameLength = number_frames
    let channelCount = Int(format.channelCount)
    let SRC_channelCount = Int(buffer.format.channelCount)

    switch buffer.format.commonFormat {
    case .pcmFormatFloat32:
        if let srcData = buffer.floatChannelData, let destData = segmentBuffer.floatChannelData {
            for channel in 0..<channelCount {
                let src = srcData[channel % SRC_channelCount].advanced(by: Int(start_frame))
                let dst = destData[channel]
                let byteCount = Int(number_frames) * MemoryLayout<Float>.size
                memcpy(dst, src, byteCount)
            }
        }
    case .pcmFormatInt16:
        if let srcData = buffer.int16ChannelData, let destData = segmentBuffer.int16ChannelData {
            for channel in 0..<channelCount {
                let src = srcData[channel % SRC_channelCount].advanced(by: Int(start_frame))
                let dst = destData[channel]
                let byteCount = Int(number_frames) * MemoryLayout<Int16>.size
                memcpy(dst, src, byteCount)
            }
        }
    case .pcmFormatInt32:
        if let srcData = buffer.int32ChannelData, let destData = segmentBuffer.int32ChannelData {
            for channel in 0..<channelCount {
                let src = srcData[channel % SRC_channelCount].advanced(by: Int(start_frame))
                let dst = destData[channel]
                let byteCount = Int(number_frames) * MemoryLayout<Int32>.size
                memcpy(dst, src, byteCount)
            }
        }
    case .pcmFormatFloat64, .otherFormat:
        assertionFailure("Unsupported PCM format in cropped_buffer")
    @unknown default:
        break
    }
    return segmentBuffer
}
