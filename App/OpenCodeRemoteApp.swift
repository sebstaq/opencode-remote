import SwiftUI

@main
struct OpenCodeRemoteApp: App {
  init() {
    #if DEBUG
      if ProcessInfo.processInfo.environment["OPENCODE_UI_MEASURE_FRAMES"] == "1" {
        Task { @MainActor in FrameDropMonitor.shared.start() }
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      content
    }
  }

  @ViewBuilder
  private var content: some View {
    let environment = ProcessInfo.processInfo.environment
    #if DEBUG
      if environment["OPENCODE_UI_SPIKE"] == "window" {
        SidebarWindowSpike()
      } else if environment["OPENCODE_UI_FIXTURE"] == "wireframe" {
        SidebarFixtureView()
      } else {
        standardContent(environment)
      }
    #else
      standardContent(environment)
    #endif
  }

  @ViewBuilder
  private func standardContent(_ environment: [String: String]) -> some View {
    if let urlString = environment["OPENCODE_MEASURE_URL"],
      let url = URL(string: urlString),
      let password = environment["OPENCODE_MEASURE_PASSWORD"]
    {
      MeasurementView(
        url: url,
        password: password,
        runs: Int(environment["OPENCODE_MEASURE_RUNS"] ?? "") ?? 20
      )
    } else {
      RootView()
    }
  }
}
