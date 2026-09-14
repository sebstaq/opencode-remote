import Foundation
import Network
import Observation
import OpenCodeAPI

struct AttemptLogEntry: Codable, Sendable {
  let date: Date
  let elapsed: Double
  let ok: Bool
  let milliseconds: Double
  let detail: String
}

struct MeasureReport: Codable, Sendable {
  let scenario: String
  let url: String
  let samples: [Double]
  let attempts: [AttemptLogEntry]
}

@MainActor
@Observable
final class ConnectionService {
  private(set) var state: ConnectionState = .idle
  private(set) var lastSeconds: [String: Double] = [:]
  private(set) var lastRecoverySeconds: Double?
  private(set) var lastRefreshSeconds: Double?
  private(set) var attemptLog: [AttemptLogEntry] = []
  private let origin: ContinuousClock.Instant

  private let username = "opencode"
  private let allowsInsecureLocal: Bool
  private let clock = ContinuousClock()
  private let collector = NetworkMetricsCollector()
  private var session: URLSession?
  private(set) var apiClient: Client?
  private var monitor: NWPathMonitor?
  private var heartbeat: Task<Void, Never>?
  private var active: (computer: Computer, password: String)?
  private var reconnectingSince: ContinuousClock.Instant?

  var activeComputer: Computer? {
    active?.computer
  }

  init(
    allowsInsecureLocal: Bool = ConnectionService.defaultAllowsInsecureLocal,
    state: ConnectionState = .idle
  ) {
    self.allowsInsecureLocal = allowsInsecureLocal
    self.state = state
    self.origin = ContinuousClock.now
  }

  private static var defaultAllowsInsecureLocal: Bool {
    #if DEBUG
      true
    #else
      false
    #endif
  }

  private static let localHosts = ["127.0.0.1", "localhost", "::1", "10.0.2.2"]

  func connect(to computer: Computer, password: String) async {
    let result = await attempt(computer: computer, password: password, rebuild: true, timeout: 8)
    lastSeconds = result.seconds
    state = result.state
    if case .connected = result.state {
      active = (computer, password)
      startMonitoring()
      startHeartbeat()
    }
  }

  func disconnect() {
    monitor?.cancel()
    monitor = nil
    heartbeat?.cancel()
    heartbeat = nil
    session?.invalidateAndCancel()
    session = nil
    apiClient = nil
    active = nil
    reconnectingSince = nil
    state = .idle
  }

  /// Called when the app returns to the foreground. Verifies the connection
  /// immediately instead of waiting for the next heartbeat.
  func refresh() async {
    guard let active else {
      return
    }
    let start = clock.now
    if case .connected = state {
      let result = await attempt(
        computer: active.computer, password: active.password, rebuild: false, timeout: 1)
      if case .connected = result.state {
        lastSeconds = result.seconds
        lastRefreshSeconds = seconds(of: start.duration(to: clock.now))
        return
      }
      await beginRecovery()
    } else {
      await beginRecovery()
    }
  }

  private func startHeartbeat() {
    heartbeat?.cancel()
    heartbeat = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if Task.isCancelled {
          return
        }
        guard let self, let active = self.active else {
          return
        }
        let result = await self.attempt(
          computer: active.computer, password: active.password, rebuild: false, timeout: 1)
        if case .connected = result.state {
          continue
        }
        await self.beginRecovery()
      }
    }
  }

  private var isRecovering = false

  private func beginRecovery() async {
    if isRecovering {
      return
    }
    isRecovering = true
    defer { isRecovering = false }
    if reconnectingSince == nil {
      reconnectingSince = clock.now
    }
    state = .reconnecting
    await recover()
  }

  private func startMonitoring() {
    monitor?.cancel()
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.handle(path: path)
      }
    }
    monitor.start(queue: DispatchQueue(label: "dev.sebstaq.opencode.remote.path"))
    self.monitor = monitor
  }

  private func handle(path: NWPath) {
    guard active != nil else {
      return
    }
    if path.status == .satisfied {
      if case .connected = state {
        return
      }
      reconnectingSince = nil
      Task { await recover() }
    } else if case .connected = state {
      reconnectingSince = clock.now
      state = .reconnecting
    }
  }

  private func recover() async {
    guard let active else {
      return
    }
    if reconnectingSince == nil {
      reconnectingSince = clock.now
    }
    state = .reconnecting
    var delay = Duration.milliseconds(200)
    while !Task.isCancelled {
      let result = await attempt(
        computer: active.computer, password: active.password, rebuild: false, timeout: 1)
      if case .connected = result.state {
        lastSeconds = result.seconds
        if let since = reconnectingSince {
          lastRecoverySeconds = seconds(of: since.duration(to: clock.now))
        }
        reconnectingSince = nil
        state = result.state
        return
      }
      if case .offline(let failure) = result.state, isNonRecoverable(failure) {
        state = result.state
        return
      }
      try? await Task.sleep(for: delay)
      delay = min(delay * 2, .milliseconds(500))
    }
  }

  private func attempt(
    computer: Computer,
    password: String,
    rebuild: Bool,
    timeout: Double
  ) async -> (state: ConnectionState, seconds: [String: Double]) {
    let metrics = ConnectionMetrics()

    let scheme = computer.url.scheme?.lowercased()
    let isLocal = Self.localHosts.contains(computer.url.host ?? "")
    guard scheme == "https" || (allowsInsecureLocal && isLocal) else {
      metrics.finish()
      return log(.offline(.invalidURL), metrics)
    }

    if rebuild || apiClient == nil {
      session?.invalidateAndCancel()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 8
      configuration.waitsForConnectivity = false
      let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
      self.session = session
      apiClient = OpenCodeAPIClient.make(
        serverURL: computer.url,
        session: session,
        middlewares: [BasicAuthMiddleware(username: username, password: password)]
      )
    }
    guard let client = apiClient else {
      metrics.finish()
      return log(.offline(.unknown("Client unavailable")), metrics)
    }
    metrics.mark("client")

    let state: ConnectionState
    do {
      let output = try await withTimeout(seconds: timeout) {
        try await client.global_period_health()
      }
      metrics.mark("health")
      metrics.addNetwork(collector.take())
      state = evaluate(output)
    } catch {
      state = .offline(map(error))
    }
    metrics.finish()
    return log(state, metrics)
  }

  private func log(
    _ state: ConnectionState,
    _ metrics: ConnectionMetrics
  ) -> (state: ConnectionState, seconds: [String: Double]) {
    attemptLog.append(
      AttemptLogEntry(
        date: Date(),
        elapsed: seconds(of: origin.duration(to: clock.now)),
        ok: isConnected(state),
        milliseconds: (metrics.seconds["total"] ?? 0) * 1000,
        detail: describe(state)
      )
    )
    return (state, metrics.seconds)
  }

  private func isNonRecoverable(_ failure: ConnectionFailure) -> Bool {
    switch failure {
    case .unauthorized, .unsupportedVersion:
      return true
    default:
      return false
    }
  }

  private func isConnected(_ state: ConnectionState) -> Bool {
    if case .connected = state {
      return true
    }
    return false
  }

  private func describe(_ state: ConnectionState) -> String {
    switch state {
    case .idle: "idle"
    case .connecting: "connecting"
    case .connected(let version): "connected \(version)"
    case .reconnecting: "reconnecting"
    case .offline(let failure): "offline \(failure.title)"
    }
  }

  func measureConnect(computer: Computer, password: String, runs: Int) async -> [Double] {
    var samples: [Double] = []
    for index in 0..<runs {
      let result = await attempt(
        computer: computer, password: password, rebuild: index == 0, timeout: 8)
      samples.append((result.seconds["total"] ?? 0) * 1000)
    }
    return samples
  }

  func writeReport(_ report: MeasureReport) throws {
    guard
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return
    }
    let url = directory.appendingPathComponent("measure-report.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url)
  }

  private func evaluate(_ output: Operations.global_period_health.Output) -> ConnectionState {
    switch output {
    case .ok(let ok):
      guard let payload = try? ok.body.json else {
        return .offline(.unknown("Unexpected health response"))
      }
      guard payload.healthy else {
        return .offline(.unreachable)
      }
      let version = ServerVersion(payload.version)
      guard version >= ServerVersion.minimumSupported else {
        return .offline(
          .unsupportedVersion(
            server: payload.version,
            minimum: ServerVersion.minimumSupported.raw
          )
        )
      }
      return .connected(version: payload.version)
    case .badRequest:
      return .offline(.unknown("The server rejected the request"))
    case .undocumented(let statusCode, _):
      if statusCode == 401 {
        return .offline(.unauthorized)
      }
      return .offline(.unknown("The server returned \(statusCode)"))
    }
  }

  private func map(_ error: Error) -> ConnectionFailure {
    if let urlError = (error as? URLError) ?? underlyingURLError(error) {
      return map(urlError)
    }
    return mapByDescription(error)
  }

  private func underlyingURLError(_ error: Error) -> URLError? {
    var current: Error? = error
    for _ in 0..<8 {
      guard let candidate = current else {
        return nil
      }
      if let urlError = candidate as? URLError {
        return urlError
      }
      let nsError = candidate as NSError
      current = (nsError.userInfo[NSUnderlyingErrorKey] as? Error) ?? nsError.underlyingErrors.first
    }
    return nil
  }

  private func map(_ error: URLError) -> ConnectionFailure {
    switch error.code {
    case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
      .networkConnectionLost, .dnsLookupFailed:
      return .unreachable
    case .timedOut:
      return .timedOut
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
      return .tls
    default:
      return .unknown(error.localizedDescription)
    }
  }

  private func mapByDescription(_ error: Error) -> ConnectionFailure {
    let text = String(describing: error).lowercased()
    if text.contains("could not connect to the server") || text.contains("could not find the host")
      || text.contains("network connection was lost")
    {
      return .unreachable
    }
    if text.contains("timed out") {
      return .timedOut
    }
    if text.contains("certificate") || text.contains("ssl") || text.contains("secure connection") {
      return .tls
    }
    return .unknown(error.localizedDescription)
  }

  private func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }

  private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw URLError(.timedOut)
      }
      guard let result = try await group.next() else {
        throw URLError(.timedOut)
      }
      group.cancelAll()
      return result
    }
  }
}
