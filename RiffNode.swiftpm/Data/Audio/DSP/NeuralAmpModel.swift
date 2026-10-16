import Accelerate
import Foundation

// MARK: - Neural Amp Model (NAM)
// Plays a Neural Amp Modeler capture (.nam): a WaveNet trained on recordings of a real amp,
// pedal or rig, so RiffNode can sound like that exact piece of gear. This is a Swift port of
// the original ("A1") WaveNet from NeuralAmpModelerCore (MIT), checked sample by sample
// against its reference renderer. Inference is block-based matrix maths with Accelerate's
// BLAS, and allocates nothing while rendering.
//
// Each layer array:  x → 1×1 rechannel → [dilated conv + condition mix → tanh → head sum;
//                    x += 1×1(activation)] × N → head 1×1.  Output = head_scale × final head.

enum NeuralAmpModelError: Error, LocalizedError {
    case notAModel
    case unsupportedArchitecture(String)
    case weightCountMismatch(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .notAModel: "That file isn't a Neural Amp Modeler capture."
        case .unsupportedArchitecture(let name): "This capture uses \(name), which RiffNode can't play yet (standard WaveNet captures work)."
        case .weightCountMismatch: "The capture's weights don't match its layout."
        }
    }
}

final class NeuralAmpModel: @unchecked Sendable {

    // MARK: Layout

    private enum Activation {
        case tanh, relu, hardTanh, sigmoid

        init?(_ name: String) {
            switch name.lowercased() {
            case "tanh", "fasttanh": self = .tanh
            case "relu": self = .relu
            case "hardtanh": self = .hardTanh
            case "sigmoid": self = .sigmoid
            default: return nil
            }
        }
    }

    /// A dense matrix, row-major (rows × cols).
    private struct Matrix {
        let rows: Int
        let cols: Int
        var values: [Float]
        init(rows: Int, cols: Int) { self.rows = rows; self.cols = cols; values = [Float](repeating: 0, count: rows * cols) }
    }

    private struct Layer {
        let dilation: Int
        let kernelSize: Int
        let gated: Bool
        let activation: Activation
        var conv: [Matrix]        // one (zChannels × channels) per tap, oldest tap first
        var convBias: [Float]
        var mixin: Matrix         // zChannels × conditionSize
        var output: Matrix        // channels × channels (the 1×1)
        var outputBias: [Float]
        var lookback: Int { dilation * (kernelSize - 1) }
    }

    private struct LayerArray {
        let inputSize: Int
        let conditionSize: Int
        let channels: Int
        let headSize: Int
        var rechannel: Matrix     // channels × inputSize, no bias
        var layers: [Layer]
        var headRechannel: Matrix // headSize × channels
        var headBias: [Float]?
    }

    private var arrays: [LayerArray] = []
    private var headScale: Float = 1
    let name: String

    /// Frames processed per inner block (larger host buffers are split).
    static let blockSize = 256

    // MARK: Render buffers (allocated once)

    /// Per layer: its input history, channels × (lookback + blockSize), row-major.
    private var histories: [UnsafeMutablePointer<Float>] = []
    private var historyWidths: [Int] = []
    private var z: UnsafeMutablePointer<Float>          // zChannels × block
    private var activated: UnsafeMutablePointer<Float>  // channels × block
    private var heads: [UnsafeMutablePointer<Float>] = []        // per array: channels × block (head accumulator)
    private var headOutputs: [UnsafeMutablePointer<Float>] = []  // per array: headSize × block
    private var arrayOutputs: [UnsafeMutablePointer<Float>] = [] // per array: channels × block
    private var condition: UnsafeMutablePointer<Float>  // 1 × block

    // MARK: Loading

    init(data: Data, name: String) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let architecture = json["architecture"] as? String,
              let config = json["config"] as? [String: Any],
              let weights = (json["weights"] as? [NSNumber])?.map({ $0.floatValue }) else {
            throw NeuralAmpModelError.notAModel
        }
        guard architecture == "WaveNet", let layerConfigs = config["layers"] as? [[String: Any]] else {
            throw NeuralAmpModelError.unsupportedArchitecture(architecture)
        }
        if let head = config["head"], !(head is NSNull) { throw NeuralAmpModelError.unsupportedArchitecture("a post-stack head") }
        self.name = name

        var cursor = 0
        func take(_ count: Int) throws -> ArraySlice<Float> {
            guard cursor + count <= weights.count else {
                throw NeuralAmpModelError.weightCountMismatch(expected: cursor + count, found: weights.count)
            }
            defer { cursor += count }
            return weights[cursor..<cursor + count]
        }
        /// Conv1×1 weights: for each output row, for each input column.
        func matrix(_ rows: Int, _ cols: Int) throws -> Matrix {
            var m = Matrix(rows: rows, cols: cols)
            m.values = Array(try take(rows * cols))
            return m
        }

        for config in layerConfigs {
            // Only the original WaveNet keys; newer variants (bottleneck, groups, FiLM…) aren't supported
            let known: Set<String> = ["input_size", "condition_size", "head_size", "channels", "kernel_size",
                                      "dilations", "activation", "gated", "head_bias"]
            if let unknown = config.keys.first(where: { !known.contains($0) }) {
                throw NeuralAmpModelError.unsupportedArchitecture("the '\(unknown)' layer option")
            }
            guard let inputSize = config["input_size"] as? Int,
                  let conditionSize = config["condition_size"] as? Int,
                  let headSize = config["head_size"] as? Int,
                  let channels = config["channels"] as? Int,
                  let kernelSize = config["kernel_size"] as? Int,
                  let dilations = config["dilations"] as? [Int],
                  let activationName = config["activation"] as? String,
                  let activation = Activation(activationName) else {
                throw NeuralAmpModelError.notAModel
            }
            let gated = config["gated"] as? Bool ?? false
            let headBias = config["head_bias"] as? Bool ?? false
            let zChannels = gated ? 2 * channels : channels

            let rechannel = try matrix(channels, inputSize)
            var layers: [Layer] = []
            for dilation in dilations {
                // Conv1D weights: for each out, for each in, for each tap ("crazy ordering")
                var taps = [Matrix](repeating: Matrix(rows: zChannels, cols: channels), count: kernelSize)
                let flat = Array(try take(zChannels * channels * kernelSize))
                var index = 0
                for out in 0..<zChannels {
                    for input in 0..<channels {
                        for k in 0..<kernelSize {
                            taps[k].values[out * channels + input] = flat[index]
                            index += 1
                        }
                    }
                }
                let convBias = Array(try take(zChannels))
                let mixin = try matrix(zChannels, conditionSize)
                let output = try matrix(channels, channels)
                let outputBias = Array(try take(channels))
                layers.append(Layer(dilation: dilation, kernelSize: kernelSize, gated: gated, activation: activation,
                                    conv: taps, convBias: convBias, mixin: mixin, output: output, outputBias: outputBias))
            }
            let headRechannel = try matrix(headSize, channels)
            let bias = headBias ? Array(try take(headSize)) : nil
            arrays.append(LayerArray(inputSize: inputSize, conditionSize: conditionSize, channels: channels,
                                     headSize: headSize, rechannel: rechannel, layers: layers,
                                     headRechannel: headRechannel, headBias: bias))
        }
        headScale = Array(try take(1))[0]
        guard cursor == weights.count else {
            throw NeuralAmpModelError.weightCountMismatch(expected: cursor, found: weights.count)
        }

        // Buffers
        let block = Self.blockSize
        let maxZ = arrays.flatMap { $0.layers.map { $0.gated ? 2 * $0.conv[0].cols : $0.conv[0].cols } }.max() ?? 1
        let maxChannels = arrays.map(\.channels).max() ?? 1
        z = .allocate(capacity: maxZ * block)
        activated = .allocate(capacity: maxChannels * block)
        condition = .allocate(capacity: block)
        for array in arrays {
            for layer in array.layers {
                let width = layer.lookback + block
                let history = UnsafeMutablePointer<Float>.allocate(capacity: array.channels * width)
                history.initialize(repeating: 0, count: array.channels * width)
                histories.append(history)
                historyWidths.append(width)
            }
            heads.append(.allocate(capacity: array.channels * block))
            headOutputs.append(.allocate(capacity: array.headSize * block))
            arrayOutputs.append(.allocate(capacity: array.channels * block))
        }
        prewarm()
    }

    /// Runs silence through the whole receptive field, so every layer starts from the state it
    /// settles into with no input (biases make it non-zero) – as the reference implementation does.
    private func prewarm() {
        let receptiveField = arrays.reduce(1) { $0 + $1.layers.reduce(0) { $0 + $1.lookback } }
        let silence = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockSize)
        defer { silence.deallocate() }
        var remaining = receptiveField
        while remaining > 0 {
            let n = min(Self.blockSize, remaining)
            silence.update(repeating: 0, count: n)
            processBlock(silence, n)
            remaining -= n
        }
    }

    deinit {
        z.deallocate(); activated.deallocate(); condition.deallocate()
        histories.forEach { $0.deallocate() }
        heads.forEach { $0.deallocate() }
        headOutputs.forEach { $0.deallocate() }
        arrayOutputs.forEach { $0.deallocate() }
    }

    // MARK: Inference

    /// Processes mono audio in place. Safe on the audio thread.
    func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        var done = 0
        while done < count {
            let n = min(Self.blockSize, count - done)
            processBlock(samples + done, n)
            done += n
        }
    }

    /// C (row stride ldc) = A (m×k) · B (k×n, row stride ldb) [+ C when accumulate]
    private func gemm(_ a: Matrix, _ b: UnsafePointer<Float>, ldb: Int, _ c: UnsafeMutablePointer<Float>,
                      ldc: Int? = nil, n: Int, accumulate: Bool) {
        a.values.withUnsafeBufferPointer { weights in
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                        Int32(a.rows), Int32(n), Int32(a.cols),
                        1, weights.baseAddress!, Int32(a.cols),
                        b, Int32(ldb),
                        accumulate ? 1 : 0, c, Int32(ldc ?? n))
        }
    }

    private func processBlock(_ samples: UnsafeMutablePointer<Float>, _ n: Int) {
        condition.update(from: samples, count: n)
        var historyIndex = 0

        for (a, array) in arrays.enumerated() {
            let channels = array.channels
            // Input to this array: the audio for the first, the previous array's output otherwise
            let input: UnsafePointer<Float> = a == 0 ? UnsafePointer(condition) : UnsafePointer(arrayOutputs[a - 1])
            // Head accumulator: zero for the first array, the previous head output otherwise
            if a == 0 {
                heads[a].update(repeating: 0, count: channels * n)
            } else {
                heads[a].update(from: headOutputs[a - 1], count: channels * n)
            }

            // Rechannel straight into the first layer's history (its "now" columns)
            let first = histories[historyIndex]
            let firstWidth = historyWidths[historyIndex]
            let firstLookback = array.layers[0].lookback
            gemm(array.rechannel, input, ldb: n, first + firstLookback, ldc: firstWidth, n: n, accumulate: false)

            for (l, layer) in array.layers.enumerated() {
                let history = histories[historyIndex + l]
                let width = historyWidths[historyIndex + l]
                let lookback = layer.lookback
                let zChannels = layer.gated ? 2 * channels : channels

                // Dilated causal conv: Σ_k W_k · x[t − d(K−1−k)]
                for (k, tap) in layer.conv.enumerated() {
                    let offset = lookback - layer.dilation * (layer.kernelSize - 1 - k)
                    gemm(tap, history + offset, ldb: width, z, n: n, accumulate: k > 0)
                }
                // + bias + condition mix
                gemm(layer.mixin, condition, ldb: n, z, n: n, accumulate: true)
                for row in 0..<zChannels {
                    var bias = layer.convBias[row]
                    vDSP_vsadd(z + row * n, 1, &bias, z + row * n, 1, vDSP_Length(n))
                }

                // Activation (gated: tanh(top) × sigmoid(bottom))
                let count = channels * n
                switch layer.activation {
                case .tanh: var c = Int32(count); vvtanhf(activated, z, &c)
                case .relu: var zero: Float = 0; vDSP_vthr(z, 1, &zero, activated, 1, vDSP_Length(count))
                case .hardTanh: var lo: Float = -1, hi: Float = 1; vDSP_vclip(z, 1, &lo, &hi, activated, 1, vDSP_Length(count))
                case .sigmoid: sigmoid(z, into: activated, count: count)
                }
                if layer.gated {
                    sigmoid(z + count, into: z + count, count: count)
                    vDSP_vmul(activated, 1, z + count, 1, activated, 1, vDSP_Length(count))
                }

                // Head accumulates the activations
                vDSP_vadd(heads[a], 1, activated, 1, heads[a], 1, vDSP_Length(count))

                // Residual: next = x + W1·act + b1 → the next layer's history, or the array output
                let isLast = l == array.layers.count - 1
                let destination: UnsafeMutablePointer<Float>
                let destinationStride: Int
                if isLast {
                    destination = arrayOutputs[a]; destinationStride = n
                } else {
                    destination = histories[historyIndex + l + 1] + array.layers[l + 1].lookback
                    destinationStride = historyWidths[historyIndex + l + 1]
                }
                gemm(layer.output, activated, ldb: n, z, n: n, accumulate: false)   // reuse z as scratch
                for row in 0..<channels {
                    var bias = layer.outputBias[row]
                    let scratch = z + row * n
                    vDSP_vsadd(scratch, 1, &bias, scratch, 1, vDSP_Length(n))
                    vDSP_vadd(scratch, 1, history + row * width + lookback, 1,
                              destination + row * destinationStride, 1, vDSP_Length(n))
                }

                // Slide this layer's history: keep the last `lookback` columns
                if lookback > 0 {
                    for row in 0..<channels {
                        let base = history + row * width
                        base.update(from: base + n, count: lookback)
                    }
                }
            }

            // Head rechannel
            gemm(array.headRechannel, heads[a], ldb: n, headOutputs[a], n: n, accumulate: false)
            if let bias = array.headBias {
                for row in 0..<array.headSize {
                    var b = bias[row]
                    vDSP_vsadd(headOutputs[a] + row * n, 1, &b, headOutputs[a] + row * n, 1, vDSP_Length(n))
                }
            }
            historyIndex += array.layers.count
        }

        // Output: head_scale × the last array's head (first channel)
        var scale = headScale
        vDSP_vsmul(headOutputs[arrays.count - 1], 1, &scale, samples, 1, vDSP_Length(n))
    }

    private func sigmoid(_ x: UnsafeMutablePointer<Float>, into y: UnsafeMutablePointer<Float>, count: Int) {
        // 1 / (1 + e^−x)
        var minusOne: Float = -1, one: Float = 1, c = Int32(count)
        vDSP_vsmul(x, 1, &minusOne, y, 1, vDSP_Length(count))
        vvexpf(y, y, &c)
        vDSP_vsadd(y, 1, &one, y, 1, vDSP_Length(count))
        vvrecf(y, y, &c)
    }
}
