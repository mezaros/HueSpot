// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import Foundation
import AppKit
import Darwin

enum ScreenCaptureSampleResult {
    case color(ColorSample)
    case noFrame
    case permissionDenied
    case failure(String)
}

/// Captures the composited on-screen pixel under the cursor using
/// CoreGraphics screen capture APIs. Kept as an actor to serialize capture calls.
actor ScreenCaptureSampler {
    static let shared = ScreenCaptureSampler()

    private enum SamplerError: Error {
        case captureUnavailable
        case nilImage
    }

    private typealias LegacyCaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private let coreGraphicsHandle: UnsafeMutableRawPointer?
    private let captureFunction: LegacyCaptureFunction?
    private let sampleSize: CGFloat = 1

    private init() {
        if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
           let symbol = dlsym(handle, "CGWindowListCreateImage") {
            coreGraphicsHandle = handle
            captureFunction = unsafeBitCast(symbol, to: LegacyCaptureFunction.self)
        } else {
            coreGraphicsHandle = nil
            captureFunction = nil
        }
    }

    deinit {
        if let coreGraphicsHandle {
            dlclose(coreGraphicsHandle)
        }
    }

    func sample(at point: CGPoint) async -> ScreenCaptureSampleResult {
        guard CGPreflightScreenCaptureAccess() else {
            return .permissionDenied
        }

        guard let rect = await captureRect(around: point) else {
            return .noFrame
        }

        do {
            let image = try captureImage(in: rect)
            guard let sample = sampleColor(from: image) else {
                return .noFrame
            }
            return .color(sample)
        } catch SamplerError.captureUnavailable {
            return .failure("legacy_capture_unavailable")
        } catch SamplerError.nilImage {
            return .noFrame
        } catch {
            let nsError = error as NSError
            return .failure("\(nsError.domain):\(nsError.code)")
        }
    }

    private func captureRect(around point: CGPoint) async -> CGRect? {
        let bounds = await MainActor.run {
            NSScreen.screens.map(\.frame).reduce(CGRect.null) { partialResult, frame in
                partialResult.union(frame)
            }
        }
        guard !bounds.isNull, !bounds.isEmpty else {
            return nil
        }

        let half = sampleSize / 2.0
        let rect = CGRect(
            x: floor(point.x - half),
            y: floor(point.y - half),
            width: sampleSize,
            height: sampleSize
        ).intersection(bounds).integral
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        // CGWindowListCreateImage expects screen-space coordinates with top-left origin.
        let converted = CGRect(
            x: rect.minX,
            y: floor(bounds.maxY - rect.maxY),
            width: rect.width,
            height: rect.height
        ).integral
        guard converted.width > 0, converted.height > 0 else {
            return nil
        }
        return converted
    }

    private func captureImage(in rect: CGRect) throws -> CGImage {
        guard let captureFunction else {
            throw SamplerError.captureUnavailable
        }

        // Capture the fully composited on-screen result (including wallpaper under transparency)
        // at nominal resolution so 1x1 maps to the logical cursor location.
        let listOptionsRaw: UInt32 = 1 << 0 // on-screen only
        let imageOptionsRaw: UInt32 = 1 << 4 // nominal resolution
        guard let image = captureFunction(rect, listOptionsRaw, UInt32(kCGNullWindowID), imageOptionsRaw)?.takeRetainedValue() else {
            throw SamplerError.nilImage
        }
        return image
    }

    private func sampleColor(from image: CGImage) -> ColorSample? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return nil
        }

        // Normalize capture output to 8-bit sRGB before sampling.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalR = 0
        var totalG = 0
        var totalB = 0
        var count = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Int(rgba[offset])
                let g = Int(rgba[offset + 1])
                let b = Int(rgba[offset + 2])
                let alpha = Int(rgba[offset + 3])
                guard alpha > 0 else {
                    continue
                }
                totalR += r
                totalG += g
                totalB += b
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let red = CGFloat(totalR) / CGFloat(count) / 255.0
        let green = CGFloat(totalG) / CGFloat(count) / 255.0
        let blue = CGFloat(totalB) / CGFloat(count) / 255.0
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)

        let hex = String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )

        return ColorSample(color: color, hex: hex)
    }
}
