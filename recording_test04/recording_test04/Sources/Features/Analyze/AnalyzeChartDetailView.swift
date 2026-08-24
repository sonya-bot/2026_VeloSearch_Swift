import SwiftUI

enum AnalyzeChartSelection: Identifiable {
  case waveform(channelNumber: Int, samples: [Float], sampleRate: Double)
  case frequencyResponse(channels: [[FrequencyResponsePoint]])

  var id: String {
    switch self {
    case .waveform(let channelNumber, _, _):
      return "waveform-\(channelNumber)"
    case .frequencyResponse:
      return "frequency-response"
    }
  }

  var title: String {
    switch self {
    case .waveform(let channelNumber, _, _):
      return "CH\(channelNumber) Waveform"
    case .frequencyResponse:
      return "Frequency Response"
    }
  }
}

struct AnalyzeChartDetailView: View {
  let selection: AnalyzeChartSelection

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      chart
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(selection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("閉じる") {
              dismiss()
            }
          }
        }
    }
  }

  @ViewBuilder
  private var chart: some View {
    switch selection {
    case .waveform(_, let samples, let sampleRate):
      DetailedAnalyzeWaveform(samples: samples, sampleRate: sampleRate)
    case .frequencyResponse(let channels):
      DetailedFrequencyResponseGraph(channels: channels)
    }
  }
}
