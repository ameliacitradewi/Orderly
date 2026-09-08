import Foundation
import PDFKit

struct PDFTextExtractor: ContentInspectionService {
    func inspectPDF(
        at url: URL,
        fileReference: String,
        maxExcerptCharacters: Int
    ) throws -> ContentObservation {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw ContentInspectionError.cannotOpenPDF
        }

        let limit = max(0, maxExcerptCharacters)
        var excerpt = ""
        var extractedCharacterCount = 0
        var includedTextCharacterCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string,
                  !text.isEmpty else {
                continue
            }

            extractedCharacterCount += text.count

            if !excerpt.isEmpty, excerpt.count < limit {
                let separator = "\n\n"
                excerpt += separator.prefix(limit - excerpt.count)
            }

            let remaining = max(0, limit - excerpt.count)
            let included = text.prefix(remaining)
            excerpt += included
            includedTextCharacterCount += included.count
        }

        return ContentObservation(
            fileReference: fileReference,
            contentType: "application/pdf",
            pageCount: document.pageCount,
            extractedCharacterCount: extractedCharacterCount,
            excerpt: excerpt,
            truncated: includedTextCharacterCount < extractedCharacterCount
        )
    }
}
