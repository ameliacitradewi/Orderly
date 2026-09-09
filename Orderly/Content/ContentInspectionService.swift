import Foundation

struct ContentObservation: Codable, Sendable, Equatable {
    let fileID: UUID
    let localReference: String?
    let globalReference: String
    let contentType: String
    let pageCount: Int?
    let extractedCharacterCount: Int
    let excerpt: String
    let truncated: Bool
}

protocol ContentInspectionService: Sendable {
    func inspectPDF(
        at url: URL,
        fileID: UUID,
        localReference: String?,
        globalReference: String,
        maxExcerptCharacters: Int
    ) throws -> ContentObservation
}

enum ContentInspectionError: LocalizedError {
    case fileOutsideAnalyzedFolder
    case unsupportedFileType
    case cannotOpenPDF

    var errorDescription: String? {
        switch self {
        case .fileOutsideAnalyzedFolder:
            return "The requested file is outside the analyzed folder."
        case .unsupportedFileType:
            return "The requested file is not a PDF."
        case .cannotOpenPDF:
            return "The PDF could not be opened for content inspection."
        }
    }
}
