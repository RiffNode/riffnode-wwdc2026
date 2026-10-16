import AVFoundation
import os

// MARK: - Audio Tap Callback (Nonisolated - Critical for Swift 6 Concurrency)
// This function MUST be a global/free function, NOT a method or closure.
// When passed to installTap, it has NO actor isolation, preventing MainActor crashes.

func audioTapCallback(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    // ✅ SAFE: This is a nonisolated global function.
    // It runs on the audio thread with no MainActor association.

    guard let channelData = buffer.floatChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return }

    let channelCount = Int(buffer.format.channelCount)

    // Get FULL samples for FFT analysis (no downsampling)
    var fullSamples = [Float](repeating: 0, count: frameLength)

    for i in 0..<frameLength {
        var maxSample: Float = 0
        // Check all channels and take the maximum (handles mono/stereo and different input configs)
        for ch in 0..<channelCount {
            let sample = channelData[ch][i]
            if abs(sample) > abs(maxSample) {
                maxSample = sample
            }
        }
        fullSamples[i] = maxSample
    }

    // Use free functions to avoid any MainActor association
    let rms = audioCalculateRMS(fullSamples)
    let waveform = audioDownsampleForDisplay(fullSamples, targetCount: 128)

    // Write to thread-safe buffer (no MainActor dependency)
    // Full samples will be accumulated in the buffer for FFT analysis
    AudioSampleBuffer.shared.write(samples: fullSamples, waveform: waveform, rms: rms)
}

// MARK: - Free Functions for Audio Processing (Thread-Safe)
// These are NOT associated with any actor - safe to call from any thread

func audioDownsampleForDisplay(_ samples: [Float], targetCount: Int) -> [Float] {
    guard samples.count > 0 else { return Array(repeating: 0, count: targetCount) }

    var result = [Float](repeating: 0, count: targetCount)
    let chunkSize = max(1, samples.count / targetCount)

    for i in 0..<targetCount {
        let start = i * chunkSize
        let end = min(start + chunkSize, samples.count)
        var maxVal: Float = 0
        for j in start..<end {
            maxVal = max(maxVal, abs(samples[j]))
        }
        result[i] = maxVal
    }
    return result
}

func audioCalculateRMS(_ samples: [Float]) -> Float {
    guard samples.count > 0 else { return 0 }
    var sum: Float = 0
    for sample in samples {
        sum += sample * sample
    }
    return sqrt(sum / Float(samples.count))
}

// MARK: - Thread-Safe Audio Sample Buffer

/// Audio data packet for thread-safe transfer
struct AudioData: Sendable {
    let samples: [Float]
    let waveform: [Float]
    let rms: Float
}

// Allows audio thread to write samples without MainActor dependency
// Main thread polls this buffer to update UI

final class AudioSampleBuffer: @unchecked Sendable {
    static let shared = AudioSampleBuffer()

    // OSAllocatedUnfairLock is ~2-4x faster than NSLock for uncontended cases
    // Better for real-time audio where low latency is critical
    private let lock = OSAllocatedUnfairLock<AudioBufferState>(initialState: AudioBufferState())

    // Target buffer size for FFT analysis (needs 2048+ samples)
    private let analysisBufferSize = 4096

    private struct AudioBufferState {
        var samples: [Float] = []
        var waveform: [Float] = Array(repeating: 0, count: 128)
        var rms: Float = 0
        // Accumulating buffer for FFT analysis
        var analysisBuffer: [Float] = []
    }

    private init() {}

    func reset() {
        lock.withLock { $0 = AudioBufferState() }
    }

    /// Write audio data from audio thread (thread-safe, lock-free optimized)
    func write(samples: [Float], waveform: [Float], rms: Float) {
        lock.withLock { state in
            state.samples = samples
            state.waveform = waveform
            state.rms = rms

            // Accumulate samples for FFT analysis
            state.analysisBuffer.append(contentsOf: samples)

            // Keep buffer at target size (sliding window)
            if state.analysisBuffer.count > analysisBufferSize {
                state.analysisBuffer.removeFirst(state.analysisBuffer.count - analysisBufferSize)
            }
        }
    }

    /// Read audio data from main thread (thread-safe, lock-free optimized)
    func read() -> AudioData {
        lock.withLock { state in
            // Return the accumulated analysis buffer for FFT
            AudioData(samples: state.analysisBuffer, waveform: state.waveform, rms: state.rms)
        }
    }
}
