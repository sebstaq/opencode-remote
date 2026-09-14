import SwiftUI

struct AddComputerForm: View {
  let service: ConnectionService
  let store: ComputerStore
  var onSaved: () -> Void = {}

  @State private var name = ""
  @State private var urlText = ""
  @State private var password = ""
  @State private var failure: ConnectionFailure?
  @State private var isConnecting = false

  var body: some View {
    Form {
      Section("Computer") {
        TextField("Name", text: $name)
        TextField("https://host.tailnet.ts.net", text: $urlText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        SecureField("Server password", text: $password)
      }

      if let failure = displayFailure {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(failure.title).font(.headline)
            Text(failure.message).font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }

      Section {
        Button {
          Task { await connect() }
        } label: {
          HStack {
            Text(isConnecting ? "Connecting…" : "Connect")
            Spacer()
            if isConnecting {
              ProgressView()
            }
          }
        }
        .disabled(!canConnect)
        .accessibilityIdentifier("addComputer.connect")
      }
    }
  }

  private var displayFailure: ConnectionFailure? {
    if let failure {
      return failure
    }
    if case .offline(let serviceFailure) = service.state {
      return serviceFailure
    }
    return nil
  }

  private var canConnect: Bool {
    !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isConnecting
  }

  private func connect() async {
    failure = nil
    let trimmedURL = urlText.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: trimmedURL) else {
      failure = .invalidURL
      return
    }
    isConnecting = true
    defer { isConnecting = false }

    let computer = Computer(name: name.isEmpty ? (url.host ?? "Computer") : name, url: url)
    await service.connect(to: computer, password: password)

    if case .offline(let failure) = service.state {
      self.failure = failure
      return
    }
    do {
      try Keychain.setPassword(password, for: computer.id)
      store.add(computer)
      password = ""
      onSaved()
    } catch {
      failure = .unknown("Could not store the credential in the keychain")
    }
  }
}
