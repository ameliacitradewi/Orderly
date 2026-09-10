import CoreGraphics
import Foundation
import ImageIO
import Vision

struct ImageEvidenceObservation: Codable, Sendable, Equatable {
    let fileID: UUID
    let localReference: String?
    let globalReference: String
    let contentType: String
    let width: Int
    let height: Int
    let frameCount: Int
    let orientation: Int?

    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }
}

/// Deterministic visual evidence from Apple frameworks. A small Vision feature-print
/// distance means visually similar, but it is never exact-duplicate verification.
struct DeterministicImageComparison: Codable, Sendable, Equatable {
    let fileIDs: [UUID]
    let globalReferences: [String]
    let sameDimensions: Bool
    let aspectRatioDifference: Double
    let featurePrintDistance: Double
}

protocol ImageEvidenceInspecting {
    func inspectImage(
        at url: URL,
        fileID: UUID,
        localReference: String?,
        globalReference: String
    ) throws -> ImageEvidenceObservation

    func compareImages(
        firstURL: URL,
        secondURL: URL,
        first: ImageEvidenceObservation,
        second: ImageEvidenceObservation
    ) throws -> DeterministicImageComparison
}

/// Uses ImageIO for trusted raster metadata and Vision feature prints for bounded
/// visual similarity. It does not perform semantic interpretation and never decides
/// whether a file may be deleted.
final class AppleImageEvidenceService: ImageEvidenceInspecting {
    func inspectImage(
        at url: URL,
        fileID: UUID,
        localReference: String?,
        globalReference: String
    ) throws -> ImageEvidenceObservation {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw ImageEvidenceError.cannotOpenImage
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            options
        ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw ImageEvidenceError.missingImageProperties
        }

        let type = CGImageSourceGetType(source).map { $0 as String } ?? "unknown"
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue

        return ImageEvidenceObservation(
            fileID: fileID,
            localReference: localReference,
            globalReference: globalReference,
            contentType: type,
            width: width,
            height: height,
            frameCount: max(CGImageSourceGetCount(source), 1),
            orientation: orientation
        )
    }

    func compareImages(
        firstURL: URL,
        secondURL: URL,
        first: ImageEvidenceObservation,
        second: ImageEvidenceObservation
    ) throws -> DeterministicImageComparison {
        let firstPrint = try featurePrint(at: firstURL)
        let secondPrint = try featurePrint(at: secondURL)
        var distance: Float = 0
        try firstPrint.computeDistance(&distance, to: secondPrint)
        guard distance.isFinite, distance >= 0 else {
            throw ImageEvidenceError.invalidFeatureDistance
        }

        let aspectDifference: Double
        let maxAspect = max(first.aspectRatio, second.aspectRatio)
        if maxAspect == 0 {
            aspectDifference = 0
        } else {
            aspectDifference = abs(first.aspectRatio - second.aspectRatio) / maxAspect
        }

        return DeterministicImageComparison(
            fileIDs: [first.fileID, second.fileID],
            globalReferences: [first.globalReference, second.globalReference],
            sameDimensions: first.width == second.width && first.height == second.height,
            aspectRatioDifference: aspectDifference,
            featurePrintDistance: Double(distance)
        )
    }

    private func featurePrint(at url: URL) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw ImageEvidenceError.featurePrintUnavailable
        }
        return result
    }
}

enum ImageEvidenceError: LocalizedError {
    case unsupportedFileType
    case cannotOpenImage
    case missingImageProperties
    case featurePrintUnavailable
    case invalidFeatureDistance
    case fileOutsideAnalyzedFolder
    case missingImageEvidence

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Image evidence currently supports common raster image formats only."
        case .cannotOpenImage:
            return "Orderly could not open this image."
        case .missingImageProperties:
            return "Orderly could not read trusted image dimensions."
        case .featurePrintUnavailable:
            return "Apple Vision could not produce a visual feature print for this image."
        case .invalidFeatureDistance:
            return "Apple Vision returned an invalid image similarity distance."
        case .fileOutsideAnalyzedFolder:
            return "Image inspection is restricted to the analyzed folder."
        case .missingImageEvidence:
            return "Both images must be inspected before visual comparison."
        }
    }
}
