import UIKit
import XCTest

@testable import OpenCodeRemote

@MainActor
final class AttachmentTests: XCTestCase {
  private func image(width: CGFloat, height: CGFloat, color: UIColor = .red) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
      .image { context in
        context.cgContext.setFillColor(color.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
      }
  }

  func testImageIsDownscaledAndEncodedAsJPEG() throws {
    let attachment = try XCTUnwrap(
      AttachmentEncoder.make(image: image(width: 2500, height: 1200), filename: "photo.heic"))
    XCTAssertEqual(attachment.mime, "image/jpeg")
    XCTAssertEqual(attachment.filename, "photo.jpg")
    XCTAssertTrue(attachment.dataURL.hasPrefix("data:image/jpeg;base64,"))
    XCTAssertLessThanOrEqual(attachment.dataURL.utf8.count, Attachment.maxBase64Bytes)
    let decoded = try XCTUnwrap(AttachmentImageDecoder.decode(attachment.dataURL))
    XCTAssertLessThanOrEqual(
      max(decoded.size.width, decoded.size.height), Attachment.maxDimension)
  }

  func testPickedImageDataIsReencodedAsJPEG() throws {
    let png = try XCTUnwrap(image(width: 40, height: 40).pngData())
    let attachment = try XCTUnwrap(
      AttachmentEncoder.make(data: png, filename: "shot.png", mime: "image/png"))
    XCTAssertEqual(attachment.mime, "image/jpeg")
    XCTAssertEqual(attachment.filename, "shot.jpg")
    XCTAssertTrue(attachment.dataURL.hasPrefix("data:image/jpeg;base64,"))
    XCTAssertNotNil(attachment.preview)
  }

  func testNonImageFileKeepsItsMime() throws {
    let attachment = try XCTUnwrap(
      AttachmentEncoder.make(
        data: Data("hello".utf8), filename: "notes.txt", mime: "text/plain"))
    XCTAssertEqual(attachment.mime, "text/plain")
    XCTAssertEqual(attachment.dataURL, "data:text/plain;base64,aGVsbG8=")
    XCTAssertNil(attachment.preview)
  }
}
