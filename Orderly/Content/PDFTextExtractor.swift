import Foundation
import PDFKit

struct PDFTextExtractor: ContentInspectionService {
    func inspectPDF(
        at url: URL,
        fileReference: String,
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
                let separator = extracted.isEmpty ? "" : "\n"
                let remainingBeforeSeparator = maxExcerptCharacters - extracted.count
                if !separator.isEmpty && remainingBeforeSeparator > 0 {
                    extracted.append(separator)
                }
                let remaining = maxExcerptCharacters - extracted.count
                if remaining > 0 {
                    extracted.append(contentsOf: text.prefix(remaining))
                }
            }
        }

        return ContentObservation(
            fileReference: fileReference,
            contentType: "application/pdf",
            pageCount: document.pageCount,
            extractedCharacterCount: totalCharacters,
            excerpt: extracted,
            truncated: totalCharacters > extracted.count
        )
    }
}
