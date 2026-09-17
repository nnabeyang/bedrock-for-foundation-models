import BedrockRuntimeAPI
import CoreImage
import Foundation
import FoundationModels
import ImageIO

/// Renders a transcript image attachment to the inline JPEG Converse takes.
///
/// The framework hands the image over as pixels (`CGImage` / `CIImage`), not
/// as the bytes it came from, so it has to be encoded here. JPEG is used for
/// every image: it is the smallest of the formats Converse accepts, and the
/// model reads a photo or a screenshot the same either way.
@available(anyAppleOS 27, *)
enum ImageAttachmentEncoder {
  /// Longest side the image is scaled down to before encoding.
  ///
  /// Above roughly this size a vision model gains no detail and the request
  /// only carries more bytes; it is also comfortably under Converse's 8000 px
  /// limit.
  static let maxPixelSize: CGFloat = 1568

  /// Converse's limit on one image's bytes.
  static let maxByteCount = 3_750_000

  /// JPEG qualities tried in turn until the bytes fit ``maxByteCount``.
  static let qualities: [CGFloat] = [0.85, 0.7, 0.5, 0.3]

  private static let context = CIContext()

  static func encode(_ attachment: Transcript.ImageAttachment) throws -> ImageBlock {
    let image = normalized(attachment.ciImage.oriented(attachment.orientation))
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    var smallest = Int.max
    for quality in qualities {
      let options: [CIImageRepresentationOption: Any] = [
        CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
          quality
      ]
      guard let data = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
      else {
        throw BedrockError.unencodableImage
      }
      if data.count <= maxByteCount {
        return ImageBlock(format: .jpeg, bytes: data)
      }
      smallest = min(smallest, data.count)
    }
    throw BedrockError.imageTooLarge(smallest)
  }

  /// Scales the image to fit ``maxPixelSize`` and moves its extent to the
  /// origin, which is where the JPEG encoder expects it after a transform.
  static func normalized(_ image: CIImage) -> CIImage {
    var result = image
    let longest = max(image.extent.width, image.extent.height)
    if longest > maxPixelSize {
      let scale = maxPixelSize / longest
      result = result.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    let origin = result.extent.origin
    if origin != .zero {
      result = result.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }
    return result
  }
}
