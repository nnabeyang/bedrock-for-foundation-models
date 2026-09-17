//
//  ImageAttachmentEncoderTests.swift
//  BedrockForFoundationModelsTests
//
//  Created by Noriaki Watanabe on 2026/09/17.
//

import CoreGraphics
import CoreImage
import Foundation
import FoundationModels
import ImageIO
import Testing

@testable import BedrockForFoundationModels

@available(anyAppleOS 27, *)
private func solidImage(width: Int, height: Int) throws -> CGImage {
  let context = try #require(
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return try #require(context.makeImage())
}

/// Pixel size of an encoded image, read back through ImageIO.
private func decodedSize(of data: Data) throws -> (width: Int, height: Int) {
  let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
  let properties = try #require(
    CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
  let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
  return (width, height)
}

@Suite("ImageAttachmentEncoder")
struct ImageAttachmentEncoderTests {
  @available(anyAppleOS 27, *)
  @Test("leaves an image that already fits at its own size")
  func keepsSmallImage() throws {
    let normalized = ImageAttachmentEncoder.normalized(CIImage(cgImage: try solidImage(width: 40, height: 20)))
    #expect(normalized.extent == CGRect(x: 0, y: 0, width: 40, height: 20))
  }

  @available(anyAppleOS 27, *)
  @Test("scales the longest side down to the pixel limit, keeping the aspect ratio")
  func scalesLargeImage() throws {
    let normalized = ImageAttachmentEncoder.normalized(CIImage(cgImage: try solidImage(width: 4000, height: 2000)))
    #expect(normalized.extent.width == ImageAttachmentEncoder.maxPixelSize)
    #expect(normalized.extent.height == ImageAttachmentEncoder.maxPixelSize / 2)
    #expect(normalized.extent.origin == .zero)
  }

  @available(anyAppleOS 27, *)
  @Test("encodes to JPEG")
  func encodesJPEG() throws {
    let block = try ImageAttachmentEncoder.encode(Transcript.ImageAttachment(try solidImage(width: 40, height: 20)))
    #expect(block.format == .jpeg)
    #expect(block.source.bytes.prefix(2) == Data([0xFF, 0xD8]))
    let size = try decodedSize(of: block.source.bytes)
    #expect(size.width == 40)
    #expect(size.height == 20)
  }

  @available(anyAppleOS 27, *)
  @Test("bakes the attachment's orientation into the pixels")
  func appliesOrientation() throws {
    let attachment = Transcript.ImageAttachment(try solidImage(width: 40, height: 20), orientation: .right)
    let block = try ImageAttachmentEncoder.encode(attachment)
    let size = try decodedSize(of: block.source.bytes)
    #expect(size.width == 20)
    #expect(size.height == 40)
  }

  @available(anyAppleOS 27, *)
  @Test("stays under the byte limit for a large image")
  func staysUnderByteLimit() throws {
    let block = try ImageAttachmentEncoder.encode(Transcript.ImageAttachment(try solidImage(width: 6000, height: 6000)))
    #expect(block.source.bytes.count <= ImageAttachmentEncoder.maxByteCount)
    let size = try decodedSize(of: block.source.bytes)
    #expect(size.width == Int(ImageAttachmentEncoder.maxPixelSize))
  }
}
