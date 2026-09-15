import OpenCodeAPI
import SwiftUI

struct SettingsSheet: View {
  let service: ConnectionService
  let store: ComputerStore
  let client: Client?
  /// A computer whose password must be re-entered: opens on the pre-filled add form.
  var reauth: Computer? = nil

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

        Section("About") {
          LabeledContent("App", value: appVersion)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .navigationDestination(isPresented: $showAdd) {
        AddComputerForm(
          service: service, store: store, prefill: reauth,
          onSaved: {
            showAdd = false
            dismiss()
          }
        )
        .navigationTitle("Add computer")
      }
      .onAppear { showAdd = reauth != nil }
    }
  }

  private func row(for computer: Computer) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(Theme.Color.inkSecondary.opacity(0.6))
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(computer.name)
        Text(computer.url.host ?? computer.url.absoluteString)
          .font(.caption)
          .foregroundStyle(Theme.Color.inkSecondary)
      }
    }
  }

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
  }
}
