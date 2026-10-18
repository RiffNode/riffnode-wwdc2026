import Accelerate
import Foundation

// MARK: - Neural Amp Model (NAM)
// Plays a Neural Amp Modeler capture (.nam): a WaveNet trained on recordings of a real amp,
// pedal or rig, so RiffNode can sound like that exact piece of gear. A Swift port of the
// WaveNet in NeuralAmpModelerCore (MIT) – the original "A1" captures and the newer "A2"
// ones (slimmable containers, per-layer kernel sizes, LeakyReLU, bottlenecks and a
// temporal head) – checked sample by sample against its reference renderer. Inference is
// block-based matrix maths with Accelerate, and allocates nothing while rendering.
//
// Each layer array:  x → 1×1 rechannel → [dilated conv + condition mix → activation → head
//                    sum; x += 1×1(activation)] × N → head conv.  Output = head_scale × head.

enum NeuralAmpModelError: Error, LocalizedError {
    case notAModel
    case unsupportedArchitecture(String)
    case weightCountMismatch(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .notAModel: "That file isn't a Neural Amp Modeler capture."
        case .unsupportedArchitecture(let name): "This capture uses \(name), which RiffNode can't play yet. Standard A1 and A2 WaveNet captures work."
        case .weightCountMismatch: "The capture's weights don't match its layout."
        }
    }
}

final class NeuralAmpModel: @unchecked Sendable {

    // MARK: Layout

    private enum Activation {
        case tanh, relu, hardTanh, sigmoid
        case leakyReLU(Float)

        init?(_ name: String) {
            switch name.lowercased() {
            case "tanh", "fasttanh": self = .tanh
            case "relu": self = .relu
            case "hardtanh": self = .hardTanh
            case "sigmoid": self = .sigmoid
            case "leakyrelu": self = .leakyReLU(0.01)
            default: return nil
            }
        }

        /// A name, or an A2-style object such as {"type": "LeakyReLU", "negative_slope": 0.01}.
        init?(json: Any?) {
            if let name = json as? String { self.init(name); return }
            guard let object = json as? [String: Any], let type = object["type"] as? String else { return nil }
            if type.lowercased() == "leakyrelu" {
                self = .leakyReLU((object["negative_slope"] as? NSNumber)?.floatValue ?? 0.01)
            } else {
                self.init(type)
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
        /// Width of the activation (A1: the channel count; A2 may squeeze it).
        let bottleneck: Int
        var conv: [Matrix]        // one (zChannels × channels) per tap, oldest tap first
        var convBias: [Float]
        var mixin: Matrix         // zChannels × conditionSize
        var output: Matrix        // channels × bottleneck (the 1×1 back to the residual)
        var outputBias: [Float]
        var lookback: Int { dilation * (kernelSize - 1) }
    }

    private struct LayerArray {
        let inputSize: Int
        let conditionSize: Int
        let channels: Int
        let headSize: Int
        /// Rows summed into the head: the layers' bottleneck.
        let headInputs: Int
        var rechannel: Matrix     // channels × inputSize, no bias
        var layers: [Layer]
        /// Head conv: one (headSize × headInputs) per tap, oldest first (A1: a single 1×1 tap).
        var headTaps: [Matrix]
        let headDilation: Int
        var headBias: [Float]?
        var headLookback: Int { headDilation * (headTaps.count - 1) }
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
    private var heads: [UnsafeMutablePointer<Float>] = []        // per array: headInputs × (lookback + block)
    private var headWidths: [Int] = []
    private var headOutputs: [UnsafeMutablePointer<Float>] = []  // per array: headSize × block
    private var arrayOutputs: [UnsafeMutablePointer<Float>] = [] // per array: channels × block
    private var condition: UnsafeMutablePointer<Float>  // 1 × block
    /// gemm scratch: a contiguous copy of a strided B, and C before it's added or strided out.
    private var gemmB: UnsafeMutablePointer<Float>
    private var gemmC: UnsafeMutablePointer<Float>

    // MARK: Loading

    init(data: Data, name: String) throws {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var architecture = json["architecture"] as? String else {
            throw NeuralAmpModelError.notAModel
        }
        // A2 files are slimmable containers: the same capture at several sizes. Like the
        // reference player, use the full-size one (the last, max_value 1.0).
        if architecture == "SlimmableContainer" {
            guard let submodels = (json["config"] as? [String: Any])?["submodels"] as? [[String: Any]],
                  let model = submodels.last?["model"] as? [String: Any],
                  let inner = model["architecture"] as? String else {
                throw NeuralAmpModelError.notAModel
            }
            json = model
            architecture = inner
        }
        guard let config = json["config"] as? [String: Any],
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
        /// Conv1D weights: for each out, for each in, for each tap ("crazy ordering"), oldest tap first.
        func taps(_ rows: Int, _ cols: Int, _ kernel: Int) throws -> [Matrix] {
            var taps = [Matrix](repeating: Matrix(rows: rows, cols: cols), count: kernel)
            let flat = Array(try take(rows * cols * kernel))
            var index = 0
            for out in 0..<rows {
                for input in 0..<cols {
                    for k in 0..<kernel {
                        taps[k].values[out * cols + input] = flat[index]
                        index += 1
                    }
                }
            }
            return taps
        }
        func unsupported(_ what: String) -> NeuralAmpModelError { .unsupportedArchitecture(what) }
        func isActive(_ value: Any?) -> Bool { (value as? [String: Any])?["active"] as? Bool ?? false }

        for config in layerConfigs {
            let known: Set<String> = ["input_size", "condition_size", "head_size", "channels", "kernel_size",
                                      "dilations", "activation", "gated", "head_bias",
                                      // A2
                                      "kernel_sizes", "bottleneck", "head", "head1x1", "layer1x1", "groups_input",
                                      "groups_input_mixin", "gating_mode", "secondary_activation", "slimmable",
                                      "conv_pre_film", "conv_post_film", "input_mixin_pre_film", "input_mixin_post_film",
                                      "activation_pre_film", "activation_post_film", "layer1x1_post_film", "head1x1_post_film"]
            if let unknown = config.keys.first(where: { !known.contains($0) }) {
                throw unsupported("the '\(unknown)' layer option")
            }
            // The A2 options this player handles; anything else is refused rather than played wrong
            for film in ["conv_pre_film", "conv_post_film", "input_mixin_pre_film", "input_mixin_post_film",
                         "activation_pre_film", "activation_post_film", "layer1x1_post_film", "head1x1_post_film"]
                where isActive(config[film]) { throw unsupported("FiLM conditioning") }
            if isActive(config["head1x1"]) { throw unsupported("a head 1×1") }
            if let layer1x1 = config["layer1x1"] as? [String: Any],
               !(layer1x1["active"] as? Bool ?? true) || (layer1x1["groups"] as? Int ?? 1) != 1 {
                throw unsupported("this layer 1×1 setup")
            }
            if (config["groups_input"] as? Int ?? 1) != 1 || (config["groups_input_mixin"] as? Int ?? 1) != 1 {
                throw unsupported("grouped convolutions")
            }
            if let slim = config["slimmable"], !(slim is NSNull) { throw unsupported("in-layer slimming") }
            if let secondary = config["secondary_activation"] as? [Any], secondary.contains(where: { !($0 is NSNull) }) {
                throw unsupported("blended gating")
            }

            guard let inputSize = config["input_size"] as? Int,
                  let conditionSize = config["condition_size"] as? Int,
                  let channels = config["channels"] as? Int,
                  let dilations = config["dilations"] as? [Int] else {
                throw NeuralAmpModelError.notAModel
            }
            let count = dilations.count
            let kernelSizes = (config["kernel_sizes"] as? [Int])
                ?? (config["kernel_size"] as? Int).map { Array(repeating: $0, count: count) }
            let activationJSON = config["activation"]
            let activations: [Activation?] = (activationJSON as? [Any])?.map { Activation(json: $0) }
                ?? Array(repeating: Activation(json: activationJSON), count: count)
            let gatingModes: [String] = (config["gating_mode"] as? [String])
                ?? Array(repeating: (config["gated"] as? Bool ?? false) ? "gated" : "none", count: count)
            guard let kernelSizes, kernelSizes.count == count, activations.count == count,
                  gatingModes.count == count, activations.allSatisfy({ $0 != nil }) else {
                throw NeuralAmpModelError.notAModel
            }
            if let mode = gatingModes.first(where: { $0 != "none" && $0 != "gated" }) { throw unsupported("'\(mode)' gating") }
            let bottleneck = config["bottleneck"] as? Int ?? channels

            // Head: A2 nests it as {out_channels, kernel_size, bias}; A1 has head_size + head_bias (a 1×1)
            let headSize: Int, headKernel: Int, headBiasOn: Bool, headDilation: Int
            if let head = config["head"] as? [String: Any] {
                guard let out = head["out_channels"] as? Int, let kernel = head["kernel_size"] as? Int,
                      let bias = head["bias"] as? Bool, kernel >= 1 else { throw NeuralAmpModelError.notAModel }
                headSize = out; headKernel = kernel; headBiasOn = bias
                headDilation = head["head_dilation"] as? Int ?? 1
            } else if let size = config["head_size"] as? Int {
                headSize = size; headKernel = 1; headBiasOn = config["head_bias"] as? Bool ?? false; headDilation = 1
            } else {
                throw NeuralAmpModelError.notAModel
            }

            let rechannel = try matrix(channels, inputSize)
            var layers: [Layer] = []
            for i in 0..<count {
                let gated = gatingModes[i] == "gated"
                let zChannels = gated ? 2 * bottleneck : bottleneck
                let conv = try taps(zChannels, channels, kernelSizes[i])
                let convBias = Array(try take(zChannels))
                let mixin = try matrix(zChannels, conditionSize)
                let output = try matrix(channels, bottleneck)
                let outputBias = Array(try take(channels))
                layers.append(Layer(dilation: dilations[i], kernelSize: kernelSizes[i], gated: gated, activation: activations[i]!,
                                    bottleneck: bottleneck, conv: conv, convBias: convBias, mixin: mixin,
                                    output: output, outputBias: outputBias))
            }
            let headTaps = try taps(headSize, bottleneck, headKernel)
            let bias = headBiasOn ? Array(try take(headSize)) : nil
            arrays.append(LayerArray(inputSize: inputSize, conditionSize: conditionSize, channels: channels,
                                     headSize: headSize, headInputs: bottleneck, rechannel: rechannel, layers: layers,
                                     headTaps: headTaps, headDilation: headDilation, headBias: bias))
        }
        headScale = Array(try take(1))[0]
        guard cursor == weights.count else {
            throw NeuralAmpModelError.weightCountMismatch(expected: cursor, found: weights.count)
        }

        // Buffers
        let block = Self.blockSize
        let maxZ = arrays.flatMap { array in array.layers.map { max($0.conv[0].rows, array.channels) } }.max() ?? 1
        let maxBottleneck = arrays.flatMap { $0.layers.map(\.bottleneck) }.max() ?? 1
        z = .allocate(capacity: maxZ * block)
        activated = .allocate(capacity: maxBottleneck * block)
        condition = .allocate(capacity: block)
        let maxDim = arrays.flatMap { array in
            [array.channels, array.headSize, array.headInputs, array.inputSize, array.conditionSize]
                + array.layers.flatMap { [$0.conv[0].rows, $0.conv[0].cols, $0.mixin.cols, $0.output.rows, $0.output.cols] }
        }.max() ?? 1
        gemmB = .allocate(capacity: max(maxDim, maxZ) * block)
        gemmC = .allocate(capacity: max(maxDim, maxZ) * block)
        for array in arrays {
            for layer in array.layers {
                let width = layer.lookback + block
                let history = UnsafeMutablePointer<Float>.allocate(capacity: array.channels * width)
                history.initialize(repeating: 0, count: array.channels * width)
                histories.append(history)
                historyWidths.append(width)
            }
            // Head inputs keep the head conv's lookback in front of each block
            let headWidth = array.headLookback + block
            let head = UnsafeMutablePointer<Float>.allocate(capacity: array.headInputs * headWidth)
            head.initialize(repeating: 0, count: array.headInputs * headWidth)
            heads.append(head)
            headWidths.append(headWidth)
            headOutputs.append(.allocate(capacity: array.headSize * block))
            arrayOutputs.append(.allocate(capacity: array.channels * block))
        }
        prewarm()
    }

    /// Runs silence through the whole receptive field, so every layer starts from the state it
    /// settles into with no input (biases make it non-zero) – as the reference implementation does.
    private func prewarm() {
        let receptiveField = arrays.reduce(1) { $0 + $1.headLookback + $1.layers.reduce(0) { $0 + $1.lookback } }
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
        gemmB.deallocate(); gemmC.deallocate()
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

    /// C (row stride ldc) = A (m×k) · B (k×n, row stride ldb) [+ C when accumulate].
    /// vDSP_mmul wants contiguous rows and overwrites C, so a strided B is packed first and
    /// an accumulated or strided C goes through scratch – a small copy next to the multiply.
    private func gemm(_ a: Matrix, _ b: UnsafePointer<Float>, ldb: Int, _ c: UnsafeMutablePointer<Float>,
                      ldc: Int? = nil, n: Int, accumulate: Bool) {
        let m = a.rows, k = a.cols, ldc = ldc ?? n
        var packedB = b
        if ldb != n {
            for row in 0..<k { (gemmB + row * n).update(from: b + row * ldb, count: n) }
            packedB = UnsafePointer(gemmB)
        }
        let direct = !accumulate && ldc == n
        let product = direct ? c : gemmC
        a.values.withUnsafeBufferPointer { weights in
            vDSP_mmul(weights.baseAddress!, 1, packedB, 1, product, 1, vDSP_Length(m), vDSP_Length(n), vDSP_Length(k))
        }
        guard !direct else { return }
        for row in 0..<m {
            let target = c + row * ldc, source = gemmC + row * n
            if accumulate {
                vDSP_vadd(target, 1, source, 1, target, 1, vDSP_Length(n))
            } else {
                target.update(from: source, count: n)
            }
        }
    }

    private func processBlock(_ samples: UnsafeMutablePointer<Float>, _ n: Int) {
        condition.update(from: samples, count: n)
        var historyIndex = 0

        for (a, array) in arrays.enumerated() {
            let channels = array.channels
            // Input to this array: the audio for the first, the previous array's output otherwise
            let input: UnsafePointer<Float> = a == 0 ? UnsafePointer(condition) : UnsafePointer(arrayOutputs[a - 1])
            // Head accumulator ("now" columns after the head conv's lookback): zero for the first
            // array, the previous head output otherwise
            let headWidth = headWidths[a], headNow = heads[a] + array.headLookback
            for row in 0..<array.headInputs {
                if a == 0 {
                    (headNow + row * headWidth).update(repeating: 0, count: n)
                } else {
                    (headNow + row * headWidth).update(from: headOutputs[a - 1] + row * n, count: n)
                }
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
                let bottleneck = layer.bottleneck
                let zChannels = layer.gated ? 2 * bottleneck : bottleneck

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
                let count = bottleneck * n
                switch layer.activation {
                case .tanh: var c = Int32(count); vvtanhf(activated, z, &c)
                case .relu: var zero: Float = 0; vDSP_vthr(z, 1, &zero, activated, 1, vDSP_Length(count))
                case .hardTanh: var lo: Float = -1, hi: Float = 1; vDSP_vclip(z, 1, &lo, &hi, activated, 1, vDSP_Length(count))
                case .sigmoid: sigmoid(z, into: activated, count: count)
                case .leakyReLU(var slope):
                    // max(x, slope·x) is LeakyReLU for slopes below 1
                    vDSP_vsmul(z, 1, &slope, activated, 1, vDSP_Length(count))
                    vDSP_vmax(z, 1, activated, 1, activated, 1, vDSP_Length(count))
                }
                if layer.gated {
                    sigmoid(z + count, into: z + count, count: count)
                    vDSP_vmul(activated, 1, z + count, 1, activated, 1, vDSP_Length(count))
                }

                // Head accumulates the activations
                for row in 0..<bottleneck {
                    let target = headNow + row * headWidth
                    vDSP_vadd(target, 1, activated + row * n, 1, target, 1, vDSP_Length(n))
                }

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

            // Head conv (A1: a 1×1; A2: a causal conv over the last few samples)
            for (k, tap) in array.headTaps.enumerated() {
                let offset = array.headLookback - array.headDilation * (array.headTaps.count - 1 - k)
                gemm(tap, heads[a] + offset, ldb: headWidth, headOutputs[a], n: n, accumulate: k > 0)
            }
            if array.headLookback > 0 {
                for row in 0..<array.headInputs {
                    let base = heads[a] + row * headWidth
                    base.update(from: base + n, count: array.headLookback)
                }
            }
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
