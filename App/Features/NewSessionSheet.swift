import OpenCodeAPI
import SwiftUI

struct ModelChoice: Hashable {
  let providerID: String
  let modelID: String
}

struct NewSessionSheet: View {
  let client: Client
  let onCreated: (SessionRow) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var agents: [String] = []
  @State private var agent = ""
  @State private var models: [ModelChoice] = []
  @State private var model: ModelChoice?
  @State private var isCreating = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Agent", selection: $agent) {
            ForEach(agents, id: \.self) { name in
              Text(name).tag(name)
            }
          }
          Picker("Model", selection: $model) {
            ForEach(models, id: \.self) { choice in
              Text("\(choice.providerID) · \(choice.modelID)").tag(Optional(choice))
            }
          }
        }

        if let error {
          Section {
            Text(error).foregroundStyle(Theme.Color.inkSecondary)
          }
        }
      }
      .navigationTitle("New session")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Create") {
            Task { await create() }
          }
          .disabled(model == nil || isCreating)
          .accessibilityIdentifier("newSession.create")
        }
      }
      .task { await load() }
    }
  }

  private func load() async {
    if case .ok(let ok) = try? await client.app_period_agents(), let list = try? ok.body.json {
      agents = list.filter { $0.hidden != true }.map(\.name)
      agent = agents.first ?? ""
    }
    if case .ok(let ok) = try? await client.config_period_providers(),
      let payload = try? ok.body.json
    {
      var choices: [ModelChoice] = []
      for provider in payload.providers {
        for id in provider.models.additionalProperties.keys.sorted() {
          choices.append(ModelChoice(providerID: provider.id, modelID: id))
        }
      }
      models = choices
      if let preferred = preferredModel(from: choices) {
        model = preferred
      } else {
        model = choices.first
      }
    }
  }

  /// Test seam: lets a UI test pin a specific (e.g. vision-capable) model
  /// instead of the first in the list.
  private func preferredModel(from choices: [ModelChoice]) -> ModelChoice? {
    #if DEBUG
      guard let raw = ProcessInfo.processInfo.environment["OPENCODE_UI_MODEL"] else { return nil }
      let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { return nil }
      return choices.first { $0.providerID == parts[0] && $0.modelID == parts[1] }
    #else
      return nil
    #endif
  }

  private func create() async {
    guard let model else {
      return
    }
    isCreating = true
    defer { isCreating = false }
    do {
      let output = try await client.session_period_create(
        body: .json(
          .init(
            agent: agent.isEmpty ? nil : agent,
            model: .init(id: model.modelID, providerID: model.providerID)
          )
        )
      )
      if case .ok(let ok) = output {
        let session = try ok.body.json
        onCreated(
          SessionRow(
            id: session.id,
            title: session.title,
            updated: Date(),
            group: URL(fileURLWithPath: session.directory).lastPathComponent
          )
        )
        dismiss()
      } else {
        error = "The server rejected the request"
      }
    } catch {
      self.error = "Could not create the session."
    }
  }
}
