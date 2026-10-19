import Accessibility
import SwiftUI

// MARK: - Audio Graph
// RiffNode's plots are drawn shapes, so VoiceOver has nothing to read in them. Each one
// also describes itself as a chart: VoiceOver then reads the axes and a summary, lets you
// step through the values, and can play the curve as a rising and falling tone (Audio Graph).

struct AudioGraphChart: AXChartDescriptorRepresentable {
    struct Axis {
        var title: String
        var range: ClosedRange<Double>
        var isLogarithmic = false
        var describe: (Double) -> String
    }

    struct Series {
        var name: String
        var points: [(x: Double, y: Double)]
    }

    var title: String
    var summary: String
    var x: Axis
    var y: Axis
    var series: [Series]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(title: x.title, range: x.range, gridlinePositions: [],
                                                valueDescriptionProvider: x.describe)
        if x.isLogarithmic { xAxis.scaleType = .log10 }
        let yAxis = AXNumericDataAxisDescriptor(title: y.title, range: y.range, gridlinePositions: [],
                                                valueDescriptionProvider: y.describe)
        let data = series.map { line in
            AXDataSeriesDescriptor(name: line.name, isContinuous: true,
                                   dataPoints: line.points.map { AXDataPoint(x: $0.x, y: $0.y) })
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, series: data)
    }
}

extension AudioGraphChart.Axis {
    /// Frequency on a log axis, read as "250 Hz" or "4.0 kHz".
    static func frequency(_ range: ClosedRange<Double>) -> Self {
        Self(title: "Frequency", range: range, isLogarithmic: true, describe: AudioGraphChart.hertz)
    }

    /// Level in decibels.
    static func decibels(_ range: ClosedRange<Double>, title: String = "Level") -> Self {
        Self(title: title, range: range) { "\(Int($0.rounded())) dB" }
    }
}

extension AudioGraphChart {
    static func hertz(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1f kHz", value / 1000) : "\(Int(value.rounded())) Hz"
    }

    static func decibels(_ value: Double, signed: Bool = false) -> String {
        let rounded = Int(value.rounded())
        return (signed && rounded > 0 ? "+" : "") + "\(rounded) dB"
    }
}

extension View {
    /// Makes a drawn plot one VoiceOver element that reads – and can play – as a chart.
    func audioGraph(_ chart: AudioGraphChart) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(chart.title)
            .accessibilityValue(chart.summary)
            .accessibilityChartDescriptor(chart)
    }
}
