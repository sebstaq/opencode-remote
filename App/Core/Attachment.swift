import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A picked attachment, normalized for the OpenCode prompt.
///
/// There is no upload endpoint: a file travels inside the prompt as a `file`
/// part whose `url` is a base64 `data:` URL. The server normalizes images it
/// receives (max 2000 px and 5 MB base64, `packages/opencode/src/image/image.ts`)
/// but resizing a large payload server-side is slow, so images are downscaled
/// and re-encoded here first. UIKit decodes HEIC, which the server's image
/// decoder cannot, so photos also leave the phone as JPEG.
struct Attachment: Identifiable, Sendable, Equatable {
  let id = UUID()
  let filename: String
  let mime: String
  let dataURL: String
  /// Small JPEG used for the composer thumbnail; nil for non-image files.
  let preview: Data?

  /// The server defaults from `packages/opencode/src/image/image.ts`.
  static let maxDimension: CGFloat = 2000
  static let maxBase64Bytes = 5 * 1024 * 1024
}

/// Turns picked data into an `Attachment`, keeping every payload inside the
/// server's limits. Main-actor bound because it uses UIKit rendering.
@MainActor
enum AttachmentEncoder {
  static func make(from item: PhotosPickerItem) async -> Attachment? {
    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    let type = item.supportedContentTypes.first
    let ext = type?.preferredFilenameExtension ?? "dat"
    let mime = type?.preferredMIMEType ?? "application/octet-stream"
    let stamp = Int(Date().timeIntervalSince1970)
    return make(data: data, filename: "attachment-\(stamp).\(ext)", mime: mime)
  }

  static func make(data: Data, filename: String, mime: String) -> Attachment? {
    if mime.hasPrefix("image/"), let image = UIImage(data: data) {
      return make(image: image, filename: baseFilename(filename) + ".jpg")
    }
    let base64 = data.base64EncodedString()
    guard base64.utf8.count <= Attachment.maxBase64Bytes else { return nil }
    return Attachment(
      filename: filename, mime: mime, dataURL: "data:\(mime);base64,\(base64)", preview: nil)
  }

  static func make(image: UIImage, filename: String) -> Attachment? {
    let resized = scaled(image, maxDimension: Attachment.maxDimension)
    var quality = 0.8
    guard var jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
    while jpeg.base64EncodedString().utf8.count > Attachment.maxBase64Bytes, quality > 0.2 {
      quality -= 0.15
      guard let next = resized.jpegData(compressionQuality: quality) else { break }
      jpeg = next
    }
    let base64 = jpeg.base64EncodedString()
    guard base64.utf8.count <= Attachment.maxBase64Bytes else { return nil }
    let thumbnail = scaled(resized, maxDimension: 160).jpegData(compressionQuality: 0.7)
    return Attachment(
      filename: baseFilename(filename) + ".jpg", mime: "image/jpeg",
      dataURL: "data:image/jpeg;base64,\(base64)", preview: thumbnail)
  }

  private static func baseFilename(_ filename: String) -> String {
    (filename as NSString).deletingPathExtension
  }

  private static func scaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension, longest > 0 else { return image }
    let scale = maxDimension / longest
    let target = CGSize(
      width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: target, format: format).image { context in
      let rect = CGRect(origin: .zero, size: target)
      context.cgContext.setFillColor(UIColor.white.cgColor)
      context.cgContext.fill(rect)
      image.draw(in: rect)
    }
  }
}

/// Decodes a `data:` URL to an image for the timeline.
enum AttachmentImageDecoder {
  nonisolated static func decode(_ dataURL: String) -> UIImage? {
    guard let comma = dataURL.firstIndex(of: ",") else { return nil }
    let body = String(dataURL[dataURL.index(after: comma)...])
    guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
      return nil
    }
    return UIImage(data: data)
  }
}

/// Camera capture. `UIImagePickerController` is used because PhotosUI has no
/// in-app camera; `NSCameraUsageDescription` in `project.yml` is required or
/// presenting it terminates the app.
struct CameraPicker: UIViewControllerRepresentable {
  let onCapture: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  static var isAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  @MainActor
  final class Coordinator: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
  {
    private let parent: CameraPicker

    init(_ parent: CameraPicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage {
        parent.onCapture(image)
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}
