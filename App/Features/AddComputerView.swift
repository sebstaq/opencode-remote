import SwiftUI

struct AddComputerView: View {
  let service: ConnectionService
  let store: ComputerStore

  var body: some View {
    AddComputerForm(service: service, store: store)
      .navigationTitle("OpenCode Remote")
  }
}
