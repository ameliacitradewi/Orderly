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

    init(
        fileID: UUID,
        localReference: String?,
        globalReference: String,
        contentType: String,
        pageCount: Int?,
        extractedCharacterCount: Int,
        excerpt: String,
        truncated: Bool
    ) {
        self.fileID = fileID
        self.localReference = localReference
        self.globalReference = globalReference
        self.contentType = contentType
        self.pageCount = pageCount
        self.extractedCharacterCount = extractedCharacterCount
        self.excerpt = excerpt
        self.truncated = truncated
    }

    /// Compatibility initializer for existing test/mocked content services.
    /// Production observations are re-bound to trusted file identity by
    /// ContentInspectionService.inspectPDF(...fileID:globalReference:...).
    init(
        fileReference: String,
        contentType: String,
        pageCount: Int?,
        extractedCharacterCount: Int,
        excerpt: String,
        truncated: Bool
    ) {
        self.init(
            fileID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            localReference: fileReference,
            globalReference: fileReference,
            contentType: contentType,
            pageCount: pageCount,
            extractedCharacterCount: extractedCharacterCount,
            excerpt: excerpt,
            truncated: truncated
        )
    }

    /// Legacy local alias retained while older tests and helpers migrate.
    var fileReference: String {
        localReference ?? globalReference
    }
}

protocol ContentInspectionService: Sendable {
    func inspectPDF(
        at url: URL,
        fileReference: String,
        maxExcerptCharacters: Int
    ) throws -> ContentObservation
}

extension ContentInspectionService {
    func inspectPDF(
        at url: URL,
        fileID: UUID,
        localReference: String?,
        globalReference: String,
        maxExcerptCharacters: Int
    ) throws -> ContentObservation {
        let extracted = try inspectPDF(
            at: url,
            fileReference: localReference ?? globalReference,
            maxExcerptCharacters: maxExcerptCharacters
        )
        return ContentObservation(
            fileID: fileID,
            localReference: localReference,
            globalReference: globalReference,
            contentType: extracted.contentType,
            pageCount: extracted.pageCount,
            extractedCharacterCount: extracted.extractedCharacterCount,
            excerpt: extracted.excerpt,
            truncated: extracted.truncated
        )
    }
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
