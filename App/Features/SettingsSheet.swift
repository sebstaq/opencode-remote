import OpenCodeAPI
import SwiftUI

struct SettingsSheet: View {
  let service: ConnectionService
  let store: ComputerStore
  let client: Client?

  @Environment(\.dismiss) private var dismiss
  @State private var showAdd = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(store.computers) { computer in
            row(for: computer)
              .swipeActions {
                Button("Delete", role: .destructive) {
                  store.remove(computer)
                }
              }
          }
        } header: {
          HStack {
            Text("Computers")
            Spacer()
            Button {
              showAdd = true
            } label: {
              Image(systemName: "plus")
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.addComputer")
          }
        }

        Section("Defaults") {
          LabeledContent("Agent", value: "Default")
          LabeledContent("Model", value: "Default")
        }

        Section("About") {
          LabeledContent("App", value: appVersion)
          LabeledContent("Server", value: serverVersion)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .navigationDestination(isPresented: $showAdd) {
        AddComputerForm(service: service, store: store, onSaved: { showAdd = false })
          .navigationTitle("Add computer")
      }
    }
  }

  private func row(for computer: Computer) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(.gray)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(computer.name)
        Text(computer.url.host ?? computer.url.absoluteString)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
  }

  private var serverVersion: String {
    if case .connected(let version) = service.state {
      return version
    }
    return "—"
  }
}
