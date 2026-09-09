import Foundation
import PDFKit

struct PDFTextExtractor: ContentInspectionService {
    func inspectPDF(
        at url: URL,
        fileID: UUID,
        localReference: String?,
        globalReference: String,
        maxExcerptCharacters: Int
    ) throws -> ContentObservation {
        guard let document = PDFDocument(url: url) else {
            throw ContentInspectionError.cannotOpenPDF
        }

        var extracted = ""
        extracted.reserveCapacity(min(maxExcerptCharacters, 8_192))
        var totalCharacters = 0

        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else { continue }
            totalCharacters += text.count

            if extracted.count < maxExcerptCharacters {
                let remaining = maxExcerptCharacters - extracted.count
                if !extracted.isEmpty && remaining > 0 {
                    extracted.append("\n")
                }
                let newRemaining = maxExcerptCharacters - extracted.count
                if newRemaining > 0 {
                    extracted.append(contentsOf: text.prefix(newRemaining))
                }
            }
        }

        return ContentObservation(
            fileID: fileID,
            localReference: localReference,
            globalReference: globalReference,
            contentType: "pdf",
            pageCount: document.pageCount,
            extractedCharacterCount: totalCharacters,
            excerpt: extracted,
            truncated: totalCharacters > extracted.count
        )
    }
}
