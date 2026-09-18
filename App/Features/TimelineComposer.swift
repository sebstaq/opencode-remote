import OpenCodeAPI
import PhotosUI
import SwiftUI

/// The message composer, rendered by the vendored timeline's
/// `MessageInputView` slot. Owns its own input state; `onSend` lets the parent
/// note a send so it can drive the donor timeline's scroll-to-user input once
/// the new row exists.
struct TimelineComposer: View {
  let model: SessionChatModel
  let client: Client
  let sessionID: String
  let onSend: () -> Void

  @State private var draft = ""
  @State private var attachments: [Attachment] = []
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var showPhotoPicker = false
  @State private var showCamera = false

  var body: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        attachmentStrip
      }
      HStack(spacing: 10) {
        Menu {
          Button {
            showPhotoPicker = true
          } label: {
            Label("Photo Library", systemImage: "photo.on.rectangle")
          }
          if CameraPicker.isAvailable {
            Button {
              showCamera = true
            } label: {
              Label("Camera", systemImage: "camera")
            }
          }
        } label: {
          Image(systemName: "plus.circle")
            .font(.system(size: 28))
            .foregroundStyle(Theme.Color.inkSecondary)
        }
        .accessibilityIdentifier("composer.attach")

        TextField("Write an instruction…", text: $draft, axis: .vertical)
          .lineLimit(1...5)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(Theme.Color.fillComposer, in: RoundedRectangle(cornerRadius: 20))
          .accessibilityIdentifier("composer.field")

        if model.isRunning {
          Button {
            Task { await model.abort(client: client, sessionID: sessionID) }
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.system(size: 30))
              .foregroundStyle(Theme.Color.fillInverted)
          }
          .accessibilityIdentifier("composer.stop")
        } else {
          Button {
            send()
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 30))
              .foregroundStyle(Theme.Color.fillInverted)
          }
          .disabled(!canSend)
          .accessibilityIdentifier("composer.send")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .photosPicker(
      isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 4
    )
    .onChange(of: photoItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await loadAttachments(items) }
    }
    .fullScreenCover(isPresented: $showCamera) {
      CameraPicker { image in
        let stamp = Int(Date().timeIntervalSince1970)
        if let attachment = AttachmentEncoder.make(
          image: image, filename: "camera-\(stamp).jpg")
        {
          attachments.append(attachment)
        }
      }
      .ignoresSafeArea()
    }
    .task {
      #if DEBUG
        // Lets UI tests exercise send/abort without the simulator keyboard.
        if let seed = ProcessInfo.processInfo.environment["OPENCODE_UI_DRAFT"], draft.isEmpty {
          draft = seed
        }
        seedAttachmentIfRequested()
      #endif
    }
  }

  private var attachmentStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(attachments) { attachment in
          ZStack(alignment: .topTrailing) {
            Group {
              if let preview = attachment.preview, let image = UIImage(data: preview) {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFill()
              } else {
                Image(systemName: "doc.fill")
                  .font(.title3)
                  .foregroundStyle(Theme.Color.inkSecondary)
              }
            }
            .frame(width: 56, height: 56)
            .background(Theme.Color.fillComposer)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
              attachments.removeAll { $0.id == attachment.id }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.Color.fillInverted)
                .background(Circle().fill(Theme.Color.surface))
            }
            .offset(x: 5, y: -5)
            .accessibilityIdentifier("composer.removeAttachment")
          }
        }
      }
      .padding(.top, 6)
      .padding(.horizontal, 2)
    }
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private func loadAttachments(_ items: [PhotosPickerItem]) async {
    for item in items {
      if let attachment = await AttachmentEncoder.make(from: item) {
        attachments.append(attachment)
      }
    }
    photoItems = []
  }

  private func send() {
    let text = draft
    let picked = attachments
    draft = ""
    attachments = []
    onSend()
    Task { await model.send(client: client, sessionID: sessionID, text: text, attachments: picked) }
  }

  #if DEBUG
    /// Test seam: a solid-red attachment so the live attachment E2E can send an
    /// image without driving the system photo picker.
    private func seedAttachmentIfRequested() {
      guard attachments.isEmpty,
        (ProcessInfo.processInfo.environment["OPENCODE_UI_ATTACHMENT"] ?? "").isEmpty == false
      else { return }
      let side: CGFloat = 400
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
      let image = renderer.image { context in
        context.cgContext.setFillColor(UIColor.red.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
      }
      if let attachment = AttachmentEncoder.make(image: image, filename: "seed.jpg") {
        attachments.append(attachment)
      }
    }
  #endif
}
