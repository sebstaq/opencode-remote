import SwiftUI

struct MeasurementView: View {
  let url: URL
  let password: String
  let runs: Int

  @State private var status = "Running…"
  @State private var samples: [Double] = []

  var body: some View {
    VStack(spacing: 12) {
      Text(status)
      if !samples.isEmpty {
        Text(summary).font(.footnote).monospaced()
      }
    }
    .padding()
    .task { await run() }
  }

  private var summary: String {
    "n=\(samples.count) min=\(format(samples.min())) p50=\(format(percentile(50))) p95=\(format(percentile(95))) max=\(format(samples.max()))"
  }

  private func run() async {
    let environment = ProcessInfo.processInfo.environment
    let scenario = environment["OPENCODE_MEASURE_SCENARIO"] ?? "connect"
    let seconds = Int(environment["OPENCODE_MEASURE_SECONDS"] ?? "") ?? 0
    let service = ConnectionService()
    let computer = Computer(name: "measure", url: url)

    if scenario == "reconnect" {
      await service.connect(to: computer, password: password)
      status = "connected, observing for \(seconds)s"
      let deadline = ContinuousClock.now.advanced(by: .seconds(max(seconds, 10)))
      while ContinuousClock.now < deadline {
        try? await Task.sleep(for: .seconds(2))
        let partial = MeasureReport(
          scenario: scenario, url: url.absoluteString, samples: [], attempts: service.attemptLog)
        try? service.writeReport(partial)
      }
    } else {
      samples = await service.measureConnect(computer: computer, password: password, runs: runs)
    }

    let report = MeasureReport(
      scenario: scenario,
      url: url.absoluteString,
      samples: samples,
      attempts: service.attemptLog
    )
    try? service.writeReport(report)
    status = "Wrote measure-report.json"
  }

  private func percentile(_ p: Double) -> Double? {
    guard !samples.isEmpty else {
      return nil
    }
    let sorted = samples.sorted()
    let rank = p / 100 * Double(sorted.count - 1)
    let lower = Int(rank.rounded(.down))
    let upper = Int(rank.rounded(.up))
    if lower == upper {
      return sorted[lower]
    }
    let weight = rank - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
  }

  private func format(_ value: Double?) -> String {
    guard let value else {
      return "—"
    }
    return String(format: "%.1f", value)
  }
}
